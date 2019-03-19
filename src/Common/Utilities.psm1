# Tools Powershell Utility functions
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

    Clear-Host
    Write-Host -ForegroundColor Cyan "PowerShell REPL + Tools $version"
    Write-host "By: Christian Gunderman"
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