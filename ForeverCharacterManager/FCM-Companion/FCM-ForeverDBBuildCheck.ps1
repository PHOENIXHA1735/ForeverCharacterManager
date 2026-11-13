# FCM v0.9.0 - low-cost scheduled ForeverDB build metadata probe.
# NEVER downloads the catalog, exports a key, or modifies a running game.
# Full reference updates remain user-triggered in FCMDataUpdater.ps1 until
# safe unattended updates have been validated on the player's Windows PC.
[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference='Stop'
$base=Split-Path -Parent $MyInvocation.MyCommand.Path
$keyFile=Join-Path $base 'foreverdb-key.dpapi'
$statusFile=Join-Path $base 'fdb-build-status.json'
$settingFile=Join-Path $base 'settings.json'
function Say([string]$msg) { if (-not $Quiet) { Write-Host ('[FCM ForeverDB] '+$msg) } }
function Write-Status($record) {
    $tmp=$statusFile+'.tmp'
    [IO.File]::WriteAllText($tmp,($record | ConvertTo-Json -Depth 4),(New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $statusFile -Force
}
$at=[DateTimeOffset]::UtcNow.ToString('o')
if (-not (Test-Path -LiteralPath $keyFile)) {
    Write-Status ([ordered]@{checkedAt=$at;status='no_key_configured';changed=$false;note='Use the FCM companion to save a personal ForeverDB key. Never distribute that key.'})
    Say 'No private key configured; scheduled build check skipped.'
    return
}
try {
    Add-Type -AssemblyName System.Security
    $cipher=[Convert]::FromBase64String(([IO.File]::ReadAllText($keyFile)).Trim())
    $bytes=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $key=[Text.Encoding]::UTF8.GetString($bytes)
    if (-not $key) { throw 'Key was empty.' }
} catch {
    Write-Status ([ordered]@{checkedAt=$at;status='key_unavailable';changed=$false;note='DPAPI key could not be opened in the current Windows user session.'})
    Say 'Key unavailable to this Windows user; no API call made.'
    return
}
$headers=@{'X-API-Key'=$key;'Accept'='application/json';'User-Agent'='FCM/0.9.0 (+https://github.com/PHOENIXHA1735/ForeverCharacterManager)'}
$endpoint='https://foreverdb.net/api/v1/builds/latest'
try {
    try {
        $reply=Invoke-RestMethod -Uri $endpoint -Headers $headers -Method Get -TimeoutSec 25 -MaximumRedirection 0
    } catch {
        $status=0
        try { $status=[int]$_.Exception.Response.StatusCode } catch {}
        if ($status -ne 404) {throw}
        # Provider also documents /api/v1/meta as a metadata route.
        $endpoint='https://foreverdb.net/api/v1/meta'
        $reply=Invoke-RestMethod -Uri $endpoint -Headers $headers -Method Get -TimeoutSec 25 -MaximumRedirection 0
    }
    $node=$reply
    if ($null -ne $reply.data) { $node=$reply.data }
    $build=''
    foreach ($field in @('build','clientBuild','version','buildNumber')) {
        try {if ($node.$field -and $node.$field -isnot [pscustomobject]) { $build=[string]$node.$field;break }} catch {}
    }
    if (-not $build -and $node.latest) {
        foreach ($field in @('build','clientBuild','version')) {
            try {if ($node.latest.$field) {$build=[string]$node.latest.$field;break}} catch {}
        }
    }
    if (-not $build -or $build.Length -gt 80) {throw 'Build field missing or invalid; no assumed change.'}
    $previous=''
    if (Test-Path -LiteralPath $settingFile) {
        try {
            $config=Get-Content -LiteralPath $settingFile -Raw | ConvertFrom-Json
            if ($config.fdbLastBuild) { $previous=[string]$config.fdbLastBuild }
        } catch {}
    }
    $previousStatus=''
    if (Test-Path -LiteralPath $statusFile) {
        try {
            $old=Get-Content -LiteralPath $statusFile -Raw | ConvertFrom-Json
            if ($old.build) {$previousStatus=[string]$old.build}
        } catch {}
    }
    if (-not $previous) {$previous=$previousStatus}
    $changed=[bool]($previous -and $previous -ne $build)
    $state=if ($changed) {'new_build_available'} elseif ($previous) {'unchanged'} else {'baseline_created'}
    Write-Status ([ordered]@{checkedAt=$at;status=$state;build=$build;previousBuild=$previous;changed=$changed;source='ForeverDB';action=$(if ($changed) {'Open FCM Data Companion, close WoW, and use Scan + Update Data.'} else {'No full download needed.'})})
    Say ('Build '+$build+'; '+$state+'.')
} catch {
    # Never include a URI, HTTP header, or key in exception/status output.
    $code=0
    try {$code=[int]$_.Exception.Response.StatusCode} catch {}
    $reason=if ($code -eq 429) {'rate_limited'} elseif ($code -eq 401 -or $code -eq 403) {'authentication_failed'} elseif ($code) {'http_'+$code} else {'unavailable_or_unrecognized'}
    Write-Status ([ordered]@{checkedAt=$at;status=$reason;changed=$false;source='ForeverDB';note='Old reference data retained. No API credentials logged.'})
    Say ('Build check '+$reason+'; no data overwritten.')
}
