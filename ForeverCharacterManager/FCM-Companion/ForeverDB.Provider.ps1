# Optional ForeverDB.net read-only provider for FCM Data Companion.
# The API key is never written to game addon files, cache exports, or logs.
$script:ForeverDBKeyFile = Join-Path $script:Base 'foreverdb-key.dpapi'
$script:ForeverDBRequests = 0
$script:ForeverDBLimit = 45
$script:ForeverDBItemsImported = 0
$script:ForeverDBRecipesImported = 0
$script:DungeonCache = @{}

function Read-ForeverDBKey {
    if (-not (Test-Path -LiteralPath $script:ForeverDBKeyFile)) { return '' }
    try {
        Add-Type -AssemblyName System.Security
        $cipher = [Convert]::FromBase64String(([IO.File]::ReadAllText($script:ForeverDBKeyFile)).Trim())
        $plain = [Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [Text.Encoding]::UTF8.GetString($plain)
    } catch {
        if ($script:logBox) { Log 'Saved ForeverDB credential could not be unlocked for this Windows user. Re-enter the key.' }
        return ''
    }
}
function Save-ForeverDBCredential {
    if ($null -eq $script:fdbKeyBox -or $null -eq $script:fdbRememberBox) { return }
    $key = $script:fdbKeyBox.Text.Trim()
    if ($script:fdbRememberBox.Checked -and $key) {
        Add-Type -AssemblyName System.Security
        $bytes = [Text.Encoding]::UTF8.GetBytes($key)
        $cipher = [Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllText($script:ForeverDBKeyFile,[Convert]::ToBase64String($cipher),(New-Object System.Text.UTF8Encoding($false)))
    } elseif (Test-Path -LiteralPath $script:ForeverDBKeyFile) {
        Remove-Item -LiteralPath $script:ForeverDBKeyFile -Force
    }
}
function Get-ForeverDBKey {
    if ($null -eq $script:fdbKeyBox) { return '' }
    return [string]$script:fdbKeyBox.Text.Trim()
}
function Fetch-ForeverDB([string]$relative) {
    $key = Get-ForeverDBKey
    Check-FcmCancel
    if (-not $key) { throw 'ForeverDB key not entered.' }
    if ($script:ForeverDBRequests -ge $script:ForeverDBLimit) { throw 'ForeverDB per-sync safety cap reached.' }
    if ($relative -notmatch '^/[a-z0-9/?=&%._-]+$') { throw 'Unsafe ForeverDB route.' }
    # Only use ForeverDB's documented official host and GET paths.
    $url = 'https://foreverdb.net/api/v1' + $relative
    if ($script:ForeverDBRequests -gt 0) { Wait-FcmResponsive 1100 }
    $script:ForeverDBRequests++
    try {
        return Invoke-FcmHttpJson $url @{
            'X-API-Key'=$key;
            'Accept'='application/json';
            'User-Agent'='FCMDataCompanion/0.8.8'
        }
    } catch {
        # Include status only. Exceptions may contain sensitive request headers.
        $status = ''
        $status = Get-FcmHttpStatus $_
        if ($status -eq 429) { throw 'ForeverDB rate limit reached (429); try again later.' }
        if ($status -eq 401 -or $status -eq 403) { throw 'ForeverDB authentication failed. Check your approved API key.' }
        if ($status) { throw "ForeverDB request failed: HTTP $status" }
        throw 'ForeverDB could not be reached or returned an unreadable response.'
    }
}
function FDB-Data($response) {
    if ($null -eq $response) { return $null }
    if ($null -ne $response.data) { return $response.data }
    return $response
}
function FDB-List($object,[string]$member) {
    if ($null -eq $object) { return @() }
    if ($member -and $null -ne $object.$member) { return @($object.$member) }
    if ($object -is [array]) { return @($object) }
    return @()
}
function FDB-Int($value) {
    try { return [int]$value } catch { return 0 }
}
function FDB-ItemId($obj) {
    if ($null -eq $obj) { return 0 }
    if ($obj -is [int] -or $obj -is [long] -or $obj -is [string]) { return FDB-Int $obj }
    foreach ($k in @('itemId','itemID','id')) { if ($obj.$k) { return FDB-Int $obj.$k } }
    if ($obj.item) { return FDB-ItemId $obj.item }
    return 0
}
function FDB-PrettyLocation($obj) {
    if ($null -eq $obj) { return '' }
    $names = @()
    foreach ($k in @('name','zone','zoneName','areaName')) {
        if ($obj.$k -and $obj.$k -is [string]) { $names += [string]$obj.$k }
    }
    if ($obj.location) {
        if ($obj.location.zone) { $names += [string]$obj.location.zone }
        if ($null -ne $obj.location.x -and $null -ne $obj.location.y) {
            $names += ('{0:0.#}, {1:0.#}' -f [double]$obj.location.x,[double]$obj.location.y)
        }
    }
    return (($names | Select-Object -Unique) -join ', ')
}
function FDB-SourceSummary($recipe) {
    if ($null -eq $recipe -or $null -eq $recipe.learnedFrom) { return 'Acquisition not specified by ForeverDB' }
    $sources = $recipe.learnedFrom.sources
    if ($null -eq $sources) { return 'Acquisition not specified by ForeverDB' }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    # Supports both a grouped sources object and a flat sources list.
    $groups = @()
    if ($sources -is [array]) { $groups = @(@{name='Source';rows=@($sources)}) }
    else {
        foreach ($prop in $sources.PSObject.Properties) { $groups += @{name=$prop.Name;rows=@($prop.Value)} }
    }
    foreach ($group in $groups) {
        foreach ($s in $group.rows) {
            if ($null -eq $s) { continue }
            $name = ''
            foreach ($key in @('name','title')) { if ($s.$key) { $name=[string]$s.$key;break } }
            if (-not $name) {
                foreach ($entity in @('vendor','trainer','npc','quest','creature')) {
                    if ($s.$entity -and $s.$entity.name) { $name=[string]$s.$entity.name;break }
                }
            }
            if (-not $name) { continue }
            $place = FDB-PrettyLocation $s
            $seen = if ($s.seenInForever -eq $true -or $s.source -eq 'forever') {' [seen in Forever]'} else {' [reference; verify in Forever]'}
            $message = $group.name + ': ' + $name
            if ($place) { $message += ' (' + $place + ')' }
            $message += $seen
            if (-not $lines.Contains($message)) { $lines.Add($message) }
            if ($lines.Count -ge 10) { break }
        }
        if ($lines.Count -ge 10) { break }
    }
    if ($lines.Count -eq 0) { return 'Acquisition listed by ForeverDB but vendor details could not be resolved.' }
    return ($lines -join '; ')
}
# Safely interpret the documented JSON envelope with data/meta and tolerate
# multiple common list shapes. Never assume that a successful HTTP response
# contains a usable collection.
function FDB-ResponseRows($value,[string[]]$collectionNames) {
    $node=$value
    for ($depth=0; $depth -lt 5; $depth++) {
        if ($null -eq $node) { return @() }
        if ($node -is [array]) { return @($node) }
        $next=$null
        foreach ($name in $collectionNames) {
            $candidate=$node.$name
            if ($null -eq $candidate) { continue }
            if ($candidate -is [array]) { return @($candidate) }
            if ($candidate -is [System.Collections.IEnumerable] -and $candidate -isnot [string] -and $candidate -isnot [System.Collections.IDictionary]) {
                return @($candidate)
            }
            if ($candidate -is [pscustomobject] -or $candidate -is [System.Collections.IDictionary]) { $next=$candidate;break }
        }
        if ($null -ne $next) { $node=$next;continue }
        if ($null -ne $node.data) { $node=$node.data;continue }
        return @()
    }
    return @()
}
function FDB-SafeShape($value) {
    if ($null -eq $value) { return 'null' }
    if ($value -is [array]) { return ('array['+$value.Count+']') }
    if ($value -is [System.Collections.IDictionary]) { return ((@($value.Keys | Select-Object -First 10)) -join ',') }
    return ((@($value.PSObject.Properties.Name | Select-Object -First 10)) -join ',')
}
function FDB-ResourceId($obj,[string[]]$names) {
    if ($null -eq $obj) {return 0}
    if ($obj -is [int] -or $obj -is [long] -or $obj -is [string]) {return FDB-Int $obj}
    foreach ($name in $names) {
        $raw=$obj.$name
        if ($null -ne $raw -and $raw -isnot [pscustomobject] -and $raw -isnot [System.Collections.IDictionary]) {
            $id=FDB-Int $raw
            if ($id -gt 0) {return $id}
        }
    }
    return 0
}
function FDB-ItemName($item) {
    if ($null -eq $item) {return ''}
    foreach ($name in @('name','itemName','displayName','title','label')) {
        $value=$item.$name
        if ($value -is [string] -and $value.Trim()) {return $value.Trim()}
    }
    if ($item.item -and $item.item -ne $item) {return FDB-ItemName $item.item}
    return ''
}
function FDB-DungeonId($obj) {
    $id=FDB-ResourceId $obj @('id','instanceId','instanceID','dungeonId','dungeonID','mapId','mapID')
    if ($id -gt 0) {return $id}
    if ($obj -and $obj.dungeon) {return FDB-DungeonId $obj.dungeon}
    return 0
}
function FDB-DungeonName($obj) {
    if ($null -eq $obj) {return ''}
    foreach ($name in @('name','instanceName','dungeonName','title')) {
        $value=$obj.$name
        if ($value -is [string] -and $value.Trim()) {return $value.Trim()}
    }
    if ($obj.dungeon -and $obj.dungeon -ne $obj) {return FDB-DungeonName $obj.dungeon}
    return ''
}
function FDB-InstanceKind($obj) {
    if ($null -eq $obj) {return ''}
    if ($obj.isRaid -eq $true) {return 'raid'}
    foreach ($field in @('type','instanceType','category','groupType')) {
        $v=[string]$obj.$field
        if ($v -match 'raid') {return 'raid'}
        if ($v -match 'dungeon') {return 'dungeon'}
    }
    return ''
}
function FDB-SaveDungeonSummary($entry,[int]$id) {
    if ($null -eq $entry -or $id -le 0) {return}
    $name=FDB-DungeonName $entry
    if (-not $name) {return}
    $key=[string]$id
    if ($script:DungeonCache.ContainsKey($key) -and $script:DungeonCache[$key].bossCount -gt 0) {return}
    $levelText='Not supplied'
    if ($entry.levelRange) { $levelText=[string]$entry.levelRange }
    elseif ($entry.minLevel -and $entry.maxLevel) {$levelText=([string]$entry.minLevel)+'-'+([string]$entry.maxLevel)}
    $script:DungeonCache[$key]=@{name=$name;levels=$levelText;kind=(FDB-InstanceKind $entry);bossCount=0;lines=@('Dungeon listed by ForeverDB; detailed boss/loot data not yet imported');lootIDs=@()}
}

function FDB-CacheItem([string]$key) {
    $result=@{}
    if (-not $script:ItemCache.ContainsKey($key)) { return $result }
    $original=$script:ItemCache[$key]
    if ($original -is [System.Collections.IDictionary]) {
        foreach ($k in $original.Keys) { $result[[string]$k]=$original[$k] }
    } elseif ($original) {
        foreach ($property in $original.PSObject.Properties) { $result[$property.Name]=$property.Value }
    }
    return $result
}
function FDB-SaveItem($item) {
    if ($null -eq $item) { return }
    $id = FDB-ItemId $item
    # List entries can contain a nested item summary; preserve full detail fields
    # from individual-item requests when available.
    if ($id -le 0) { return }
    $name=FDB-ItemName $item
    if (-not $name) {
        # Keep a traceable ID-only entry rather than silently losing entire
        # catalog pages. Such entries are explicitly not verified item details.
        $name='Item #' + $id
    }
    $key = [string]$id
    $info = FDB-CacheItem $key
    if ($item.item -and $item.item -isnot [string] -and $item.item -isnot [int]) { $item=$item.item }
    # Never replace a known item name with an ID-only placeholder.
    if (-not $info.name -or $name -notmatch '^Item #\d+$') { $info.name = [string]$name }
    if (-not $info.category) { $info.category = 'WoW Forever item' }
    $info.metadataSource = 'Data from ForeverDB.net (https://foreverdb.net)'
    $info.link = 'https://foreverdb.net/items/' + $id
    if ($name -match '^Item #\d+$') {
        $info.sourceStatus = 'Catalog ID only; name and details not yet verified'
    } elseif ($item.betaEvent -eq $true) {
        $info.sourceStatus = 'Historical beta event item; not a standard launch recommendation'
    } elseif ($item.speculation -eq $true -or ($item.speculationReasons -and @($item.speculationReasons).Count -gt 0)) {
        $info.sourceStatus = 'Speculative availability; unverified in live Forever'
    } else {
        $info.sourceStatus = 'ForeverDB client item record; availability not guaranteed'
    }
    # Keep only limited, readable fields; never turn speculative items into guaranteed drops.
    if ($item.stats) {
        $stats=@()
        foreach ($p in $item.stats.PSObject.Properties) { if ($p.Value -and $stats.Count -lt 18) { $stats += $p.Name + ': ' + $p.Value } }
        if ($stats.Count) { $info.stats=$stats -join '; ' }
    }
    # Preserve metadata needed for classification, equipment filtering and trust.
    # Field names differ between compact list results and single-item details.
    $map = @{
        quality=@('quality','rarity');
        itemLevel=@('itemLevel','ilvl');
        requiredLevel=@('requiredLevel','minLevel','requiredCharacterLevel');
        classID=@('classId','classID','itemClassId','itemClassID','class');
        subclass=@('subclassName','subClassName','subclass');
        equipLoc=@('equipLoc','inventoryTypeName','inventorySlotName');
        slotID=@('inventoryType','slotId','slotID');
        binding=@('binding','bindType','bonding');
        sellPrice=@('sellPrice','vendorSellPrice','sell');
    }
    foreach ($field in $map.Keys) {
        foreach ($candidate in $map[$field]) {
            $value=$item.$candidate
            if ($null -eq $value -or $value -is [array] -or $value -is [pscustomobject] -or $value -is [System.Collections.IDictionary]) {continue}
            if ([string]$value -ne '') { $info[$field]=[string]$value;break }
        }
    }
    if ($item.class -and $item.class.id -and -not $info.classID) { $info.classID=[string]$item.class.id }
    if ($item.quality -and $item.quality.id -and -not $info.quality) { $info.quality=[string]$item.quality.id }
    if ($item.quality -and $item.quality.name -and -not $info.quality) { $info.quality=[string]$item.quality.name }
    if ($item.subclass -and $item.subclass.name) { $info.subclass=[string]$item.subclass.name }
    if ($item.equipLoc -and $item.equipLoc.name) { $info.equipLoc=[string]$item.equipLoc.name }
    $info.betaEvent=($item.betaEvent -eq $true)
    $info.speculation=($item.speculation -eq $true)
    if ($item.speculationReasons) { $info.availabilityNote = 'ForeverDB flags uncertain availability; inspect the item page.' }
    if ($item.liveClient) { $info.liveClientNote='Client changes reported; compare with the live in-game tooltip.' }
    if ($item.effects) {
        $effectSummary=@()
        foreach ($effect in @($item.effects | Select-Object -First 6)) {
            $description=''
            if ($effect -is [string]) {$description=$effect}
            elseif ($effect.description) {$description=[string]$effect.description}
            elseif ($effect.name) {$description=[string]$effect.name}
            if ($description) { $effectSummary += $description.Substring(0,[Math]::Min(170,$description.Length)) }
        }
        if ($effectSummary.Count) {$info.effects=$effectSummary -join '; '}
        else { $info.effects='Effect records present; review item in game' }
    }
    $script:ItemCache[$key] = $info
    $script:ForeverDBItemsImported++
}
function FDB-RecipeRows($data) {
    if ($data -is [array]) { return @($data) }
    if ($data.recipes) {
        if ($data.recipes -is [array]) { return @($data.recipes) }
        if ($data.recipes.data) { return @($data.recipes.data) }
        if ($data.recipes.items) { return @($data.recipes.items) }
    }
    if ($data.items) { return @($data.items) }
    return @()
}
function FDB-SaveRecipe($recipe,[string]$profession) {
    if ($null -eq $recipe) { return }
    $id=0
    foreach ($f in @('spellId','spellID','recipeId','recipeID','id')) { if ($recipe.$f) { $id=FDB-Int $recipe.$f; if ($id -gt 0) { break } } }
    if ($id -le 0 -or -not $recipe.name) { return }
    $mats = @()
    foreach ($mat in @(FDB-List $recipe 'reagents')) {
        $mid=FDB-ItemId $mat
        $qty=0
        foreach ($k in @('count','quantity','qty','amount')) { if ($mat.$k) { $qty = FDB-Int $mat.$k;break } }
        if ($mid -gt 0 -and $qty -gt 0) { $mats += @{id=$mid;count=$qty;name=[string]$mat.name} }
    }
    $resultID=0
    foreach ($f in @('outputItemId','outputItemID','resultItemId','createsItemId')) {
        if ($recipe.$f) { $resultID=FDB-Int $recipe.$f;break }
    }
    if (-not $resultID) {
        foreach ($f in @('makes','output','result','creates')) {
            if ($recipe.$f) { $resultID=FDB-ItemId $recipe.$f; if ($resultID -gt 0) { break } }
        }
    }
    $skill=0
    if ($recipe.skill) {
        if ($recipe.skill -is [string] -or $recipe.skill -is [int]) { $skill=FDB-Int $recipe.skill }
        elseif ($recipe.skill.orange) { $skill=FDB-Int $recipe.skill.orange }
    }
    if ($recipe.requiredSkill) { $skill=FDB-Int $recipe.requiredSkill }
    $r=[ordered]@{
        name=[string]$recipe.name; profession=$profession; skill=$skill;
        resultID=$resultID; reagents=$mats;
        acquisition=(FDB-SourceSummary $recipe);
        source='Recipe data from ForeverDB.net (https://foreverdb.net); acquisition confidence varies'
    }
    # If recipe is missing a verified output or reagent list, keep it in the
    # Item Explorer reference library only; do not make craft-ready claims.
    $script:RecipeCache[[string]$id]=$r
    $script:ForeverDBRecipesImported++
    if ($resultID -gt 0) {
        $key=[string]$resultID
        $info=FDB-CacheItem $key
        if (-not $info.name) { $info.name=[string]$recipe.name }
        $info.recipes = $r.acquisition
        $info.metadataSource = 'Data from ForeverDB.net (https://foreverdb.net)'
        $script:ItemCache[$key]=$info
    }
}
function FDB-FishingLocations($response) {
    $data=FDB-Data $response
    $zones=@()
    if ($data.zones) { $zones=@($data.zones) }
    elseif ($data.fishing -and $data.fishing.zones) { $zones=@($data.fishing.zones) }
    foreach ($zone in $zones) {
        $zoneName = if ($zone.name) {[string]$zone.name} elseif ($zone.zone) {[string]$zone.zone} else {''}
        if (-not $zoneName) { continue }
        $catches=@()
        foreach ($key in @('catches','fish','items')) { if ($zone.$key) { $catches=@($zone.$key);break } }
        foreach ($catch in $catches) {
            $id = FDB-ItemId $catch
            if ($id -le 0) { continue }
            $key=[string]$id
            $info=FDB-CacheItem $key
            $old=[string]$info.where
            if ($old -notlike "*$zoneName*") {
                if ($old) { $info.where = $old + '; ' + $zoneName }
                else { $info.where = 'Fishing zone: ' + $zoneName }
            }
            $info.metadataSource = 'Fishing reference: ForeverDB.net (https://foreverdb.net); check source confidence'
            $script:ItemCache[$key]=$info
        }
    }
}
function FDB-Gathering($response,[string]$kind) {
    $data=FDB-Data $response
    # Different endpoints group by nodes, herbs, veins, catches or zones.
    $groups=@()
    foreach ($prop in @('nodes','herbs','veins','fish','catches','resources','items')) {
        if ($data.$prop) { $groups+=@($data.$prop) }
    }
    foreach ($g in $groups) {
        $id=FDB-ItemId $g
        if ($id -le 0) {continue}
        $key=[string]$id; $item=FDB-CacheItem $key
        $zones=@()
        if ($g.zones) {
            foreach ($zone in @($g.zones)) { $z=FDB-PrettyLocation $zone; if ($z) { $zones+=$z } }
        }
        if ($zones.Count -gt 0) {
            $where=$kind + ': ' + (($zones | Select-Object -Unique | Select-Object -First 14) -join ', ')
            if ($item.where -and $item.where -ne $where) { $item.where += '; ' + $where }
            else { $item.where=$where }
            $item.metadataSource='Gathering reference: ForeverDB.net (https://foreverdb.net)'
            $script:ItemCache[$key]=$item
        }
    }
}
function FDB-ArrayRows($node,[string[]]$nestedNames) {
    if ($null -eq $node) {return @()}
    if ($node -is [array]) {return @($node)}
    if ($node -is [System.Collections.IEnumerable] -and $node -isnot [string] -and $node -isnot [System.Collections.IDictionary] -and $node -isnot [pscustomobject]) {
        return @($node)
    }
    if ($node -is [pscustomobject] -or $node -is [System.Collections.IDictionary]) {
        foreach ($nested in $nestedNames) {
            if ($null -ne $node.$nested) {return @(FDB-ArrayRows $node.$nested @('items','entries','drops','bosses','encounters','records','results','data','list'))}
        }
    }
    return @()
}
function FDB-BossRows($detail) {
    # Some API responses contain boss names as strings, not boss objects.
    foreach ($key in @('bosses','encounters','bossList','bossNames')) {
        $node=$detail.$key
        if ($null -eq $node) {continue}
        $rows=@(FDB-ArrayRows $node @('items','bosses','encounters','entries','data','list','names','records'))
        if ($rows.Count -gt 0) {return $rows}
    }
    if ($detail.dungeon -and $detail.dungeon -ne $detail) {return @(FDB-BossRows $detail.dungeon)}
    return @()
}
function FDB-BossName($boss) {
    if ($null -eq $boss) {return ''}
    if ($boss -is [string]) {return $boss.Trim()}
    foreach ($key in @('name','bossName','creatureName','displayName','encounterName','title')) {
        if ($boss.$key -is [string] -and $boss.$key.Trim()) {return [string]$boss.$key.Trim()}
    }
    foreach ($node in @('npc','creature','encounter','boss','unit')) {
        if ($boss.$node -is [string] -and $boss.$node.Trim()) {return [string]$boss.$node.Trim()}
        if ($boss.$node -and $boss.$node.name) {return [string]$boss.$node.name}
    }
    $bossId=FDB-ResourceId $boss @('id','bossId','npcId','creatureId')
    if ($bossId -gt 0) {return "Boss #$bossId (name unavailable)"}
    return 'Boss name not supplied by source'
}
function FDB-BossLoot($boss) {
    if ($null -eq $boss -or $boss -is [string]) {return @()}
    foreach ($field in @('loot','notableLoot','lootTable','drops','items','rewards')) {
        $node=$boss.$field
        if ($null -eq $node) {continue}
        $rows=@(FDB-ArrayRows $node @('items','entries','drops','loot','results','rewards','data'))
        if ($rows.Count -gt 0) {return $rows}
    }
    return @()
}
function FDB-DungeonLoot($detail) {
    # These records are tied to the dungeon, NOT automatically to a boss.
    foreach ($field in @('notableLoot','loot','dungeonLoot','lootTable','drops')) {
        $node=$detail.$field
        if ($null -eq $node) {continue}
        $rows=@(FDB-ArrayRows $node @('items','entries','drops','loot','results','rewards','data'))
        if ($rows.Count -gt 0) {return $rows}
    }
    if ($detail.dungeon -and $detail.dungeon -ne $detail) {return @(FDB-DungeonLoot $detail.dungeon)}
    return @()
}
function FDB-DropBossName($drop) {
    if ($null -eq $drop) {return ''}
    foreach ($field in @('bossName','sourceBoss','droppedByBoss','encounterName')) {
        if ($drop.$field -is [string] -and $drop.$field.Trim()) {return [string]$drop.$field.Trim()}
    }
    foreach ($field in @('boss','encounter','droppedBy')) {
        $node=$drop.$field
        if ($node -is [string] -and $node.Trim()) {return [string]$node.Trim()}
        if ($node -and $node.name -is [string]) {return [string]$node.name.Trim()}
    }
    # A generic source string may mean 'client clue', not a boss name.
    if ($drop.source -and $drop.source.bossName) {return [string]$drop.source.bossName}
    return ''
}
function FDB-DropEntry($drop) {
    $itemId=FDB-ItemId $drop
    if ($itemId -le 0) {return $null}
    $name=FDB-ItemName $drop
    if (-not $name) {$name='Item #'+$itemId}
    return @{id=$itemId;name=$name}
}
function FDB-RecordDungeonItem([int]$itemId,[string]$itemName,[string]$dungeon,[string]$bossName) {
    $ref=FDB-CacheItem ([string]$itemId)
    if (-not $ref.name -or $ref.name -match '^Item #\d+$') {$ref.name=$itemName}
    $ref.dungeon=$dungeon + $(if ($bossName) {' / ' + $bossName} else {' (boss unconfirmed)'})
    $ref.metadataSource='Data from ForeverDB.net (https://foreverdb.net); dungeon association only, not confirmed live drop'
    $script:ItemCache[[string]$itemId]=$ref
}
function FDB-SaveDungeon($detail) {
    if ($null -eq $detail) {return}
    $id=FDB-DungeonId $detail
    $dungeonName=FDB-DungeonName $detail
    if ($id -le 0 -or -not $dungeonName) {return}
    $bossRecords=@();$lines=@();$dungeonLoot=@()
    $lootIDs=New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($boss in @(FDB-BossRows $detail)) {
        Check-FcmCancel
        if ($null -eq $boss -or $bossRecords.Count -ge 90) {continue}
        $bossName=FDB-BossName $boss
        $bossId=FDB-ResourceId $boss @('id','bossId','npcId','creatureId')
        $drops=@();$bossSeen=@{}
        foreach ($drop in @(FDB-BossLoot $boss)) {
            if ($null -eq $drop -or $drops.Count -ge 65) {continue}
            $entry=FDB-DropEntry $drop
            if (-not $entry -or $bossSeen.ContainsKey([string]$entry.id)) {continue}
            $bossSeen[[string]$entry.id]=$true
            $drops+= $entry
            [void]$lootIDs.Add([int]$entry.id)
            FDB-RecordDungeonItem $entry.id $entry.name $dungeonName $bossName
        }
        $bossRecords+=@{id=$bossId;name=$bossName;loot=@($drops)}
        $lines+='Boss: '+$bossName+' ('+$drops.Count+' attributed loot records)'
    }
    $dungeonSeen=@{}
    foreach ($drop in @(FDB-DungeonLoot $detail)) {
        Check-FcmCancel
        if ($null -eq $drop -or $dungeonLoot.Count -ge 100) {continue}
        $entry=FDB-DropEntry $drop
        if (-not $entry) {continue}
        [void]$lootIDs.Add([int]$entry.id)
        $sourceName=FDB-DropBossName $drop
        $matched=-1
        if ($sourceName) {
            for ($i=0;$i -lt $bossRecords.Count;$i++) {
                if ($bossRecords[$i].name -ieq $sourceName) {$matched=$i;break}
            }
        }
        if ($matched -ge 0) {
            $seen=@($bossRecords[$matched].loot | Where-Object {[int]$_.id -eq [int]$entry.id})
            if ($seen.Count -eq 0 -and $bossRecords[$matched].loot.Count -lt 65) {
                $bossRecords[$matched].loot+= $entry
            }
            FDB-RecordDungeonItem $entry.id $entry.name $dungeonName $sourceName
        } else {
            $alreadyAttributed=$false
            foreach ($knownBoss in $bossRecords) {
                foreach ($knownDrop in @($knownBoss.loot)) {
                    if ([int]$knownDrop.id -eq [int]$entry.id) {$alreadyAttributed=$true;break}
                }
                if ($alreadyAttributed) {break}
            }
            if (-not $alreadyAttributed -and -not $dungeonSeen.ContainsKey([string]$entry.id)) {
                # No demonstrable boss association: list once at the dungeon level.
                $dungeonSeen[[string]$entry.id]=$true
                $dungeonLoot+= $entry
                FDB-RecordDungeonItem $entry.id $entry.name $dungeonName ''
            }
        }
    }
    $levelText='Not supplied'
    if ($detail.levelRange) {$levelText=[string]$detail.levelRange}
    elseif ($detail.minLevel -and $detail.maxLevel) {$levelText=([string]$detail.minLevel)+'-'+([string]$detail.maxLevel)}
    $kind=FDB-InstanceKind $detail
    $old=$script:DungeonCache[[string]$id]
    if (-not $kind -and $old) {$kind=[string]$old.kind}
    if ($levelText -eq 'Not supplied' -and $old -and $old.levels) {$levelText=[string]$old.levels}
    # Retain better cached details when the API temporarily returns less data.
    $oldBosses=@()
    if ($old -and $old.bosses) {$oldBosses=@($old.bosses | Where-Object {$_})}
    if ($bossRecords.Count -eq 0 -and $oldBosses.Count -gt 0) {
        $bossRecords=$oldBosses
    }
    if ($dungeonLoot.Count -eq 0 -and $old -and $old.dungeonLoot) {
        $dungeonLoot=@($old.dungeonLoot | Where-Object {$_})
    }
    if ($oldBosses.Count -gt 0 -and $bossRecords.Count -eq $oldBosses.Count) {
        for ($i=0;$i -lt $bossRecords.Count;$i++) {
            $before=$oldBosses[$i]
            if ($before.name -and ([string]$before.name) -notmatch 'name not supplied|name unavailable' -and
                    ([string]$bossRecords[$i].name) -match 'name not supplied|name unavailable') {
                $bossRecords[$i].name=[string]$before.name
            }
            $newDrops=@($bossRecords[$i].loot | Where-Object {$_})
            if ($newDrops.Count -eq 0 -and $before.loot) {
                $bossRecords[$i].loot=@($before.loot | Where-Object {$_})
            }
        }
    }
    foreach ($b in $bossRecords) {foreach ($drop in @($b.loot)) {if ([int]$drop.id -gt 0) {[void]$lootIDs.Add([int]$drop.id)}}}
    foreach ($drop in $dungeonLoot) {if ([int]$drop.id -gt 0) {[void]$lootIDs.Add([int]$drop.id)}}
    $script:DungeonCache[[string]$id]=@{name=$dungeonName;levels=$levelText;kind=$kind;
        bossCount=$bossRecords.Count;bosses=@($bossRecords);dungeonLoot=@($dungeonLoot);lines=$lines;lootIDs=@($lootIDs)}
}
function FDB-SaveVendor($vendor) {
    if ($null -eq $vendor -or -not $vendor.name) { return 0 }
    $location=FDB-PrettyLocation $vendor
    $seen=($vendor.seenInForever -eq $true)
    $count=0
    $goods=@()
    foreach ($field in @('items','stock','sells','inventory','wares')) {
        if ($vendor.$field) { $goods=@($vendor.$field);break }
    }
    foreach ($good in $goods) {
        $id=FDB-ItemId $good
        if ($id -le 0) { continue }
        $key=[string]$id
        $entry=FDB-CacheItem $key
        if (-not $entry.name -and $good.name) { $entry.name=[string]$good.name }
        $tag=([string]$vendor.name)
        if ($location) {$tag+=' (' + $location + ')'}
        $tag += $(if ($seen) {' [observed in Forever]'} else {' [reference, not verified in Forever]'})
        if ([string]$entry.soldBy -notlike "*$([string]$vendor.name)*") {
            if ($entry.soldBy) { $entry.soldBy = [string]$entry.soldBy + '; ' + $tag }
            else { $entry.soldBy = $tag }
        }
        $entry.vendorSource='Vendor records from ForeverDB.net (https://foreverdb.net)'
        $script:ItemCache[$key]=$entry
        $count++
    }
    return $count
}
function Sync-ForeverDB {
    Check-FcmCancel
    if (-not (Get-ForeverDBKey)) {
        Log 'ForeverDB not configured; public TheWoWDB/AHledger refresh still works. An approved ForeverDB key is optional.'
        return
    }
    $script:ForeverDBRequests=0
    $script:ForeverDBItemsImported=0
    $script:ForeverDBRecipesImported=0
    try {
        $meta=Fetch-ForeverDB '/meta'
        $build = (FDB-Data $meta).build
        Log ('ForeverDB API connected' + $(if ($build) {"; reference build $build."} else {'.'}))
    } catch {
        Log ('ForeverDB skipped: ' + $_.Exception.Message)
        return
    }
    # First repaired run goes back to page zero: older versions advanced the
    # cursor even when item rows could not be decoded and saved.
    if ((FDB-Int $script:Config.fdbCatalogImporter) -lt 2) {
        $script:Config.fdbItemOffset=0
        $script:Config.fdbDungeonOffset=0
        $script:Config.fdbCatalogImporter=2
        Log 'Catalog migration: restarting from offset 0 to recover item pages skipped by older importers; cached records are retained.'
    }
    # Fetch up to ten pages per run, never counting an unsaved page as progress.
    try {
        $itemOffset=[int]$script:Config.fdbItemOffset
        $pageCount=0; $seen=0; $saved=0; $reachedEnd=$false
        for ($pageIndex=0; $pageIndex -lt 10; $pageIndex++) {
            Check-FcmCancel
            if ($script:ForeverDBRequests -ge ($script:ForeverDBLimit - 18)) {break}
            $page=FDB-Data (Fetch-ForeverDB ("/items?limit=100&offset=$itemOffset"))
            $items=@(FDB-ResponseRows $page @('items','results','records','entries','list'))
            if ($items.Count -eq 0) {
                # Empty results can be the end of the catalog, or a changed
                # JSON envelope. Log shape without exposing item/player data.
                if ($pageCount -eq 0) {Log ('Catalog response fields: ' + (FDB-SafeShape $page))}
                $reachedEnd=$true
                break
            }
            $countBefore=$script:ItemCache.Count
            $validated=0
            foreach ($item in $items) {
                $id=FDB-ItemId $item
                if ($id -le 0 -and $item.item) {$id=FDB-ItemId $item.item}
                if ($id -le 0) {continue}
                FDB-SaveItem $item
                if ($script:ItemCache.ContainsKey([string]$id)) {$validated++}
            }
            if ($validated -eq 0) {
                Log ('CATALOG PARSE WARNING: ' + $items.Count + ' rows returned at offset ' + $itemOffset + ' but none could be saved. First row fields: ' + (FDB-SafeShape $items[0]) + '. Cursor not advanced.')
                break
            }
            $itemOffset+=$items.Count
            $seen+=$items.Count
            $saved+=$validated
            $pageCount++
            if ($items.Count -lt 100) {$reachedEnd=$true;break}
            [System.Windows.Forms.Application]::DoEvents()
        }
        $script:Config.fdbItemOffset=$(if ($reachedEnd) {0} else {$itemOffset})
        Log "ForeverDB catalog: $seen returned; $saved recognized item entries across $pageCount pages; $($script:ItemCache.Count) cached; next offset $($script:Config.fdbItemOffset)."
        if ($reachedEnd) {Log 'ForeverDB catalog end reached; a subsequent pass starts from the beginning.'}
    } catch {Log ('ForeverDB catalog pagination stopped; existing cached records retained: ' + $_.Exception.Message)}

    # Fetch the full instance index in one request. Detailed boss records are
    # obtained in eight-record batches, keeping the per-sync API budget bounded.
    # The in-game curated directory remains useful even without any API response.
    Check-FcmCancel
    if ($script:ForeverDBRequests -lt ($script:ForeverDBLimit-7)) {
        try {
            $payload=FDB-Data (Fetch-ForeverDB '/dungeons?limit=100&offset=0')
            $rows=@(FDB-ResponseRows $payload @('dungeons','items','instances','results','records','entries'))
            if ($rows.Count -eq 0) {
                Log ('ForeverDB dungeon listing contained no recognized rows; response fields: ' + (FDB-SafeShape $payload))
            } else {
                $index=@();$badIDs=0
                foreach ($entry in $rows) {
                    Check-FcmCancel
                    $id=FDB-DungeonId $entry
                    if ($id -le 0) { $badIDs++;continue }
                    FDB-SaveDungeonSummary $entry $id
                    $index+=@($id)
                }
                if ($badIDs -gt 0) {Log ('Dungeon entries without numeric IDs: ' + $badIDs + '; sample fields: ' + (FDB-SafeShape $rows[0]))}
                $index=@($index | Select-Object -Unique)
                # fdbDungeonOffset now points at the next record awaiting detail,
                # not the list page offset. Cap work to eight details per scan.
                $cursor=[int]$script:Config.fdbDungeonOffset
                if ($cursor -lt 0 -or $cursor -ge $index.Count) { $cursor=0 }
                $details=0
                $reportedShape=$false
                for ($i=0; $i -lt [Math]::Min(8,$index.Count); $i++) {
                    Check-FcmCancel
                    if ($script:ForeverDBRequests -ge ($script:ForeverDBLimit-3)) {break}
                    $id=[int]$index[($cursor+$i) % $index.Count]
                    try {
                        $detail=FDB-Data (Fetch-ForeverDB ("/dungeons/$id"))
                        if (-not $reportedShape) {
                            Log ('Dungeon detail fields (names only): ' + (FDB-SafeShape $detail))
                            $reportedShape=$true
                        }
                        if ((FDB-DungeonId $detail) -eq $id -and (FDB-DungeonName $detail)) {
                            FDB-SaveDungeon $detail
                            $details++
                        } else {
                            Log "Dungeon #$id detail response was missing an ID or name; summary retained."
                        }
                    } catch {Log "Dungeon #$id details unavailable; summary retained."}
                }
                if ($index.Count -gt 0) { $script:Config.fdbDungeonOffset=($cursor+[Math]::Min(8,$index.Count)) % $index.Count }
                $withBoss=0; $withLoot=0; $namedBosses=0; $linkedDrops=0
                foreach ($rec in @($script:DungeonCache.Values)) {
                    $bs=@($rec.bosses)
                    if ($bs.Count -gt 0 -and $null -ne $rec.bosses) {$withBoss++}
                    $localDrops=0
                    foreach ($b in $bs) {
                        if (-not $b) {continue}
                        if ($b.name -and ([string]$b.name) -notmatch 'name not supplied|name unavailable') {$namedBosses++}
                        $localDrops+=@($b.loot | Where-Object {$_}).Count
                    }
                    $localDrops+=@($rec.dungeonLoot | Where-Object {$_}).Count
                    if ($localDrops -gt 0) {$withLoot++}
                    $linkedDrops+=$localDrops
                }
                Log "ForeverDB dungeons: $($index.Count) index entries, $details detail responses this sync, $($script:DungeonCache.Count) cached instances; $withBoss with bosses, $withLoot with loot, $namedBosses named boss records, $linkedDrops dungeon/boss-associated items; next detail index $($script:Config.fdbDungeonOffset)."
            }
        } catch {Log ('ForeverDB dungeon listing unavailable: ' + $_.Exception.Message)}
    }

    Check-FcmCancel
    $ids=@(Get-ObservedIds)
    $ids+=6291
    foreach ($term in ($script:termsBox.Text -split '[,;\r\n]')) {
        Check-FcmCancel
        $s=$term.Trim()
        if (-not $s) { continue }
        if ($s -match '^\d{1,7}$') { $ids += [int]$s; continue }
        try {
            $result=Fetch-ForeverDB ('/items?q=' + [uri]::EscapeDataString($s) + '&limit=12')
            $data=FDB-Data $result
            $rows=@()
            if ($data.items) { $rows=@($data.items) }
            elseif ($data -is [array]) { $rows=@($data) }
            foreach ($item in $rows) { FDB-SaveItem $item; $id=FDB-ItemId $item; if ($id -gt 0) { $ids += $id } }
        } catch { Log ('ForeverDB item search unavailable: ' + $_.Exception.Message) }
        if ($script:ForeverDBRequests -ge 6) { break }
    }
    $ids=@($ids | Sort-Object -Unique | Select-Object -First 20)
    foreach ($id in $ids) {
        Check-FcmCancel
        if ($script:ForeverDBRequests -ge 27) { break }
        try { FDB-SaveItem (FDB-Data (Fetch-ForeverDB "/items/$id")) }
        catch { Log "ForeverDB item #$id lookup unavailable; cached details retained." }
        [System.Windows.Forms.Application]::DoEvents()
    }
    foreach ($profession in @('cooking','tailoring','enchanting','engineering','first-aid','alchemy','blacksmithing','leatherworking')) {
        Check-FcmCancel
        if ($script:ForeverDBRequests -ge ($script:ForeverDBLimit - 5)) { break }
        try {
            $offsetKey='fdbProfessionOffset_' + $profession
            $offset=[int]$script:Config[$offsetKey]
            $res=Fetch-ForeverDB ("/professions/${profession}?limit=100&offset=$offset")
            $data=FDB-Data $res
            $rows=@(FDB-RecipeRows $data)
            foreach ($r in $rows) { FDB-SaveRecipe $r $profession }
            if ($rows.Count -gt 0) { $script:Config[$offsetKey]=$offset+$rows.Count }
            else { $script:Config[$offsetKey]=0 }
            Log "ForeverDB $profession imported: $($rows.Count) recipes (offset $offset)."
        } catch { Log "ForeverDB $profession reference lookup unavailable; older cached data retained." }
        [System.Windows.Forms.Application]::DoEvents()
    }
    foreach ($kind in @('fishing','mining','herbalism','skinning')) {
        Check-FcmCancel
        if ($script:ForeverDBRequests -ge ($script:ForeverDBLimit - 3)) {break}
        try {
            $gathered=Fetch-ForeverDB ('/gathering/' + $kind)
            if ($kind -eq 'fishing') {FDB-FishingLocations $gathered}
            FDB-Gathering $gathered $kind
        } catch { Log "ForeverDB $kind reference unavailable; keeping cached values." }
    }
    # An acquisition source is never inferred from reputationFaction:
    # on vendors this normally indicates a price discount, not an unlock gate.
    Check-FcmCancel
    if ($script:ForeverDBRequests -lt ($script:ForeverDBLimit-5)) {
        try {
            $vendorOffset=[int]$script:Config.fdbVendorOffset
            $response=FDB-Data (Fetch-ForeverDB ("/vendors?limit=5&offset=$vendorOffset"))
            $vendors=if ($response.vendors) {@($response.vendors)} elseif ($response.items) {@($response.items)} elseif ($response -is [array]) {@($response)} else {@()}
            if ($vendors.Count -gt 0) { $script:Config.fdbVendorOffset=$vendorOffset+$vendors.Count }
            else { $script:Config.fdbVendorOffset=0 }
            $count=0
            foreach ($vendor in @($vendors | Select-Object -First 4)) {
                if ($script:ForeverDBRequests -ge ($script:ForeverDBLimit - 1)) {break}
                $id=FDB-Int $vendor.id
                if ($id -le 0) {continue}
                try { $count+=FDB-SaveVendor (FDB-Data (Fetch-ForeverDB "/vendors/$id")) }
                catch { Log "Vendor #$id details unavailable; kept previous data." }
            }
            Log "ForeverDB vendor inventory: $count item source links this sync."
        } catch { Log 'ForeverDB vendor import unavailable; cached items kept.' }
    }
    Check-FcmCancel
    Save-ForeverDBCredential
    Save-Config
    Log "ForeverDB update complete: $($script:ForeverDBItemsImported) item entries, $($script:ForeverDBRecipesImported) recipe entries, $($script:ForeverDBRequests) API calls."
}
