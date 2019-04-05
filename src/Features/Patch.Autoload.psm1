# Application binary patching tool
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

# Gets a patch profile file path.
function Get-PatchProfilePath($patchProfile)
{
    if ([string]::IsNullOrWhiteSpace($patchProfile))
    {
        Throw "Must provide a patch profile name argument"
    }

    return Join-Path $Global:ScratchDir "$patchProfile.patchprofile"
}

# Gets the target directory for the patching operation.
function Get-PatchTargetDirectory
{
    if ([string]::IsNullOrWhiteSpace($env:PatchTargetDir))
    {
        Write-Host -ForegroundColor Yellow "For patching instances of VS, use vsget to find an instance, and vspatch to set it as the current."
        Throw "Must define `$env:PatchTargetDir prior to patching."
    }

    return $env:PatchTargetDir
}

function Write-PatchSchema
{
    Write-Output @"
Patch schema is as follows:"

{
    "sourceDirectory": "",
    "files": {
        "relative source path": "relative destination path"
    },
    "commands": [
        "foo.exe"
    ]
}

"@
}

# Opens a patch profile for editing.
function Edit-PatchProfile($patchProfile)
{
    Write-PatchSchema
    & notepad.exe (Get-PatchProfilePath $patchProfile)
}

# Gets a list of known process baselines.
function Get-PatchProfiles
{
    Get-ChildItem "$Global:ScratchDir\*.patchprofile"
}

function RevertItem($destinationFile)
{
    $stockRevisionFile = "$destinationFile.stockrevision"
    $updateHashFile = "$destinationFile.updatehash"

    # Reverting backup file.
    Write-Host "  - Reverting backup of $destinationFile..."
    try
    {
        # If this file isn't patched, return success.
        if (-not (Test-Path $stockRevisionFile))
        {
            return $true
        }

        # Ensure that the patched file hash matches the one we saved when we performed
        # the patch. This eliminates the possibility that the application being updated
        # could overwrite the patched bits and then be wiped out by 'reverting'.
        $destinationHash = (Get-FileHash $destinationFile).Hash
        if ($destinationHash -eq (Get-Content $updateHashFile))
        {
            Copy-Item -Path $stockRevisionFile -Destination $destinationFile -Force
        }
        else
        {
            Write-Host -ForegroundColor Yellow "Hash file mismatch. There appears to have been an update. Skipping $destinationFile"
        }

        Remove-Item -Path $stockRevisionFile -Force
        Remove-Item -Path $updateHashFile -Force

        return $true
    }
    catch
    {
        ## Do this in a try catch so a failure to revert doesn't cause backup to be deleted.
        Write-Host "Failed reverting $destinationFile"
        return $false
    }
}

# Invokes a patch profile on a program install.
function Invoke-PatchProfile($patchProfile)
{
    function PatchItem ($sourceFile, $destinationFile)
    {
        $backupFile = "$destinationFile.stockrevision"
        $hashFile = "$destinationFile.updatehash"

        try
        {
            # Item was backed up previously. Revert it.
            # This is done to ensure that files that were updated
            # and backed up again.
            if (Test-Path $backupFile)
            {
                Write-Host "Previously patched. Reverting..."
                RevertItem $destinationFile
            }

            Write-Host "  - Creating backup of $destinationFile..."
                Copy-Item -Path $destinationFile -Destination $backupFile -Force

            # Save new file hash. This enables us to check before reverting
            # so we don't accidentally 'revert' to the wrong bits if the
            # product is updated and then the user tries to revert.
            (Get-FileHash $sourceFile).Hash | Set-Content -Path $hashFile

            # Copy new file.
            Write-Host "  - Patching $sourceFile with $destinationFile..."
            Copy-Item -Path $sourceFile -Destination $destinationFile -Force

            return $true
        }
        catch
        {
            # Perform patch in a try-catch so that we don't modify anything
            # if the backup fails.
            return $false
        }
    }

    $patchProfile = (Get-PatchProfilePath $patchProfile)
    $content = (Get-Content $patchProfile)
    $jsonContent = $content | ConvertFrom-Json

    # Determine the source directory.
    $sourceDirectory = $jsonContent.sourceDirectory
    Write-Host "Source Directory: $sourceDirectory"
    if ([string]::IsNullOrWhiteSpace($sourceDirectory) -or (-not (Test-Path $sourceDirectory)))
    {
        Throw "Unspecified or inaccessible sourceDirectory $sourceDirectory"
    }

    # Determine the destination directory.
    $destinationDirectory = Get-PatchTargetDirectory
    Write-Host "Destination Directory: $destinationDirectory"

    $files = $jsonContent.files
    foreach ($file in $files)
    {
        foreach ($property in $file.PSObject.Properties)
        {
            $sourceFile = (Join-Path $sourceDirectory $property.Name)
            $destinationFile = (Join-Path $destinationDirectory $property.Value)
            
            if (-not (PatchItem $sourceFile $destinationFile))
            {
                Stop-LockingApp $destinationFile
            }
        }
    }

    $commands = $jsonContent.commands
    foreach ($command in $commands)
    {
        Write-Host "- Running > $command"
        Invoke-Expression $command
    }
}

# Stops processes that have locked modules.
function Stop-LockingApp($fileName)
{
    Write-Host -ForegroundColor Yellow "Checking for processes locking $fileName..."

    $lockingProcesses = [FileUtil]::WhoIsLocking($fileName)
    foreach ($process in $lockingProcesses)
    {
        $mainModulePath = $process.Path
        Write-Host -ForegroundColor Yellow "Killing $mainModulePath"
        $process.Kill()
        $process.WaitForExit()
    }
}

function Get-PatchStatus
{
    # Determine the destination directory.
    $destinationDirectory = Get-PatchTargetDirectory
    Write-Output "Destination Directory: $destinationDirectory"

    Write-Output "The following files have been patched:"

    $stockRevisions = Get-ChildItem -Recurse (Join-Path $destinationDirectory "*.stockrevision")
    foreach ($stockRevision in $stockRevisions)
    {
        $originalFileName = $stockRevision.Name.SubString(0, $stockRevision.Name.Length - ".stockrevision".Length)
        Write-Host "  - $originalFileName"
    }
}

# Invokes a patch profile revert on a program install.
function Invoke-RevertPatchProfile($patchProfile)
{
    $patchProfile = (Get-PatchProfilePath $patchProfile)
    $content = (Get-Content $patchProfile)
    $jsonContent = $content | ConvertFrom-Json

    # Determine the destination directory.
    $destinationDirectory = Get-PatchTargetDirectory
    Write-Host "Destination Directory: $destinationDirectory"

    $files = $jsonContent.files
    foreach ($file in $files)
    {
        foreach ($property in $file.PSObject.Properties)
        {
            $destinationFile = (Join-Path $destinationDirectory $property.Value)

            if (-not (RevertItem $destinationFile))
            {
                Stop-LockingApp $destinationFile
                RevertItem $destinationFile
            }
        }
    }

    $commands = $jsonContent.commands
    foreach ($command in $commands)
    {
        Write-Host "- Running > $command"
        Invoke-Expression $command
    }
}

New-Alias -Name ptedit -Value Edit-PatchProfile
New-Alias -Name ptget -Value Get-PatchProfiles
New-Alias -Name ptapply -Value Invoke-PatchProfile
New-Alias -Name ptstatus -Value Get-PatchStatus
New-Alias -Name ptrevert -Value Invoke-RevertPatchProfile
