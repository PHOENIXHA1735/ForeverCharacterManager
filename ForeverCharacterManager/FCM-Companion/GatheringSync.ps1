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
    if (Game-Is-Running) { throw 'Close WoW before syncing community gathering data.' }
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
    [void]$lines.Add("FCM.communityGathering = {schema=1,version=$([int]$manifest.version),nodes={")
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
    $path=Join-Path $dest 'CommunityGathering.generated.lua'
    $temp="$path.tmp"
    try {
        [IO.File]::WriteAllLines($temp,$lines,(New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temp -Destination $path -Force
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
    Log "Community gathering database v$($manifest.version) installed: $count locations. Launch WoW to merge them."
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
