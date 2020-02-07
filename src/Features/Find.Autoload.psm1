# File and Text Search Aliases
# By: Christian Gunderman

<#
.SYNOPSIS
Finds a file with a path name similar to the given pattern.

.PARAMETER pattern
A pattern, such as '*foo*' that is used to match subdirectories of the current dir.
#>

function Find-FilePath($pattern)
{
    (Get-ChildItem -Recurse "$pattern").FullName
}

<#
.SYNOPSIS
Finds text in a file that matches the given pattern.

.PARAMETER pattern
A pattern, such as '*foo*' that is used to match content in files in under the current dir.
#>
function Find-InFiles($pattern)
{
    Get-ChildItem -Recurse | Select-String -SimpleMatch $pattern
}

New-Alias -Name findp -Value Find-FilePath
New-Alias -Name findif -Value Find-InFiles