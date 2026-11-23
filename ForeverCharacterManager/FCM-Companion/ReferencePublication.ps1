# Publish only standalone, already registered reference datasets. Collection
# and normalization happen before this lock, and never execute downloaded Lua.
function Publish-FCMReferenceData {
    param([string]$Addon,[string]$Name,[byte[]]$Bytes)
    if($Name -notin @('ExternalData.generated.lua','CommunityGathering.generated.lua','GatheringReferenceData.lua','PublicHistory.generated.lua')){
        throw 'This dataset is outside the live reference publication allowlist.'
    }
    if(!$Bytes -or $Bytes.Length -gt 24MB){throw 'Invalid reference payload size.'}
    if($Name -eq 'PublicHistory.generated.lua' -and $Bytes.Length -gt 8MB){throw 'Public history exceeds 8 MiB.'}
    $text=[Text.UTF8Encoding]::new($false,$true).GetString($Bytes)
    $prefix=switch($Name){
        'ExternalData.generated.lua' {'local _, FCM = ...'}
        'CommunityGathering.generated.lua' {'-- FCM community gathering: data only'}
        'GatheringReferenceData.lua' {'-- Generated offline Gathering reference;'}
        'PublicHistory.generated.lua' {'FCM_PublicHistory={'}
    }
    $suffix=switch($Name){
        'ExternalData.generated.lua' {'-- FCM reference complete'}
        'CommunityGathering.generated.lua' {'}}'}
        'GatheringReferenceData.lua' {'}'}
        'PublicHistory.generated.lua' {'}'}
    }
    if(!$text.TrimEnd().EndsWith($suffix,[StringComparison]::Ordinal)){throw 'Incomplete generated reference footer.'}
    if(!$text.StartsWith($prefix,[StringComparison]::Ordinal) -or !$text.EndsWith("`n") -or $text.Contains([char]0)){
        throw 'Incomplete or unexpected generated reference.'
    }
    $root=(Get-Item -LiteralPath $Addon -Force -ErrorAction Stop).FullName
    for($dir=$root;$dir;$dir=Split-Path -Parent $dir){
        if((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){
            throw 'Linked publication root refused.'
        }
    }
    $target=Join-Path $root $Name
    foreach($nameToc in 'ForeverCharacterManager.toc','ForeverCharacterManager_Camelot.toc'){
        $toc=Get-Item -LiteralPath (Join-Path $root $nameToc) -Force -ErrorAction Stop
        if(($toc.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
           $Name -notin @(Get-Content -LiteralPath $toc.FullName | ForEach-Object {$_.Trim()})){
            throw 'Target is not registered in both reviewed TOCs.'
        }
    }
    # Take a cross-process filesystem lock. A closed process releases it even
    # when its lock file remains. Each dataset has independent atomic activation.
    $lockPath=$target+'.publish.lock'
    if((Test-Path -LiteralPath $lockPath) -and ((Get-Item -LiteralPath $lockPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked publication lock refused.'}
    $lock=[IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None')
    try {
        $temp=$target+'.pending'
        foreach($path in $target,$temp,($target+'.bak')){
            if((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked reference file refused.'}
        }
        $algorithm=[Security.Cryptography.SHA256]::Create()
        try {$hash=[BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-','')}
        finally {$algorithm.Dispose()}
        $stage=$temp+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        try {
            $writer=[IO.File]::Open($stage,'CreateNew','Write','None')
            try {$writer.Write($Bytes,0,$Bytes.Length);$writer.Flush($true)}
            finally {$writer.Dispose()}
            if((Get-FileHash -LiteralPath $stage).Hash -ne $hash){throw 'Staging verification failed.'}
            if(Test-Path -LiteralPath $temp){[IO.File]::Replace($stage,$temp,[NullString]::Value)}
            else{[IO.File]::Move($stage,$temp)}
        } finally {[IO.File]::Delete($stage)}
        $backup=$null
        $oldHash=$null
        if(Test-Path -LiteralPath $target){
            $oldHash=(Get-FileHash -LiteralPath $target).Hash
            if($oldHash -eq $hash){
                [IO.File]::Delete($temp)
                return [pscustomobject]@{Published=$true;Changed=$false;Sha256=$hash}
            }
            $backup=$target+'.bak'
            $backupTemp=$backup+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
            [IO.File]::Copy($target,$backupTemp)
            if((Get-FileHash -LiteralPath $backupTemp).Hash -ne $oldHash){throw 'Backup verification failed.'}
            if(Test-Path -LiteralPath $backup){[IO.File]::Replace($backupTemp,$backup,[NullString]::Value)}
            else{[IO.File]::Move($backupTemp,$backup)}
        }
        try {
            if($backup){[IO.File]::Replace($temp,$target,[NullString]::Value)}
            else{[IO.File]::Move($temp,$target)}
        } catch [IO.IOException] {
            return [pscustomobject]@{Published=$false;Changed=$false;Pending=$temp;Sha256=$hash}
        } catch [PlatformNotSupportedException] {
            return [pscustomobject]@{Published=$false;Changed=$false;Pending=$temp;Sha256=$hash}
        }
        try {
            if((Get-FileHash -LiteralPath $target).Hash -ne $hash){throw 'Published reference hash mismatch.'}
        } catch {
            if($backup){
                $restore=$target+'.'+[guid]::NewGuid().ToString('N')+'.restore'
                [IO.File]::Copy($backup,$restore)
                [IO.File]::Replace($restore,$target,[NullString]::Value)
                if((Get-FileHash -LiteralPath $target).Hash -ne $oldHash){throw "Rollback mismatch. Backup retained: $backup"}
            } else {[IO.File]::Move($target,$temp)}
            throw 'Published reference could not be verified.'
        }
        [pscustomobject]@{Published=$true;Changed=$true;Sha256=$hash;Backup=$backup}
    } finally {$lock.Dispose()}
}

function ConvertTo-FCMLuaLiteral($value) {
    $s = [string]$value
    # Lua 5.1 cannot embed raw control characters in quoted strings.
    $s=[regex]::Replace($s,'[\x00-\x08\x0B\x0C\x0E-\x1F]',' ')
    # Truncate before escaping to avoid splitting an escape sequence.
    if ($s.Length -gt 600) { $s = $s.Substring(0,600) }
    $s = $s.Replace('\','\\').Replace('"','\"').Replace("`r",'').Replace("`n",'\n').Replace("`t",'\t')
    return '"' + $s + '"'
}
function Add-FCMDungeonDropLua($builder,$drop) {
    [void]$builder.Append('{id=' + [int]$drop.id + ',name='+(ConvertTo-FCMLuaLiteral $drop.name)+
        ',sourceType='+(ConvertTo-FCMLuaLiteral $drop.sourceType)+',evidence='+(ConvertTo-FCMLuaLiteral $drop.evidence)+
        ',observedCount='+[int]$drop.observedCount+',sampleKills='+[int]$drop.sampleKills+'},')
}
function Add-FCMDungeonReferenceLua {
    param([Text.StringBuilder]$Builder, $DungeonCache)
    $sb=$Builder
    foreach ($key in @($DungeonCache.Keys | Where-Object {$_ -match '^\d{1,8}$'} | Sort-Object {[int]$_} | Select-Object -First 1000)) {
        $d=$DungeonCache[$key]
        [void]$sb.Append('FCM.externalData.dungeons[' + $key + '] = {name=' + (ConvertTo-FCMLuaLiteral $d.name) + ',levels='+(ConvertTo-FCMLuaLiteral $d.levels)+',kind='+(ConvertTo-FCMLuaLiteral $d.kind)+',sourceProvider='+(ConvertTo-FCMLuaLiteral $d.sourceProvider)+',referenceCheckedAt='+(ConvertTo-FCMLuaLiteral $d.referenceCheckedAt)+',sourceEvidence='+(ConvertTo-FCMLuaLiteral $d.sourceEvidence)+',bossCount=' + [int]$d.bossCount + ',lootIDs={')
        foreach ($itemID in @($d.lootIDs | Select-Object -First 100)) { if ([int]$itemID -gt 0) { [void]$sb.Append(([int]$itemID).ToString() + ',') } }
        [void]$sb.Append('},bosses={')
        foreach ($boss in @($d.bosses | Select-Object -First 90)) {
            if (-not $boss) {continue}
            [void]$sb.Append('{id=' + [int]$boss.id + ',npcId=' + [int]$boss.npcId + ',name='+(ConvertTo-FCMLuaLiteral $boss.name)+',loot={')
            foreach ($drop in @($boss.loot | Select-Object -First 65)) {
                if (-not $drop -or [int]$drop.id -le 0) {continue}
                Add-FCMDungeonDropLua $sb $drop
            }
            [void]$sb.Append('}},')
        }
        [void]$sb.Append('},dungeonLoot={')
        foreach ($drop in @($d.dungeonLoot | Select-Object -First 100)) {
            if (-not $drop -or [int]$drop.id -le 0) {continue}
            Add-FCMDungeonDropLua $sb $drop
        }
        [void]$sb.Append('},lines={')
        foreach ($line in @($d.lines | Select-Object -First 100)) { [void]$sb.Append((ConvertTo-FCMLuaLiteral $line) + ',') }
        [void]$sb.AppendLine('}}')
    }
}
