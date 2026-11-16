@echo off
setlocal
echo FCM - Create AH scan history folders only
echo This will not copy any AHledger file or schedule any task.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-FCM-AHHistory.ps1"
if errorlevel 1 (
    echo.
    echo Setup did not finish. Read the error above.
) else (
    echo.
    echo AHHistory folder setup completed.
)
echo.
pause
