# Visual Studio instances tool: Navigate between, wipe, and debug VS instances
# By: Christian Gunderman

function Start-VSWhere
{
    if (-not (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"))
    {
        Throw "Unable to find 'vswhere.exe'. Is Visual Studio installed?"
    }

    return &"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -prerelease -format json | ConvertFrom-Json
}

# Lists all installed VS instances
function Get-VSInstances
{
    $instances = Start-VSWhere

    Write-Host -ForegroundColor Cyan "Installed VS Instances:"

    $i = 1
    foreach ($instance in $instances)
    {
        $displayName = $instance.displayName
        $installationName = $instance.installationName
        $installationPath = $instance.installationPath
        $nickName = $instance.properties.nickname
        $instanceId = $instance.instanceId

        Write-Host "`n$i): $displayName`n    ->  $installationName`n    ->  $installationPath`n    ->  Nick Name: $nickName`n    ->  Instance Id: $instanceId"

        $i++
    }
}

function Get-VSInstance($instance)
{
    if ([string]::IsNullOrWhiteSpace($instance))
    {
        $instance = 1
    }

    $instances = Start-VSWhere

    if ($instances.Count -lt $instance)
    {
        Throw "Invalid instance number."
    }

    return $instances[$instance - 1]
}

# Starts a VS instance by its number with the specified arguments.
function Start-VSInstanceInternal($instance, $wait, $arguments)
{
    $instance = Get-VSInstance $instance

    $productPath = $instance.productPath

    # There's undoubtedly a better way to do this but figuring out
    # what's going on when creating an array of arguments in Powershell's
    # type-ambiguous world is massive pain. </rant>
    if ($arguments -eq $null)
    {
        if ($wait)
        {
            Start-Process -FilePath $productPath -Wait
        }
        else
        {
            Start-Process -FilePath $productPath
        }
    }
    else
    {
        if ($wait)
        {
            Start-Process -FilePath $productPath -ArgumentList $arguments -Wait
        }
        else
        {
            Start-Process -FilePath $productPath -ArgumentList $arguments
        }
    }
    return
}

# Starts a VS instance by its number with the specified arguments.
function Start-VSInstance($instance, $arguments)
{
    Start-VSInstanceInternal $instance $false $arguments
}

function Reset-VSInstance($instance)
{
    Start-VSInstanceInternal $instance $true /resetuserdata
}

function ConfigureVSInstance($instance)
{
    Start-VSInstanceInternal $instance $true /updateconfiguration
}

# Starts a VS instance's installation path by its number.
function Start-VSInstancePath($instance)
{
    $instance = Get-VSInstance $instance

    Start-Process $instance.installationPath
}

# Starts a VS instance's dev prompt by its number.
function Start-VSInstancePrompt($instance)
{
    $instance = Get-VSInstance $instance

    $installationPath = $instance.installationPath

    Clear-Host

    # Start a new session with both the dev prompt and tools environments.
    & cmd.exe /K "`"$installationPath\Common7\Tools\VsDevCmd.bat`" & `"$Global:FeatureDir\..\Tools.bat`""
}

# Sets patch path to a VS install directory based on its number.
function Set-VSPatchTarget($instanceId)
{
    $instance = Get-VSInstance $instanceId

    # Set the variable listened to by the patch script so that patch knows which VS to update.
    $env:PatchTargetDir = $instance.installationPath

    # Set our target exe so the patch script knows how to start us.
    $env:PatchTargetExe = (Join-Path $env:PatchTargetDir "Common7\IDE\devenv.exe")

    # Apex VS testing framework looks at this environment variable to determine which VS to run against.
    ${env:VisualStudio.InstallationUnderTest.Path} = $env:PatchTargetDir

    Write-Host "Set patch target to #$instanceId`: $env:PatchTargetExe"
}

function ChooseVSInstance
{
    Write-Host -ForegroundColor Yellow "Must specify application/instance to patch by setting `$env:PatchTargetDir"
    Write-Host "Falling back to asking for VS version..."
    Write-Host

    # List VS instances
    Write-Host -ForegroundColor Cyan Choose VS instance to patch
    Get-VSInstances

    # Set VS instance
    $instance = Read-Host
    Set-VSPatchTarget $instance

    # Ensure user made a valid selection.
    if ([string]::IsNullOrEmpty($env:PatchTargetDir))
    {
        Throw "Must specify application/instance to patch by setting `$env:PatchTargetDir"
    }
}

New-Alias -Name vsget -Value Get-VSInstances
New-Alias -Name vsstart -Value Start-VSInstance
New-Alias -Name vsreset -Value Reset-VSInstance
New-Alias -Name vsconfig -Value ConfigureVSInstance
New-Alias -Name vspath -Value Start-VSInstancePath
New-Alias -Name vscmd -Value Start-VSInstancePrompt
New-Alias -Name vspatch -Value Set-VSPatchTarget
