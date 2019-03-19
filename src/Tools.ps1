# PowerShell REPL + Tools Powershell Script Entry Point
# By: Christian Gunderman

$Global:PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# Record feature directory for scripts.
$Global:FeatureDir = "$Global:PSScriptRoot\Features"

Import-Module "$Global:PSScriptRoot\Common\Config.psm1"
Import-Module "$Global:PSScriptRoot\Common\Componentization.psm1"
Import-Module "$Global:PSScriptRoot\Common\Utilities.psm1"

# Make a scratch directory for storing local preferences and tool output.
$Global:ScratchDir = "$Global:PSScriptRoot\Scratch"
Write-Host "Scratch directory is at `"$Global:ScratchDir`""
New-Item -ItemType Directory -Path $Global:ScratchDir -ErrorAction SilentlyContinue | Out-Null

Write-VersionInfo

