# FCM community gathering snapshots: GitHub GET only, no credentials or uploads.
# A contribution export is anonymous and intentionally requires manual review.
$script:GatheringGitHubBase = 'https://raw.githubusercontent.com/PHOENIXHA1735/ForeverCharacterManager/main/CommunityData'

function ConvertTo-FCMGatherString([string]$value) {
    if ($value.Length -gt 100 -or $value -match '[\x00-\x1f]') { throw 'Untrusted gathering node name.' }
    return '"' + $value.Replace('\','\\').Replace('"','\"') + '"'
}

function Test-FCMGatherNode($node, [string]$expectedKind) {
    if ($null -eq $node -or [string]$node.kind -ne $expectedKind) { return $null }
    try {
        $mapID=[int]$node.mapID; $x=[int]$node.x; $y=[int]$node.y
        $name=[string]$node.name
        if ($mapID -lt 1 -or $mapID -gt 200000 -or $x -lt 0 -or $x -gt 10000 -or
            $y -lt 0 -or $y -gt 10000 -or $name.Length -lt 2 -or $name.Length -gt 100 -or
            $name -match '[\x00-\x1f|]') { return $null }
        return [pscustomobject]@{kind=$expectedKind;mapID=$mapID;x=$x;y=$y;name=$name}
    } catch { return $null }
}

function Sync-FCMGatheringCommunity {
    $dest=Target-Addon
    if (-not (Test-Path -LiteralPath (Join-Path $dest 'Gathering.lua'))) {
        throw 'Install the FCM gathering update before downloading community nodes.'
    }
    $headers=@{'User-Agent'='ForeverCharacterManager-CommunitySync';'Accept'='application/json'}
    $manifest=Invoke-FcmHttpJson "$($script:GatheringGitHubBase)/manifest.json" $headers
    if ([int]$manifest.schema -ne 1 -or [int]$manifest.version -lt 1) {
        throw 'Unrecognized gathering manifest. Previous data was preserved.'
    }
    $kinds=@('herbalism','mining','fishing','treasure')
    $lines=New-Object 'System.Collections.Generic.List[string]'
    [void]$lines.Add('-- FCM community gathering: data only, no account or character information.')
    [void]$lines.Add('local _, FCM = ...')
    [void]$lines.Add("FCM.communityGathering = {schema=1,generatedUtc=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()),version=$([int]$manifest.version),nodes={")
    $seen=@{}; $count=0
    foreach ($kind in $kinds) {
        $filename="$kind.json"
        $document=Invoke-FcmHttpJson "$($script:GatheringGitHubBase)/$filename" $headers
        if ([int]$document.schema -ne 1 -or $null -eq $document.nodes) {
            throw "Invalid community file $filename; previous data was preserved."
        }
        if (@($document.nodes).Count -gt 150000) { throw 'Community file exceeds the safe node limit.' }
        foreach ($node in @($document.nodes)) {
            $valid=Test-FCMGatherNode $node $kind
            if ($null -eq $valid) { continue }
            $key="$kind|$($valid.mapID)|$($valid.x)|$($valid.y)|$($valid.name.ToLowerInvariant())"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key]=$true; $count++
            if ($count -gt 300000) { throw 'Community database exceeds the safe node limit.' }
            $name=ConvertTo-FCMGatherString $valid.name
            [void]$lines.Add("{kind=`"$kind`",mapID=$($valid.mapID),x=$($valid.x),y=$($valid.y),name=$name},")
        }
    }
    [void]$lines.Add('}}')
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n")+"`n")
    $result=Publish-FCMReferenceData -Addon $dest -Name 'CommunityGathering.generated.lua' -Bytes $bytes
    if(!$result.Published){Log "Community reference staged. Pending: $($result.Pending)";return}
    Log "Community gathering database v$($manifest.version) published: $count locations. Reload the UI to load it."

}

function Export-FCMGatheringContributions {
    if (Game-Is-Running) { throw 'Log out and close WoW so your latest gathering discoveries are saved first.' }
    $root=$script:gameBox.Text.Trim()
    $accounts=Join-Path $root 'WTF\Account'
    if (-not (Test-Path -LiteralPath $accounts)) { throw 'WoW account SavedVariables directory not found.' }
    $seen=@{}; $nodes=New-Object 'System.Collections.Generic.List[object]'
    # This matches only FCM_GatherExport's sanitized marker lines. Never parse,
    # execute, copy or upload any of the private FCM_DB Lua code.
    $pattern='FCMG1\|(herbalism|mining|fishing|treasure)\|(\d{1,6})\|(\d{1,5})\|(\d{1,5})\|([^"\\\r\n|]{2,300})'
    foreach ($account in @(Get-ChildItem -LiteralPath $accounts -Directory -ErrorAction SilentlyContinue)) {
        $path=Join-Path $account.FullName 'SavedVariables\ForeverCharacterManager.lua'
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($line in @(Get-Content -LiteralPath $path)) {
            $m=[regex]::Match($line,$pattern)
            if (-not $m.Success) { continue }
            try { $name=[uri]::UnescapeDataString($m.Groups[5].Value) } catch { continue }
            $candidate=[pscustomobject]@{kind=$m.Groups[1].Value;mapID=[int]$m.Groups[2].Value;
                x=[int]$m.Groups[3].Value;y=[int]$m.Groups[4].Value;name=$name}
            $valid=Test-FCMGatherNode $candidate $candidate.kind
            if ($null -eq $valid) { continue }
            $key="$($valid.kind)|$($valid.mapID)|$($valid.x)|$($valid.y)|$($valid.name.ToLowerInvariant())"
            if (-not $seen.ContainsKey($key)) { $seen[$key]=$true; $nodes.Add($valid) }
        }
    }
    if ($nodes.Count -eq 0) { Log 'No personal gathering discoveries found yet. Gather a named herb or vein in WoW, then log out.'; return }
    $export=[ordered]@{schema=1;format='fcm-gathering-contribution';nodes=@($nodes.ToArray())}
    $path=Join-Path $script:Base 'fcm-gathering-contribution.json'
    [IO.File]::WriteAllText($path,($export | ConvertTo-Json -Depth 6),(New-Object System.Text.UTF8Encoding($false)))
    Log "Exported $($nodes.Count) anonymous personal locations to $path. Review the file before sharing via GitHub issue/PR. Nothing was uploaded."
}

# Manual reference refresh. Use the same credentialed request path, pacing,
# quota ledger, and Retry-After handling as the rest of the companion.
function Sync-FCMGatheringReference {
    $addon=Target-Addon
    $target=Join-Path $addon 'GatheringReferenceData.lua'
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Install the Gathering browser before its reference refresh.' }
    $pythonConfig=Join-Path $script:Base 'python-path.local.txt'
    $python=if(Test-Path -LiteralPath $pythonConfig){([IO.File]::ReadAllText($pythonConfig)).Trim()}else{
        $command=Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if($command){$command.Source}
    }
    if(!$python -or $python -match '[\x00-\x1f]' -or ![IO.Path]::IsPathRooted($python) -or !(Test-Path -LiteralPath $python -PathType Leaf)){
        throw 'Configure a working absolute Python path before refreshing Gathering.'
    }
    $lock=Enter-FCMCatalogLock
    try {
        $script:ForeverDBRequests=0
        $meta=Fetch-ForeverDB '/meta'
        $build=[string](FDB-Data $meta).build
        if($build -notmatch '^\d+(\.\d+){2,3}$'){throw 'ForeverDB did not report a usable build.'}
        $receiptPath=Join-Path $addon 'GatheringReference.local.json'
        $receipt=$null
        if(Test-Path -LiteralPath $receiptPath){
            try {$receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -ErrorAction Stop} catch {}
        }
        $publishedHash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $verifiedAt=0L
        $recent=$receipt -and [long]::TryParse([string]$receipt.verifiedAt,[ref]$verifiedAt) -and
            $verifiedAt -le $now -and $verifiedAt -gt ($now-86400)
        if($recent -and $receipt.build -ceq $build -and $receipt.sha256 -eq $publishedHash){
            Log 'Gathering reference is current for the verified build. Endpoint downloads skipped.'
            return
        }
        $work=Join-Path ([IO.Path]::GetTempPath()) ('fcm-gather-reference-'+[guid]::NewGuid())
        New-Item -ItemType Directory -Path $work -ErrorAction Stop | Out-Null
        $generation=Join-Path $work 'generation'
        $receiptTemp=$receiptPath+'.'+[guid]::NewGuid().ToString('N')+'.pending'
        $kinds=@('herbalism','mining','fishing')
        try {
            foreach($kind in $kinds){
                $response=Fetch-ForeverDB ('/gathering/'+$kind)
                if([string]$response.meta.build -cne $build){throw 'Provider build changed during refresh.'}
                foreach($member in 'next','nextPage','nextOffset','hasMore'){
                    if($response.meta.$member -or $response.data.$member){throw 'Provider returned an incomplete page.'}
                }
                $safe=[ordered]@{data=$response.data;meta=[ordered]@{build=$build;attribution=$response.meta.attribution}}
                [IO.File]::WriteAllText((Join-Path $work "$kind.json"),($safe | ConvertTo-Json -Depth 64),[Text.UTF8Encoding]::new($false))
            }
            $null=& $python -B (Join-Path $script:Base 'import_foreverdb_gathering.py') $work $generation 2>&1
            if($LASTEXITCODE -ne 0){throw 'Gathering provider response could not be validated. Previous reference retained.'}
            $payload=[IO.File]::ReadAllBytes((Join-Path $generation 'GatheringReferenceData.lua'))
            $audit=Get-Content -LiteralPath (Join-Path $generation 'audit.json') -Raw | ConvertFrom-Json
            if((Get-FileHash -LiteralPath (Join-Path $generation 'GatheringReferenceData.lua')).Hash -ne $audit.outputs.'GatheringReferenceData.lua'){
                throw 'Gathering generation hash mismatch.'
            }
            $result=Publish-FCMReferenceData -Addon $addon -Name 'GatheringReferenceData.lua' -Bytes $payload
            if(!$result.Published){Log "Gathering reference staged. Pending: $($result.Pending)";return}
            $hash=$result.Sha256
            $checkpoint=@{build=$build;sha256=$hash;verifiedAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
            [IO.File]::WriteAllText($receiptTemp,($checkpoint | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
            if(Test-Path -LiteralPath $receiptPath){[IO.File]::Replace($receiptTemp,$receiptPath,[NullString]::Value)}
            else{[IO.File]::Move($receiptTemp,$receiptPath)}
            Log 'Verified ForeverDB Gathering reference published.'
        } finally {
            foreach($kind in $kinds){[IO.File]::Delete((Join-Path $work "$kind.json"))}
            if(Test-Path -LiteralPath $generation){
                foreach($name in 'audit.json','gathering-reference.json','GatheringReferenceData.lua'){
                    [IO.File]::Delete((Join-Path $generation $name))
                }
                [IO.Directory]::Delete($generation)
            }
            [IO.File]::Delete($receiptTemp)
            [IO.Directory]::Delete($work)
        }
    } finally {
        $lock.ReleaseMutex()
        $lock.Dispose()
    }
}
