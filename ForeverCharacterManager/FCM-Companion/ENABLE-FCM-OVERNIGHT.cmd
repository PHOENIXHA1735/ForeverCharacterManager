@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Enable-FCM-OvernightCatalog.ps1" -RunNow
if errorlevel 1 (
  echo.
  echo Setup did not complete. Review the message above and retry.
)
pause
