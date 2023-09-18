# Git utilities
# By: Christian Gunderman

function Set-GitRoot()
{
    $env:GitRoot = Get-GitRoot
}

function Get-GitRoot()
{
    if (Get-Command git 2>$null)
    {
        $root =  . git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0)
        {
            return Convert-Path $root
        }
    }
    else
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
    }

    Write-Host -ForegroundColor Yellow "Not a git repository"
}
