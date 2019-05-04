# MSBuild tools: Aliases and tools for working with MSBuild
# By: Christian Gunderman

# Builds a project using typical settings.
function Start-MSBuild($project)
{
    & msbuild.exe /r /t:build /m $project
}

# Builds a project with a clickable error list that launches in VS.
function Start-MSBuildWithErrorList($project)
{
    & msbuild.exe /t:build /m $project | & "$Global:FeatureDir\MSBuildErrorList.ps1"
}

# Cleans a project.
function Start-MSClean($project)
{
    & msbuild.exe /t:clean /m $project
}

# Restores a project.
function Start-MSRestore($project)
{
    & msbuild.exe /t:restore /m $project
}

New-Alias -Name msbbuild -Value Start-MSBuild
New-Alias -Name msbebuild -Value Start-MSBuildWithErrorList
New-Alias -Name msbclean -Value Start-MSClean
New-Alias -Name msbrestore -Value Start-MSRestore