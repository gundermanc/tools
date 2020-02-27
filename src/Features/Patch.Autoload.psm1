# Robust Application Patching utility.
# Features profile configuration, patching, reverting, hash validation, F5 debugging of profiles,
# packaging of bits to share with others, etc... all without requiring projects to be modified.
# By: Christian Gunderman

Import-Module "$Global:CommonDir\clown-car-packager-api.psm1"

# Gets a patch profile file path.
function Get-PatchProfilePath($patchProfile)
{
    # Patch profile wasn't specified?
    if ([string]::IsNullOrWhiteSpace($patchProfile))
    {
        if ([string]::IsNullOrWhiteSpace($env:PatchProfile))
        {
            Write-Host -ForegroundColor Cyan "Patch profiles:"
            Get-PatchProfiles | Foreach-Object {
                $fileName = $_.Name
                Write-Host "  - $fileName"
            }

            # Prompt the user for one to use for just this instance. They can use ptuse to remember it.
            Write-Host -ForegroundColor Yellow "No patch profile name argument was provided. Run 'ptuse [profile]' to remember a patch profile for this console session"
            Write-Host -Foreground Yellow "Enter a patch profile name:"
            Set-CurrentPatchProfile (Read-Host)
        }

        # Read value from the environment variable.
        $patchProfile = $env:PatchProfile
    }

    return Join-Path $Global:ScratchDir "$patchProfile.patchprofile"
}

# Gets the target directory for the patching operation.
function Get-PatchTargetDirectory
{
    if ([string]::IsNullOrWhiteSpace($env:PatchTargetDir))
    {
        Invoke-Expression $env:PatchTargetChooseCmd

        if ([string]::IsNullOrWhiteSpace($env:PatchTargetDir))
        {
            Throw "Must specify `$env:PatchTargetDir or a `$env:PatchTargetChooseCmd that will set it when run"
        }
    }

    return $env:PatchTargetDir
}

function Get-PatchConfiguration($patchProfile)
{
    $patchProfile = (Get-PatchProfilePath $patchProfile)
    $content = (Get-Content $patchProfile)
    $jsonContent = $content | ConvertFrom-Json

    Write-Host -ForegroundColor Cyan "Setting environment from '$patchProfile'..."

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

            Write-Host "  - Setting variable $name to '$value'..."
            Invoke-Expression "$name = `"$value`""
        }
    }

    # Determine the source directory. Supports environment variables.
    # This line here is for compat with existing profiles. New profiles should set a variable instead.
    if ([string]::IsNullOrWhiteSpace($env:PatchSourceDir))
    {
        $env:PatchSourceDir = $ExecutionContext.InvokeCommand.ExpandString($jsonContent.sourceDirectory)
    }

    Write-Host "  - Source Directory: $env:PatchSourceDir"
    if ([string]::IsNullOrWhiteSpace($env:PatchSourceDir) -or (-not (Test-Path $env:PatchSourceDir)))
    {
        Throw "Unspecified or inaccessible `$env:PatchSourceDir $env:PatchSourceDir"
    }

    # Ensure that either $env:PatchTargetDir is specified or $env:PatchTargetChooseCmd is so we have a way to
    # prompt the user for the target.
    if ([string]::IsNullOrWhiteSpace($env:PatchTargetDir) -and [string]::IsNullOrWhiteSpace($env:PatchTargetChooseCmd))
    {
        $env:PatchTargetChooseCmd = "ChooseVSInstance"
    }

    return $jsonContent
}

<#
.SYNOPSIS
Opens a patch profile for editing.

.PARAMETER patchProfile
Name of the patch profile to open.

.EXAMPLE
Patch schema is as follows:

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

             $env:PatchBuildCmd - The command to build with prior to patching.

             $env:PatchSourceDir - The source folder to copy bits from.

             $env:PatchTargetDir - The destination to patch to. You can optionally
             set this with the vspath alias or your own script.

             $env:PatchTargetExe - The main executable of the application being
             patched.

             $env:PatchDisableVersionCheck - Disables the slow assembly binding
             version check performed before patching .NET assemblies.

             $env:PatchTargetChooseCmd - Enables customization of the 'choose app
             to patch' function. By default, asks which install of Visual Studio.

files: a dictionary of source -> destination path that are backedup and patched.
                                 Can use environment variables.

commands: an array of PowerShell commands to run after the patch and unpatch.

#>
function Edit-PatchProfile($patchProfile)
{
    Write-Host -Foreground Yellow "Run 'Get-help ptedit -Examples' for schema information."
    & notepad.exe (Get-PatchProfilePath $patchProfile)
}

<#
.SYNOPSIS
Gets a list of patch profiles installed on the machine.
#>
function Get-PatchProfiles
{
    Get-ChildItem "$Global:ScratchDir\*.patchprofile"
}

function CheckAssemblyVersions($source, $destination)
{
    # No-op if the patch profile opted out.
    if ($env:PatchDisableVersionCheck -eq $true)
    {
        Write-Host "  - Skipping version check, disabled by PatchDisableVersionCheck environment variable."
        return
    }

    # Do nothing if either file doesn't exist.
    if ((-not (Test-Path $source) -or (-not (Test-Path $destination))))
    {
        return
    }

    # Do nothing if the destination file isn't an executable.
    $destinationExtension = [System.IO.Path]::GetExtension($destination)
    if ($destinationExtension -ine ".dll" -and $destinationExtension -ine ".exe")
    {
        return
    }

    Write-Host "  - Checking that assembly versions match..."

    $powershellPath = (Join-Path $PsHome "powershell.exe")

    # Load assemblies in separate process and check their versions to make sure
    # they match. This is done in a separate process so that the assemblies are
    # unlocked at exit.
    $checkOutput = & $powershellPath -c {
        param($source, $destination)

        try
        {
            $sourceAssembly = [System.Reflection.Assembly]::LoadFrom($source)
            $destinationAssembly = [System.Reflection.Assembly]::LoadFrom($destination)

            $sourceVersion = $sourceAssembly.GetName().Version.ToString()
            $destinationVersion = $destinationAssembly.GetName().Version.ToString()

            if (-not ($sourceVersion -eq $destinationVersion))
            {
                $fileName = [System.IO.Path]::GetFileName($destination)
                Write-Output "Mismatched assembly version for '$fileName'. Original is $destinationVersion, new is $sourceVersion"
                Write-Output "'$fileName' may fail to load unless application has correct binding redirects."
            }
        }
        catch [System.BadImageFormatException]
        {
            # Failed to load or more of the assemblies, most likely due to it being unmanaged.
            # Do nothing.
        }
    } -args $source, $destination

    Write-Host -ForegroundColor Yellow $checkOutput
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

        # Before checking the hash, if there's a backup hash (we've been patched)
        # and the file is a link, this was probably a ptf5. Delete it so we don't
        # write to the link target.
        if ((Get-Item $destinationFile).Attributes -band [IO.FileAttributes]::ReparsePoint)
        {
            Remove-Item -Force $destinationFile
            Copy-Item -Path $stockRevisionFile -Destination $destinationFile -Force
        }
        else
        {
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
                Write-Host -ForegroundColor Yellow "There appears to have been an update. Skipping reverting $destinationFile."
            }
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
        Write-Host -ForegroundColor Red "  - Failed reverting $destinationFile"
        return $false
    }
}

<#
.SYNOPSIS
Applies a patch profile to an application installation.

.PARAMETER patchProfile
The name of the patch profile. If left blank, will prompt or use
result of last call to 'ptuse'.
#>
function Invoke-PatchProfile($patchProfile)
{
    function PatchItem ($sourceFile, $destinationFile)
    {
        $sourceFileName = [System.IO.Path]::GetFileName($sourceFile)
        Write-Host -ForegroundColor Cyan "Applying '$sourceFileName...'"
        $backupFile = "$destinationFile.stockrevision"
        $hashFile = "$destinationFile.updatehash"

        try
        {
            # Ensure directory exists. For simplicity (laziness) unpatch won't delete directories.
            $destinationFileDirectory = ([System.IO.Path]::GetDirectoryName($destinationFile))
            New-Item -ItemType Directory -Force -Path $destinationFileDirectory

            # Item was backed up previously. Revert it.
            # This is done to ensure that files that were updated
            # and backed up again.
            if (Test-Path $hashFile)
            {
                Write-Host "  - Previously patched. Reverting..."
                if (-not (RevertItem $destinationFile))
                {
                    Stop-LockingApp $destinationFile
                    if (-not (RevertItem $destinationFile))
                    {
                        return $false
                    }
                }
            }

            # Print a warning if the managed assembly versions mismatch.
            # In managed applications, this will prevent the assembly from loading
            # unless there are binding redirects.
            CheckAssemblyVersions $sourceFile $destinationFile

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

            Write-Host

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
    Write-Host "  - Destination Directory: $destinationDirectory"

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

<#
.SYNOPSIS
Lists file that have been patched on the target application.
#>
function Get-PatchStatus
{
    # Populate any environment variables that might be needed from the profile.
    Get-PatchConfiguration | Out-Null

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

<#
.SYNOPSIS
Reverts patched changes to the target application.

.PARAMETER patchProfile
The name of the patch profile to use. If empty, will prompt.
#>
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

            $destinationFileName = [System.IO.Path]::GetFileName($destinationFile)
            Write-Host -ForegroundColor Cyan "Reverting '$destinationFileName...'"

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

<#
.SYNOPSIS
Opens a solution in Visual Studio for F5 debugging.

.DESCRIPTION
This script creates backups of all target files and then installs
links into the target directory to replace the files that are patched.

Each build in Visual Studio then updates the targets of the links, causing
the program's linked copies to magically be updated. 'StartProgram' behavior
is injected into the application via 'StartProgram' MSBuild properties
understood by the IDE.

.PARAMETER vsInstance
The number of the VS instance, returned by 'vsget', that will be used 
for editing and debugging.

.PARAMETER solutionPath
The path of the solution to open in Visual Studio.

.PARAMETER patchProfile
The patch profile to apply on build.
#>
function Start-F5InVS($vsInstance, $solutionPath, $patchProfile)
{
    if ([string]::IsNullOrWhiteSpace($vsInstance) -or [string]::IsNullOrWhiteSpace($solutionPath) -or [string]::IsNullOrWhiteSpace($patchProfile))
    {
        Throw "Requires vsinstance, solution path, and patch profile name arguments"
    }

    $solutionPath = $ExecutionContext.InvokeCommand.ExpandString($solutionPath)
    if (-not (Test-Path $solutionPath))
    {
        Throw "Unable to find solution at $solutionPath"
    }

    # HACK: Start by applying the patch profile the normal way. This effectively lets us
    # easily reuse the code we have for creating backups and unlocking locked files to
    # backup all files we'll touch.
    Invoke-PatchProfile($patchProfile)

    Set-GitRoot

    # Check that given patch profile exists. Should throw on error.
    Get-PatchProfilePath($patchProfile)

    # Check that the user has chosen a patch target directory first. Should throw on error.
    $destinationDirectory = Get-PatchTargetDirectory

    # Replace all product files we'll patch with links to build outputs.
    # These links with magically (and invisibly) update the product each time
    # we build.
    Write-Host -ForegroundColor Cyan "Replacing '$patchProfile' files with links..."
    $jsonContent = (Get-PatchConfiguration $patchProfile)
    $files = $jsonContent.files
    foreach ($file in $files)
    {
        foreach ($property in $file.PSObject.Properties)
        {
            $sourceFile = (Join-Path $env:PatchSourceDir $ExecutionContext.InvokeCommand.ExpandString($property.Name))
            $destinationFile = (Join-Path $destinationDirectory $ExecutionContext.InvokeCommand.ExpandString($property.Value))

            $destinationFileDirectory = [System.IO.Path]::GetDirectoryName($destinationFile)
            $destinationFileName = [System.IO.Path]::GetFileName($destinationFile)

            # Create link.
            Push-Location $destinationFileDirectory
            Remove-Item -Path $destinationFile -Force
            New-Item -ItemType SymbolicLink -Name "$destinationFileName" -Value $sourceFile | Out-Null
            Pop-Location 
        }
    }

    # Record old values of env. variables so they can be reverted after VS is launched.
    $oldStartAction=$env:StartAction
    $oldStartProgram=$env:StartProgram

    # Set environment variables that will be read by Microsoft common targets and perform the patch.
    $env:StartAction="Program"
    $env:StartProgram=$env:PatchTargetExe
    $env:PatchProfileName=$patchProfile

    # Start selected Visual Studio instance.
    vsstart $vsInstance $solutionPath

    # Revert env. variable settings so we don't patch on PostBuildEvent for command line builds.
    $env:StartAction=$oldStartAction
    $env:StartProgram=$oldStartProgram
}

<#
.SYNOPSIS
Builds the specified patch profile.

.PARAMETER patchProfile
The name of the patch profile to build.
#>
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


<#
.SYNOPSIS
Launches the target application that we are patching.

.PARAMETER patchProfile
The name of the profile to use.
#>
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

<#
.SYNOPSIS
Builds, patches, and runs the target of a patch profile.

.PARAMETER patchProfile
Name of profile in scratch directory to apply.
#>
function Invoke-BuildAndRunPatchProfile($patchProfile)
{
    # Build project.
    Invoke-BuildPatchProfile $patchProfile

    # Patch target.
    Invoke-PatchProfile $patchProfile

    # Run target.
    Invoke-RunPatchProfileTarget $patchProfile
}

<#
.SYNOPSIS
Enables setting a current preferred patch profile.

.PARAMETER patchProfile
The name (without an extension) of a profile in the scratch directory to use for search.

#>
function Set-CurrentPatchProfile($patchProfile)
{
    # Ensure we have a profile of that name.
    Get-PatchProfilePath $patchProfile | Out-Null

    # Save it for later.
    $env:PatchProfile = $patchProfile

    # Update the title
    $host.ui.RawUI.WindowTitle = "$patchProfile - Windows Application Developer Tools"

    Write-Host
}

<#
.SYNOPSIS
Creates a packed patch for buddy testing or installation on a demo machine.

.PARAMETER patchProfile
Name of a patch profile file in scratch directory to use to pack.

.PARAMETER outputDirectory
Directory to write patch script self-extractor to.
#>
function New-PatchPackage($patchProfile, $outputDirectory)
{
    # Ensure we have a profile of that name.
    $patchProfilePath = Get-PatchProfilePath $patchProfile

    # Create packaging directory.
    $packingDirectoryName = [guid]::NewGuid()
    $tempDirectory = [System.IO.Path]::GetTempPath()
    $packagingDirectory = (Join-Path $tempDirectory $packingDirectoryName)
    New-Item $packagingDirectory -ItemType Container -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Packaging Directory: $packagingDirectory"

    # Determine output directory
    if ([string]::IsNullOrWhiteSpace($outputDirectory))
    {
        $outputDirectory = (Convert-Path .)
    }
    Write-Host "Output directory: $outputDirectory"

    # Copy entrypoint script.
    Write-Host "Copying entrypoint script..."
    Copy-Item -Path "$Global:DependenciesDir\PatchPackageMain.psm1" "$packagingDirectory\main.psm1"

    # Copy common bits.
    Write-Host "Copying Common scripts..."
    New-Item "$packagingDirectory\Common" -ItemType Container -ErrorAction SilentlyContinue | Out-Null
    Copy-Item -Path "$Global:CommonDir\*" "$packagingDirectory\Common" -Force

    # Copy features bits.
    Write-Host "Copying Feature scripts..."
    New-Item "$packagingDirectory\Features" -ItemType Container -ErrorAction SilentlyContinue | Out-Null
    Copy-Item -Path "$Global:FeatureDir\*" "$packagingDirectory\Features" -Force

    # Copy bits to patch.
    Write-Host "Copying bits to patch..."
    $binariesDirectory = "$packagingDirectory\Binaries"
    New-Item $binariesDirectory -ItemType Container -ErrorAction SilentlyContinue | Out-Null
    Set-GitRoot
    $jsonContent = (Get-PatchConfiguration $patchProfile)
    $files = $jsonContent.files
    $updatedFiles = @{}
    foreach ($file in $files)
    {
        foreach ($property in $file.PSObject.Properties)
        {
            $sourceFile = (Join-Path $env:PatchSourceDir $ExecutionContext.InvokeCommand.ExpandString($property.Name))

            # Update file paths to point to the packaged file.
            # NOTE: if there are multiple files with the same name, we'll run into problems here.
            $sourceFileName = [System.IO.Path]::GetFileName($sourceFile)
            Write-Host "Copying $sourceFileName..."
            $updatedFiles["$sourceFileName"] = $property.Value

            Copy-Item $sourceFile $binariesDirectory -Force
        }
    }

    # Copy patch profile, replacing the source directory with the content directory of the package.
    Write-Host "Copying tweaked patch profile..."
    Write-Host $jsonContent.variables.Properties
    $jsonContent.files = $updatedFiles
    $jsonContent.variables | Add-Member -Name "`$env:PatchSourceDir" -Value "`$Global:PSScriptRoot\Binaries" -MemberType NoteProperty -Force
    $patchProfileFileName = [System.IO.Path]::GetFileName($patchProfilePath)
    $serializedJson = $jsonContent | ConvertTo-Json
    Set-Content -Path "$packagingDirectory\$patchProfileFileName" -Value $serializedJson

    # Create package.
    $packageFileName = "$patchProfile.patch.bat"
    Write-ClownCar $packageFileName $packagingDirectory
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
New-Alias -Name ptpack -Value New-PatchPackage