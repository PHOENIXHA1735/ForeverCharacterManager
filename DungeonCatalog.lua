local _, FCM = ...
-- v0.7.7: static, sourced dungeon *directory*; boss/loot records remain imported.
-- Levels below are Icy Veins reference ranges (24 October 2026), not a promise of entry,
-- level appropriateness, faction accessibility, current loot, or client availability.
local source = "https://www.icy-veins.com/wow-forever/dungeons-overview"
local directory = {
    {name="Ragefire Chasm", low=13, high=18, new=false},
    {name="Hall of Thanes", low=13, high=20, new=true},
    {name="Ruins of Lordaeron", low=15, high=22, new=true},
    {name="Wailing Caverns", low=15, high=24, new=false},
    {name="Deadmines", low=17, high=26, new=false},
    {name="Shadowfang Keep", low=20, high=30, new=false},
    {name="Blackfathom Deeps", low=24, high=32, new=false},
    {name="Stormwind Stockades", low=24, high=32, new=false},
    {name="Excavation Site: Wetlands", low=26, high=33, new=true},
    {name="City of Dalaran", low=28, high=35, new=true},
    {name="Gnomeregan", low=29, high=38, new=false},
    {name="Razorfen Kraul", low=29, high=38, new=false},
    {name="Scarlet Monastery - Graveyard", low=30, high=38, new=false},
    {name="Scarlet Monastery - Library", low=33, high=41, new=false},
    {name="The Drowned City", low=35, high=40, new=true},
    {name="Scarlet Monastery - Armory", low=36, high=44, new=false},
    {name="Razorfen Downs", low=37, high=46, new=false},
    {name="Scarlet Monastery - Cathedral", low=38, high=46, new=false},
    {name="Krol'dok Stronghold", low=40, high=45, new=true},
    {name="Uldaman", low=41, high=51, new=false},
    {name="Zul'Farrak", low=44, high=54, new=false},
    {name="Maraudon", low=46, high=55, new=false},
    {name="Alcaz Island Prison", low=48, high=53, new=true},
    {name="Sunken Temple", low=50, high=60, new=false},
    {name="Blackrock Depths", low=52, high=60, new=false},
    {name="Dire Maul (East)", low=54, high=60, new=false},
    {name="Blackmaw Hold", low=55, high=60, new=true},
    {name="Lower Blackrock Spire", low=55, high=60, new=false},
    {name="Dire Maul (North)", low=56, high=60, new=false},
    {name="Dire Maul (West)", low=56, high=60, new=false},
    {name="Scholomance", low=58, high=60, new=false},
    {name="Shaper's Terrace", low=58, high=60, new=true},
    {name="Stratholme (Main Gate)", low=58, high=60, new=false},
    {name="Stratholme (Service Gate)", low=58, high=60, new=false},
    {name="Upper Blackrock Spire", low=59, high=60, new=false},
}
FCM.dungeonDirectorySource = source
FCM.dungeonDirectory = directory
local aliases = {
    ["thedeadmines"]="deadmines",
    ["thehallofthanes"]="hallofthanes",
    ["thestockade"]="stormwindstockades",
    ["thestockades"]="stormwindstockades",
    ["stormwindstockade"]="stormwindstockades",
    ["scarletmonasterygraveyard"]="scarletmonasterygraveyard",
    ["scarletmonasterylibrary"]="scarletmonasterylibrary",
    ["scarletmonasteryarmory"]="scarletmonasteryarmory",
    ["scarletmonasterycathedral"]="scarletmonasterycathedral",
    ["alcazprison"]="alcazislandprison",
    ["excavationsite"]="excavationsitewetlands",
    ["diremauleast"]="diremauleast",
    ["diremaulnorth"]="diremaulnorth",
    ["diremaulwest"]="diremaulwest",
    ["blackrockspirelower"]="lowerblackrockspire",
    ["blackrockspireupper"]="upperblackrockspire",
}
local raids = {
    ["templeofahnqiraj"]=true, ["ahnqirajtemple"]=true,
    ["ruinsofahnqiraj"]=true, ["naxxramas"]=true,
    ["moltencore"]=true, ["blackwinglair"]=true,
    ["onyxiaslair"]=true, ["zulgurub"]=true,
}
local function normalized(name)
    local key=string.lower(tostring(name or "")):gsub("[^%w]", "")
    return aliases[key] or key
end
local function recordKind(rec, normalizedName)
    local declared=string.lower(tostring(rec.kind or rec.type or rec.instanceType or ""))
    if declared:find("raid",1,true) then return "raid" end
    if declared:find("dungeon",1,true) then return "dungeon" end
    if raids[normalizedName] then return "raid" end
    return "unclassified"
end
function FCM:BrowseDungeons(view,levelFilter,playerLevel)
    view=(view=="raids" or view=="all") and view or "dungeons"
    levelFilter=(levelFilter=="current") and "current" or "all"
    playerLevel=tonumber(playerLevel)
    local rows,byName,used={}, {}, {}
    local live=(self.externalData and self.externalData.dungeons) or {}
    for id,entry in pairs(live) do
        if type(entry)=="table" and entry.name then
            local key=normalized(entry.name)
            if key~="" then
                local old=byName[key]
                if not old or (tonumber(entry.bossCount) or 0)>(tonumber(old.record.bossCount) or 0) then
                    byName[key]={id=id,record=entry}
                end
            end
        end
    end
    for i,ref in ipairs(directory) do
        local key=normalized(ref.name)
        local imported=byName[key]
        local entry=imported and imported.record or nil
        if imported then used[imported.id]=true end
        local row={id="guide:"..i,name=ref.name,kind="dungeon",low=ref.low,high=ref.high,
            levels=ref.low.."-"..ref.high, newToForever=ref.new,source=source,
            bossCount=entry and tonumber(entry.bossCount) or nil,
            lines=entry and entry.lines or nil,lootIDs=entry and entry.lootIDs or nil,
            bosses=entry and entry.bosses or nil,
            dungeonLoot=entry and entry.dungeonLoot or nil,
            imported=entry~=nil,referenceOnly=entry==nil}
        if (view=="dungeons" or view=="all") and
            (levelFilter~="current" or (playerLevel and playerLevel>=ref.low and playerLevel<=ref.high)) then
            rows[#rows+1]=row
        end
    end
    for id,rec in pairs(live) do
        if type(rec)=="table" and rec.name and not used[id] then
            local key=normalized(rec.name)
            local kind=recordKind(rec,key)
            local low,high=tostring(rec.levels or ""):match("(%d+)%s*[-–]%s*(%d+)")
            low,high=tonumber(low),tonumber(high)
            if (view=="all" or (view=="raids" and kind=="raid") or
                    (view=="dungeons" and kind=="dungeon")) and
                (levelFilter~="current" or (playerLevel and low and high and playerLevel>=low and playerLevel<=high)) then
                rows[#rows+1]={id="import:"..tostring(id),name=rec.name,kind=kind,
                    low=low,high=high,levels=rec.levels or "Not supplied",
                    bossCount=tonumber(rec.bossCount),lines=rec.lines,lootIDs=rec.lootIDs,
                    bosses=rec.bosses,dungeonLoot=rec.dungeonLoot,
                    imported=true,source="https://foreverdb.net",referenceOnly=false}
            end
        end
    end
    table.sort(rows,function(a,b)
        if a.kind~=b.kind then return a.kind=="dungeon" or (a.kind=="raid" and b.kind=="unclassified") end
        if (a.low or 999)~=(b.low or 999) then return (a.low or 999)<(b.low or 999) end
        return a.name<b.name
    end)
    return rows
end

-- Conservative filtering for the currently selected character.  "candidate"
-- never means confirmed equippable or a recommended upgrade. We avoid hiding
-- ambiguous item records because imported metadata can be incomplete.
local maxArmor={MAGE=1,PRIEST=1,WARLOCK=1,ROGUE=2,DRUID=2,HUNTER=3,SHAMAN=3,WARRIOR=4,PALADIN=4}
local armorNames={cloth=1,leather=2,mail=3,plate=4}
function FCM:DungeonItemEligibility(itemID, ch)
    if not ch then return "unknown","select a character" end
    local id=tonumber(itemID)
    if not id or id<=0 then return "unknown","item ID unavailable" end
    local imported=self.externalData and self.externalData.items and self.externalData.items[id] or {}
    local info=(self.Gear and self.Gear:Info(id)) or nil
    local classID=tonumber(imported.classID) or (info and info.classID)
    local subID=(info and tonumber(info.subclassID)) or tonumber(imported.subclassID)
    if classID==4 then
        local armor=(subID and subID>=1 and subID<=4) and subID or armorNames[string.lower(tostring(imported.subclass or ""))]
        if armor and armor>(maxArmor[ch.class] or 4) then
            return "other","incompatible armor type"
        end
    end
    local mask=tonumber(imported.allowableClassMask or imported.classMask)
    local classBits={WARRIOR=1,PALADIN=2,HUNTER=4,ROGUE=8,PRIEST=16,SHAMAN=64,MAGE=128,WARLOCK=256,DRUID=1024}
    if mask and mask>0 and classBits[ch.class] then
        local bit=classBits[ch.class]
        if math.floor(mask/bit)%2==0 then return "other","class restricted" end
    end
    if classID and classID~=2 and classID~=4 then
        return "other","not equipment (reference loot)"
    end
    local required=tonumber(imported.requiredLevel) or (info and tonumber(info.level))
    if required and required>0 and required>(tonumber(ch.level) or 0) then
        return "future","future: requires level "..required
    end
    if not info and not imported.equipLoc and not imported.slotID then
        return "unknown","eligibility not verified"
    end
    local itemScore=self.Gear and self.Gear:Score(id,ch,self:Mode(ch))
    if itemScore then return "candidate","possible class item; estimated score "..self.Gear:ScoreLabel(itemScore) end
    return "candidate","potential class item; verify equip rules"
end
