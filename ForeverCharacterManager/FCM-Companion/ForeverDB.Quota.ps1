# Shared, local ForeverDB request budget for every FCM companion entry point.
# This file never contains an API key, player record, or raw HTTP response.
# Count attempts BEFORE transmission; even failed requests consume our budget.
# Keep the ledger independent of where the companion was launched (installed
# AddOns directory versus an extracted test ZIP) for this Windows user.
$script:ForeverDBQuotaRoot=if ($env:LOCALAPPDATA) {Join-Path $env:LOCALAPPDATA 'ForeverCharacterManager'} else {$script:Base}
$script:ForeverDBBudgetPath=Join-Path $script:ForeverDBQuotaRoot 'foreverdb-request-budget.json'
$script:ForeverDBLegacyBudgetPath=Join-Path $script:Base 'overnight-catalog-budget.json'
$script:ForeverDBPriorBudgetPath=Join-Path $script:Base 'foreverdb-request-budget.json'
$script:ForeverDBBackoffPath=Join-Path $script:ForeverDBQuotaRoot 'foreverdb-request-backoff.json'
$script:ForeverDBPriorBackoffPath=Join-Path $script:Base 'foreverdb-request-backoff.json'
$script:ForeverDBLegacyBackoffPath=Join-Path $script:Base 'overnight-catalog-backoff.json'
$script:ForeverDBDailyCap=4500
$script:ForeverDBRequestSpacingMs=4000

function Write-FCMForeverDBAtomicJson([string]$path,$record) {
    $parent=Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent)) {New-Item -ItemType Directory -Path $parent -Force | Out-Null}
    $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temp,($record | ConvertTo-Json -Compress),(New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $path) {
            # Atomic file replacement prevents a crash between unlink/rename
            # from resetting today's request count back to zero.
            [IO.File]::Replace($temp,$path,$null)
        } else {[IO.File]::Move($temp,$path)}
    } finally {
        if (Test-Path -LiteralPath $temp) {Remove-Item -LiteralPath $temp -Force}
    }
}

function Test-FCMForeverDBBackoff {
    foreach ($path in @($script:ForeverDBBackoffPath,$script:ForeverDBPriorBackoffPath,$script:ForeverDBLegacyBackoffPath)) {
        if (-not (Test-Path -LiteralPath $path)) {continue}
        try {
            $record=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $until=[DateTime]::Parse([string]$record.untilUtc).ToUniversalTime()
            if ([DateTime]::UtcNow -lt $until) {return $true}
        } catch {return $true} # Do not bypass an unreadable provider cooldown.
    }
    return $false
}
function Set-FCMForeverDBBackoff([int]$seconds) {
    $seconds=[Math]::Max(60,$seconds)
    $record=[ordered]@{untilUtc=[DateTime]::UtcNow.AddSeconds($seconds).ToString('o');reason='ForeverDB HTTP 429 Retry-After'}
    Write-FCMForeverDBAtomicJson $script:ForeverDBBackoffPath $record
}

function Get-FCMForeverDBBudgetInfo {
    $today=[DateTime]::UtcNow.ToString('yyyy-MM-dd')
    $count=0
    $lastRequestUtc=$null
    if (Test-Path -LiteralPath $script:ForeverDBBudgetPath) {
        try {
            $record=Get-Content -LiteralPath $script:ForeverDBBudgetPath -Raw | ConvertFrom-Json
            if ([string]$record.requests -notmatch '^\d{1,8}$' -or [string]$record.utcDay -notmatch '^\d{4}-\d\d-\d\d$') {throw 'Bad budget fields'}
            if ($record.utcDay -eq $today) {$count=[int]$record.requests}
            if ($record.lastRequestUtc) {
                $lastRequestUtc=[DateTime]::Parse([string]$record.lastRequestUtc).ToUniversalTime()
            }
        } catch {throw 'ForeverDB shared budget is unreadable; all further requests stopped to protect quota.'}
    }
    # Migration: an older overnight task may have already used API calls today.
    # The maximum (not the sum) prevents double-counting migrated requests.
    foreach ($legacyPath in @($script:ForeverDBLegacyBudgetPath,$script:ForeverDBPriorBudgetPath)) {
        if (-not (Test-Path -LiteralPath $legacyPath)) {continue}
        try {
            $legacy=Get-Content -LiteralPath $legacyPath -Raw | ConvertFrom-Json
            if ([string]$legacy.requests -notmatch '^\d{1,8}$' -or [string]$legacy.utcDay -notmatch '^\d{4}-\d\d-\d\d$') {throw 'Bad legacy budget fields'}
            if ($legacy.utcDay -eq $today) {$count=[Math]::Max($count,[int]$legacy.requests)}
        } catch {throw 'Previous companion budget is unreadable; requests stopped rather than risking an incorrect count.'}
    }
    return [pscustomobject]@{
        utcDay=$today;requests=$count;remaining=[Math]::Max(0,$script:ForeverDBDailyCap-$count)
        cap=$script:ForeverDBDailyCap;lastRequestUtc=$lastRequestUtc
    }
}

function Reserve-FCMForeverDBRequest {
    # The build-check task can run separately from the main Windows companion.
    # Serialize quota writes and request timestamps across all those processes.
    $mutex=[System.Threading.Mutex]::new($false,'Local\FCM-ForeverDB-Shared-Quota')
    $locked=$false
    try {
        try {$locked=$mutex.WaitOne(10000)} catch [System.Threading.AbandonedMutexException] {$locked=$true}
        if (-not $locked) {throw 'Another FCM task holds the quota ledger; request deferred.'}
        if (Test-FCMForeverDBBackoff) {throw 'ForeverDB provider Retry-After cooldown is active; request deferred.'}
        $budget=Get-FCMForeverDBBudgetInfo
        if ($budget.remaining -le 0) {throw 'FCM combined manual + scheduled 4,500-request UTC-day limit reached.'}
        if ($script:ForeverDBDailyRemaining -match '^\d+$' -and [int]$script:ForeverDBDailyRemaining -le 500) {
            throw 'ForeverDB reports 500 or fewer requests left; reserving them for other account activity.'
        }
        if ($budget.lastRequestUtc) {
            $elapsed=([DateTime]::UtcNow-$budget.lastRequestUtc).TotalMilliseconds
            if ($elapsed -lt $script:ForeverDBRequestSpacingMs) {
                $wait=[int][Math]::Min($script:ForeverDBRequestSpacingMs,[Math]::Ceiling($script:ForeverDBRequestSpacingMs-$elapsed))
                if (Get-Command Wait-FcmResponsive -ErrorAction SilentlyContinue) {Wait-FcmResponsive $wait}
                else {[Threading.Thread]::Sleep($wait)}
            }
        }
        # A wait can cross UTC midnight; re-read before consuming a slot.
        $budget=Get-FCMForeverDBBudgetInfo
        if ($budget.remaining -le 0) {throw 'FCM combined daily request limit reached.'}
        $record=[ordered]@{
            utcDay=$budget.utcDay;requests=($budget.requests+1)
            cap=$script:ForeverDBDailyCap;lastRequestUtc=[DateTime]::UtcNow.ToString('o')
            scope='FCM manual + scheduled ForeverDB requests; all local companion entry points'
        }
        Write-FCMForeverDBAtomicJson $script:ForeverDBBudgetPath $record
        return $record.requests
    } finally {
        if ($locked) {$mutex.ReleaseMutex()}
        $mutex.Dispose()
    }
}
