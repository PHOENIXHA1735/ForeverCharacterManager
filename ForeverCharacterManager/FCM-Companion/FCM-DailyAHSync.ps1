# FCM v0.9.0 - scheduled current Auction House refresh (not an AH game scan)
# Personal-use AHledger integration. Downloads current prices only, never an archive.
# The source response's Cache-Control max-age controls expiration. No credentials.
[CmdletBinding()]
param(
    [ValidateSet('','normal','pvp','rp','rppvp')][string]$Ruleset = '',
    [ValidateSet('','us','eu','cn')][string]$Region = '',
    [ValidateSet('Run','Purge','Fixture')][string]$Mode = 'Run',
    [string]$FixtureFolder = '',
    [switch]$Quiet
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$companion = Split-Path -Parent $MyInvocation.MyCommand.Path
$addon = Split-Path -Parent $companion
if (-not (Test-Path -LiteralPath (Join-Path $addon 'ForeverCharacterManager.toc'))) {
    throw 'Run from the FCM-Companion folder INSIDE an installed ForeverCharacterManager addon.'
}
$cacheFile = Join-Path $addon 'AHPrices.generated.lua'
$statusFile = Join-Path $companion 'ah-refresh-status.json'
$credit = 'Prices from AHledger (ahledger.com); https://ahledger.com'
$now = [DateTimeOffset]::UtcNow
function Say([string]$message) { if (-not $Quiet) { Write-Host ('[FCM AH] ' + $message) } }
function Save-Status($obj) {
    # No character names, game account data, raw price tables, or credentials are logged.
    $tmp = "$statusFile.tmp"
    [IO.File]::WriteAllText($tmp,($obj | ConvertTo-Json -Depth 5),(New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $statusFile -Force
}
function Read-Expires($path) {
    if (-not (Test-Path -LiteralPath $path)) {return 0L}
    try {
        $h = @(Get-Content -LiteralPath $path -TotalCount 10 -ErrorAction Stop)
        $line = @($h | Where-Object {$_ -match '^-- FCM-AH-EXPIRES-UNIX:\s*(\d+)$'} | Select-Object -First 1)
        if ($line.Count -gt 0 -and $line[0] -match '(\d+)$') {return [long]$Matches[1]}
    } catch {}
    return 0L
}
if ($Mode -eq 'Purge') {
    if (Test-Path -LiteralPath $cacheFile) {
        $expires = Read-Expires $cacheFile
        if ($expires -eq 0 -or $expires -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
            Remove-Item -LiteralPath $cacheFile -Force
            Say 'Expired current-price cache deleted. No history was archived.'
        }
    }
    return
}
# Derive the faction pair from the selected market, not from a hard-coded realm.
if (-not $Ruleset -or -not $Region) {
    $setting = Join-Path $companion 'settings.json'
    if (Test-Path -LiteralPath $setting) {
        try {
            $cfg = Get-Content -LiteralPath $setting -Raw | ConvertFrom-Json
            if ([string]$cfg.market -match '^forever\.(normal|pvp|rp|rppvp)\.(alliance|horde)\.(us|eu|cn)$') {
                if (-not $Ruleset) {$Ruleset=$Matches[1]}
                if (-not $Region) {$Region=$Matches[3]}
            }
        } catch { Say 'Companion settings unreadable; using default market pair.' }
    }
}
if (-not $Ruleset) {$Ruleset='normal'}
if (-not $Region) {$Region='us'}
# Syntax deliberately avoids importing untrusted PowerShell scripts or evaluating API data.
$markets = @("forever.$Ruleset.alliance.$Region","forever.$Ruleset.horde.$Region")
$results = @{}
$failed = @()
foreach ($market in $markets) {
    try {
        $uri = 'https://api.ahledger.com/v1/pricetable/' + $market
        if ($Mode -eq 'Fixture') {
            if (-not $FixtureFolder) {throw 'Fixture mode requires -FixtureFolder'}
            $path=Join-Path $FixtureFolder ($market+'.txt')
            $payload=Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            $maxAge=300
        } else {
            $response=Invoke-WebRequest -Uri $uri -Method Get -Headers @{'Accept'='text/plain';'User-Agent'='FCM-DailyAHSync/0.9.0'} -UseBasicParsing -TimeoutSec 45 -MaximumRedirection 0
            if ([int]$response.StatusCode -ne 200) {throw ('HTTP ' + [int]$response.StatusCode)}
            $payload=[string]$response.Content
            $cacheControl=[string]$response.Headers['Cache-Control']
            if ($cacheControl -notmatch '(?i)(?:^|[, ])max-age\s*=\s*(\d+)') {
                throw 'Response lacks cache max-age; cannot retain prices safely.'
            }
            $maxAge=[int]$Matches[1]
            if ($maxAge -le 60) {throw 'Provider cache lifetime is too short for a safe scheduled export.'}
        }
        $lines=@($payload -split "`n")
        if ($lines.Count -gt 60000) {throw 'Unexpectedly large price table.'}
        $header=($lines[0] -replace "`r",'').Trim()
        $expectedMarket=$market.Replace('.','/')
        $prefix='AHL1|'+$expectedMarket+'|'
        if (-not $header.StartsWith($prefix,[System.StringComparison]::Ordinal)) {
            throw 'Unexpected API format or market in price table.'
        }
        $fields=$header.Split('|')
        if ($fields.Length -lt 4 -or $fields[2] -notmatch '^\d{9,13}$' -or $fields[3] -notmatch '^\d+$') {
            throw 'Invalid source snapshot metadata.'
        }
        $rows=New-Object 'System.Collections.Generic.List[string]'
        $ids=New-Object 'System.Collections.Generic.HashSet[int]'
        foreach ($line in $lines | Select-Object -Skip 1) {
            $p=($line -replace "`r",'').Trim()
            if ($p -notmatch '^\d+:') {continue}
            $parts=$p.Split(':')
            if ($parts.Length -lt 5 -or $parts.Length -gt 12) {continue}
            $id=0; $median=0L; $low=0L
            if (-not [int]::TryParse($parts[0],[ref]$id) -or $id -le 0 -or $id -gt 9999999) {continue}
            if (-not [long]::TryParse($parts[1],[ref]$median) -or $median -le 0) {continue}
            if (-not $ids.Add($id)) {continue}
            [void][long]::TryParse($parts[2],[ref]$low)
            $m7=0L; $m30=0L; $qty=0L; $sold10=0L
            [void][long]::TryParse($parts[3],[ref]$qty)
            [void][long]::TryParse($parts[4],[ref]$m7)
            if ($parts.Length -gt 5) {[void][long]::TryParse($parts[5],[ref]$m30)}
            if ($parts.Length -gt 8) {[void][long]::TryParse($parts[8],[ref]$sold10)}
            $items=@('median='+$median, 'minBuyout='+[Math]::Max(0,$low), 'quantity='+[Math]::Max(0,$qty))
            if ($m7 -gt 0) {$items+=('median7d='+$m7)}
            if ($m30 -gt 0) {$items+=('median30d='+$m30)}
            if ($sold10 -ge 0 -and $parts.Length -gt 8 -and $parts[8] -ne '') {$items+=('soldPerDay='+([double]$sold10/10.0).ToString('0.0',[Globalization.CultureInfo]::InvariantCulture))}
            $rows.Add('FCM.externalData.pricesByMarket["'+$market+'"]['+$id+']={' +($items -join ',')+',market="'+$market+'"}')
        }
        if ($rows.Count -lt 1) {throw 'Price table had no valid priced items; retaining prior unexpired cache.'}
        $results[$market]=@{rows=$rows;observedAt=[long]$fields[2];maxAge=$maxAge;count=$rows.Count}
        Say "$market`: $($rows.Count) currently priced items received."
    } catch {
        $failed+=($market+': '+$_.Exception.Message)
        Say ($market+': unavailable ('+$_.Exception.Message+').')
    }
}
if ($results.Count -ne 2) {
    Save-Status ([ordered]@{runAt=$now.ToString('o');result='failed';markets=$markets;errors=$failed;note='No fabricated data; previous cache retained only until its expiration.'})
    throw 'Both faction price tables are required. Previous unexpired cache unchanged.'
}
$expires= [long]::MaxValue
foreach ($m in $markets) {
    $e=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+[long]$results[$m].maxAge
    if ($e -lt $expires) {$expires=$e}
}
$out=New-Object System.Text.StringBuilder
[void]$out.AppendLine('-- FCM-AH-EXPIRES-UNIX: '+$expires)
[void]$out.AppendLine('-- Generated current-price cache; erase after API cache expiry. NOT a price archive.')
[void]$out.AppendLine('local _, FCM = ...')
[void]$out.AppendLine('FCM.externalData=FCM.externalData or {}')
[void]$out.AppendLine('FCM.externalData.pricesByMarket=FCM.externalData.pricesByMarket or {}')
[void]$out.AppendLine('FCM.externalData.dailyAHRuleSet="'+$Ruleset+'"')
[void]$out.AppendLine('FCM.externalData.dailyAHRegion="'+$Region+'"')
[void]$out.AppendLine('FCM.externalData.dailyAHCredit="'+$credit+'"')
[void]$out.AppendLine('FCM.externalData.dailyAHExpiresAt='+$expires)
foreach ($market in $markets) {
    [void]$out.AppendLine('FCM.externalData.pricesByMarket["'+$market+'"]={}')
    $r=$results[$market]
    foreach ($row in $r.rows) {
        $entry=$row.Replace('}',',expiresAt='+$expires+',observedAt="'+[DateTimeOffset]::FromUnixTimeSeconds([long]$r.observedAt).ToString('yyyy-MM-ddTHH:mm:ssZ')+'"}')
        [void]$out.AppendLine($entry)
    }
}
# Schedule automatic removal at the real source-cache expiration. If Task
# Scheduler cannot arrange deletion, don't keep a copy beyond source TTL.
if ($Mode -ne 'Fixture') {
    try {
        $purgeName='FCM AH Current Cache Expiration'
        $psExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $purgeArgs='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$MyInvocation.MyCommand.Path+'" -Mode Purge -Quiet'
        $purgeAction=New-ScheduledTaskAction -Execute $psExe -Argument $purgeArgs -WorkingDirectory $companion
        $purgeWhen=[DateTimeOffset]::FromUnixTimeSeconds($expires).LocalDateTime.AddSeconds(15)
        $purgeTrigger=New-ScheduledTaskTrigger -Once -At $purgeWhen
        $purgeSettings=New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
        $purgePrincipal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $purgeName -Action $purgeAction -Trigger $purgeTrigger -Settings $purgeSettings -Principal $purgePrincipal -Force | Out-Null
    } catch {throw 'Could not schedule source-cache expiry cleanup; refusing to retain API data: '+$_.Exception.Message}
}
$tmp="$cacheFile.tmp"
[IO.File]::WriteAllText($tmp,$out.ToString(),(New-Object System.Text.UTF8Encoding($false)))
Move-Item -LiteralPath $tmp -Destination $cacheFile -Force
$marketCounts=@{}
foreach ($market in $markets) {$marketCounts[$market]=$results[$market].count}
Save-Status ([ordered]@{runAt=$now.ToString('o');result='success';source='AHledger';credit=$credit;markets=$marketCounts;cacheExpiresAt=[DateTimeOffset]::FromUnixTimeSeconds($expires).ToString('o');note='Current listings only. No long-term AH price archive. Reload WoW to view refreshed data.'})
Say ('Current-price cache updated; source cache expires at '+[DateTimeOffset]::FromUnixTimeSeconds($expires).ToLocalTime().ToString('g'))
