# Powershell REPL + Tools Installer Entry Point
# By: Christian Gunderman

Import-Module (Join-Path (Get-ClownCarDirectory) "Common\Config.psm1")
Import-Module (Join-Path (Get-ClownCarDirectory) "Common\Utilities.psm1")

$ExitCommand = "Exit"
$PowerShellCommand = "powershell.exe"
$ShortcutName = "Tools.lnk"
$StandaloneInstallerName = "StandAloneInstaller.bat"
$StartupFile = "Tools.bat"

function Get-InstallationPath
{
    return (Get-ConfigurationValue "InstallationPath")
}

function Get-StartupPath
{
    return (Join-Path (Get-InstallationPath) $StartupFile)
}

function Are-ToolsInstalled
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

    function Install-ToolsInternal
    {
        $installationPath = Get-InstallationPath

        if (-not (Are-ToolsInstalled $installationPath))
        {
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
            Write-Host "Adding 'tools' to user's path..."
            $path = [Environment]::GetEnvironmentVariable("PATH")
            [Environment]::SetEnvironmentVariable("PATH", "$path;$installationPath", [EnvironmentVariableTarget]::User);

            Write-Host -ForegroundColor Green "`nInstall completed"

            # Start main process...
            Write-Host "Starting main process..."
            Start-MainProcess $installationPath
        }
        else
        {
            Write-Host -ForegroundColor Yellow "Already installed to $installationPath"
            Write-Host -ForegroundColor Red "`nInstall failed"
        }
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

function Exit-ToolsInstaller
{
    ClownCarCleanupAndExit
}

function ConsoleLoop
{
    Write-VersionInfo

    if (Are-ToolsInstalled)
    {
        Write-Host "Installed" -ForegroundColor Green
    }
    else
    {
        Write-Host "Not installed" -ForegroundColor Yellow
    }

    Write-Host "Install-Tools - installs to this computer."
    Write-Host "Uninstall-Tools - removes an existing installation."
    Write-Host "Open-InstallDirectory - opens the installation directory."
    Write-Host "Exit-ToolsInstaller - terminates the prompt"
    Write-Host

    do
    {
        Write-Host -NoNewline "ToolsInstaller> "
        $command = Read-Host

        if (($command -ine $ExitCommand) -and ($command -ine ""))
        {
            Invoke-Expression $command
        }
    }
    while ($command -ine $ExitCommand)
}

function Main
{
    # Start command console, if not disabled in the configuration.
    if (-not (Get-ConfigurationValue "DisableConsole"))
    {
        ConsoleLoop
        ClownCarCleanupAndExit
    }
    else
    {
        Install-Tools
    }
}
