param([Parameter(Mandatory=$true)][string]$Python)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repo 'ForeverCharacterManager/FCM-Companion'
$test=Join-Path ([IO.Path]::GetTempPath()) ('fcm-entrypoints-'+[guid]::NewGuid())
$child=$null
try {
    $addon=Join-Path $test 'ForeverCharacterManager'
    $comp=Join-Path $addon 'FCM-Companion'
    New-Item -ItemType Directory -Path $comp -Force | Out-Null
    Get-ChildItem -LiteralPath $source -File | Copy-Item -Destination $comp
    Copy-Item -LiteralPath (Join-Path $repo 'tools/release/run_private_gated.py') -Destination $comp
    New-Item -ItemType File -Path (Join-Path $addon 'ForeverCharacterManager.toc') | Out-Null
    $updater=Join-Path $test 'updater.py'
    'from pathlib import Path; Path(__file__).with_name("ran").touch()' | Set-Content $updater -Encoding ascii
    $digest=(Get-FileHash -LiteralPath $updater).Hash
    $raw=Join-Path $test 'AHledger.lua'
    'fixture = {}' | Set-Content $raw -Encoding ascii
    $ready=Join-Path $test 'ready'
    $holder=Join-Path $test 'holder.py'
    @('from pathlib import Path','import sys, time','sys.path.insert(0, sys.argv[1])','from fcm_writer_lease import writer','with writer(sys.argv[2]):','    Path(sys.argv[3]).touch()','    time.sleep(60)') | Set-Content $holder -Encoding ascii
    $child=Start-Process -FilePath $Python -ArgumentList @('-B',('"{0}"' -f $holder),('"{0}"' -f $comp),('"{0}"' -f $addon),('"{0}"' -f $ready)) -WindowStyle Hidden -PassThru
    $end=[DateTime]::UtcNow.AddSeconds(12)
    while (!(Test-Path -LiteralPath $ready)) {
        if($child.HasExited -or [DateTime]::UtcNow -gt $end){throw 'Disposable writer never acquired its lease.'}
        Start-Sleep -Milliseconds 50
    }
    $calls=@(
        { & "$comp/FCM-DailyAHSync.ps1" -Mode Run -Quiet },
        { & "$comp/FCM-ForeverDBBuildCheck.ps1" -Quiet },
        { & "$comp/FCM-AHHistory.ps1" -Sources $raw -GameRoot $test -SkipAnalysis },
        { & "$comp/FCMDataUpdater.ps1" -OvernightCatalog },
        { & "$comp/Publish-FCMPublicHistory.ps1" -Python $Python -Root $test -Binding invented }
    )
    foreach ($call in $calls) {
        $denied=$false
        try { & $call } catch {
            if($_.Exception.Message -notmatch '(?i)lock|portion of the file'){throw}
            $denied=$true
        }
        if(!$denied){throw 'PowerShell writer admitted during a Python write.'}
    }
    if(Test-Path "$addon/AHHistory"){throw 'Collector wrote before acquiring the lease.'}
    $child.Kill()
    $child.WaitForExit()
    $marker=Join-Path $addon '.fcm-maintenance.json'
    '{}' | Set-Content $marker -Encoding ascii
    $denied=$false
    try { & "$comp/FCM-ForeverDBBuildCheck.ps1" -Quiet } catch {
        if($_.Exception.Message -notmatch 'maintenance is active'){throw}
        $denied=$true
    }
    if(!$denied){throw 'Durable marker did not fence the build check.'}
    Remove-Item -LiteralPath $marker
    & "$comp/FCM-ForeverDBBuildCheck.ps1" -Quiet
    if(!(Test-Path "$comp/fdb-build-status.json")){throw 'Fixture build status missing.'}
    & "$comp/FCM-AHHistory.ps1" -Sources $raw -GameRoot $test -SkipAnalysis
    if(!(Test-Path "$addon/AHHistory/Index/status.json")){throw 'Fixture archive status missing.'}
    & $Python -I -B "$comp/run_private_gated.py" --addon $addon --updater $updater --sha256 $digest
    if($LASTEXITCODE -ne 0 -or !(Test-Path "$test/ran")){throw 'Private guarded launcher failed.'}
    'PASS: live Windows lease contention, interrupted owner, durable marker and fixture writes'
} finally {
    if($child -and !$child.HasExited){$child.Kill();$child.WaitForExit()}
    if ((Test-Path -LiteralPath $test) -and (Resolve-Path -LiteralPath $test).ProviderPath -eq $test) {
        Remove-Item -LiteralPath $test -Recurse -Force
    }
}
