# Tools Powershell Componentization
# By: Christian Gunderman

# Define common paths and import core pieces.
$Global:CommonDir = "$Global:PSScriptRoot\Common"
$Global:DependenciesDir = "$Global:PSScriptRoot\Dependencies"
$Global:FeatureDir = "$Global:PSScriptRoot\Features"

Import-Module "$Global:CommonDir\Config.psm1"
Import-Module "$Global:CommonDir\Utilities.psm1"

# Import features.
$modules = Get-ChildItem -Recurse -Force "$Global:PSScriptRoot\Features\*.AutoLoad.psm1"
foreach ($module in $modules)
{
    Write-Host "Importing `"$module`"..."
    Import-Module $module
}
