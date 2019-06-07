@echo off

:: Windows Application Developer Tools
:: By: Christian Gunderman

:: Run our powershell entry point.
powershell.exe -NoExit -ExecutionPolicy Bypass "& '%~dp0\Tools.ps1'"
