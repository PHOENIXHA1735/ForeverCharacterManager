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
Write-Output 'PASS: initial copy, deduplication, preservation, UTC/hash metadata, change retention, overlap lock and locked-source cleanup. Synthetic fixture only.'
