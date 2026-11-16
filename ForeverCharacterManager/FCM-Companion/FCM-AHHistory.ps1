# Local-only archive. Windows PowerShell 5.1. Never downloads data.
[CmdletBinding()]
param(
    [ValidateSet('Sync','Enable','Disable','Status')][string]$Mode = 'Sync',
    [string]$AddonRoot = '',
    [string]$GameRoot = '',
    [string[]]$Sources = @(),
    [switch]$IncludeProviderTables,
    [switch]$SkipAnalysis
)
$ErrorActionPreference = 'Stop'
$companion = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $AddonRoot) { $AddonRoot = Split-Path -Parent $companion }
$taskName = 'FCM-AHHistory'
if (-not (Test-Path -LiteralPath (Join-Path $AddonRoot 'ForeverCharacterManager.toc'))) { throw 'FCM manifest missing' }
$AddonRoot = (Resolve-Path -LiteralPath $AddonRoot).ProviderPath
$history = Join-Path $AddonRoot 'AHHistory'
if (-not $GameRoot) { $GameRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $AddonRoot)) }
if ($Mode -eq 'Status') { Get-ScheduledTask -TaskName $taskName -ErrorAction Stop; return }
if ($Mode -eq 'Disable') { Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null; return }
if ($Mode -eq 'Enable') {
    $taskArgs = ('-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -AddonRoot "{1}"' -f $MyInvocation.MyCommand.Path,$AddonRoot)
    if ($IncludeProviderTables) { $taskArgs += ' -IncludeProviderTables' }
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $taskArgs
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 30)
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 25) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    $legacy=Get-ScheduledTask -TaskName 'FCM Daily Auction House Refresh' -ErrorAction SilentlyContinue
    if ($legacy) { Disable-ScheduledTask -TaskName $legacy.TaskName -ErrorAction Stop | Out-Null }
    return
}
foreach ($part in @('Incoming','RawScans','MarketTables','Index','Logs','Parsed','Quarantine')) {
    $folder = Join-Path $history $part
    if (Test-Path -LiteralPath $folder) {
        if ((Get-Item -LiteralPath $folder).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Archive links refused' }
    } else { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
}
# An exclusive file handle also prevents manual and scheduled invocations overlapping.
try { $lock = [IO.File]::Open((Join-Path $history 'Index\archive.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
catch [IO.IOException] { Write-Output 'Another archive operation holds the lock'; return }
$copied=0; $unchanged=0; $failed=0
function Log-Event([string]$message) {
    Add-Content -LiteralPath (Join-Path $history 'Logs\archive.log') -Value (([DateTime]::UtcNow.ToString('o'))+' '+$message) -Encoding UTF8
}
try {
    if (-not $Sources.Count) {
        $wtf = Join-Path $GameRoot 'WTF'
        $Sources = @(Get-ChildItem -LiteralPath $wtf -Filter 'AHledger.lua' -File -Recurse -ErrorAction Stop | Where-Object { $_.Directory.Name -eq 'SavedVariables' } | Select-Object -ExpandProperty FullName)
        # Provider snapshots are NOT personal AH scans. Never archive them
        # by default: authorization for retention beyond cache expiry varies.
        if ($IncludeProviderTables) {
            $Sources += Join-Path $GameRoot 'Interface\AddOns\AHledger\AHledger_Data.lua'
        }
    }
    foreach ($source in $Sources) {
        $temp = $null
        try {
            $info = Get-Item -LiteralPath $source -ErrorAction Stop
            if ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked source refused' }
            if ($info.Name -ieq 'AHledger_Data.lua') {
                if (-not $IncludeProviderTables) {
                    throw 'Provider-table archival requires explicit -IncludeProviderTables and retention permission'
                }
                $kind='MarketTables'
            }
            elseif ($info.Name -ieq 'AHledger.lua') { $kind='RawScans' }
            else { throw 'Unexpected source name' }
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $sourceId = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($info.FullName.ToLowerInvariant())))).Replace('-','').Substring(0,16) } finally { $sha.Dispose() }
            $destination = Join-Path (Join-Path $history $kind) $sourceId
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            $temp = Join-Path $history ('Incoming\'+[Guid]::NewGuid().ToString('N')+'.tmp')
            # Deny writers during copy; if WoW/Sync is writing, fail and retry next run.
            $input = [IO.File]::Open($info.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try {
                $output = [IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try { $input.CopyTo($output); $output.Flush($true) } finally { $output.Dispose() }
                $hash = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash
                $current = Get-Item -LiteralPath $source
                if ($current.Length -ne $info.Length -or $current.LastWriteTimeUtc -ne $info.LastWriteTimeUtc) { throw 'Source changed during copy' }
            } finally { $input.Dispose() }
            $existing = @(Get-ChildItem -LiteralPath $destination -Filter ('*_'+$hash+'.lua'))
            if ($existing.Count) { $unchanged++; Remove-Item -LiteralPath $temp; $temp=$null; continue }
            $stamp=[DateTime]::UtcNow
            $base = $stamp.ToString('yyyyMMddTHHmmssfffffffZ')+'_'+$hash+'.lua'
            $final = Join-Path $destination $base
            # Metadata first, then an atomic same-volume rename publishes complete bytes.
            $meta = [ordered]@{schema=1;kind=$kind;source=$info.FullName;sourceId=$sourceId;sourceLength=$info.Length;sourceModifiedUtc=$info.LastWriteTimeUtc.ToString('o');archivedUtc=$stamp.ToString('o');sha256=$hash;file=$base}
            [IO.File]::WriteAllText(($final+'.json'),($meta | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
            [IO.File]::Move($temp,$final); $temp=$null
            $copied++; Log-Event ('copied '+$kind+' '+$sourceId+' '+$hash)
        } catch { $failed++; Log-Event ('error '+$_.Exception.Message); Write-Warning $_.Exception.Message }
        finally { if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp } }
    }
    if (-not $SkipAnalysis) {
        $processor = Join-Path $companion 'fcm_history.py'
        if (Test-Path -LiteralPath $processor) {
            $python='python.exe'
            $pythonConfig=Join-Path $companion 'python-path.local.txt'
            if (Test-Path -LiteralPath $pythonConfig) { $python=([IO.File]::ReadAllText($pythonConfig)).Trim() }
            & $python $processor --addon $AddonRoot
            if ($LASTEXITCODE -ne 0) { throw 'History processor failed' }
        }
    }
    $status = @{utc=[DateTime]::UtcNow.ToString('o');copied=$copied;unchanged=$unchanged;failed=$failed}
    $status | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $history 'Index\status.json') -Encoding UTF8
    $status | ConvertTo-Json -Compress | Write-Output
    if ($failed) { throw ('Archival errors: '+$failed) }
} finally { $lock.Dispose() }
