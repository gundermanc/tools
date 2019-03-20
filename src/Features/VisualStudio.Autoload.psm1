# Visual Studio instances tool: Navigate between, wipe, and debug VS instances
# By: Christian Gunderman

function Start-VSWhere
{
    if (-not (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"))
    {
        Write-Output -Foreground Yellow "Unable to find 'vswhere.exe'. Is Visual Studio installed?"
    }

    return &"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -prerelease
}

# Lists all installed VS instances
function Get-VSInstances
{
    $output = Start-VSWhere

    $installationName = ""
    $installationPath = ""
    $displayName = ""

    $i = 1
    foreach ($line in $output)
    {
        if ($line.StartsWith("installationName:"))
        {
            $installationName = $line.Substring("installationName:".Length).Trim()
        }

        if ($line.StartsWith("installationPath:"))
        {
            $installationPath = $line.Substring("installationPath:".Length).Trim()
        }

        if ($line.StartsWith("displayName:"))
        {
            $displayName = $line.Substring("displayName:".Length).Trim()
            Write-Output "`n$i): $displayName`n    ->  $installationName`n    ->  $installationPath"
            $i++
        }
    }
}

# Starts a VS instance by its number with the specified arguments.
function Start-VSInstance($instance, $arguments)
{
    if ([string]::IsNullOrWhiteSpace($instance))
    {
        $instance = 1
    }

    $output = Start-VSWhere

    $i = 1
    foreach ($line in $output)
    {
        if ($line.StartsWith("productPath: "))
        {
            if ($i -eq $instance)
            {
                & $line.Substring("productPath: ".Length).Trim() $arguments
                return
            }
            $i++
        }
    }
}

function Reset-VSInstance($instance)
{
    Start-VSInstance $instance /resetuserdata
}

function Configure-VSInstance($instance)
{
    Start-VSInstance $instance /updateconfiguration
}

# Starts a VS instance's installation path by its number.
function Start-VSInstancePath($instance)
{
    if ([string]::IsNullOrWhiteSpace($instance))
    {
        $instance = 1
    }

    $output = Start-VSWhere

    $i = 1
    foreach ($line in $output)
    {
        if ($line.StartsWith("installationPath: "))
        {
            if ($i -eq $instance)
            {
                start $line.Substring("installationPath: ".Length).Trim()
                return
            }
            $i++
        }
    }
}

# Starts a VS instance's dev prompt by its number.
function Start-VSInstancePrompt($instance)
{
    if ([string]::IsNullOrWhiteSpace($instance))
    {
        $instance = 1
    }

    $output = Start-VSWhere

    $i = 1
    foreach ($line in $output)
    {
        if ($line.StartsWith("installationPath: "))
        {
            if ($i -eq $instance)
            {
                $installationPath = $line.Substring("installationPath: ".Length).Trim()

                Write-Host -Foreground Yellow "Importing Developer Command Prompt environment...`n`n"
                & "$installationPath\Common7\Tools\VsDevCmd.bat"
                return
            }
            $i++
        }
    }
}

# Starts a VS instance's dev prompt by its number.
function Start-VSInstanceAppData($instance)
{
    if ([string]::IsNullOrWhiteSpace($instance))
    {
        $instance = 1
    }

    $output = Start-VSWhere

    $i = 1
    foreach ($line in $output)
    {
        if ($line.StartsWith("installationPath: "))
        {
            if ($i -eq $instance)
            {
                $installationPath = $line.Substring("installationPath: ".Length).Trim()

                Write-Host -Foreground Yellow "Importing Developer Command Prompt environment...`n`n"
                & "$installationPath\Common7\Tools\VsDevCmd.bat"
                return
            }
            $i++
        }
    }
}

# Sets patch path to a VS install directory based on its number.
function Set-VSPatchTarget($instance)
{
    if ([string]::IsNullOrWhiteSpace($instance))
    {
        $instance = 1
    }

    $output = Start-VSWhere

    $i = 1
    foreach ($line in $output)
    {
        if ($line.StartsWith("installationPath: "))
        {
            if ($i -eq $instance)
            {
                $env:PatchTargetDir = $line.Substring("installationPath: ".Length).Trim()
                return
            }
            $i++
        }
    }
}


New-Alias -Name vsget -Value Get-VSInstances
New-Alias -Name vsstart -Value Start-VSInstance
New-Alias -Name vsreset -Value Reset-VSInstance
New-Alias -Name vsconfig -Value Configure-VSInstance
New-Alias -Name vspath -Value Start-VSInstancePath
New-Alias -Name vscmd -Value Start-VSInstancePrompt
New-Alias -Name vspatch -Value Set-VSPatchTarget
