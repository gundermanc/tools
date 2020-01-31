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
    Write-Verbose "Importing `"$module`"..."
    Import-Module $module
}

function Get-ToolModuleHelp
{
    [CmdletBinding(PositionalBinding = $true)]
    param(
        [Parameter()]
        [string]$moduleName = [string]::Empty)

    function Write-ModuleInfo($module, $listAliases = $false)
    {
        $moduleName = $module.Name
        Write-Host -ForegroundColor Cyan "  - $moduleName"

        if ($listAliases)
        {
            $module.ExportedAliases.Keys | Foreach-Object {
                $aliasName = $_
                $remarks = (Get-Help $aliasName).Synopsis
                Write-Host "    $aliasName - $remarks"
            }

            Write-Host
        }
    }

    $isAllModules = ($moduleName -eq "*")

    if (($moduleName.Length -eq 0) -or $isAllModules)
    {
        Write-VersionInfo
        Write-Host "Run 'toolhelp *' to see all aliases or 'toolhelp [module]' to see aliases from that module."
        Write-Host
        Write-Host "Run 'help [alias]' to see help for a particular alias."
        Write-Host

        Write-Host -ForegroundColor Cyan "Loaded modules:"
        Get-module -All | Where-Object { $_.Name -like "*autoload*" } | ForEach-Object { Write-ModuleInfo $_ $isAllModules }
    }
    else
    {
        Get-module -All | Where-Object { $_.Name -like "*$moduleName*" } | ForEach-Object { Write-ModuleInfo $_ $true }
    }

    Write-Host
}

New-Alias -Name "toolhelp" -Value Get-ToolModuleHelp