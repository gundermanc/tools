# Application binary patching tool
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

# Invokes a patch profile on a program install.
function Invoke-PatchProfile($patchProfile)
{
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
            $backupFile = "$destinationFile.stockrevision"

            # Create backup file if this is the first time patching this file.
            if (-not (Test-Path $backupFile))
            {
                Write-Host "  - Creating backup of $destinationFile..."
                Copy-Item -Path $destinationFile -Destination $backupFile -Force
            }

            # Copy new file.
            Write-Host "  - Patching $sourceFile with $destinationFile..."
            Copy-Item -Path $sourceFile -Destination $destinationFile -Force
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

    $stockRevisions = Get-ChildItem -Recurse (Join-Path $destinationDirectory "*.stockrevision")
    foreach ($stockRevision in $stockRevisions)
    {
        $originalFileName = $stockRevision.Name.SubString(0, $stockRevision.Name.Length - ".stockrevision".Length)
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

            # Reverting backup file.
            Write-Host "  - Reverting backup of $destinationFile..."
            Copy-Item -Path "$destinationFile.stockrevision" -Destination $destinationFile -Force
            Remove-Item -Path "$destinationFile.stockrevision" -Force
        }
    }

    $commands = $jsonContent.commands
    foreach ($command in $commands)
    {
        Write-Host "- Running > $command"
        Invoke-Expression $command
    }
}

New-Alias -Name ptedit -Value Edit-PatchProfile
New-Alias -Name ptget -Value Get-PatchProfiles
New-Alias -Name ptapply -Value Invoke-PatchProfile
New-Alias -Name ptstatus -Value Get-PatchStatus
New-Alias -Name ptrevert -Value Invoke-RevertPatchProfile
