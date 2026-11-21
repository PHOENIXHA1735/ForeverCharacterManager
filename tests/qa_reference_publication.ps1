$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../ForeverCharacterManager/FCM-Companion/ReferencePublication.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('fcm-publication-'+[guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($root)
$name='ExternalData.generated.lua'
$target=Join-Path $root $name
foreach($toc in 'ForeverCharacterManager.toc','ForeverCharacterManager_Camelot.toc'){
    [IO.File]::WriteAllText((Join-Path $root $toc),$name)
}
function Payload($value){
    ,([Text.Encoding]::UTF8.GetBytes("local _, FCM = ...`nFCM.fixture=$value`n-- FCM reference complete`n"))
}
function Reject([scriptblock]$action){
    $failed=$false
    try{& $action | Out-Null}catch{$failed=$true}
    if(!$failed){throw 'Unexpected successful publication.'}
}
[IO.File]::WriteAllBytes($target,(Payload 1))
$first=(Get-FileHash -LiteralPath $target).Hash
Reject {Publish-FCMReferenceData $root $name ([Text.Encoding]::UTF8.GetBytes("local _, FCM = ...`n"))}
Reject {Publish-FCMReferenceData $root 'FCM.lua' (Payload 2)}
if((Get-FileHash -LiteralPath $target).Hash -ne $first){throw 'Rejected payload changed active bytes'}
$hold=[IO.File]::Open(($target+'.publish.lock'),'OpenOrCreate','ReadWrite','None')
try{
    $child=Join-Path $root 'writer.ps1'
    [IO.File]::WriteAllText($child,@'
        param($helper,$addon,$name)
        $ErrorActionPreference='Stop'
        . $helper
        try {Publish-FCMReferenceData $addon $name ([Text.Encoding]::UTF8.GetBytes("local _, FCM = ...`n-- FCM reference complete`n")) | Out-Null; exit 1}
        catch [IO.IOException] {exit 42}
'@)
    $engine=(Get-Process -Id $PID).Path
    & $engine -NoProfile -ExecutionPolicy Bypass -File $child (Join-Path $PSScriptRoot '../ForeverCharacterManager/FCM-Companion/ReferencePublication.ps1') $root $name
    if($LASTEXITCODE -ne 42){throw 'Cross-process writer was not blocked'}
    $global:LASTEXITCODE=0 # The expected child refusal is a successful test.
}finally{$hold.Dispose()}
$reader=[IO.File]::Open($target,'Open','Read','ReadWrite')
try{
    $result=Publish-FCMReferenceData $root $name (Payload 2)
    if($result.Published -or !(Test-Path -LiteralPath $result.Pending)){throw 'Locked reader did not defer publication'}
}finally{$reader.Dispose()}
if((Get-FileHash -LiteralPath $target).Hash -ne $first){throw 'Deferred publication changed the destination'}
$share=[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
$reader=[IO.File]::Open($target,'Open','Read',$share)
try{
    $result=Publish-FCMReferenceData $root $name (Payload 2)
    if(!$result.Published){throw 'Compatible reader prevented publication'}
    $r=[IO.StreamReader]::new($reader)
    if($r.ReadToEnd() -notmatch 'fixture=1'){throw 'Existing reader received incomplete bytes'}
}finally{$reader.Dispose()}
if([IO.File]::ReadAllText($target) -notmatch 'fixture=2'){throw 'New reader did not see the new file'}
if((Get-FileHash -LiteralPath $result.Backup).Hash -ne $first){throw 'Verified backup differs'}
$second=(Get-FileHash -LiteralPath $target).Hash
$script:inject=$true
function Get-FileHash {
    param([string]$LiteralPath)
    if($script:inject -and $LiteralPath -eq $target -and [IO.File]::ReadAllText($target) -match 'fixture=3'){
        $script:inject=$false
        throw 'Injected final verification failure'
    }
    Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath
}
Reject {Publish-FCMReferenceData $root $name (Payload 3)}
if($script:inject -or (Get-FileHash -LiteralPath $target).Hash -ne $second){throw 'Rollback failed'}
'PASS: incomplete payload and non-data refusal, competing process lock, compatible reader, blocked publish and retry, backup and verification rollback'
