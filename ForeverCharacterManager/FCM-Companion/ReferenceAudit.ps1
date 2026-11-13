# FCM v0.9.0 reference audit. Offline-only. Never stores character/account data.
# Cache state is provided by FCMDataUpdater.ps1 after loading reference-cache.json.
function Get-FCMReferenceAudit {
    $now=[DateTime]::UtcNow
    $items=[ordered]@{ total=0; foreverDB=0; theWoWDB=0; other=0; idOnly=0; speculative=0; oldOrUndated=0; withGathering=0; withVendor=0; withDungeonSource=0; invalidIDs=0 }
    foreach ($key in @($script:ItemCache.Keys)) {
        if ([string]$key -notmatch '^\d{1,7}$' -or [int]$key -le 0) { $items.invalidIDs++;continue }
        $r=$script:ItemCache[$key];$items.total++
        $p=[string]$r.sourceProvider
        if (-not $p) { $p=[string]$r.metadataSource }
        if ($p -match 'ForeverDB') {$items.foreverDB++}
        elseif ($p -match 'TheWoWDB') {$items.theWoWDB++}
        else {$items.other++}
        if ([string]$r.name -match '^Item #\d+$' -or [string]$r.sourceStatus -match 'Catalog ID only') { $items.idOnly++ }
        if ($r.speculation -eq $true -or $r.betaEvent -eq $true -or [string]$r.sourceStatus -match 'Speculative|beta event') { $items.speculative++ }
        if ([string]$r.where -match 'Gathering|Fishing|Mining|Herbalism') { $items.withGathering++ }
        if ($r.soldBy) { $items.withVendor++ }
        if ($r.dungeon -or $r.dungeonSources) { $items.withDungeonSource++ }
        $d=[DateTime]::MinValue
        $checked=[string]$r.referenceCheckedAt
        if (-not [DateTime]::TryParse($checked,[ref]$d) -or $d.ToUniversalTime().AddDays(30) -lt $now) {
            $items.oldOrUndated++
        }
    }
    $recipes=[ordered]@{ total=0; withoutOutput=0; withoutReagents=0; invalidReagents=0; foreverDB=0; ahledger=0; other=0; invalidIDs=0 }
    foreach ($key in @($script:RecipeCache.Keys)) {
        if ([string]$key -notmatch '^\d{1,8}$' -or [long]$key -le 0) { $recipes.invalidIDs++;continue }
        $r=$script:RecipeCache[$key];$recipes.total++
        try {if ([int]$r.resultID -le 0) {$recipes.withoutOutput++}}
        catch {$recipes.withoutOutput++}
        $mats=@($r.reagents | Where-Object { $null -ne $_ })
        if ($mats.Count -eq 0) { $recipes.withoutReagents++ }
        foreach ($m in $mats) {
            try {if ([int]$m.id -le 0 -or [double]$m.count -le 0) {$recipes.invalidReagents++}}
            catch {$recipes.invalidReagents++}
        }
        $provider=[string]$r.sourceProvider
        if (-not $provider) {$provider=[string]$r.source}
        if ($provider -match 'ForeverDB') {$recipes.foreverDB++}
        elseif ($provider -match 'AHledger') {$recipes.ahledger++}
        else {$recipes.other++}
    }
    $dungeons=[ordered]@{ total=0; withBosses=0; withBossAttributedLoot=0; withoutBossAttribution=0; bosses=0; bossLootLinks=0; dungeonOnlyLinks=0; invalidIDs=0 }
    foreach ($key in @($script:DungeonCache.Keys)) {
        if ([string]$key -notmatch '^\d{1,8}$' -or [long]$key -le 0) { $dungeons.invalidIDs++;continue }
        $d=$script:DungeonCache[$key];$dungeons.total++
        $bosses=@($d.bosses | Where-Object { $null -ne $_ })
        if ($bosses.Count -gt 0) {$dungeons.withBosses++}
        $dungeons.bosses += $bosses.Count
        $attributed=0
        foreach ($boss in $bosses) {$attributed+=@($boss.loot | Where-Object { $_ -and [int]$_.id -gt 0 }).Count}
        $dungeons.bossLootLinks+=$attributed
        if ($attributed -gt 0) {$dungeons.withBossAttributedLoot++}
        $unattributed=@($d.dungeonLoot | Where-Object {$_ -and [int]$_.id -gt 0 }).Count
        $dungeons.dungeonOnlyLinks+=$unattributed
        if ($unattributed -gt 0) {$dungeons.withoutBossAttribution++}
    }
    return [ordered]@{
        version='0.9.0'; generatedUTC=$now.ToString('o'); scope='External reference cache only; no character records included';
        verification='Source-reported records are NOT independently confirmed in the live WoW Forever client';
        staleThresholdDays=30; items=$items; recipes=$recipes; dungeons=$dungeons;
    }
}
function Write-FCMReferenceAudit {
    $audit=Get-FCMReferenceAudit
    $json=ConvertTo-Json -InputObject $audit -Depth 6
    $null=ConvertFrom-Json -InputObject $json
    $path=Join-Path $script:Base 'reference-audit.json'
    $temp=$path+'.tmp'
    [IO.File]::WriteAllText($temp,$json,(New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $path -Force
    Log ('REFERENCE HEALTH: {0} items ({1} ID-only, {2} speculative, {3} old/undated); {4} recipes ({5} without output, {6} without reagents); {7} dungeons ({8} with boss-linked loot, {9} with dungeon-only links).' -f $audit.items.total,$audit.items.idOnly,$audit.items.speculative,$audit.items.oldOrUndated,$audit.recipes.total,$audit.recipes.withoutOutput,$audit.recipes.withoutReagents,$audit.dungeons.total,$audit.dungeons.withBossAttributedLoot,$audit.dungeons.withoutBossAttribution)
    Log 'Saved reference-audit.json locally. Counts reflect imported references, not verified live sources. No account/character data is included.'
    return $audit
}
