# Registers two independent Windows Task Scheduler jobs for this FCM install.
# The Auction House job pulls AHledger current prices. The ForeverDB job
# checks build metadata only; it does not invoke a full catalog import.
# Run as the Windows user whose ForeverDB DPAPI key was saved by FCM.
[CmdletBinding()]
param(
    [ValidateSet(30,60)][int]$AuctionMinutes=30,
    [ValidateSet(12,24)][int]$ForeverDBHours=12,
    [switch]$RunNow
)
$ErrorActionPreference='Stop'
$base=Split-Path -Parent $MyInvocation.MyCommand.Path
$addon=Split-Path -Parent $base
if (-not (Test-Path -LiteralPath (Join-Path $addon 'ForeverCharacterManager.toc'))) {
    throw 'Install and run from the FCM-Companion folder inside WoW Interface\AddOns\ForeverCharacterManager.'
}
if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw 'Windows Task Scheduler is unavailable. Use Windows PowerShell 5.1.'
}
$ahScript=Join-Path $base 'FCM-DailyAHSync.ps1'
$fdbScript=Join-Path $base 'FCM-ForeverDBBuildCheck.ps1'
foreach ($path in @($ahScript,$fdbScript)) { if (-not (Test-Path -LiteralPath $path)) {throw ('Required script missing: '+(Split-Path -Leaf $path))} }
$exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal=New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
# Windows Task Scheduler supports minute/hour repetition triggers. A ten-year
# trigger is used to avoid short expiration; rerunning this installer renews it.
$tenYears=New-TimeSpan -Days 3650
# AHledger's own Sync application owns its current-price cache and refresh
# intervals. The former FCM background price-export task is removed rather than
# bypassing the provider's short Cache-Control lifetime.
foreach ($obsolete in @('FCM Auction House Price Refresh','FCM Daily Auction House Refresh')) {
    $task=Get-ScheduledTask -TaskName $obsolete -ErrorAction SilentlyContinue
    if ($task) { Unregister-ScheduledTask -TaskName $obsolete -Confirm:$false; Write-Host ('Removed obsolete: '+$obsolete) }
}
$name='FCM ForeverDB Build Check'
$args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$fdbScript+'" -Quiet'
$action=New-ScheduledTaskAction -Execute $exe -Argument $args -WorkingDirectory $base
$trigger=New-ScheduledTaskTrigger -Once -At ([DateTime]::Now.AddMinutes(2)) -RepetitionInterval (New-TimeSpan -Minutes ($ForeverDBHours*60)) -RepetitionDuration $tenYears
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Host ('Enabled: '+$name+'; every '+($ForeverDBHours*60)+' minutes.')
Write-Host 'Auction House: install AHledger + AHledger Sync for provider-managed 30-minute price refreshes.'
Write-Host 'FCM consumes AHledgerAPI while in game; no FCM AH Windows task is created.'
Write-Host 'Runs only while signed into Windows. Game login is not required for metadata/price downloads.'
Write-Host 'AHledger Sync is separate from your ForeverDB key and API allowance.'
Write-Host 'The ForeverDB job makes at most a build-metadata GET per check, not a full data import.'
Write-Host 'Status: fdb-build-status.json in FCM-Companion. AHledger Sync handles its own prices.'
if ($RunNow) {
    Start-ScheduledTask -TaskName $name
    Write-Host 'First ForeverDB build check started.'
}
