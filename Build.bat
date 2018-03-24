@echo off

:: Powershell REPL + Tools -> Installer Batch Script Self Extractor Build Script
:: By: Christian Gunderman

:: Build.bat must be run within the src directory.
cd external\clown-car

:: Generate the installer self-extracting batch script.
clown-car.bat ..\..\StandAloneInstaller.bat ..\..\src
