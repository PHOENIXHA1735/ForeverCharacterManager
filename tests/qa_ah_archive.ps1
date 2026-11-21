$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script=Join-Path $repo 'ForeverCharacterManager\FCM-Companion\FCM-AHHistory.ps1'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('fcm-synthetic-'+[Guid]::NewGuid().ToString('N'))
$addon=Join-Path $fixture 'Interface\AddOns\ForeverCharacterManager'
$sourceDir=Join-Path $fixture 'sources'
New-Item -ItemType Directory -Path $addon,$sourceDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $addon 'ForeverCharacterManager.toc') -Value '## Synthetic'
$source=Join-Path $sourceDir 'AHledger.lua'
Set-Content -LiteralPath $source -Value 'AHledgerDB = { synthetic = true }'
$before=(Get-FileHash -LiteralPath $source).Hash
& $script -AddonRoot $addon -Sources @($source) -SkipAnalysis
& $script -AddonRoot $addon -Sources @($source) -SkipAnalysis
$archives=@(Get-ChildItem -LiteralPath (Join-Path $addon 'AHHistory\RawScans') -Recurse -Filter '*.lua')
if ($archives.Count -ne 1) { throw 'Duplicate archive created' }
if ((Get-FileHash -LiteralPath $source).Hash -ne $before) { throw 'Source modified' }
$meta=Get-Content -LiteralPath ($archives[0].FullName+'.json') -Raw | ConvertFrom-Json
if ($meta.sha256 -ne $before -or [DateTime]::Parse($meta.archivedUtc).ToUniversalTime() -gt [DateTime]::UtcNow) { throw 'Metadata incorrect' }
Add-Content -LiteralPath $source -Value '-- synthetic change'
& $script -AddonRoot $addon -Sources @($source) -SkipAnalysis
if (@(Get-ChildItem -LiteralPath (Join-Path $addon 'AHHistory\RawScans') -Recurse -Filter '*.lua').Count -ne 2) { throw 'Changed source not retained' }
$lock=[IO.File]::Open((Join-Path $addon 'AHHistory\Index\archive.lock'),'Open','ReadWrite','None')
try { & $script -AddonRoot $addon -Sources @($source) -SkipAnalysis } finally { $lock.Dispose() }
$input=[IO.File]::Open($source,'Open','ReadWrite','None')
try {
    try { & $script -AddonRoot $addon -Sources @($source) -SkipAnalysis; throw 'Expected locked source failure' }
    catch { if ($_.Exception.Message -notmatch 'Archival errors') { throw } }
} finally { $input.Dispose() }
if (@(Get-ChildItem -LiteralPath (Join-Path $addon 'AHHistory\Incoming') -File).Count) { throw 'Incomplete copy published' }
# Provider table retention requires an explicit opt-in, even for named input.
$providerSource=Join-Path $sourceDir 'AHledger_Data.lua'
Set-Content -LiteralPath $providerSource -Value 'AHledgerData = { synthetic = true }'
try {
    & $script -AddonRoot $addon -Sources @($providerSource) -SkipAnalysis
    throw 'Expected non-opted-in provider-table archival to be refused'
} catch {
    if ($_.Exception.Message -notmatch 'Archival errors') { throw }
}
$providerDir=Join-Path $addon 'AHHistory\MarketTables'
if (@(Get-ChildItem -LiteralPath $providerDir -Recurse -Filter '*.lua').Count -ne 0) {
    throw 'Provider table copied without explicit retention opt-in'
}
& $script -AddonRoot $addon -Sources @($providerSource) -IncludeProviderTables -SkipAnalysis
if (@(Get-ChildItem -LiteralPath $providerDir -Recurse -Filter '*.lua').Count -ne 1) {
    throw 'Explicit synthetic provider-table opt-in did not work'
}
$disableProbe=@{Called=$false}
function Disable-ScheduledTask { param($TaskName,$ErrorAction) if ($TaskName -ne 'FCM-AHHistory') { throw 'Wrong task' }; $disableProbe.Called=$true }
& $script -AddonRoot $addon -Mode Disable
if (-not $disableProbe.Called -or @(Get-ChildItem -LiteralPath (Join-Path $addon 'AHHistory\RawScans') -Recurse -Filter '*.lua').Count -ne 2) { throw 'Disable changed archive contents' }
# Exercise the hidden-launcher contract with a synthetic PowerShell target.
# This never runs the real archiver through WScript or touches a user's WoW files.
$launcher=Join-Path $repo 'ForeverCharacterManager\FCM-Companion\FCM-AHHistory-Hidden.vbs'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'Hidden AHHistory launcher absent' }
$enableSource=[IO.File]::ReadAllText($script)
if ($enableSource -notmatch 'FCM-AHHistory-Hidden\.vbs' -or $enableSource -notmatch 'wscript\.exe' -or $enableSource -notmatch 'launcherMode') {
    throw 'Enable mode must register the fixed-mode hidden launcher'
}
$probeCompanion=Join-Path $addon 'FCM-Companion'
New-Item -ItemType Directory -Path $probeCompanion -Force | Out-Null
$probeLauncher=Join-Path $probeCompanion 'FCM-AHHistory-Hidden.vbs'
Copy-Item -LiteralPath $launcher -Destination $probeLauncher
@'
param([string]$Mode, [string]$AddonRoot, [switch]$IncludeProviderTables)
if ($Mode -ne 'Sync') { exit 91 }
if (-not (Test-Path -LiteralPath (Join-Path $AddonRoot 'ForeverCharacterManager.toc'))) { exit 92 }
if (Test-Path -LiteralPath (Join-Path $AddonRoot 'launcher-error.flag')) { exit 9 }
$label=if ($IncludeProviderTables) { 'provider' } else { 'personal' }
[IO.File]::WriteAllText((Join-Path $AddonRoot 'launcher-probe.txt'),$label)
exit 0
'@ | Set-Content -LiteralPath (Join-Path $probeCompanion 'FCM-AHHistory.ps1') -Encoding UTF8
$wscript=Join-Path $env:SystemRoot 'System32\wscript.exe'
if (-not (Test-Path -LiteralPath $wscript)) { throw 'Windows Script Host unavailable to test hidden launcher' }
& $wscript '//B' '//NoLogo' $probeLauncher 'personal'
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $addon 'launcher-probe.txt') -Raw).Trim() -ne 'personal') {
    throw 'Personal mode did not invoke the fixed synthetic target correctly'
}
& $wscript '//B' '//NoLogo' $probeLauncher 'provider'
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $addon 'launcher-probe.txt') -Raw).Trim() -ne 'provider') {
    throw 'Explicit provider mode failed to propagate opt-in'
}
$failureFlag=Join-Path $addon 'launcher-error.flag'
Set-Content -LiteralPath $failureFlag -Value 'synthetic-failure'
& $wscript '//B' '//NoLogo' $probeLauncher 'personal'
if ($LASTEXITCODE -ne 9) { throw 'Hidden launcher did not forward child PowerShell failure' }
Remove-Item -LiteralPath $failureFlag
& $wscript '//B' '//NoLogo' $probeLauncher 'unexpected'
if ($LASTEXITCODE -ne 64) { throw 'Hidden launcher accepted an unexpected mode' }
Remove-Item -LiteralPath (Join-Path $probeCompanion 'FCM-AHHistory.ps1')
& $wscript '//B' '//NoLogo' $probeLauncher 'personal'
if ($LASTEXITCODE -ne 2) { throw 'Missing target script must return exit code 2' }
Write-Output 'PASS: fixed-mode hidden AHHistory launcher, opt-in routing, invalid-mode refusal and exit codes (synthetic fixture).'

Write-Output 'PASS: initial copy, deduplication, preservation, UTC/hash metadata, change retention, overlap lock and locked-source cleanup. Synthetic fixture only, including provider opt-in.'
