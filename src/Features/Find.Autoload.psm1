# File and Text Search Aliases
# By: Christian Gunderman

# Finds a file with a path name similar to the given pattern.
function Find-FilePath($pattern)
{
    (Get-ChildItem -Recurse "$pattern").FullName
}

# Finds text in a file that matches the given pattern.
function Find-InFiles($pattern)
{
    Get-ChildItem -Recurse | Select-String -SimpleMatch $pattern
}

New-Alias -Name findp -Value Find-FilePath
New-Alias -Name findif -Value Find-InFiles