# Process Baselining tool: Easily snapshot and kill unwanted processes.
# By: Christian Gunderman

$GetLockingProcessesCode = @"

// 💕💕 Some fancy code, shamelessly borrowed right from Stackoverflow 💕💕
// https://stackoverflow.com/questions/1304/how-to-check-for-file-lock/20623302#20623302
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

static public class FileUtil
{
    [StructLayout(LayoutKind.Sequential)]
    struct RM_UNIQUE_PROCESS
    {
        public int dwProcessId;
        public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
    }

    const int RmRebootReasonNone = 0;
    const int CCH_RM_MAX_APP_NAME = 255;
    const int CCH_RM_MAX_SVC_NAME = 63;

    enum RM_APP_TYPE
    {
        RmUnknownApp = 0,
        RmMainWindow = 1,
        RmOtherWindow = 2,
        RmService = 3,
        RmExplorer = 4,
        RmConsole = 5,
        RmCritical = 1000
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct RM_PROCESS_INFO
    {
        public RM_UNIQUE_PROCESS Process;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_APP_NAME + 1)]
        public string strAppName;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_SVC_NAME + 1)]
        public string strServiceShortName;

        public RM_APP_TYPE ApplicationType;
        public uint AppStatus;
        public uint TSSessionId;
        [MarshalAs(UnmanagedType.Bool)]
        public bool bRestartable;
    }

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmRegisterResources(uint pSessionHandle,
                                          UInt32 nFiles,
                                          string[] rgsFilenames,
                                          UInt32 nApplications,
                                          [In] RM_UNIQUE_PROCESS[] rgApplications,
                                          UInt32 nServices,
                                          string[] rgsServiceNames);

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Auto)]
    static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);

    [DllImport("rstrtmgr.dll")]
    static extern int RmEndSession(uint pSessionHandle);

    [DllImport("rstrtmgr.dll")]
    static extern int RmGetList(uint dwSessionHandle,
                                out uint pnProcInfoNeeded,
                                ref uint pnProcInfo,
                                [In, Out] RM_PROCESS_INFO[] rgAffectedApps,
                                ref uint lpdwRebootReasons);

    /// <summary>
    /// Find out what process(es) have a lock on the specified file.
    /// </summary>
    /// <param name="path">Path of the file.</param>
    /// <returns>Processes locking the file</returns>
    /// <remarks>See also:
    /// http://msdn.microsoft.com/en-us/library/windows/desktop/aa373661(v=vs.85).aspx
    /// http://wyupdate.googlecode.com/svn-history/r401/trunk/frmFilesInUse.cs (no copyright in code at time of viewing)
    /// 
    /// </remarks>
    static public List<Process> WhoIsLocking(string path)
    {
        uint handle;
        string key = Guid.NewGuid().ToString();
        List<Process> processes = new List<Process>();

        int res = RmStartSession(out handle, 0, key);

        if (res != 0)
            throw new Exception("Could not begin restart session.  Unable to determine file locker.");

        try
        {
            const int ERROR_MORE_DATA = 234;
            uint pnProcInfoNeeded = 0,
                 pnProcInfo = 0,
                 lpdwRebootReasons = RmRebootReasonNone;

            string[] resources = new string[] { path }; // Just checking on one resource.

            res = RmRegisterResources(handle, (uint)resources.Length, resources, 0, null, 0, null);

            if (res != 0) 
                throw new Exception("Could not register resource.");                                    

            //Note: there's a race condition here -- the first call to RmGetList() returns
            //      the total number of process. However, when we call RmGetList() again to get
            //      the actual processes this number may have increased.
            res = RmGetList(handle, out pnProcInfoNeeded, ref pnProcInfo, null, ref lpdwRebootReasons);

            if (res == ERROR_MORE_DATA)
            {
                // Create an array to store the process results
                RM_PROCESS_INFO[] processInfo = new RM_PROCESS_INFO[pnProcInfoNeeded];
                pnProcInfo = pnProcInfoNeeded;

                // Get the list
                res = RmGetList(handle, out pnProcInfoNeeded, ref pnProcInfo, processInfo, ref lpdwRebootReasons);

                if (res == 0)
                {
                    processes = new List<Process>((int)pnProcInfo);

                    // Enumerate all of the results and add them to the 
                    // list to be returned
                    for (int i = 0; i < pnProcInfo; i++)
                    {
                        try
                        {
                            processes.Add(Process.GetProcessById(processInfo[i].Process.dwProcessId));
                        }
                        // catch the error -- in case the process is no longer running
                        catch (ArgumentException) { }
                    }
                }
                else
                    throw new Exception("Could not list processes locking resource.");                    
            }
            else if (res != 0)
                throw new Exception("Could not list processes locking resource. Failed to get size of result.");                    
        }
        finally
        {
            RmEndSession(handle);
        }

        return processes;
    }
}
"@

Add-Type -TypeDefinition $GetLockingProcessesCode

<#
.SYNOPSIS
Stops all processes that have locked the given file.

.PARAMETER fileName
Path to file that is currently locked.
#>
function Stop-LockingApp($fileName)
{
    if ([string]::IsNullOrWhiteSpace($fileName))
    {
        Throw "Expected 1 argument: profile name"
    }

    Write-Host -ForegroundColor Yellow "  - Checking for processes locking $fileName..."

    $lockingProcesses = [FileUtil]::WhoIsLocking($fileName)
    foreach ($process in $lockingProcesses)
    {
        $mainModulePath = $process.Path
        Write-Host -ForegroundColor Yellow "  - Killing $mainModulePath"
        $process.Kill()
        $process.WaitForExit()
    }
}

<#
.SYNOPSIS
Writes the list of processes locking the specified file.

.PARAMETER baselineFile
The name of the file in scratch directory to write to.

.PARAMETER fileName
The file that is locked.
#>
function Write-LockingProcesses($baselineFile, $fileName)
{
    $baselinePath = Get-ProcessBaselinePath($baselineFile)

    if ([string]::IsNullOrWhiteSpace($fileName))
    {
        Throw "Expected 2 arguments: profile name and file to scan."
    }

    Write-Host -ForegroundColor Yellow "Checking for processes locking $fileName..."

    $lockingProcesses = [FileUtil]::WhoIsLocking($fileName)
    Set-Content -Path $baselinePath -Value $lockingProcesses.Path
}

function Get-ProcessBaselinePath($baselineFile)
{
    if (-not [Environment]::Is64BitProcess)
    {
        Write-Host -ForegroundColor Yellow "32 bit Powershell detected. 64 bit processes cannot be baselined"
    }

    if ([string]::IsNullOrWhiteSpace($baselineFile))
    {
        $baselineFile = "Default"
    }

    return Join-Path $Global:ScratchDir "$baselineFile.processbaseline"
}

<#
.SYNOPSIS
Gets a list of process baselines from the scratch directory.
#>
function Get-ProcessBaselines
{
    Get-ChildItem "$Global:ScratchDir\*.processbaseline"
}

<#
.SYNOPSIS
Serializes a list of currently running processes to a file.

.DESCRIPTION
This cmdlet can be used for baselining processes running on a machine
in order to kill-all and return to a clean state.

This is useful for context-switching or enumerating processes that might
be locking build artifacts.

.PARAMETER baselineFile
The name of the file to write the process names to in the scratch dir.

#>
function New-ProcessBaseline($baselineFile)
{
    $baselineFile = Get-ProcessBaselinePath $baselineFile

    $processes = (Get-Process | Where-Object Path -ne  $null | Sort-Object -Property Path)
    Set-Content -Path $baselineFile $processes.Path
}

<#
.SYNOPSIS
Stops all processes except those in the baseline.

.DESCRIPTION
This is useful for killing exes that might have locked files during build.

.PARAMETER baselineFile
The name of the file in the scratch directory with processes.
#>
function Stop-NonProcessBaseline($baselineFile)
{
    $baselineFile = Get-ProcessBaselinePath $baselineFile

    $baselineProcesses = (Get-Content -Path $baselineFile)

    $runningProcesses = Get-Process | Where-Object Path -ne  $null | Sort-Object -Property Path

    foreach ($process in $runningProcesses)
    {
        if (-not $baselineProcesses.Contains($process.Path))
        {
            Write-Host "Stopping " $process.Path
            Stop-Process -Id $process.Id
        }
    }
}

<#
.SYNOPSIS
Stops the given list of processes.

.PARAMETER baselineFile
Path to a file with process names to kill.

#>
function Stop-ProcessBaseline($baselineFile)
{
    $baselineFile = Get-ProcessBaselinePath $baselineFile

    $baselineProcesses = (Get-Content -Path $baselineFile)

    $runningProcesses = Get-Process | Where-Object Path -ne  $null | Sort-Object -Property Path

    foreach ($process in $runningProcesses)
    {
        if ($baselineProcesses.Contains($process.Path))
        {
            Write-Host "Stopping " $process.Path
            Stop-Process -Id $process.Id
        }
    }
}

<#
.SYNOPSIS
Opens the given list of processes for editing.

.PARAMETER baselineFile
The name of a baseline (without extension) in the scratch directory to open.

#>
function Edit-ProcessBaseline($baselineFile)
{
    $baselineFile = Get-ProcessBaselinePath $baselineFile

    &notepad.exe $baselineFile
}

<#
.SYNOPSIS
Starts a process with administrative privileges.

.DESCRIPTION
Calling with zero parameters restarts the tools prompt as admin.
Starting with 1 parameter runs the specified command. Pass 0 or more
additional parameters to pass arguments.

.PARAMETER command

#>
function Start-AdminProcess([string]$command)
{
    # If unspecified command, drop into a tools prompt as admin.
    if ([string]::IsNullOrWhiteSpace($command))
    {
        # Drop into a new tools prompt. Don't pass -Wait
        # because we are creating a terminal process to
        # replace this one.
        Start-Process "cmd.exe" -ArgumentList ("/K", "$Global:FeatureDir\..\Tools.bat") -Verb RunAs
        exit
        return
    }

    if ($args.Length -gt 0)
    {
        echo $args
        Start-Process $command -ArgumentList $args -Verb RunAs -Wait
    }
    else
    {
        Start-Process $command -Verb RunAs -Wait
    }
}

New-Alias -Name pbunlock -Value Stop-LockingApp
New-Alias -Name pbldmp -Value Write-LockingProcesses
New-Alias -Name pbget -Value Get-ProcessBaselines
New-Alias -Name pbnew -Value New-ProcessBaseline
New-Alias -Name pbnstop -Value Stop-NonProcessBaseline
New-Alias -Name pbstop -Value Stop-ProcessBaseline
New-Alias -Name pbedit -Value Edit-ProcessBaseline
New-Alias -Name sudo -Value Start-AdminProcess