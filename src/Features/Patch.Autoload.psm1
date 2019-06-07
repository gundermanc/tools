# Robust Application Patching utility.
# Features profile configuration, patching, reverting, hash validation, and F5 debugging of profiles
# without require projects to be modified.
# By: Christian Gunderman

# Gets a patch profile file path.
function Get-PatchProfilePath($patchProfile)
{
    if ([string]::IsNullOrWhiteSpace($patchProfile))
    {
        Throw "Must provide a patch profile name argument"
    }

    return Join-Path $Global:ScratchDir "$patchProfile.patchprofile"
}

# Gets the target directory for the patching operation.
function Get-PatchTargetDirectory
{
    if ([string]::IsNullOrWhiteSpace($env:PatchTargetDir))
    {
        Write-Host -ForegroundColor Yellow "For patching instances of VS, use vsget to find an instance, and vspatch to set it as the current."
        Throw "Must define `$env:PatchTargetDir prior to patching."
    }

    return $env:PatchTargetDir
}

function Write-PatchSchema
{
    Write-Output @"
Patch schema is as follows:"

{
    "sourceDirectory": "",
    "files": {
        "relative source path": "relative destination path"
    },
    "commands": [
        "foo.exe"
    ]
}

"@
}

# Opens a patch profile for editing.
function Edit-PatchProfile($patchProfile)
{
    Write-PatchSchema
    & notepad.exe (Get-PatchProfilePath $patchProfile)
}

# Gets a list of known process baselines.
function Get-PatchProfiles
{
    Get-ChildItem "$Global:ScratchDir\*.patchprofile"
}

function RevertItem($destinationFile)
{
    $stockRevisionFile = "$destinationFile.stockrevision"
    $updateHashFile = "$destinationFile.updatehash"

    # Reverting backup file.
    Write-Host "  - Reverting backup of $destinationFile..."
    try
    {
        # Nothing to revert.
        if (-not (Test-Path $updateHashFile))
        {
            return $true
        }

        # Ensure that the patched file hash matches the one we saved when we performed
        # the patch. This eliminates the possibility that the application being updated
        # could overwrite the patched bits and then be wiped out by 'reverting'.
        $destinationHash = (Get-FileHash $destinationFile).Hash
        if ($destinationHash -eq (Get-Content $updateHashFile))
        {
            # This file may not exist if the patch script copied it over for the first time.
            if ((Test-Path $stockRevisionFile))
            {
                Copy-Item -Path $stockRevisionFile -Destination $destinationFile -Force
            }
            else
            {
                Remove-Item $destinationFile
            }
        }
        else
        {
            Write-Host -ForegroundColor Yellow "Hash file mismatch. There appears to have been an update. Skipping $destinationFile"
        }

        # This file may not exist if the patch script copied it over for the first time.
        if ((Test-Path $stockRevisionFile))
        {
            Remove-Item -Path $stockRevisionFile -Force
        }
        Remove-Item -Path $updateHashFile -Force

        return $true
    }
    catch
    {
        ## Do this in a try catch so a failure to revert doesn't cause backup to be deleted.
        Write-Host -ForegroundColor Red "Failed reverting $destinationFile"
        return $false
    }
}

# Invokes a patch profile on a program install.
function Invoke-PatchProfile($patchProfile)
{
    function PatchItem ($sourceFile, $destinationFile)
    {
        $backupFile = "$destinationFile.stockrevision"
        $hashFile = "$destinationFile.updatehash"

        try
        {
            # Item was backed up previously. Revert it.
            # This is done to ensure that files that were updated
            # and backed up again.
            if (Test-Path $hashFile)
            {
                Write-Host "Previously patched. Reverting..."
                if (-not (RevertItem $destinationFile))
                {
                    Stop-LockingApp $destinationFile
                    if (-not (RevertItem $destinationFile))
                    {
                        return $false
                    }
                }
            }

            if (Test-Path $destinationFile)
            {
                Write-Host "  - Creating backup of $destinationFile..."
                Copy-Item -Path $destinationFile -Destination $backupFile -Force
            }
            else
            {
                Write-Host -ForegroundColor Yellow "$destinationFile did not exist in destination directory prior to this or a previous patch operation"
            }

            # Save new file hash. This enables us to check before reverting
            # so we don't accidentally 'revert' to the wrong bits if the
            # product is updated and then the user tries to revert.
            (Get-FileHash $sourceFile).Hash | Set-Content -Path $hashFile

            # Copy new file.
            Write-Host "  - Patching $destinationFile with $sourceFile..."
            Copy-Item -Path $sourceFile -Destination $destinationFile -Force

            return $true
        }
        catch
        {
            # Perform patch in a try-catch so that we don't modify anything
            # if the backup fails.
            Write-Host -ForegroundColor Red "Failed to patch $destinationFile"
            return $false
        }
    }

    $patchProfile = (Get-PatchProfilePath $patchProfile)
    $content = (Get-Content $patchProfile)
    $jsonContent = $content | ConvertFrom-Json

    # Determine the source directory.
    $sourceDirectory = $jsonContent.sourceDirectory
    Write-Host "Source Directory: $sourceDirectory"
    if ([string]::IsNullOrWhiteSpace($sourceDirectory) -or (-not (Test-Path $sourceDirectory)))
    {
        Throw "Unspecified or inaccessible sourceDirectory $sourceDirectory"
    }

    # Determine the destination directory.
    $destinationDirectory = Get-PatchTargetDirectory
    Write-Host "Destination Directory: $destinationDirectory"

    $files = $jsonContent.files
    foreach ($file in $files)
    {
        foreach ($property in $file.PSObject.Properties)
        {
            $sourceFile = (Join-Path $sourceDirectory $property.Name)
            $destinationFile = (Join-Path $destinationDirectory $property.Value)
            
            if (-not (PatchItem $sourceFile $destinationFile))
            {
                Stop-LockingApp $destinationFile
                PatchItem $sourceFile $destinationFile
            }
        }
    }

    $commands = $jsonContent.commands
    foreach ($command in $commands)
    {
        Write-Host "- Running > $command"
        Invoke-Expression $command
    }
}

function Get-PatchStatus
{
    # Determine the destination directory.
    $destinationDirectory = Get-PatchTargetDirectory
    Write-Output "Destination Directory: $destinationDirectory"

    Write-Output "The following files have been patched:"

    $updatehashes = Get-ChildItem -Recurse (Join-Path $destinationDirectory "*.updatehash")
    foreach ($updateHash in $updatehashes)
    {
        $originalFileName = $updateHash.Name.SubString(0, $updateHash.Name.Length - ".updatehash".Length)
        Write-Host "  - $originalFileName"
    }
}

# Invokes a patch profile revert on a program install.
function Invoke-RevertPatchProfile($patchProfile)
{
    $patchProfile = (Get-PatchProfilePath $patchProfile)
    $content = (Get-Content $patchProfile)
    $jsonContent = $content | ConvertFrom-Json

    # Determine the destination directory.
    $destinationDirectory = Get-PatchTargetDirectory
    Write-Host "Destination Directory: $destinationDirectory"

    $files = $jsonContent.files
    foreach ($file in $files)
    {
        foreach ($property in $file.PSObject.Properties)
        {
            $destinationFile = (Join-Path $destinationDirectory $property.Value)

            if (-not (RevertItem $destinationFile))
            {
                Stop-LockingApp $destinationFile
                RevertItem $destinationFile
            }
        }
    }

    $commands = $jsonContent.commands
    foreach ($command in $commands)
    {
        Write-Host "- Running > $command"
        Invoke-Expression $command
    }
}

# Opens a solution + patch profile in Visual Studio for F5 debugging.
function Start-F5InVS($vsInstance, $solutionPath, $patchProfile)
{
    if ([string]::IsNullOrWhiteSpace($vsInstance) -or [string]::IsNullOrWhiteSpace($solutionPath) -or [string]::IsNullOrWhiteSpace($patchProfile))
    {
        Throw "Requires vsinstance, solution path, and patch profile name"
    }

    if (-not (Test-Path $solutionPath))
    {
        Throw "Unable to find solution at $solutionPath"
    }

    # Check that given patch profile exists. Should throw on error.
    Get-PatchProfilePath($patchProfile)

    # Check that the user has chosen a patch target directory first. Should throw on error.
    Get-PatchTargetDirectory

    # Record old values of env. variables so they can be reverted after VS is launched.
    $oldStartAction=$env:StartAction
    $oldStartProgram=$env:StartProgram
    $oldPatchProfileName=$env:PatchProfileName
    $oldPostBuildEvent = $env:PostBuildEvent

    # Set environment variables that will be read by Microsoft common targets and perform the patch.
    # TODO: PatchTargetExe should be configurable in the profile.
    $env:StartAction="Program"
    $env:StartProgram=$env:PatchTargetExe
    $env:PatchProfileName="search"

    $powershellPath = (Join-Path $PsHome "powershell.exe")
    $toolsPath = (Join-Path (Join-Path $Global:FeatureDir "..") "Tools.ps1")

    # Inject post build event action into Visual Studio.
    # Note: this may not work if props or targets imported before us makes use of this feature.
    $env:RunPostBuildEvent="OnBuildSuccess"
    $env:PostBuildEvent="$powershellPath -c $toolsPath;ptapply $patchProfile"

    # Start selected Visual Studio instance.
    vsstart $vsInstance $solutionPath

    # Revert env. variable settings so we don't patch on PostBuildEvent for command line builds.
    $env:StartAction=$oldStartAction
    $env:StartProgram=$oldStartProgram
    $env:PatchProfileName=$oldPatchProfileName
    $env:PostBuildEvent=$oldPostBuildEvent
}

New-Alias -Name ptedit -Value Edit-PatchProfile
New-Alias -Name ptget -Value Get-PatchProfiles
New-Alias -Name ptapply -Value Invoke-PatchProfile
New-Alias -Name ptstatus -Value Get-PatchStatus
New-Alias -Name ptrevert -Value Invoke-RevertPatchProfile
New-Alias -Name ptF5 -Value Start-F5InVS
