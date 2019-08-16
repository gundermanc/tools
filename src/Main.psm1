# Windows Application Developer Tools
# By: Christian Gunderman

Import-Module (Join-Path (Get-ClownCarDirectory) "Common\Config.psm1")
Import-Module (Join-Path (Get-ClownCarDirectory) "Common\Utilities.psm1")

$ExitCommand = "Exit"

function Exit-ToolsInstaller
{
    ClownCarCleanupAndExit
}

function ConsoleLoop
{
    Write-VersionInfo

    if (AreToolsInstalled)
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
