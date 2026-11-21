local FCM={externalData={dungeons={}}}
assert(loadfile("ForeverCharacterManager/DungeonCatalog.lua"))("FCM",FCM)
local function find(rows,name)
    for _,row in ipairs(rows) do if row.name==name then return row end end
    error("Missing directory row "..name)
end
local empty=FCM:BrowseDungeons("dungeons","all",1)
assert(#empty==35)
local missing=find(empty,"Sunken Temple")
assert(missing.referenceOnly and not missing.imported)
local named,linked,associated=FCM:DungeonReferenceCounts(missing)
assert(named==0 and linked==0 and associated==0)
FCM.externalData.dungeons[12]={
    name="The Temple of Atal'Hakkar",sourceProvider="ForeverDB",bossCount=2,
    bosses={
        {name="First",loot={{id=22},{id=22}}},
        {name="Second",loot={{id=23}}},
    },
    dungeonLoot={{id=24}},
}
local populated=FCM:BrowseDungeons("dungeons","all",1)
assert(#populated==35)
local row=find(populated,"Sunken Temple")
assert(row.imported and row.sourceProvider=="ForeverDB")
assert(row.bosses[1].name=="First" and row.bosses[2].name=="Second")
named,linked,associated=FCM:DungeonReferenceCounts(row)
assert(named==2 and linked==2 and associated==1)
assert(FCM:DungeonAssociatedDrops(row)[1].id==24)
assert(#FCM:BrowseDungeons("dungeons","current",1)==0)
FCM.externalData.items={
    [22]={classID=4,subclass="plate",requiredLevel=20},
    [23]={classID=4,subclass="cloth",requiredLevel=20},
}
assert(FCM:DungeonItemEligibility(22,{class="MAGE",level=1})=="other")
assert(FCM:DungeonItemEligibility(23,{class="MAGE",level=1})=="future")
print("PASS: dungeon aliases, missing references, level-independent browse, boss order and separate loot")
