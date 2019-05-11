# PowerShell REPL + Tools Powershell Script Entry Point
# By: Christian Gunderman

$Global:PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# Record feature directory for scripts.
$Global:FeatureDir = "$Global:PSScriptRoot\Features"

# Make a scratch directory for storing local preferences and tool output.
# This is stored one level up from the install directory so that it persists.
$Global:ScratchDir = "$Global:PSScriptRoot\..\ToolsScratch"
Write-Host "Scratch directory is at `"$Global:ScratchDir`". Run 'scratch' to go there."
New-Item -ItemType Directory -Path $Global:ScratchDir -ErrorAction SilentlyContinue | Out-Null

Import-Module "$Global:PSScriptRoot\Common\Config.psm1"
Import-Module "$Global:PSScriptRoot\Common\Componentization.psm1"
Import-Module "$Global:PSScriptRoot\Common\Utilities.psm1"

New-NavLocation scratch $Global:ScratchDir

Write-VersionInfo

InstallUpdates
