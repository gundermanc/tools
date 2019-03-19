# PowerShell Tools Self Extractor
(C) 2019 Christian Gunderman
Contact Email: gundermanc@gmail.com

## Introduction:
This repo is the current and future home of a self-extracting PowerShell
tools archive that contains a number of useful scripts and aliases.

## 'Building'
- Clone the repository recursively
- Run Build.cmd
- Build produces 'StandaloneInstaller.bat' with packaged scripts.

## Tools
### Process Snapshot
Defines some convenient scripts and aliases for killing groups of processes
to help get you unblocked if a build executable is locking a file.

- pbget: Gets a list of Process Baseline profiles that you have saved.
- pbnew [profile]: Dumps all active processes to a named profile or 'Default' profile if not specified.
- pbnstop [profile]: Stops all executables except those reference by the given profile or 'Default' profile if not specified.
- pbstop [profile]: Stops all executables referenced by the given profile or 'Default' profile if not specified.
- pbedit [profile]: Opens a named profile for manual editing.

## ChangeLog
- 3/18/2019 - Added Process Snapshot Tools and README and eliminated REPL.