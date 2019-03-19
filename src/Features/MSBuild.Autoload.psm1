# MSBuild tools: Aliases and tools for working with MSBuild
# By: Christian Gunderman

# Builds a project using typical settings.
function Start-MSBuild
{
    & msbuild.exe /t:build /m
}

# Builds a project with a clickable error list that launches in VS.
function Start-MSBuildWithErrorList
{
    & msbuild.exe /t:build /m | & "$Global:FeatureDir\MSBuildErrorList.ps1"
}

# Cleans a project.
function Start-MSClean
{
    & msbuild.exe /t:clean /m
}

# Restores a project.
function Start-MSRestore
{
    & msbuild.exe /t:restore /m
}

New-Alias -Name msbbuild -Value Start-MSBuild
New-Alias -Name msbebuild -Value Start-MSBuildWithErrorList
New-Alias -Name msbclean -Value Start-MSClean
New-Alias -Name msbrestore -Value Start-MSRestore