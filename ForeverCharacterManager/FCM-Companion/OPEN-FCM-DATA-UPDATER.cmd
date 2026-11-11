@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0FCMDataUpdater.ps1"
if errorlevel 1 (
  echo.
  echo The updater could not start. Please send the error above for troubleshooting.
  pause
)
