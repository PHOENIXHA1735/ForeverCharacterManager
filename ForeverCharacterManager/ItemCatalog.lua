local _, FCM = ...
-- FCM v0.7.3: bounded browsing of reference items and observed inventory.
-- Imported client records are NOT proof that an item currently drops or can be bought.
local groups = {
    {id="all",title="All categories"}, {id="weapon",title="Weapons"},
    {id="container",title="Bags & containers"},
    {id="armor",title="Armor"}, {id="jewelry",title="Jewelry & trinkets"},
    {id="consumable",title="Consumables"}, {id="material",title="Materials & reagents"},
    {id="recipe",title="Recipes & patterns"}, {id="quest",title="Quest items"},
    {id="profession",title="Profession tools"}, {id="enchant",title="Enchantments & gems"},
    {id="special",title="Special & miscellaneous"},
}
FCM.itemCategoryOptions = groups
FCM.itemScopeOptions = {
    {id="all",title="All records"}, {id="owned",title="Owned by my characters"},
    {id="referenced",title="External reference recorded"},
    {id="uncertain",title="Uncertain or historical"},
    {id="unresolved",title="Observed, missing reference"},
}
FCM.itemQualityOptions = {
    {id="all",title="Any quality"},{id="0",title="Poor"},
    {id="1",title="Common"},{id="2",title="Uncommon"},
    {id="3",title="Rare"},{id="4",title="Epic"},
    {id="5",title="Legendary"},{id="unknown",title="Not recorded"},
}
local qualityNames={"Poor","Common","Uncommon","Rare","Epic","Legendary"}
local function clean(s) return tostring(s or "") end
-- Search is submitted explicitly by the UI; fuzzy matching is applied to
-- names only after submission so browsing thousands of items stays responsive.
-- Tokens match in any order. A single typo ("bear mean" -> "Bear Meat")
-- is tolerated on words with 4+ characters. No fuzzy numeric IDs.
local function nearWord(a,b)
    if #a<4 or #b<4 or a:sub(1,1)~=b:sub(1,1) then return false end
    if math.abs(#a-#b)>1 then return false end
    local i,j,errors=1,1,0
    while i<=#a and j<=#b do
        if a:sub(i,i)==b:sub(j,j) then i=i+1;j=j+1
        else
            errors=errors+1
            if errors>1 then return false end
            if #a==#b then i=i+1;j=j+1
            elseif #a>#b then i=i+1
            else j=j+1 end
        end
    end
    return errors+math.max(#a-i+1,#b-j+1)<=1
end
function FCM:SearchMatches(haystack,query)
    haystack=string.lower(clean(haystack))
    query=string.lower(clean(query)):gsub("^%s+",""):gsub("%s+$","")
    if query=="" then return true end
    if haystack:find(query,1,true) then return true end
    -- Numeric and item ID searches must be exact substrings, never fuzzy.
    if query:match("^%d+$") then return haystack:find(query,1,true)~=nil end
    local words={}
    for part in haystack:gmatch("[%w]+") do words[#words+1]=part end
    local searched=false
    for term in query:gmatch("[%w]+") do
        searched=true
        local matched=false
        for _,word in ipairs(words) do
            if word:find(term,1,true) or nearWord(term,word) then
                matched=true;break
            end
        end
        if not matched then return false end
    end
    return searched
end
local function numericQuality(v)
    local n=tonumber(v)
    if n then return n end
    local q=string.lower(clean(v))
    for i,name in ipairs(qualityNames) do if string.lower(name)==q then return i-1 end end
    return nil
end
function FCM:ItemQualityName(item)
    local q=numericQuality(item and item.quality)
    return q and qualityNames[q+1] or "Not recorded"
end
local function itemClassID(item)
    return tonumber(item.classID or item.classId or item.itemClassID)
end
function FCM:ItemCategory(item)
    item=item or {}
    local class=itemClassID(item)
    local slot=clean(item.equipLoc or item.inventoryType or item.slotName)
    local sln=string.lower(slot)
    if slot=="INVTYPE_NECK" or slot=="INVTYPE_FINGER" or slot=="INVTYPE_TRINKET" or
       sln=="neck" or sln=="finger" or sln=="trinket" or tonumber(item.slotID)==2 or
       tonumber(item.slotID)==11 or tonumber(item.slotID)==12 then return "jewelry" end
    if class==2 then return "weapon" end
    if class==4 then return "armor" end
    if class==0 then return "consumable" end
    if class==7 or class==5 or class==6 then return "material" end
    if class==9 then return "recipe" end
    if class==12 then return "quest" end
    if class==8 or class==3 then return "enchant" end
    if class==1 then return "container" end
    if class==11 then return "profession" end
    local category=string.lower(clean(item.category))
    local name=string.lower(clean(item.name))
    if category:find("weapon",1,true) then return "weapon" end
    if category:find("armor",1,true) or category:find("armour",1,true) then return "armor" end
    if category:find("jewel",1,true) or category:find("trinket",1,true) then return "jewelry" end
    if category:find("consum",1,true) or category:find("potion",1,true) or category:find("food",1,true) then return "consumable" end
    if category:find("reagent",1,true) or category:find("material",1,true) or category:find("trade goods",1,true) then return "material" end
    if category:find("recipe",1,true) or category:find("pattern",1,true) or name:find("recipe:",1,true)==1 or name:find("pattern:",1,true)==1 then return "recipe" end
    if category:find("quest",1,true) then return "quest" end
    if category:find("profession",1,true) or category:find("tool",1,true) then return "profession" end
    if category:find("enchant",1,true) or category:find("gem",1,true) then return "enchant" end
    return "special"
end
-- Three-level Auction House-style taxonomy. Imported data does not always
-- contain subclass or equipment slot, so unknown types are NOT guessed.
FCM.itemTypeOptions={
    all={{id="all",title="All types"}},
    weapon={{id="all",title="All weapons"},{id="onehand",title="One-handed"},
        {id="twohand",title="Two-handed"},{id="wand",title="Wands"},
        {id="ranged",title="Ranged"},{id="offhand",title="Off-hand"}},
    armor={{id="all",title="All armor"},{id="cloth",title="Cloth"},
        {id="leather",title="Leather"},{id="mail",title="Mail"},
        {id="plate",title="Plate"},{id="shield",title="Shields"},
        {id="cloak",title="Cloaks"}},
    material={{id="all",title="All materials"},{id="cloth",title="Cloth"},
        {id="herb",title="Herbs"},{id="ore",title="Ore"},
        {id="bar",title="Bars"},{id="leather",title="Leather"},
        {id="enchant",title="Enchanting"},{id="gem",title="Gems"}},
}
FCM.armorSlots={{id="all",title="All slots"},{id="head",title="Head"},
    {id="shoulder",title="Shoulders"},{id="chest",title="Chest"},
    {id="wrist",title="Wrists"},{id="hands",title="Hands"},
    {id="waist",title="Waist"},{id="legs",title="Legs"},
    {id="feet",title="Feet"},{id="back",title="Back"}}
FCM.weaponFamilies={
    {id="all",title="All weapon types"},{id="sword",title="Swords"},
    {id="axe",title="Axes"},{id="mace",title="Maces"},
    {id="dagger",title="Daggers"},{id="fist",title="Fist weapons"},
    {id="staff",title="Staves"},{id="polearm",title="Polearms"},
    {id="bow",title="Bows"},{id="gun",title="Guns"},
    {id="crossbow",title="Crossbows"},{id="wand",title="Wands"},
}
function FCM:ItemSlotOptions(category,kind)
    if category=="armor" and kind~="shield" then return self.armorSlots end
    if category=="weapon" then return self.weaponFamilies end
    return {{id="all",title="All"}}
end
local armorSlots={INVTYPE_HEAD="head",INVTYPE_SHOULDER="shoulder",
    INVTYPE_CHEST="chest",INVTYPE_ROBE="chest",INVTYPE_WRIST="wrist",
    INVTYPE_HAND="hands",INVTYPE_WAIST="waist",INVTYPE_LEGS="legs",
    INVTYPE_FEET="feet",INVTYPE_CLOAK="back",
    HEAD="head",SHOULDER="shoulder",SHOULDERS="shoulder",CHEST="chest",
    WRIST="wrist",WRISTS="wrist",HANDS="hands",WAIST="waist",LEGS="legs",
    FEET="feet",BACK="back"}
local numericSlots={[1]="head",[3]="shoulder",[5]="chest",[6]="waist",
    [7]="legs",[8]="feet",[9]="wrist",[10]="hands",[16]="back"}
function FCM:ItemHierarchy(item)
    item=item or {}
    local cat=self:ItemCategory(item)
    local equip=string.upper(clean(item.equipLoc or item.inventoryType or ""))
    local sub=string.lower(clean(item.subclass or item.subClassName or ""))
    local subID=tonumber(item.subClassID or item.subclassID or item.subclassId or item.subClassId or item.subclass)
    local itemname=string.lower(clean(item.name))
    if cat=="armor" then
        if equip=="INVTYPE_SHIELD" or subID==6 or sub:find("shield",1,true) then return cat,"shield","all" end
        if equip=="INVTYPE_CLOAK" or sub:find("cloak",1,true) then return cat,"cloak","back" end
        local kind="unknown"
        for _,name in ipairs({"cloth","leather","mail","plate"}) do
            if sub:find(name,1,true) then kind=name;break end
        end
        if kind=="unknown" then
            local byID={[1]="cloth",[2]="leather",[3]="mail",[4]="plate"}
            kind=byID[subID] or kind
        end
        return cat,kind,armorSlots[equip] or numericSlots[tonumber(item.slotID)] or "unknown"
    elseif cat=="weapon" then
        local family="unknown"
        for _,name in ipairs({"crossbow","polearm","dagger","sword","staff","mace","fist","axe","wand","gun","bow"}) do
            if sub:find(name,1,true) then family=name;break end
        end
        if family=="unknown" then
            -- Classic/Forever weapon subclass IDs where the source gives only an ID.
            local byID={[0]="axe",[1]="axe",[2]="bow",[3]="gun",
                [4]="mace",[5]="mace",[6]="polearm",[7]="sword",
                [8]="sword",[10]="staff",[13]="fist",[15]="dagger",
                [18]="crossbow",[19]="wand"}
            family=byID[subID] or family
        end
        -- A staff is two-handed; wands and physical ranged have their own category.
        local kind="unknown"
        if family=="wand" or (equip=="INVTYPE_RANGEDRIGHT" and itemname:find("wand",1,true)) then kind="wand"
        elseif family=="bow" or family=="gun" or family=="crossbow" or equip=="INVTYPE_RANGED" then kind="ranged"
        elseif equip=="INVTYPE_2HWEAPON" or tonumber(item.slotID)==17 or
           subID==1 or subID==5 or subID==8 or family=="staff" or family=="polearm" or
           sub:find("two%-hand") or sub:find("2h",1,true) then kind="twohand"
        elseif equip=="INVTYPE_WEAPONOFFHAND" or equip=="INVTYPE_HOLDABLE" or
           tonumber(item.slotID)==22 or tonumber(item.slotID)==23 then kind="offhand"
        elseif equip=="INVTYPE_WEAPON" or equip=="INVTYPE_WEAPONMAINHAND" or
           subID==0 or subID==4 or subID==7 or subID==13 or subID==15 or
           tonumber(item.slotID)==13 or tonumber(item.slotID)==21 or
           sub:find("one%-hand") then kind="onehand" end
        return cat,kind,family
    elseif cat=="material" then
        local typeName="unknown"
        local source=sub.." "..itemname
        if source:find("cloth",1,true) or source:find("linen",1,true) or source:find("wool",1,true) or source:find("silk",1,true) then typeName="cloth"
        elseif source:find("herb",1,true) or source:find("flower",1,true) then typeName="herb"
        elseif source:find("ore",1,true) then typeName="ore"
        elseif source:find("bar",1,true) then typeName="bar"
        elseif source:find("leather",1,true) or source:find("hide",1,true) then typeName="leather"
        elseif source:find("enchant",1,true) or source:find("essence",1,true) or source:find("dust",1,true) then typeName="enchant"
        elseif source:find("gem",1,true) then typeName="gem" end
        return cat,typeName,"all"
    end
    return cat,"all","all"
end
local function uncertain(item)
    local state=string.lower(clean(item and item.sourceStatus))
    return state:find("specul",1,true)~=nil or state:find("beta event",1,true)~=nil or
           state:find("historical",1,true)~=nil or state:find("not confirmed",1,true)~=nil or
           state:find("unverified",1,true)~=nil
end
local function hasExternalSource(item)
    return item and (item.metadataSource or item.source or item.link) ~= nil
end
function FCM:ItemOwnedIDs()
    local owned={}
    for _,ch in ipairs(self:VisibleCharacters()) do
        for _,where in ipairs({ch.bags or {},ch.bank or {},ch.gear or {}}) do
            for _,record in pairs(where) do
                local id=type(record)=="table" and tonumber(record.itemID)
                if id and id>0 then owned[id]=true end
            end
        end
    end
    return owned
end
-- Return first maxRows and an accurate match count. Do not create 30,000 UI frames.
function FCM:BrowseItems(query,category,scope,quality,maxRows,itemType,itemSlot,sortMode)
    query=string.lower(clean(query))
    category=category or "all"
    scope=scope or "all"
    quality=quality or "all"
    itemType=itemType or "all"
    itemSlot=itemSlot or "all"
    sortMode=sortMode or "name"
    local max=math.max(1,math.min(tonumber(maxRows) or 190,200))
    local found,count={},0
    local owned=self:ItemOwnedIDs()
    local data=(self.externalData and self.externalData.items) or {}
    local hasID={}
    local function consider(id,record,sourceRecord)
        id=tonumber(id)
        if not id or id<=0 or hasID[id] then return end
        hasID[id]=true
        record=record or {}
        local name=clean(record.name)
        if name=="" then name="Item #"..id end
        local group,kind,slot=self:ItemHierarchy(record)
        local q=numericQuality(record.quality)
        local match=(query=="" or self:SearchMatches(name,query) or string.find(tostring(id),query,1,true))
        if not match or (category~="all" and category~=group) or
            (itemType~="all" and itemType~=kind) or
            (itemSlot~="all" and itemSlot~=slot) then return end
        if quality=="unknown" then if q~=nil then return end
        elseif quality~="all" and q~=tonumber(quality) then return end
        local isExternal=sourceRecord and hasExternalSource(record)
        if scope=="owned" and not owned[id] then return end
        if scope=="referenced" and not isExternal then return end
        if scope=="uncertain" and not uncertain(record) then return end
        if scope=="unresolved" and isExternal then return end
        count=count+1
        if true then
            found[#found+1]={id=id,name=name,item=record,group=group,itemType=kind,itemSlot=slot,owned=owned[id] and true or false,
                externallySourced=isExternal and true or false,uncertain=uncertain(record)}
        end
    end
    -- External records first, preserving curated metadata and source attribution.
    local ids={}
    for id in pairs(data) do if type(id)=="number" then ids[#ids+1]=id end end
    table.sort(ids)
    for _,id in ipairs(ids) do consider(id,data[id],true) end
    -- Include unreferenced items observed on offline characters.
    for id in pairs(owned) do
        if not hasID[id] then
            local entry=nil
            for _,ch in pairs((self.db and self.db.characters) or {}) do
                for _,storage in ipairs({ch.bags or {},ch.bank or {},ch.gear or {}}) do
                    for _,rec in pairs(storage) do
                        if tonumber(rec.itemID)==id then entry=rec;break end
                    end
                    if entry then break end
                end
                if entry then break end
            end
            consider(id,{name=(entry and entry.name) or (self.ItemName and self.ItemName(id)) or ("Item #"..id),
                sourceStatus="Seen in character scan; external item details unavailable"},false)
        end
    end
    -- Exact ID lookup should still produce a transparent unknown-item record.
    local requested=tonumber(query)
    if requested and requested>0 and requested==math.floor(requested) and not hasID[requested] then
        consider(requested,{name=(self.ItemName and self.ItemName(requested)) or ("Item #"..requested),
            sourceStatus="No imported item details for this ID"},false)
    end
    table.sort(found,function(a,b)
        if sortMode=="quality" then
            local aq,bq=numericQuality(a.item.quality) or -1,numericQuality(b.item.quality) or -1
            if aq~=bq then return aq>bq end
        elseif sortMode=="itemlevel" or sortMode=="requiredlevel" then
            local key=sortMode=="itemlevel" and "itemLevel" or "requiredLevel"
            local aq,bq=tonumber(a.item[key] or a.item.ilvl) or -1,
                        tonumber(b.item[key] or b.item.ilvl) or -1
            if aq~=bq then return aq>bq end
        end
        local an,bn=string.lower(a.name),string.lower(b.name)
        if an==bn then return a.id<b.id end
        return an<bn
    end)
    while #found>max do table.remove(found) end
    return found,count
end
local function field(lines,label,value)
    if value~=nil and clean(value)~="" then lines[#lines+1]=label..": "..clean(value) end
end
function FCM:CatalogItemDetails(id,ch)
    id=tonumber(id)
    if not id then return "Invalid item ID" end
    local item=(self.externalData and self.externalData.items and self.externalData.items[id]) or {}
    local lines={"|cffffd983ITEM DATABASE RECORD|r",""}
    local mode=clean(item.sourceStatus)
    local categoryID=self:ItemCategory(item)
    local categoryLabel=categoryID
    for _,option in ipairs(self.itemCategoryOptions or {}) do
        if option.id==categoryID then categoryLabel=option.title;break end
    end
    field(lines,"Category group",categoryLabel)
    field(lines,"Item quality",self:ItemQualityName(item))
    field(lines,"Item level",item.itemLevel or item.ilvl)
    field(lines,"Required level",item.requiredLevel or item.minLevel)
    field(lines,"Equipment slot",item.equipLoc or item.inventoryType)
    field(lines,"Class ID",item.classID)
    field(lines,"Subclass",item.subclass)
    field(lines,"Bind type",item.binding)
    field(lines,"Reported vendor inventory",item.soldBy)
    field(lines,"Vendor reference",item.vendorSource)
    field(lines,"Data limitations",item.availabilityNote)
    field(lines,"Client version note",item.liveClientNote)
    if item.sellPrice then field(lines,"Vendor sell value",self.MoneyLabel and self:MoneyLabel(item.sellPrice) or item.sellPrice) end
    if item.betaEvent then lines[#lines+1]="Historical beta-event copy: not assumed obtainable at launch." end
    if item.speculation then lines[#lines+1]="Availability speculative: do not treat this as an obtainable upgrade." end
    if mode~="" then field(lines,"Availability confidence",mode) end
    if ch and (item.equipLoc or item.inventoryType) then
        lines[#lines+1]=""
        lines[#lines+1]="For "..self:DisplayCharacter(ch)..":"
        if tonumber(item.requiredLevel or item.minLevel) and tonumber(ch.level) and tonumber(ch.level)<tonumber(item.requiredLevel or item.minLevel) then
            lines[#lines+1]="  Below item's required level (cannot equip yet)."
        else
            lines[#lines+1]="  Check armor/weapon proficiency, faction and other restrictions in-game."
        end
        lines[#lines+1]="  This record alone is NOT an upgrade recommendation."
        if self.Gear and self.Gear.CompareActivities then
            local info=self.Gear:Info(id)
            local slotName=(info and info.equip) or item.equipLoc or item.inventoryType
            local slotSet=self.Gear.slots and self.Gear.slots[slotName]
            local slot=slotSet and slotSet[1]
            if slot then
                local worn=ch.gear and ch.gear[slot]
                lines[#lines+1]=""
                lines[#lines+1]="Activity comparisons (weighted points, not DPS):"
                for _,r in ipairs(self.Gear:CompareActivities(id,ch,
                        worn and (worn.link or worn.itemID),slot,slotName)) do
                    lines[#lines+1]="  "..r.label.." ["..(self.modeLabels[r.style] or r.style).."]: "..
                        (r.delta and string.format("%+.1f",r.delta) or "insufficient equipped/item stats")
                end
                lines[#lines+1]="  Effects, set bonuses and hit caps are not simulated."
            end
        end
    end
    if self.FarmAdviceLines then
        lines[#lines+1]=""
        for _,line in ipairs(self:FarmAdviceLines(id,1,ch,7)) do lines[#lines+1]=line end
    end
    lines[#lines+1]=""
    lines[#lines+1]=self:ExpandedItemDetails(id)
    return table.concat(lines,"\n")
end
