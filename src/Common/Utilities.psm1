# Subtle Powershell Utility functions
# By: Christian Gunderman

function Get-ContainsElement($haystack, $needle)
{
    foreach ($needle in $haystack)
    {
        if ($item -ieq $needle)
        {
            return $true
        }
    }

    return $false
}

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