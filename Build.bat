@echo off

:: Windows Application Developer Tools -> Installer Batch Script Self Extractor Build Script
:: By: Christian Gunderman

git submodule init
git submodule update

:: Include Clown-car in the package. It's used by some of the features.
copy external\clown-car\resources\clown-car-packager-api.psm1 src\Common

:: Build.bat must be run within the src directory.
cd external\clown-car

:: Generate the installer self-extracting batch script.
clown-car.bat ..\..\StandAloneInstaller.bat ..\..\src
