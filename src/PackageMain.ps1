# PowerShell REPL + Tools Powershell Script Entry Point
# By: Christian Gunderman

$Global:PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

Import-Module "$Global:PSScriptRoot\Common\Config.psm1"
Import-Module "$Global:PSScriptRoot\Common\Utilities.psm1"

Write-VersionInfo

# Primitive initial tools REPL.
do
{
    $location = (Get-Location).Path
    Write-Host -NoNewline "Tools@$location> "
    $command = Read-Host

    if (($command -ine $ExitCommand) -and ($command -ine ""))
    {
        Invoke-Expression $command
    }
}
while ($command -ine $ExitCommand)
