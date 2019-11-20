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

    # Ensure that either $env:PatchTargetDir is specified or $env:PatchTargetChooseCmd is so we have a way to
    # prompt the user for the target.
    if ([string]::IsNullOrWhiteSpace($env:PatchTargetDir) -and [string]::IsNullOrWhiteSpace($env:PatchTargetChooseCmd))
    {
        $env:PatchTargetChooseCmd = "ChooseVSInstance"
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

function CheckAssemblyVersions($source, $destination)
{
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

# Creates a packed patch for buddy testing or installation on a demo machine.
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