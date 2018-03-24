# Powershell REPL + Tools Installer Entry Point
# By: Christian Gunderman

Import-Module (Join-Path (Get-ClownCarDirectory) "Common\Config.psm1")
Import-Module (Join-Path (Get-ClownCarDirectory) "Common\Utilities.psm1")

$ExitCommand = "Exit"
$PowerShellCommand = "powershell.exe"
$StandaloneInstallerName = "StandAloneInstaller.bat"
$StartupFile = "PackageMain.ps1"

function Get-InstallationPath
{
    return (Get-ConfigurationValue "InstallationPath")
}

function Are-ToolsInstalled
{
    $installationPath = Get-InstallationPath
    return (($installationPath -ine $null) -and (Test-Path $installationPath))
}

function Install-Tools
{
    function Start-MainProcess($packagePath)
    {
        # Start script in this console.
        Set-Location $packagePath
        & ".\PackageMain.ps1"
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

            # Start main process...
            Write-Host "Starting main process..."
            Start-MainProcess (Join-Path $installationPath $StartupFile)

            Write-Host -ForegroundColor Green "`nInstall completed"
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
    $version = (Get-ConfigurationValue "Version")

    Clear-Host
    Write-Host -ForegroundColor Cyan "PowerShell REPL + Tools $version"
    Write-host "By: Christian Gunderman"
    Write-Host

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
        Install-Subtle
    }
}
