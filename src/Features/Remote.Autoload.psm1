# Experimental tool for Patching apps on Remote Machines
# By: Christian Gunderman

# NOTE: currently only works with patching Visual Studio. Needs to be generalized.

<#
.SYNOPSIS
Sets the name of the machine to patch.

.PARAMETER machineName
The name of the machine to patch.
#>
function Set-TargetMachine($machineName)
{
    $env:PatchTargetMachine = $machineName
}

<#
.SYNOPSIS
Gets the target machine that will be used for patching.
#>
function Get-TargetMachine
{
    # If user hasn't specified a machine name, prompt for one.
    if ([string]::IsNullOrWhiteSpace($env:PatchTargetMachine))
    {
        Write-Host -ForegroundColor Yellow "No machine name was set with 'ptrtarget'. Please enter machine name: "
        $machineName = Read-Host
        Set-TargetMachine $machineName
    }

    return $env:PatchTargetMachine
}


<#
.SYNOPSIS
Builds and patches the target of a patch profile on a remote machine.

.PARAMETER patchProfile
Name of a patch profile in the scratch directory to apply to remote machine.

#>
function Invoke-BuildAndPatchProfile($patchProfile)
{
    # Build project.
    Invoke-BuildPatchProfile $patchProfile

    # Patch target.
    Invoke-PatchProfileOnMachine $patchProfile
}

<#
.SYNOPSIS
Invokes a patch profile on a remote machine.

.PARAMETER patchProfile
Name of a patch profiel in the scratch directory.

.NOTES
Currently only tested to work with machines that are authenticated to the
same Active Directory user ID.
#>
function Invoke-PatchProfileOnMachine($patchProfile)
{
    $targetMachine = Get-TargetMachine

    if ([string]::IsNullOrEmpty($launch))
    {
        $launch = $false
    }

    # Pack up the selected profile's bits into a self-extracting package.
    # This is done to ensure functionality like killing of processes works.
    Write-Host -ForegroundColor Cyan "Packing up patch into self-extracting batch script..."
    New-PatchPackage($patchProfile)
    $patchPackage = "$patchProfile.patch.bat"
    Write-Host "Wrote $patchPackage"

    # Log in to remote machine.
    Write-Host -ForegroundColor Cyan "Logging into remote machine..."
    $session = New-PSSession -ComputerName $targetMachine

    # Copy patch to target machine. Assume the user has privileges through the domain.
    # TODO: support username and password?
    Write-Host -ForegroundColor Cyan "Copying lastapplied.patch.bat to remote machine's desktop..."
    $patchDestinationPath = (Join-Path (Join-Path $env:USERPROFILE Desktop) "lastapplied.patch.bat")
    Copy-Item -Path $patchPackage -Destination $patchDestinationPath -ToSession $session

    # Ask for VS instance to patch.
    # TODO: abstract away to work with non-VS apps.
    Write-Host -Foreground Cyan "Listing patchable VS installs..."
    Invoke-Command -Session $session -ScriptBlock {
        param($patchDestinationPath)
        & $patchDestinationPath "vsget"
    } -ArgumentList $patchDestinationPath
    Write-Host -ForegroundColor Cyan "Which VS instance number would you like to patch?"
    $id = Read-Host
    Write-Host "Selected #$id" 

    # Apply patch to remote machine.
    Write-Host -Foreground Cyan "Applying patch to remote machine..."
    Invoke-Command -Session $session -ScriptBlock {
        param($patchDestinationPath, $id)
        & $patchDestinationPath "vspatch $id;ptapply;done"
    } -ArgumentList $patchDestinationPath,$id
}

New-Alias -Name ptrtarget -Value Set-TargetMachine
New-Alias -Name ptrapply -Value Invoke-PatchProfileOnMachine
New-Alias -Name ptrbuildapply -Value Invoke-BuildAndPatchProfile
