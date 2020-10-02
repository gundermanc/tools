﻿# Tools Powershell Utility functions
# By: Christian Gunderman

function Wait-ForAnyKey
{
    Write-Host -ForegroundColor Yellow "Press any key to continue..."
    [void]$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Set-ItemsHiddenAndReadonly($path)
{
    function Set-FileHiddenAndReadonly($item)
    {
        Write-Host "Setting $item hidden and readonly"
        $item.Attributes = ([System.IO.FileAttributes]::Hidden,[System.IO.FileAttributes]::ReadOnly)
    }

    # Hide and set install items to read only.
    Set-FileHiddenAndReadonly (Get-Item $path)
    (Get-ChildItem -Recurse $path) | foreach { Set-FileHiddenAndReadonly $_ }
}

function Write-VersionInfo
{
    $version = (Get-ConfigurationValue "Version")

    Write-Host "-------------------------------------------------------------------"
    Write-Host -ForegroundColor Cyan "  Windows Application Developer Tools $version"
    Write-Host
    Write-host "  By: Christian Gunderman"
    Write-Host "-------------------------------------------------------------------"
    Write-Host
}

function Get-DesktopPath
{
    return [Environment]::GetFolderPath("Desktop")
}

function Get-StartMenuPath
{
    return [Environment]::GetFolderPath("StartMenu")
}

function New-Shortcut($targetFilePath, $shortcutPath)
{
    Write-Host "Creating shortcut $shortcutPath -> $targetFilePath"
    $wscriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $wscriptShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $targetFilePath
    $shortcut.Save()
}

function Set-Title([string]$additionalInfo)
{
    $title = "Windows Application Developer Tools"

    if (-not [string]::IsNullOrWhiteSpace($additionalInfo))
    {
        $title = $additionalInfo + " - " + $title
    }

    if ([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544"))
    {
        $title = "ADMIN - " + $title
    }
    
    $host.ui.RawUI.WindowTitle = $title
}

function InstallUpdates
{
    function DownloadAndInstallUpdate($url) {
        try
        {
            Write-Host -ForegroundColor Cyan Downloading update...
            $client = New-Object system.net.WebClient
            $updateFileName = [System.IO.Path]::GetTempFileName()
            $updateFileName += ".bat"
            $client.DownloadFile("$url", $updateFileName);

            & $updateFileName
            exit
        }
        catch
        {
            Write-Host -ForegroundColor Red "Failed to download update from $url"
        }        
    }
    Write-Host -ForegroundColor Cyan "Checking for updates..."
    $version = (Get-ConfigurationValue "Version")
    $result = (Invoke-RestMethod https://api.github.com/repos/gundermanc/tools/releases)

    if ($result.Length -gt 0)
    {
        $latestRelease = $result[0]
        if (![string]::IsNullOrWhiteSpace($latestRelease.tag_name))
        {
            $latestVersion = 0.0
            try
            {
                $latestVersion = [float]::Parse($latestRelease.tag_name);
            }
            catch
            {
                Write-Host -ForegroundColor Yellow "Failed to decode latest release version number."
            }

            if ($latestVersion -gt [float]::Parse($version))
            {
                Write-Host -ForegroundColor Yellow "`nUpdate available! ... $releaseName ... From $version to $latestVersion `n"
                Start-Sleep -Seconds 2
                DownloadAndInstallUpdate($latestRelease.assets[0].browser_download_url)
            }
            else
            {
                Write-Host -ForegroundColor Green "Up to date!"
            }

            $releaseName = $latestRelease.name
            Write-Host -ForegroundColor Yellow "`nCurrent Release: $releaseName version $version"
            Write-Host $latestRelease.body
            Write-Host
            Write-Host Install link:  $latestRelease.html_url
            Write-Host

            return
        }
    }

    Write-Host -ForegroundColor Red "Check for updates failed."
}