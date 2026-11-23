# Offline, zero-network regression for explicit boss attribution and source kinds.
# Runs on Windows PowerShell 5.1 and never touches real companion caches.
$ErrorActionPreference = 'Stop'
$script:Base = $PSScriptRoot
function Check-FcmCancel { }
. (Join-Path $PSScriptRoot 'ForeverDB.Provider.ps1')

function Require([bool]$condition,[string]$message) {
    if (-not $condition) {throw $message}
}

try {
    $script:ItemCache=@{}
    $script:DungeonCache=@{}
    $detail=[pscustomobject]@{
        id=9001;name='Fixture Dungeon';type='dungeon'
        bosses=@(
            [pscustomobject]@{id=1001;name='Named Boss'},
            [pscustomobject]@{id=1002;name='Second Boss'}
        )
        loot=@(
            [pscustomobject]@{itemId=6001;name='Boss ID Drop';bossId=1001;seenInForever=$true;observedCount=10;sampleKills=27},
            [pscustomobject]@{itemId=6002;name='Boss Name Drop';bossName='Second Boss';source='Classic'},
            [pscustomobject]@{itemId=6003;name='Unknown Source Drop'},
            [pscustomobject]@{itemId=6004;name='Conflicting ID';bossId=9999;bossName='Second Boss'}
        )
    }
    FDB-SaveDungeon $detail
    $record=$script:DungeonCache['9001']
    Require ($null -ne $record) 'Dungeon fixture was not saved.'
    Require (@($record.bosses[0].loot).Count -eq 1) 'Explicit numeric boss ID was not matched.'
    Require ([int]$record.bosses[0].loot[0].id -eq 6001) 'Wrong numeric boss association.'
    Require (@($record.bosses[1].loot).Count -eq 1) 'Explicit boss name was not matched.'
    Require ([int]$record.bosses[1].loot[0].id -eq 6002) 'Wrong named boss association.'
    Require ($record.bosses[0].loot[0].evidence -eq 'forever-observed' -and $record.bosses[0].loot[0].sampleKills -eq 27) 'Observed evidence was lost.'
    Require ($record.bosses[1].loot[0].evidence -eq 'classic') 'Classic reference was not labeled.'
    Require (@($record.dungeonLoot).Count -eq 2) 'Unattributed or conflicting loot must remain dungeon-wide.'
    Require ([int]$record.dungeonLoot[0].id -eq 6003) 'Unattributed item was lost.'
    . (Join-Path $PSScriptRoot 'ReferencePublication.ps1')
    $builder=[Text.StringBuilder]::new()
    Add-FCMDungeonReferenceLua $builder $script:DungeonCache
    Require ($builder.ToString().Contains('evidence="forever-observed",observedCount=10,sampleKills=27')) 'Export discarded observation metadata.'

    $item=@{}
    $source=[pscustomobject]@{sources=@([pscustomobject]@{
        kind='container';name='Example Cache';zoneName='Example Zone'
    })}
    FDB-ReadFarmDrops $item $source
    Require (@($item.farmSources).Count -eq 1) 'Typed container source was not imported.'
    Require ($item.farmSources[0].kind -eq 'container') 'Container source misidentified as a creature.'

    Write-Host 'PASS: explicit boss ID/name loot, unknown-boss isolation, and typed container imports.'
    exit 0
} catch {
    Write-Host ('FAIL: source mapping test: '+$_.Exception.Message) -ForegroundColor Red
    exit 1
}
