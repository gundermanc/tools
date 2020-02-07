# Tools Powershell Configuration
# By: Christian Gunderman

$ShortcutName = "Tools.lnk"
$StandaloneInstallerName = "StandAloneInstaller.bat"
$StartupFile = "Tools.bat"

function New-InstallationPath
{
    $installationDirectory = "Tools"
    return (Join-Path $env:LOCALAPPDATA $installationDirectory)
}

$ConfigurationValues =
@{
    "DisableConsole" = $true
    "InstallationPath" = New-InstallationPath
    "IsInstalled" = $false
    "Version" = "0.55"
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
        Write-Verbose "Registry Option -> $key $regValue"
        return $regValue
    }

    $defaultValue = $ConfigurationValues[$key]

    Write-Verbose "Default Option -> $key = $defaultValue"

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

function Get-InstallationPath
{
    return (Get-ConfigurationValue "InstallationPath")
}

function Get-StartupPath
{
    return (Join-Path (Get-InstallationPath) $StartupFile)
}

function AreToolsInstalled
{
    $installationPath = Get-InstallationPath
    return (($installationPath -ine $null) -and (Test-Path $installationPath))
}

function Install-Tools
{
    function Start-MainProcess
    {
        # Start script in this console.
        & (Get-StartupPath)
        Return
    }

    function Update-Path
    {
        Write-Host "Adding 'tools' to user's path..."
        $systemPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
        $userPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)

        # Create set of items in the system path.
        $systemPathSet = New-Object -TypeName System.Collections.Generic.HashSet[string]
        $systemPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $systemPathSet.Add($_) | Out-Null }

        # Create set of items in the user path.
        $userPathSet = New-Object -TypeName System.Collections.Generic.HashSet[string]
        $userPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { 
            # Avoid re-adding items inherited from the system
            # path to the user path and de-dupe any existing
            # duplicates.
            if (-not $systemPathSet.Contains($_))
            {
                $userPathSet.Add($_) | Out-Null
            }
        }

        # Ensure user path contains installation location.
        $userPathSet.Add($installationPath) | Out-Null

        $updatedUserPath = [string]::Join(";", $userPathSet)
        Write-Host "Updated user path: $updatedUserPath"
        [Environment]::SetEnvironmentVariable("PATH", $updatedUserPath, [EnvironmentVariableTarget]::User)
    }

    function Install-ToolsInternal
    {
        $installationPath = Get-InstallationPath

        if ((AreToolsInstalled $installationPath))
        {
            Write-Host -ForegroundColor Yellow "Already installed to $installationPath"
            Uninstall-Tools
        }

        Write-Host "Installing to $installationPath`n"

        # Record installation directory.
        Write-Host "Saving installation directory..."
        Set-ConfigurationValue "InstallationPath" $installationPath

        # Copy package contents.
        Write-Host "Copying package contents..."
        Copy-Item -Recurse (Get-ClownCarDirectory) $installationPath

        # We're done with the installer Entry script, delete it.
        Write-Host "Deleting installer script."
        Remove-Item (Join-Path $installationPath "Main.psm1")

        # Copy the installer locally so that we have a copy of it.
        Write-Host "Copying the installer to the installation..."
        Copy-Item (Get-ClownCarScriptName) (Join-Path $installationPath $StandaloneInstallerName)

        # Protect the install directory.
        Write-Host "Protecting installation directory..."
        Set-ItemsHiddenAndReadonly $installationPath

        # Create shortcut on the desktop and start menu.
        Write-Host "Creating shortcut..."
        $startupPath = (Get-StartupPath)
        New-Shortcut  $startupPath (Join-Path (Get-DesktopPath) $ShortcutName)
        New-Shortcut  $startupPath (Join-Path (Get-StartMenuPath) $ShortcutName)

        # Add tools to system path.
        Update-Path

        Write-Host -ForegroundColor Green "`nInstall completed"

        # Start main process...
        Write-Host "Starting main process..."
        Start-MainProcess $installationPath
    }

    Write-Host -ForegroundColor Cyan "Beginning installation...`n"
    Install-ToolsInternal
}

function Open-InstallDirectory
{
    $installationPath = Get-InstallationPath
    Start-Process "explorer.exe" $installationPath
}

function Uninstall-Tools
{
    $installationPath = (Get-ConfigurationValue "InstallationPath")

    if (($installationPath -ine $null) -and (Test-Path $installationPath))
    {
        Write-Host -ForegroundColor Cyan "Uninstalling from $installationPath`n"

        # Delete all files.
        Remove-Item -Recurse -Force $installationPath -ErrorAction Stop

        # Delete registry keys.
        Remove-ConfigurationValues

        # Delete shortcuts.
        Remove-Item -Force (Join-Path (Get-DesktopPath) $ShortcutName) -ErrorAction Continue
        Remove-Item -Force (Join-Path (Get-StartMenuPath) $ShortcutName) -ErrorAction Continue

        # Remove tools from system path.
        Write-Host "Removing 'tools' from user's path..."
        $path = [Environment]::GetEnvironmentVariable("PATH")
        [Environment]::SetEnvironmentVariable("PATH", $path.Replace(";$installationPath", ""), [EnvironmentVariableTarget]::User);

        Write-Host -ForegroundColor Green "Uninstallation completed"
    }
    else
    {
        Write-Host -ForegroundColor Yellow "Not yet installed."
    }
}