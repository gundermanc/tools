# Navigation Aliases
# By: Christian Gunderman

<#
.SYNOPSIS
Lists all registered navigation aliases.
#>
function Get-NavAliasesPath
{
    return Join-Path $Global:ScratchDir ".aliases"
}

function Write-NavAliasesSchema
{
    Write-Output @"
Aliases schema is as follows:"

{
    "aliasName": "alias destination"
}
"@
}

<#
.SYNOPSIS
Opens the navigation aliases file for editing.
#>
function Edit-NavAliases
{
    $aliasesPath = (Get-NavAliasesPath)

    Write-NavAliasesSchema

    & notepad.exe $aliasesPath
}

<#
.SYNOPSIS
Gets a list of registered navigation aliases.

.NOTES
Aliases are stored in the user's scratch directory.
#>
function Read-NavAliases
{
    $aliasesPath = Get-NavAliasesPath
    if (-not (Test-Path $aliasesPath))
    {
        Write-Host -ForegroundColor Yellow "Unable to read existing aliases file..."
        return @{}
    }

    $content = (Get-Content $aliasesPath)
    $jsonContent = $content | ConvertFrom-Json
    $aliases = $jsonContent
    $readAliases = @{}
    foreach ($alias in $aliases)
    {
        foreach ($property in $alias.PSObject.Properties)
        {
            $aliasName = $property.Name
            $destination = $property.Value

            $readAliases[$aliasName] = $destination
        }
    }

    return $readAliases
}

<#
.SYNOPSIS
Navigates to a location named by an alias. Creates if it doesn't exist.

.PARAMETER desiredAlias
The name of the location to navigate to.
#>
function Push-NavLocation($desiredAlias)
{
    $aliases = Read-NavAliases

    $destination = $aliases[$desiredAlias]
    if ($destination -ne $null)
    {
        Set-Location $destination
        return
    }

    Write-Host -ForegroundColor Yellow "Undefined alias"
    Write-Host "Enter destination:"
    $destination = Read-Host

    New-NavLocation $desiredAlias $destination
}

<#
.SYNOPSIS
Shell-opens a location named by an alias. Creates if it doesn't exist.

.DESCRIPTION
This alias opens the named alias using the associated program, enabling
navigation to paths in explorer, opening URLs, etc.

.PARAMETER desiredAlias
The alias to navigate to or create.
#>
function Start-NavLocation($desiredAlias)
{
    $aliases = Read-NavAliases

    $destination = $aliases[$desiredAlias]
    if ($destination -ne $null)
    {
        start $destination
        return
    }

    Write-Host -ForegroundColor Yellow "Undefined alias"
    Write-Host "Enter destination:"
    $destination = Read-Host

    New-NavLocation $desiredAlias $destination
}

<#
.SYNOPSIS
Creates a new navigation alias.

.PARAMETER name
Name of the alias.

.PARAMETER destination
The path, URI, etc. to navigate to.
#>
function New-NavLocation($name, $destination)
{
    if ([string]::IsNullOrWhiteSpace($name))
    {
        Throw "Must provide name"
    }

    if ([string]::IsNullOrWhiteSpace($destination))
    {
        Throw "Must provide destination"
    }

    $aliases = Read-NavAliases

    $aliases[$name] = $destination

    $jsonContent = ConvertTo-Json $aliases
    Set-Content -Path (Get-NavAliasesPath) $jsonContent -ErrorAction Stop

    Write-Host -ForegroundColor Green "Defined new alias '$name' at '$destination'"
}

New-Alias -Name nvedit -Value Edit-NavAliases
New-Alias -Name nvget -Value Read-NavAliases
New-Alias -Name nvgo -Value Push-NavLocation
New-Alias -Name nvnew -Value New-NavLocation
New-Alias -Name nve -Value Start-NavLocation
