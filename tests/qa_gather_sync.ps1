$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repo 'ForeverCharacterManager\FCM-Companion'
$test=Join-Path ([IO.Path]::GetTempPath()) ('fcm-gather-sync-test-'+[guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($test)
$script:Base=$test
$script:addon=Join-Path $test 'addon'
[void][IO.Directory]::CreateDirectory($script:addon)
$python=if($env:FCM_TEST_PYTHON){$env:FCM_TEST_PYTHON}else{(Get-Command python.exe -CommandType Application | Select-Object -First 1).Source}
Set-Content -LiteralPath (Join-Path $test 'python-path.local.txt') -Value $python -Encoding ASCII
foreach($name in 'build_gather_reference.py','import_foreverdb_gathering.py','gathering-reference.json'){
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination $test
}
$target=Join-Path $script:addon 'GatheringReferenceData.lua'
Set-Content -LiteralPath $target -Value '-- original'
foreach($toc in 'ForeverCharacterManager.toc','ForeverCharacterManager_Camelot.toc'){Set-Content -LiteralPath (Join-Path $script:addon $toc) -Value 'GatheringReferenceData.lua'}
. (Join-Path $source 'ReferencePublication.ps1')
. (Join-Path $source 'GatheringSync.ps1')
function Game-Is-Running { return $true }
function Target-Addon { return $script:addon }
function Log($text) { Write-Host $text }
function Enter-FCMCatalogLock {
    $m=[Threading.Mutex]::new()
    [void]$m.WaitOne()
    return $m
}
function FDB-Data($response) { return $response.data }
$script:build='1.60.1.1'
$script:failure=''
$script:routes=[Collections.Generic.List[string]]::new()
function Fetch-ForeverDB($route){
    $script:routes.Add($route)
    if($route -eq '/meta'){return @{data=@{build=$script:build}}}
    $kind=$route.Split('/')[-1]
    if($kind -eq 'mining' -and $script:failure -eq 'rate'){throw 'HTTP 429 fixture'}
    $zones=@(@{mapId=1;name='Fixture Zone';skill=1;noEscapeSkill=25;nodes=@();pools=@();loot=@();caughtInForever=@()})
    if($kind -eq 'mining' -and $script:failure -eq 'corrupt'){$zones=@()}
    $response=@{
        meta=@{build=$script:build;attribution='ForeverDB';client='invented identifier'}
        data=@{profession=$kind;url="https://foreverdb.net/profession/$kind";zones=$zones
            nodes=@(@{name='Fixture Resource';objectIds=@(123);skill=1;alsoGives=@();topZones=@()})
            pools=@('Fixture Pool')}
    }
    if($kind -eq 'mining' -and $script:failure -eq 'partial'){$response.meta.hasMore=$true}
    $response
}
Sync-FCMGatheringReference
if($script:routes.Count -ne 4){throw 'Initial acquisition did not use the four expected requests'}
$first=(Get-FileHash -LiteralPath $target).Hash
Sync-FCMGatheringReference
if($script:routes.Count -ne 5 -or $script:routes[4] -ne '/meta'){throw 'Valid checkpoint did not skip payload requests'}
$script:build='1.60.1.2'
foreach($errorType in 'rate','corrupt','partial'){
    $script:failure=$errorType
    $rejected=$false
    try {Sync-FCMGatheringReference} catch {$rejected=$true}
    if(!$rejected -or (Get-FileHash -LiteralPath $target).Hash -ne $first){throw "Failed refresh changed published data: $errorType"}
}
$script:failure=''
Sync-FCMGatheringReference
if((Get-FileHash -LiteralPath $target).Hash -eq $first){throw 'Changed build was not refreshed'}
if((Get-Content -LiteralPath $target -Raw).Contains('invented identifier')){throw 'Provider client identifier escaped'}
Write-Host 'PASS: quota-aware entry point, checkpoint replay, build refresh, HTTP 429, empty and partial responses'
