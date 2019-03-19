@echo off

:: Powershell REPL + Tools Main
:: By: Christian Gunderman

:: Run our powershell entry point.
powershell.exe -NoExit -ExecutionPolicy Bypass "& '%~dp0\PackageMain.ps1'"
