# Tools Powershell Componentization
# By: Christian Gunderman

# Import features.
$modules = Get-ChildItem -Recurse -Force "$Global:PSScriptRoot\Features\*.AutoLoad.psm1"
foreach ($module in $modules)
{
    Write-Host "Importing `"$module`"..."
    Import-Module $module
}

