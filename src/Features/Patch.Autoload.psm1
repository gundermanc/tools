# Robust Application Patching utility.
# Features profile configuration, patching, reverting, hash validation, and F5 debugging of profiles
# without require projects to be modified.
# By: Christian Gunderman

# Gets a patch profile file path.
function Get-PatchProfilePath($patchProfile)
{
    if ([string]::IsNullOrWhiteSpace($patchProfile))
    {
        if ([string]::IsNullOrWhiteSpace($env:PatchProfile))
        {
            Throw "Must provide a patch profile name argument"
        }

        $patchProfile = $env:PatchProfile
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

function Get-PatchConfiguration($patchProfile)
{
    $patchProfile = (Get-PatchProfilePath $patchProfile)
    $content = (Get-Content $patchProfile)
    $jsonContent = $content | ConvertFrom-Json

    # Define any given environment variables.
    $variables = $jsonContent.variables
    foreach ($file in $variables)
    {
        foreach ($property in $file.PSObject.Properties)
        {
            $name = [string]$property.Name
            $value = [string]$ExecutionContext.InvokeCommand.ExpandString($property.Value)

            if ([string]::IsNullOrEmpty($value))
            {
                Write-Host -ForegroundColor Yellow "Variable $name has empty value"
            }

            Write-Host "Setting variable $name to '$value'..."
            Invoke-Expression "$name = `"$value`""
        }
    }

    # Determine the source directory. Supports environment variables.
    # This line here is for compat with existing profiles. New profiles should set a variable instead.
    if ([string]::IsNullOrWhiteSpace($env:PatchSourceDir))
    {
        $env:PatchSourceDir = $ExecutionContext.InvokeCommand.ExpandString($jsonContent.sourceDirectory)
    }

    Write-Host "Source Directory: $env:PatchSourceDir"
    if ([string]::IsNullOrWhiteSpace($env:PatchSourceDir) -or (-not (Test-Path $env:PatchSourceDir)))
    {
        Throw "Unspecified or inaccessible `$env:PatchSourceDir $env:PatchSourceDir"
    }

    return $jsonContent
}

function Write-PatchSchema
{
    Write-Output @"
Patch schema is as follows:"

{
    "variables": {
        "`$env:EnvVariableName": "value"
    },
    "files": {
        "relative source path": "relative destination path"
    },
    "commands": [
        "Start-Process foo.exe -Wait -ArgumentsList 'So Argumentative'"
    ]
}

variables: Strings that are expanded to PowerShell variables. Use `$env:Foo to
           define environment variables, try `$env:GitRoot to create paths relative
           to the repo root, and try `$env: to reference environment variables.
           
           The following are 'special' variables that light up aliases:

             `$env:PatchBuildCmd - The command to build with prior to patching.

             `$env:PatchSourceDir - The source folder to copy bits from.

             `$env:PatchTargetDir - The destination to patch to. You can optionally
             set this with the vspath alias or your own script.

             `$env:PatchTargetExe - The main executable of the application being
           patched.

files: a dictionary of source -> destination path that are backedup and patched.
                                 Can use environment variables.

commands: an array of PowerShell commands to run after the patch and unpatch.

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

    Set-GitRoot

    $jsonContent = (Get-PatchConfiguration $patchProfile)

    # Determine the destination directory.
    $destinationDirectory = Get-PatchTargetDirectory
    Write-Host "Destination Directory: $destinationDirectory"

    $files = $jsonContent.files
    foreach ($file in $files)
    {
        foreach ($property in $file.PSObject.Properties)
        {
            $sourceFile = (Join-Path $env:PatchSourceDir $ExecutionContext.InvokeCommand.ExpandString($property.Name))
            $destinationFile = (Join-Path $destinationDirectory $ExecutionContext.InvokeCommand.ExpandString($property.Value))
            
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
        $command = $ExecutionContext.InvokeCommand.ExpandString($command)
        Write-Host "- Running > $command"
        Invoke-Expression $command
    }
}

function Get-PatchStatus
{
    Set-GitRoot

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
    Set-GitRoot

    $jsonContent = (Get-PatchConfiguration $patchProfile)

    # Determine the destination directory.
    $destinationDirectory = Get-PatchTargetDirectory
    Write-Host "Destination Directory: $destinationDirectory"

    $files = $jsonContent.files
    foreach ($file in $files)
    {
        foreach ($property in $file.PSObject.Properties)
        {
            $destinationFile = (Join-Path $destinationDirectory $ExecutionContext.InvokeCommand.ExpandString($property.Value))

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
        $command = $ExecutionContext.InvokeCommand.ExpandString($command)
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

    $solutionPath = $ExecutionContext.InvokeCommand.ExpandString($solutionPath)
    if (-not (Test-Path $solutionPath))
    {
        Throw "Unable to find solution at $solutionPath"
    }

    Set-GitRoot

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
    $env:StartAction="Program"
    $env:StartProgram=$env:PatchTargetExe
    $env:PatchProfileName=$patchProfile

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

# Invokes a patch profile build operation.
function Invoke-BuildPatchProfile($patchProfile)
{
    Set-GitRoot

    # Read in variables.
    Get-PatchConfiguration $patchProfile | Out-Null

    if ([string]::IsNullOrEmpty($env:PatchBuildCmd))
    {
        Throw "Must set `$env:PatchBuildCmd prior to using this alias. Consider setting it in your profile 'variables' section."
    }

    # Run the build command.
    Invoke-Expression $env:PatchBuildCmd

    if ($LASTEXITCODE -ne 0)
    {
        Throw "Build failed"
    }
}

# Invokes a patch profile target executable.
function Invoke-RunPatchProfileTarget($patchProfile)
{
    Set-GitRoot

    # Read in variables.
    Get-PatchConfiguration $patchProfile | Out-Null

    if ([string]::IsNullOrEmpty($env:PatchTargetExe))
    {
        Throw "Must set `$env:PatchTargetExe prior to using this alias. Consider using 'vspatch' or setting it in your profile 'variables' section."
    }

    # Run the target executable.
    & $env:PatchTargetExe
}

# Builds, patches, and runs the target of a patch profile.
function Invoke-BuildAndRunPatchProfile($patchProfile)
{
    # Build project.
    Invoke-BuildPatchProfile $patchProfile

    # Patch target.
    Invoke-PatchProfile $patchProfile

    # Run target.
    Invoke-RunPatchProfileTarget $patchProfile
}

# Enables setting a current preferred patch profile.
function Set-CurrentPatchProfile($patchProfile)
{
    # Ensure we have a profile of that name.
    Get-PatchProfilePath $patchProfile | Out-Null

    # Save it for later.
    $env:PatchProfile = $patchProfile
}

New-Alias -Name ptedit -Value Edit-PatchProfile
New-Alias -Name ptget -Value Get-PatchProfiles
New-Alias -Name ptapply -Value Invoke-PatchProfile
New-Alias -Name ptstatus -Value Get-PatchStatus
New-Alias -Name ptrevert -Value Invoke-RevertPatchProfile
New-Alias -Name ptF5 -Value Start-F5InVS
New-Alias -Name ptbuild -Value Invoke-BuildPatchProfile
New-Alias -Name ptrun -Value Invoke-RunPatchProfileTarget
New-Alias -Name ptbuildrun -Value Invoke-BuildAndRunPatchProfile
New-Alias -Name ptuse -Value Set-CurrentPatchProfile
