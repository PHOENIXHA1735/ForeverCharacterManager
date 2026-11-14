# Register a local, user-scoped, read-only ForeverDB catalog refresh task.
# No credentials are placed in Task Scheduler arguments or exported to GitHub.
[CmdletBinding()]
param([switch]$RunNow)

$ErrorActionPreference='Stop'
$base=Split-Path -Parent $MyInvocation.MyCommand.Path
$addon=Split-Path -Parent $base
if (-not (Test-Path -LiteralPath (Join-Path $addon 'ForeverCharacterManager.toc'))) {
    throw 'Run from the installed WoW Interface\AddOns\ForeverCharacterManager\FCM-Companion folder.'
}
if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw 'Windows Task Scheduler cmdlets are required. Use Windows PowerShell 5.1.'
}
if ([TimeZoneInfo]::Local.Id -ne 'Pacific Standard Time') {
    throw 'The PC time zone is not Pacific. Set Windows to Pacific Time so the 22:00-12:00 local triggers match the Pacific-only safety guard.'
}
$updater=Join-Path $base 'FCMDataUpdater.ps1'
if (-not (Test-Path -LiteralPath $updater)) {throw 'FCMDataUpdater.ps1 is missing.'}
if (-not (Test-Path -LiteralPath (Join-Path $base 'ForeverDB.Quota.ps1'))) {throw 'ForeverDB.Quota.ps1 is missing.'}
if (-not (Test-Path -LiteralPath (Join-Path $base 'foreverdb-key.dpapi'))) {
    throw 'Save your approved ForeverDB API key with Remember encrypted in the companion first.'
}
$config=Join-Path $base 'settings.json'
if (-not (Test-Path -LiteralPath $config)) {throw 'Configure the game folder in the FCM companion first.'}
$setting=Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
if (-not $setting.gameRoot -or -not (Test-Path -LiteralPath (Join-Path ([string]$setting.gameRoot) 'Interface\AddOns\ForeverCharacterManager\ExternalData.lua'))) {
    throw 'Install FCM in your configured WoW Forever game folder first.'
}

$exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$args='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$updater+'" -OvernightCatalog'
$action=New-ScheduledTaskAction -Execute $exe -Argument $args -WorkingDirectory $base
$principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 12) -MultipleInstances IgnoreNew

# Exactly 56 daily starts: 22:00, 22:15, ... 11:45 Pacific. Windows Task
# Scheduler allows 48 triggers per task, so split the window into two tasks.
# Both jobs use the same cross-process quota and catalog locks.
$windows=@(
    @{name='FCM ForeverDB Overnight Catalog';startHour=22;slots=28},
    @{name='FCM ForeverDB Morning Catalog';startHour=5;slots=28}
)
foreach ($window in $windows) {
    $triggers=@()
    for ($slot=0; $slot -lt $window.slots; $slot++) {
        $minute=($window.startHour*60+15*$slot) % 1440
        $triggers+=New-ScheduledTaskTrigger -Daily -At ([DateTime]::Today.AddMinutes($minute)
    }
    Register-ScheduledTask -TaskName $window.name -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Force | Out-Null
    Write-Host ('Enabled: '+$window.name+' ('+$triggers.Count+' daily starts).')
}
Write-Host 'Runs every 15 minutes from 22:00 through 11:45 Pacific, every day.'
Write-Host 'Skips if WoW is running, or your Windows user is signed out / the PC is off.'
Write-Host 'At most 15 ForeverDB requests/minute, 4,500 combined FCM manual + scheduled requests/UTC day; preserves 500 provider-reported daily requests.'
Write-Host 'Results: overnight-catalog-status.json; next in-game reload is needed to see new items.'
Write-Host 'Data from ForeverDB.net: https://foreverdb.net'
if ($RunNow) {
    Start-ScheduledTask -TaskName 'FCM ForeverDB Overnight Catalog'
    Write-Host 'Requested an immediate trial; outside 22:00-12:00 Pacific, the updater will safely skip.'
}
