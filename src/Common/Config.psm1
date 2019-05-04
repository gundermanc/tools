# Tools Powershell Configuration
# By: Christian Gunderman

function New-InstallationPath
{
    $installationGuid = [Guid]::NewGuid()
    return (Join-Path $env:LOCALAPPDATA $InstallationGuid)
}

$ConfigurationValues =
@{
    "DisableConsole" = $true
    "InstallationPath" = New-InstallationPath
    "IsInstalled" = $false
    "Version" = "0.25"
}

$RegistryRootKeyPath = "HKCU:Software\Tools"

function Get-ConfigurationValueInRegistry($name)
{
    if (Test-Path $RegistryRootKeyPath)
    {
        return (Get-ItemProperty -Path $RegistryRootKeyPath -Name $name -ErrorAction SilentlyContinue).$name
    }
    else
    {
        return $null
    }
}

function Set-ConfigurationValueInRegistry($name, $value)
{
    if (-not (Test-Path $RegistryRootKeyPath))
    {
        New-Item $RegistryRootKeyPath
    }

    return (Set-ItemProperty -Path $RegistryRootKeyPath -Name $name -Value $value)
}

function Get-ConfigurationValue($key)
{
    $regValue = (Get-ConfigurationValueInRegistry $key)

    if ($regValue -ne $null)
    {
        Write-Host "Registry Option -> " $key $regValue
        return $regValue
    }

    Write-Host "Default Option -> " $key = $ConfigurationValues[$key]

    return $ConfigurationValues[$key]
}

function Set-ConfigurationValue($key, $value)
{
    return (Set-ConfigurationValueInRegistry $key $value)
}

function Remove-ConfigurationValues
{
    Remove-Item $RegistryRootKeyPath
}