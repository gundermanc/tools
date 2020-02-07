# Aliases for collecting dumps + traces in a simple way (locally or on build machines)
# By: Christian Gunderman

$JITDebuggingExcludePath = "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion\AeDebug\AutoExclusionList"
$LocalDumpsPath = "HKLM:SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps"

<#
.SYNOPSIS
Adds the specified exe name to Windows automatic dump collection.

.PARAMETER exeName
Name of the EXE to capture dumps for on crash.

.PARAMETER path
Parameter description
#>
function Add-AutoDump($exeName, $path)
{
    ThrowIfNotAdmin

    # Validate arguments.
    if ([string]::IsNullOrWhiteSpace($exeName) -or [string]::IsNullOrWhiteSpace($path))
    {
        Throw "Must provide 'exeName' and 'path' parameters."
    }

    # Append extension, if needed.
    if ([string]::IsNullOrWhiteSpace(([System.IO.Path]::GetExtension($exeName))))
    {
        $exeName += ".exe"
    }

    # Make sure we're dealing with real, full paths.
    $path = (Resolve-Path $path)

    $key = "$LocalDumpsPath\$exeName"

    # Windows has a magic registry key for collecting dumps at a certain path.
    if (-not (Test-Path $key))
    {
        New-Item -Path $key | Out-Null
    }
    Set-ItemProperty -Path $key -Name "DumpCount" -Value "10"
    Set-ItemProperty -Path $key -Name "DumpFolder" -Value $path
    Set-ItemProperty -Path $key -Name "DumpType" -Value 2
    Write-Host -ForegroundColor Green "Set '$exeName' to capture dumps to '$path'"
}

<#
.SYNOPSIS
Lists all EXEs that are configured for automatic dump collection.
#>
function Get-AutoDump()
{
    Get-ChildItem "HKLM:SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps" |
        Foreach-Object { [System.IO.Path]::GetFileName($_.Name) }
}

<#
.SYNOPSIS
Disables automatic dump collection for specified EXE.

.PARAMETER exeName
EXE to unregister.
#>
function Remove-AutoDump($exeName)
{
    ThrowIfNotAdmin

    # Validate arguments.
    if ([string]::IsNullOrWhiteSpace($exeName))
    {
        Throw "Must provide 'exeName'"
    }

    # Append extension, if needed.
    if ([string]::IsNullOrWhiteSpace(([System.IO.Path]::GetExtension($exeName))))
    {
        $exeName += ".exe"
    }

    $key = "$LocalDumpsPath\$exeName"

    # Ensure we're already registered.
    if (-not (Test-Path $key))
    {
        Throw "'$exeName' is not currently configured for collection."
    }

    # Delete item.
    Remove-Item $key
    Remove-ItemProperty -Path $JITDebuggingExcludePath -Name $exeName -ErrorAction SilentlyContinue
    Write-Host -ForegroundColor Green "Disabled '$exeName' dump capture."
}

New-Alias -Name "dmpadd" -Value Add-AutoDump
New-Alias -Name "dmpget" -Value Get-AutoDump
New-Alias -Name "dmprm" -Value Remove-AutoDump
