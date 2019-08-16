# Git utilities
# By: Christian Gunderman

function Set-GitRoot()
{
    $env:GitRoot = Get-GitRoot
}

function Get-GitRoot()
{
    $currentDirectory = Convert-Path .
    $lastIndex = $currentDirectory.LastIndexOf('\')

    while ($lastIndex -ne -1)
    {
        if (Test-Path (Join-Path $currentDirectory ".git") -PathType Container)
        {
            return $currentDirectory
        }

        $currentDirectory = $currentDirectory.Substring(0, $lastIndex)
        $lastIndex = $currentDirectory.LastIndexOf('\')
    }

    Write-Host -ForegroundColor Yellow "Not a git repository"
}
