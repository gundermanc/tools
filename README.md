# Windows Application Developer Tools
(C) 2019 Christian Gunderman
Contact Email: gundermanc@gmail.com

## Introduction:
This repo is the current and future home of a self-extracting PowerShell
tools archive that contains a number of useful scripts and aliases for developers
of .NET applications on Windows. It attempts to solve a number of problems including
improving the workflow for creating aliases, robust patching of installed applications,
F5 debugging of patched applications, and easier invocation of MSBuild and Visual Studio.

It was originally created to improve productivity of developers building Visual Studio. ❤

## 'Building'
- Clone the repository recursively
- Update submodules
- Run Build.cmd
- Build produces 'StandaloneInstaller.bat' with packaged scripts.

## 'Installing'
Installation extracts tools to your user directory and creates a shortcut on the desktop
and the Start Menu as well as registering a 'tools' command to your user path.
- Run 'StandaloneInstaller.bat'
- Run Install-Tools

## Using
Tools are in a special custom command prompt called the tools prompt which is added to your
user path. You can enter this prompt in any command prompt by running `tools.bat` in a command
prompt or `tools.ps1` in a Powershell session.

## Tools
### Find
Aliases for finding files and text:
- findp [path]: Searches subdirectory for paths containing [path].
- findif [text]: Searches subdirectory for files containing [text].

### MSBuild
Defines some aliases for MSBuild with a clickable GUI error list
that makes navigating MSBuild spew more pleasant.
- msbbuild: Build with typical settings
- msbclean: Clean project
- msbrestore: Perform Nuget restore.

### Patching applications
Defines some simple commands for backing up, patching, and restoring
installed applications based on a configuration file. This script features
automatic killing of locking processes as well as hash-verification, ensuring
that patch and revert are reliable. It has also experimental support for F5
debugging any VS solution via patch profiles.

Use with Visual Studio
'vspatch' command to patch a VS install.
- ptedit [profile]: Opens the selected profile for editing.
- ptget [profile]: Gets a list of profiles.
- ptapply [profile]: Applies the selected profile.
- ptstatus [profile]: Checks the current target application for patched files.
- ptrevert [profile]: Reverts the current profile's patched binaries.
- ptF5 [vsinstance] [solutionpath] [profile]: Launches the specified instance of VS with the specified solution + profile configured for one-click (F5) debugging.

### Process Snapshot
Defines some convenient scripts and aliases for killing groups of processes
to help get you unblocked if a build executable is locking a file.
- pbunlock [fileName]: Kills all processes that are locking a file.
- pbldmp [profile] [fileName]: Dumps a list of all processes locking the given file into a profile.
- pbget: Gets a list of Process Baseline profiles that you have saved.
- pbnew [profile]: Dumps all active processes to a named profile or 'Default' profile if not specified.
- pbnstop [profile]: Stops all executables except those reference by the given profile or 'Default' profile if not specified.
- pbstop [profile]: Stops all executables referenced by the given profile or 'Default' profile if not specified.
- pbedit [profile]: Opens a named profile for manual editing.

### Navigation aliases
Defines aliases for navigating and opening explorer in named paths.
- nvedit: Opens the list of aliases for editing.
- nvget: Lists all defined aliases.
- nvgo: `cd`s to the given alias or prompts you to define it if undefined.
- nvnew: Defines or redefines an alias.
- nve: Launches a named location in file explorer.

### Visual Studio
Aliases for launching Visual Studio installs developer command prompts.
- vsget: Lists all VS installs and their [instance] number.
- vsstart [instance]: Starts a specific VS instance by its number.
- vsreset [instance]: Wipes a specific VS instance by its number.
- vsconfig [instance]: Updates configuration timestamp on a specific VS.
- vspath [instance]: Opens installation path on a specific VS.
- vscmd [instance]: Launches developer command prompt for a specific VS.
- vspatch [instance]: Selects an instance of VS as the target application for patching.

## ChangeLog
- 6/7/2019 - Fixed killing of locking processes when doing revert. Fixed overwriting of backup when revert fails. Print release notes on startup. Init submodule on build.
- 5/10/2019 - Add 'scratch' to default nav locations.
- 5/4/2019 - Auto updater.
- 5/3/2019 - Fixed dev prompts, fixed some bugs with F5, improved patching reliability, aliases for listing processes locking a file.
- 4/5/2019  - Kills processes locking files during patch operation, verifies hashes on restore, less likely to accidentally delete backups on exception, and enables F5 debugging.
- 3/23/2019 - Fix revert when patch is run multiple times and add navigation aliases.
- 3/20/2019 - Wait for VS config tasks to complete and store scratch outside of install directory.
- 3/19/2019 - Added patching aliases.
- 3/18/2019 - Added many tools and README.
