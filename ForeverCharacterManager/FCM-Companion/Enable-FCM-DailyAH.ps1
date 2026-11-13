# Run once as the normal Windows user from inside the installed FCM companion.
# Creates a user-level daily task. Does not require GitHub, a token, or elevation.
[CmdletBinding()]
param(
    [ValidateRange(0,23)][int]$Hour=9,
    [ValidateRange(0,59)][int]$Minute=0,
    [switch]$RunNow
)
$ErrorActionPreference='Stop'
$base=Split-Path -Parent $MyInvocation.MyCommand.Path
$scanner=Join-Path $base 'FCM-DailyAHSync.ps1'
if (-not (Test-Path -LiteralPath $scanner)) {throw 'FCM-DailyAHSync.ps1 is missing.'}
if (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $base) 'ForeverCharacterManager.toc'))) {
    throw 'Copy this companion into the installed WoW addon folder before enabling the schedule.'
}
if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw 'Windows Task Scheduler is unavailable in this PowerShell session.'
}
$taskName='FCM Daily Auction House Refresh'
$powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$scanner+'" -Quiet'
$action=New-ScheduledTaskAction -Execute $powershell -Argument $args -WorkingDirectory $base
$time=[DateTime]::Today.AddHours($Hour).AddMinutes($Minute)
$trigger=New-ScheduledTaskTrigger -Daily -At $time
$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -MultipleInstances IgnoreNew
$principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Host "Created '$taskName' for $($time.ToString('HH:mm')) every day, indefinitely."
Write-Host 'The computer must be powered on and you must be signed in. A missed run starts when available.'
Write-Host 'Daily refresh is read-only. It uses current AHledger data, not a long-term price archive.'
Write-Host ('Status file: '+(Join-Path $base 'ah-refresh-status.json'))
if ($RunNow) {
    Write-Host 'Starting the first refresh in Windows Task Scheduler...'
    Start-ScheduledTask -TaskName $taskName
}
