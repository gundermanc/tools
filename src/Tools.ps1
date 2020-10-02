# PowerShell REPL + Tools Powershell Script Entry Point
# By: Christian Gunderman

$Global:PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

Import-Module "$Global:PSScriptRoot\Common\Componentization.psm1"

Set-Title
Write-VersionInfo

Write-Host -ForegroundColor Cyan "Configuration Directory:"
Write-Host

# Make a scratch directory for storing local preferences and tool output.
# This is stored one level up from the install directory so that it persists when updated.
$Global:ScratchDir = "$Global:PSScriptRoot\..\ToolsScratch"
New-Item -ItemType Directory -Path $Global:ScratchDir -ErrorAction SilentlyContinue | Out-Null
$Global:ScratchDir = (Resolve-Path "$Global:PSScriptRoot\..\ToolsScratch").Path

# Create an alias to the scratch directory.
New-NavLocation scratch $Global:ScratchDir | Out-Null
Write-Host "The 'scratch' directory holds your per-machine configuration. Run 'nve scratch' to go there."
Write-Host

# Check for updates.
InstallUpdates

# Tips.
Write-Host -ForegroundColor Cyan Help:
Write-Host " - Get help for this tool with 'toolhelp' command."
Write-Host " - See README for more documentation: https://github.com/gundermanc/tools/blob/master/README.md"
Write-Host