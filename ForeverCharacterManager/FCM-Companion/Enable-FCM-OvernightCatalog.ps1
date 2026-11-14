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
    throw 'The PC time zone is not Pacific. Set Windows to Pacific Time so the 21:00-05:00 local triggers match the Pacific-only safety guard.'
}
$updater=Join-Path $base 'FCMDataUpdater.ps1'
if (-not (Test-Path -LiteralPath $updater)) {throw 'FCMDataUpdater.ps1 is missing.'}
if (-not (Test-Path -LiteralPath (Join-Path $base 'foreverdb-key.dpapi'))) {
    throw 'Save your approved ForeverDB API key with Remember encrypted in the companion first.'
}
$config=Join-Path $base 'settings.json'
if (-not (Test-Path -LiteralPath $config)) {throw 'Configure the game folder in the FCM companion first.'}
$setting=Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
if (-not $setting.gameRoot -or -not (Test-Path -LiteralPath (Join-Path ([string]$setting.gameRoot) 'Interface\AddOns\ForeverCharacterManager\ExternalData.lua'))) {
    throw 'Install FCM in your configured WoW Forever game folder first.'
}

$name='FCM ForeverDB Overnight Catalog'
$exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$args='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$updater+'" -OvernightCatalog'
$action=New-ScheduledTaskAction -Execute $exe -Argument $args -WorkingDirectory $base
$principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 12) -MultipleInstances IgnoreNew

# Exactly 32 daily starts: 21:00, 21:15, ... 04:45 Pacific. 05:00 is
# excluded; a second guard in the updater prevents accidental daytime runs.
$triggers=@()
for ($slot=0; $slot -lt 32; $slot++) {
    $minute=(21*60+15*$slot) % 1440
    $triggers+=New-ScheduledTaskTrigger -Daily -At ([DateTime]::Today.AddMinutes($minute)
}
Register-ScheduledTask -TaskName $name -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Force | Out-Null
Write-Host ('Enabled: '+$name)
Write-Host 'Runs every 15 minutes from 21:00 through 04:45 Pacific, every day.'
Write-Host 'Skips if WoW is running, or your Windows user is signed out / the PC is off.'
Write-Host 'At most 15 ForeverDB requests/minute, 1,200 unattended requests/UTC day; preserves 500 provider-reported daily requests.'
Write-Host 'Results: overnight-catalog-status.json; next in-game reload is needed to see new items.'
Write-Host 'Data from ForeverDB.net: https://foreverdb.net'
if ($RunNow) {
    Start-ScheduledTask -TaskName $name
    Write-Host 'Requested an immediate trial; outside 21:00-05:00 Pacific, the updater will safely skip.'
}
