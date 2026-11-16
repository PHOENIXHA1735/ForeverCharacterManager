@echo off
setlocal
echo FCM R6.1 - Inventory and Vendor Cleanup Test Installer
echo World of Warcraft must be fully closed before continuing.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-FCM-R61-Cleanup.ps1"
echo.
pause
