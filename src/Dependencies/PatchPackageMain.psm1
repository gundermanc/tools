# Patch package entry point
# By: Christian Gunderman

# Define content directory.
$Global:PSScriptRoot = Get-ClownCarDirectory

Import-Module "$Global:PSScriptRoot\Common\Componentization.psm1" | Out-Null

$profilePath = (Get-ChildItem "$Global:PSScriptRoot\*.patchprofile").FullName
$profileName = [System.Io.Path]::GetFileNameWithoutExtension($profilePath)

# Treat the content directory as the scratch directory for all commands.
$Global:ScratchDir = $Global:PSScriptRoot

# Set the included patch profile as the default one for all patch commands.
$env:PatchProfile = $profileName

function done
{
    ClownCarCleanupAndExit
}

function Write-Help
{
    Write-Host -ForegroundColor Cyan "Self-extracting application patch tool"
    Write-Host "By: Christian Gunderman"
    Write-Host

    Write-Host -ForegroundColor Cyan "Applies profile: $profileName"
    Write-Host

    Write-Host -ForegroundColor Cyan "Updates files:"
    (Get-ChildItem "$Global:PSScriptRoot\Binaries\*").Name | Foreach-Object { Write-Host " - $_" }
    Write-Host

    Write-Host -ForegroundColor Cyan "Commands:"
    Write-Host " - ptapply - installs to this computer."
    Write-Host " - ptrevert - uninstalls from this computer."
    Write-Host " - ptstatus - lists modifications made to this computer."
    Write-Host " - done - terminates the prompt"
    Write-Host
}

function ConsoleLoop
{
    Write-Help

    do
    {
        Write-Host -NoNewline "Patch> "
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
    $args = Get-ClownCarArguments

    if ($args.Length -eq 0)
    {
        ConsoleLoop
    }
    else
    {
        $argString = [string]::Join(" ", $args)
        Write-Host "Received arguments: $argString"
        
        # In remote patching scenarios, caller wants to just call functions
        # that were packed up.
        Invoke-Expression $argString
    }

    ClownCarCleanupAndExit
}
