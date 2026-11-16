@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0FCM-AHHistory.ps1" -Mode Disable
pause
