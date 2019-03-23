# Navigation Aliases
# By: Christian Gunderman

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

function Edit-NavAliases
{
    $aliasesPath = (Get-NavAliasesPath)

    Write-NavAliasesSchema

    & notepad.exe $aliasesPath
}

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

    Write-Host -ForegroundColor Green "Defined new alias"
}

New-Alias -Name nvedit -Value Edit-NavAliases
New-Alias -Name nvget -Value Read-NavAliases
New-Alias -Name nvgo -Value Push-NavLocation
New-Alias -Name nvnew -Value New-NavLocation
New-Alias -Name nve -Value Start-NavLocation
