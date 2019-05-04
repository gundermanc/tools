# MSBuild tools: Aliases and tools for working with MSBuild
# By: Christian Gunderman

function EnsureMSBuild
{
    if (!(Get-Command msbuild -ErrorAction SilentlyContinue))
    {
        Throw "Path to MSBuild.exe not found. Run vsget to select an instance and vscmd [id] to select a VS dev environment to import."
    }
}

# Builds a project using typical settings.
function Start-MSBuild($project)
{
    EnsureMSBuild
    & msbuild.exe /r /t:build /m $project | & "$Global:FeatureDir\MSBuildErrorList.ps1"
}

# Cleans a project.
function Start-MSClean($project)
{
    EnsureMSBuild
    & msbuild.exe /t:clean /m $project | & "$Global:FeatureDir\MSBuildErrorList.ps1"
}

# Restores a project.
function Start-MSRestore($project)
{
    EnsureMSBuild
    & msbuild.exe /t:restore /m $project | & "$Global:FeatureDir\MSBuildErrorList.ps1"
}

New-Alias -Name msbbuild -Value Start-MSBuild
New-Alias -Name msbclean -Value Start-MSClean
New-Alias -Name msbrestore -Value Start-MSRestore
