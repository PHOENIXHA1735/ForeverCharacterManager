-- Future Gear Planner: read-only candidate collection, phase 1.
-- Does not claim upgrades, predict future character stats, or modify SavedVariables.
-- Deliberately not loaded by the production TOC until reviewed and integrated.
local _, FCM = ...
FCM.FutureGearPlanner = FCM.FutureGearPlanner or {}
local P = FCM.FutureGearPlanner

local classBits={WARRIOR=1,PALADIN=2,HUNTER=4,ROGUE=8,PRIEST=16,
    SHAMAN=64,MAGE=128,WARLOCK=256,DRUID=1024}
local armorCeil={MAGE=1,PRIEST=1,WARLOCK=1,ROGUE=2,DRUID=2,
    HUNTER=3,SHAMAN=3,PALADIN=4,WARRIOR=4}

local function positiveInteger(v)
    local n=tonumber(v)
    return n and n>0 and n==math.floor(n) and n or nil
end
local function val(t,k)
    return type(t)=="table" and t[k] or nil
end
local function tcopy(t)
    local copy={}
    for _,v in ipairs(t or {}) do copy[#copy+1]=v end
    return copy
end
local function fromRef(items,id)
    return items[id] or items[tostring(id)] or {}
end
-- These are *inventory type* IDs, not character inventory slot numbers.
-- The companion emits slotID/inventoryType and sometimes a human-readable
-- equipLoc rather than WoW's INVTYPE_* token.
local inventoryTypes={
    [1]="INVTYPE_HEAD",[2]="INVTYPE_NECK",[3]="INVTYPE_SHOULDER",
    [5]="INVTYPE_CHEST",[6]="INVTYPE_WAIST",[7]="INVTYPE_LEGS",
    [8]="INVTYPE_FEET",[9]="INVTYPE_WRIST",[10]="INVTYPE_HAND",
    [11]="INVTYPE_FINGER",[12]="INVTYPE_TRINKET",[13]="INVTYPE_WEAPON",
    [14]="INVTYPE_SHIELD",[15]="INVTYPE_RANGED",[16]="INVTYPE_CLOAK",
    [17]="INVTYPE_2HWEAPON",[20]="INVTYPE_ROBE",[21]="INVTYPE_WEAPONMAINHAND",
    [22]="INVTYPE_WEAPONOFFHAND",[23]="INVTYPE_HOLDABLE",
    [25]="INVTYPE_THROWN",[26]="INVTYPE_RANGEDRIGHT",[28]="INVTYPE_RELIC",
}
local equipNames={
    head="INVTYPE_HEAD",neck="INVTYPE_NECK",shoulder="INVTYPE_SHOULDER",
    shoulders="INVTYPE_SHOULDER",chest="INVTYPE_CHEST",robe="INVTYPE_ROBE",
    waist="INVTYPE_WAIST",belt="INVTYPE_WAIST",legs="INVTYPE_LEGS",
    feet="INVTYPE_FEET",boots="INVTYPE_FEET",wrist="INVTYPE_WRIST",
    wrists="INVTYPE_WRIST",hands="INVTYPE_HAND",gloves="INVTYPE_HAND",
    finger="INVTYPE_FINGER",ring="INVTYPE_FINGER",trinket="INVTYPE_TRINKET",
    weapon="INVTYPE_WEAPON",onehand="INVTYPE_WEAPON",
    mainhand="INVTYPE_WEAPONMAINHAND",
    offhand="INVTYPE_WEAPONOFFHAND",twohand="INVTYPE_2HWEAPON",
    twohanded="INVTYPE_2HWEAPON",shield="INVTYPE_SHIELD",
    holdable="INVTYPE_HOLDABLE",heldinoffhand="INVTYPE_HOLDABLE",
    cloak="INVTYPE_CLOAK",back="INVTYPE_CLOAK",ranged="INVTYPE_RANGED",
    thrown="INVTYPE_THROWN",relic="INVTYPE_RELIC",
}
local armorNames={cloth=1,leather=2,mail=3,plate=4,shield=6}
local function equipToken(value,slots)
    if value==nil then return nil end
    if slots[value] then return value end
    if type(value)=="number" then return inventoryTypes[value] end
    if type(value)=="string" then
        local clean=value:lower():gsub("[^%w]","")
        return equipNames[clean] or inventoryTypes[tonumber(value)]
    end
    return nil
end
local function rawEquip(ref,info,gear)
    local slots=gear.slots
    -- Real Nov 19 companion records write human-readable slotID such as
    -- "Main Hand", "One-Hand", "Two-Hand", "Held In Off-hand", "Chest".
    -- equipLoc may be absent for every imported item. Do not assume slotID
    -- is a numeric inventory type or misread it as a character gear slot.
    local live=info and equipToken(info.equip,slots)
    if live and slots[live] then return live end
    local named=equipToken(ref.equipLoc or ref.equip,slots)
    local inventory=equipToken(ref.slotID,slots)
    if named and inventory and named~=inventory then
        return nil,"Conflicting inventory type and equipment location"
    end
    local selected=named or inventory
    if not selected or not slots[selected] then
        return nil,"Equipment location not validated"
    end
    return selected
end
local function bindingCode(info,ref)
    local candidate=(info and info.bindType) or ref.bindType or ref.binding
    local number=tonumber(candidate)
    if number and number>=1 and number<=4 then return number end
    local normalized=tostring(candidate or ""):lower():gsub("[^%w]","")
    if normalized=="bop" or normalized=="bindonpickup" or
        normalized=="bindsonpickup" or normalized=="bindsonacquire" then return 1 end
    if normalized=="boe" or normalized=="bindonequip" or
        normalized=="bindsonequip" or normalized=="bindswhenequipped" then return 2 end
    if normalized=="bou" or normalized=="bindonuse" or
        normalized=="bindswhenused" then return 3 end
    return nil
end
local function itemInformation(id,items,gear)
    local ref=fromRef(items,id)
    local info=nil
    if gear and type(gear.Info)=="function" then
        local ok,result=pcall(gear.Info,gear,id)
        if ok and type(result)=="table" then info=result end
    end
    local importedLevel=positiveInteger(ref.requiredLevel or ref.minLevel)
    local clientLevel=positiveInteger(val(info,"level"))
    -- Never confuse itemLevel/ilvl with the character level needed to equip.
    if importedLevel and clientLevel and importedLevel~=clientLevel then
        return nil,"Conflicting required levels: imported "..importedLevel..", client "..clientLevel
    end
    local required=clientLevel or importedLevel
    if not required then return nil,"Required character level unavailable" end
    local equip,equipReason=rawEquip(ref,info,gear)
    if not equip then return nil,equipReason end
    local slots=gear.slots[equip]
    local clientSubclass=tonumber(info and info.subclassID)
    local importedSubclass=tonumber(ref.subclassID)
    if not importedSubclass and type(ref.subclass)=="string" then
        importedSubclass=armorNames[ref.subclass:lower():gsub("^%s+",""):gsub("%s+$","")]
    end
    if clientSubclass and importedSubclass and clientSubclass~=importedSubclass then
        return nil,"Conflicting armor subclasses in client and reference"
    end
    local status="reference-unverified"
    if ref.betaEvent==true then status="historical-beta-event"
    elseif ref.speculation==true then status="speculative" end
    return {
        itemID=id,itemName=(info and info.name) or ref.name or ("Item #"..id),
        requiredLevel=required,equip=equip,slots=tcopy(slots),slot=slots[1],
        classID=tonumber((info and info.classID) or ref.classID),
        subclassID=clientSubclass or importedSubclass,
        bindType=bindingCode(info,ref),bindingReference=ref.binding,
        allowableClassMask=tonumber(ref.allowableClassMask or ref.classMask),
        itemSourceProvider=ref.sourceProvider or ref.metadataSource or ref.source,
        itemEvidence=ref.sourceEvidence or ref.sourceStatus,
        itemCheckedAt=ref.referenceCheckedAt,
        itemReferenceURL=ref.link,itemLevel=tonumber(ref.itemLevel),
        availabilityStatus=status,availabilityNote=ref.availabilityNote,
        -- Information only. This is not a stat snapshot or comparison.
        comparison="not-evaluated",scored=false,
    }
end
local function eligibility(item,ch,targetLevel)
    if item.requiredLevel>targetLevel then return "blocked","Required level above selected lookahead" end
    local mask=item.allowableClassMask
    local bit=classBits[ch.class]
    if mask and mask>0 and bit and math.floor(mask/bit)%2==0 then
        return "blocked","Class restriction excludes selected character"
    end
    local unknown={}
    if not bit then unknown[#unknown+1]="Character class unknown" end
    if item.classID==4 and item.subclassID and item.subclassID>=1 and item.subclassID<=4 then
        if armorCeil[ch.class] and item.subclassID>armorCeil[ch.class] then
            return "blocked","Armor type not supported by class"
        end
        -- Whether later armor proficiencies apply at a given level/build is
        -- a separate unresolved check. Do not assume level-60 abilities.
        if (ch.class=="HUNTER" or ch.class=="SHAMAN") and item.subclassID==3
                and targetLevel<40 then
            unknown[#unknown+1]="Mail proficiency at this level not verified"
        elseif (ch.class=="PALADIN" or ch.class=="WARRIOR") and item.subclassID==4
                and targetLevel<40 then
            unknown[#unknown+1]="Plate proficiency at this level not verified"
        end
    end
    if item.classID==2 then
        unknown[#unknown+1]="Weapon subtype, training and hand restrictions require client validation"
    elseif item.classID~=4 then
        unknown[#unknown+1]="Item equipment type/class not confirmed"
    elseif item.subclassID==nil then
        unknown[#unknown+1]="Armor subtype not confirmed"
    elseif item.subclassID>=5 then
        unknown[#unknown+1]="Shield/offhand/relic eligibility requires client validation"
    end
    if not mask or mask<=0 then
        unknown[#unknown+1]="Explicit class-mask restrictions not supplied"
    end
    if #unknown>0 then return "verify",table.concat(unknown,"; ") end
    return "compatible","Known class/armor checks passed; no live equip guarantee"
end
local function recordSource(kind,name,extra)
    local s={kind=kind,name=name}
    for k,v in pairs(extra or {}) do s[k]=v end
    return s
end
local function recipeSource(recipe,kind,ch)
    local crafters={}
    for _,crafter in ipairs(recipe.crafters or {}) do
        local allowed=type(FCM.CanCollaborate)=="function" and FCM:CanCollaborate(crafter,ch)==true or false
        local skill,detail="verify","Skill not checked"
        if type(FCM.RecipeSkillStatus)=="function" then
            local ok,a,b=pcall(FCM.RecipeSkillStatus,FCM,recipe,crafter)
            if ok then skill,detail=a or "verify",b or "" end
        end
        crafters[#crafters+1]={key=crafter.key,compatible=allowed,
            skillStatus=skill,skillDetail=detail}
    end
    table.sort(crafters,function(a,b)return tostring(a.key)<tostring(b.key) end)
    return recordSource(kind,recipe.name or ("Recipe #"..tostring(recipe.id or "?")),{
        recipeID=positiveInteger(recipe.id),profession=recipe.profession,
        requiredSkill=tonumber(recipe.requiredSkill or recipe.skill),
        knownCrafters=crafters,observedOn=(kind=="crafted-unlearned") and
            #(recipe.seenOn or {}) or nil,
        learnedStatus=kind=="crafted-learned" and "learned" or
            (kind=="crafted-unlearned" and "unlearned" or "external-reference"),
        acquisition=recipe.acquisition or recipe.source,
        provider=recipe.sourceProvider,checkedAt=recipe.referenceCheckedAt,
        evidence=recipe.sourceEvidence or recipe.status,
    })
end

-- Returns candidate records only. No scoring, no future stats projection,
-- no inventory, queue, SavedVariables or external-provider mutations.
-- filters.source: all | crafting | dungeons; filters.slot: equip location or slot number.
function P:Candidates(ch,lookahead,filters)
    filters=filters or {}
    if type(ch)~="table" or not positiveInteger(ch.level) or
            (lookahead~=5 and lookahead~=10) then return {},"Select a character and +5 or +10 levels" end
    if filters.source and filters.source~="all" and filters.source~="crafting" and
            filters.source~="dungeons" then return {},"Invalid source filter" end
    local current=positiveInteger(ch.level)
    local target=math.min(60,current+lookahead)
    local gear=FCM.Gear
    if not gear or type(gear.slots)~="table" then return {},"Gear slot reference unavailable" end
    local data=(FCM.externalData or {})
    local items=data.items or {}
    local rows,byID={},{}
    local includeCrafting=(not filters.source or filters.source=="all" or filters.source=="crafting")
    local includeDungeons=(not filters.source or filters.source=="all" or filters.source=="dungeons")
    local function add(id,src)
        id=positiveInteger(id)
        if not id then return end
        local row=byID[id]
        if not row then
            local item=itemInformation(id,items,gear)
            if not item or item.requiredLevel<=current or item.requiredLevel>target then return end
            local compatible,reason=eligibility(item,ch,target)
            if compatible=="blocked" then return end
            if filters.slot and filters.slot~="all" then
                local matched=filters.slot==item.equip
                for _,slot in ipairs(item.slots) do if slot==filters.slot then matched=true end end
                if not matched then return end
            end
            item.eligibility=compatible;item.eligibilityReason=reason
            item.characterKey=ch.key;item.class=ch.class;item.specialization=ch.talentSpec
            item.levelNow=current;item.targetLevel=target;item.gearStamp=ch.gearStamp
            item.sources={};item.sourceKeys={}
            row=item;byID[id]=row;rows[#rows+1]=row
        end
        local key=src.kind.."|"..tostring(src.recipeID or "").."|"..
            tostring(src.dungeonID or "").."|"..tostring(src.boss or "").."|"..tostring(src.name)
        if not row.sourceKeys[key] then
            row.sourceKeys[key]=true
            -- A same-faction crafter is NOT enough for bind-on-pickup items.
            -- Unknown binding or unverified skill never becomes "ready".
            if src.kind=="crafted-learned" then
                local eligible=false
                for _,crafter in ipairs(src.knownCrafters or {}) do
                    local status="verify"
                    if not crafter.compatible then
                        status="blocked"
                    elseif row.bindType==1 and crafter.key~=ch.key then
                        status="blocked"
                    elseif row.bindType==nil and crafter.key~=ch.key then
                        status="verify"
                    elseif crafter.skillStatus=="blocked" then
                        status="blocked"
                    elseif crafter.skillStatus=="ready" then
                        status="eligible-scan-only"
                    end
                    crafter.recipientStatus=status
                    if status=="eligible-scan-only" then eligible=true end
                end
                src.hasPotentialCrafter=eligible
            end
            row.sources[#row.sources+1]=src
        end
    end
    if includeCrafting then
        if type(FCM.AllRecipes)=="function" then
            for _,r in ipairs(FCM:AllRecipes() or {}) do
                if type(r)=="table" then add(r.outputID or r.resultID,recipeSource(r,"crafted-learned",ch)) end
            end
        end
        if type(FCM.UnlearnedRecipes)=="function" then
            for _,r in ipairs(FCM:UnlearnedRecipes() or {}) do
                if type(r)=="table" then add(r.outputID or r.resultID,recipeSource(r,"crafted-unlearned",ch)) end
            end
        end
        for key,r in pairs(data.recipes or {}) do
            if type(r)=="table" then
                local reference={}
                for k,v in pairs(r) do reference[k]=v end
                reference.id=reference.id or positiveInteger(key)
                add(r.outputID or r.resultID,recipeSource(reference,"crafted-reference",ch))
            end
        end
    end
    if includeDungeons then
        for dungeonID,dungeon in pairs(data.dungeons or {}) do
            if type(dungeon)=="table" then
                local kind=tostring(dungeon.kind or dungeon.type or dungeon.instanceType or ""):lower()
                if not kind:find("raid",1,true) then
                    local dungeonName=dungeon.name or ("Dungeon reference "..tostring(dungeonID))
                    local details={dungeonID=tostring(dungeonID),provider=dungeon.sourceProvider,
                        checkedAt=dungeon.referenceCheckedAt,evidence=dungeon.sourceEvidence,
                        classification=(kind:find("dungeon",1,true) and "dungeon" or "unverified")}
                    local seen={}
                    for _,boss in ipairs(dungeon.bosses or {}) do
                        local bossName=tostring(boss.name or "")
                        local valid=bossName~="" and not bossName:lower():find("name unavailable",1,true)
                            and not bossName:lower():find("name not supplied",1,true)
                        for _,drop in ipairs(boss.loot or {}) do
                            local id=positiveInteger(type(drop)=="table" and (drop.id or drop.itemID) or drop)
                            if id then
                                local detail={}
                                for k,v in pairs(details) do detail[k]=v end
                                detail.boss=valid and bossName or nil
                                local sourceKind=kind:find("dungeon",1,true) and
                                    (valid and "dungeon-boss" or "dungeon-unassigned") or
                                    (valid and "instance-boss-unverified" or "instance-unassigned")
                                add(id,recordSource(sourceKind,dungeonName,detail))
                                seen[id]=true
                            end
                        end
                    end
                    for _,drop in ipairs(dungeon.dungeonLoot or {}) do
                        local id=positiveInteger(type(drop)=="table" and (drop.id or drop.itemID) or drop)
                        if id then
                            local sourceKind=kind:find("dungeon",1,true) and
                                "dungeon-unassigned" or "instance-unassigned"
                            add(id,recordSource(sourceKind,dungeonName,details))
                            seen[id]=true
                        end
                    end
                    for _,id in ipairs(dungeon.lootIDs or {}) do
                        local key=positiveInteger(id)
                        if key and not seen[key] then
                            local sourceKind=kind:find("dungeon",1,true) and
                                "dungeon-unassigned" or "instance-unassigned"
                            add(key,recordSource(sourceKind,dungeonName,details))
                        end
                    end
                end
            end
        end
    end
    for _,row in ipairs(rows) do
        row.sourceKeys=nil
        table.sort(row.sources,function(a,b)
            local ak=a.kind.."/"..a.name.."/"..tostring(a.boss or "").."/"..tostring(a.recipeID or "")
            local bk=b.kind.."/"..b.name.."/"..tostring(b.boss or "").."/"..tostring(b.recipeID or "")
            return ak<bk
        end)
    end
    table.sort(rows,function(a,b)
        if a.requiredLevel~=b.requiredLevel then return a.requiredLevel<b.requiredLevel end
        return a.itemID<b.itemID
    end)
    return rows,nil
end
