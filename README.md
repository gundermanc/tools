# Windows Application Developer Tools
(C) 2019 Christian Gunderman
Contact Email: gundermanc@gmail.com

## Introduction:
This repo is the current and future home of a self-extracting PowerShell
tools archive that contains a number of useful scripts and aliases for developers
of .NET applications on Windows. It attempts to solve a number of problems including
improving the workflow for creating aliases, robust patching of installed applications,
and easier invocation of MSBuild and Visual Studio.

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

## Tools
### Find
Aliases for finding files and text:
- findp [path]: Searches subdirectory for paths containing [path].
- findif [text]: Searches subdirectory for files containing [text].

### MSBuild
Defines some aliases for MSBuild as well as a clickable GUI error list
that makes navigating MSBuild spew more pleasant.
- msbbuild: Build with typical settings
- msbebuild: Build with typical settings and pipe the output into a GUI error list.
- msbclean: Clean project
- msbrestore: Perform Nuget restore.

### Patching applications
Defines some simple commands for backing up, patching, and restoring
installed applications based on a configuration file. Use with Visual Studio
'vspatch' command to patch a VS install.
- ptedit [profile]: Opens the selected profile for editing.
- ptget [profile]: Gets a list of profiles.
- ptapply [profile]: Applies the selected profile.
- ptstatus [profile]: Checks the current target application for patched files.
- ptrevert [profile]: Reverts the current profile's patched binaries.

### Process Snapshot
Defines some convenient scripts and aliases for killing groups of processes
to help get you unblocked if a build executable is locking a file.
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
- 4/5/2019  - Kills processes locking files during patch operation and less likely to accidentally delete backups.
- 3/23/2019 - Fix revert when patch is run multiple times and add navigation aliases.
- 3/20/2019 - Wait for VS config tasks to complete and store scratch outside of install directory.
- 3/19/2019 - Added patching aliases.
- 3/18/2019 - Added many tools and README.
