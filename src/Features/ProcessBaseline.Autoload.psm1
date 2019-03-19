# Process Baselining tool: Easily snapshot and kill unwanted processes.
# By: Christian Gunderman

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

# Gets a list of known process baselines.
function Get-ProcessBaselines
{
    Get-ChildItem "$Global:ScratchDir\*.processbaseline"
}

# Serializes a list of currently running processes with the given name.
function New-ProcessBaseline($baselineFile)
{
    $baselineFile = Get-ProcessBaselinePath $baselineFile

    $processes = (Get-Process | Where-Object Path -ne  $null | Sort-Object -Property Path)
    Set-Content -Path $baselineFile $processes.Path
}

# Stops all but the given list of processes. This is useful for killing exes that might
# have locked files during build.
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

# Stops the given list of processes.
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

# Opens the given list of processes for editing.
function Edit-ProcessBaseline($baselineFile)
{
    $baselineFile = Get-ProcessBaselinePath $baselineFile

    &notepad.exe $baselineFile
}

New-Alias -Name pbget -Value Get-ProcessBaselines
New-Alias -Name pbnew -Value New-ProcessBaseline
New-Alias -Name pbnstop -Value Stop-NonProcessBaseline
New-Alias -Name pbstop -Value Stop-ProcessBaseline
New-Alias -Name pbedit -Value Edit-ProcessBaseline
