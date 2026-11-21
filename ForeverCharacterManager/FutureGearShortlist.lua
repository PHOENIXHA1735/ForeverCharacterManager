-- Future Gear Planner: display-only per-slot shortlist.
-- Loaded only after FutureGearPlanner.lua and FutureGearAssessment.lua in a
-- future QA build. Not in the production TOC; no SavedVariables mutations.
local _, FCM = ...
FCM.FutureGearPlanner = FCM.FutureGearPlanner or {}
local P = FCM.FutureGearPlanner

-- Normal equipment: 5 initially, expand up to 10 per logical slot.
-- Weapons: 3 initially, expand up to 5 per actual weapon slot.
P.ShortlistDefaults = {itemsPerSlot=5, weaponsPerSlot=3}
local function limit(value,low,high,default)
    local n=tonumber(value)
    if not n or n~=math.floor(n) then return default end
    return math.max(low,math.min(high,n))
end
local weaponEquip={
    INVTYPE_WEAPON=true, INVTYPE_WEAPONMAINHAND=true,
    INVTYPE_WEAPONOFFHAND=true, INVTYPE_2HWEAPON=true,
    INVTYPE_RANGED=true, INVTYPE_RANGEDRIGHT=true, INVTYPE_THROWN=true,
}
local function isWeapon(row)
    return tonumber(row.classID)==2 or weaponEquip[row.equip]==true
end
-- Passing an imported class mask, suitable stat weights or a candidate label
-- is NOT evidence that the toon can train/use the weapon. Only a later
-- client-backed eligibility check can populate this evidence structure.
local function verifiedWeapon(row,ch)
    local evidence=row.weaponEligibility
    if row.eligibility~="compatible" or type(evidence)~="table" or
            evidence.status~="verified" or evidence.source~="in-game" or
            evidence.itemID~=row.itemID or evidence.class~=ch.class or
            evidence.equip~=row.equip then return false end
    local verifiedLevel=tonumber(evidence.equippableAtLevel)
    if not verifiedLevel or verifiedLevel<row.requiredLevel or
            verifiedLevel>row.targetLevel then return false end
    -- Do not reuse prior-build verification if the client build changed.
    if type(GetBuildInfo)=="function" then
        local ok,_,build=pcall(GetBuildInfo)
        if ok and build and tostring(evidence.gameBuild)~=tostring(build) then return false end
    end
    return true
end
local slotNames={
    [1]="Head",[2]="Neck",[3]="Shoulders",[4]="Shirt",[5]="Chest",
    [6]="Waist",[7]="Legs",[8]="Feet",[9]="Wrists",[10]="Hands",
    [11]="Rings",[12]="Rings",[13]="Trinkets",[14]="Trinkets",[15]="Back",
    [16]="Main hand",[17]="Off hand",[18]="Ranged",
}
local function section(row,weapon)
    local slot=tonumber(row.compareSlot) or tonumber(row.slot)
    if row.equip=="INVTYPE_FINGER" then slot=11 end
    if row.equip=="INVTYPE_TRINKET" then slot=13 end
    if not slot or not slotNames[slot] then return nil end
    -- A selected one-hander may compare against the main or off-hand slot.
    -- Never claim it fits both. Gear:CompareItem selects the valid slot.
    return (weapon and "weapon:" or "equipment:")..tostring(slot),
        (slotNames[slot]..(weapon and " weapons" or ""))
        ,slot
end
local rank={
    ["verified-weighted-upgrade"]=1,
    ["qualitative-candidate"]=2,
    ["provisional-estimate"]=3,
    ["insufficient-information"]=4,
    ["not-a-verified-upgrade"]=5,
}
local function finite(x)
    return type(x)=="number" and x==x and x~=math.huge and x~=-math.huge
end
local function better(a,b)
    local ra,rb=rank[a.assessment] or 6,rank[b.assessment] or 6
    if ra~=rb then return ra<rb end
    -- Numerical ranking is permitted ONLY within comparable evidence tiers.
    if (ra==1 or ra==3) and finite(a.weightedDelta) and finite(b.weightedDelta)
            and a.weightedDelta~=b.weightedDelta then
        return a.weightedDelta>b.weightedDelta
    end
    if tonumber(a.requiredLevel)~=tonumber(b.requiredLevel) then
        return (tonumber(a.requiredLevel) or 999)<
            (tonumber(b.requiredLevel) or 999)
    end
    return (tonumber(a.itemID) or 9999999)<(tonumber(b.itemID) or 9999999)
end

-- Assessed rows are grouped and ranked *after* collecting every available
-- source; limiting earlier could hide a better item. This is a DISPLAY
-- shortlist, never a claim that an unknown-ranked item is best for the spec.
function P:Shortlist(ch,assessed,opts)
    opts=opts or {}
    if type(ch)~="table" or type(assessed)~="table" then
        return nil,"A character and assessed candidates are required"
    end
    local regular=limit(opts.itemsPerSlot,5,10,5)
    local weapons=limit(opts.weaponsPerSlot,3,5,3)
    local map,groups={},{}
    local result={groups=groups,itemsPerSlot=regular,weaponsPerSlot=weapons,
        hiddenByLimit=0,withheldWeapons=0,skippedInvalid=0,totalShown=0}
    for _,row in ipairs(assessed) do
        if type(row)=="table" and type(row.itemID)=="number" and
                row.characterKey==ch.key and row.class==ch.class and
                row.specialization==ch.talentSpec and row.levelNow==ch.level and
                type(row.sources)=="table" and #row.sources>0 and
                tonumber(row.requiredLevel) and tonumber(row.targetLevel) and
                row.requiredLevel>ch.level and row.requiredLevel<=row.targetLevel and
                (row.eligibility=="compatible" or row.eligibility=="verify") then
            local weapon=isWeapon(row)
            if weapon and not verifiedWeapon(row,ch) then
                result.withheldWeapons=result.withheldWeapons+1
            else
                local key,label,slot=section(row,weapon)
                if key then
                    local group=map[key]
                    if not group then
                        group={key=key,label=label,slot=slot,isWeapon=weapon,
                            rows={},seen={},total=0,hidden=0}
                        groups[#groups+1]=group
                        map[key]=group
                    end
                    local prior=group.seen[row.itemID]
                    if not prior then
                        group.seen[row.itemID]=row
                        group.rows[#group.rows+1]=row
                    elseif better(row,prior) then
                        group.seen[row.itemID]=row
                        for i,existing in ipairs(group.rows) do
                            if existing.itemID==row.itemID then
                                group.rows[i]=row
                                break
                            end
                        end
                    end
                else
                    result.skippedInvalid=result.skippedInvalid+1
                end
            end
        else
            result.skippedInvalid=result.skippedInvalid+1
        end
    end
    for _,group in ipairs(groups) do
        table.sort(group.rows,better)
        group.total=#group.rows
        local cap=group.isWeapon and weapons or regular
        group.hidden=math.max(0,group.total-cap)
        while #group.rows>cap do table.remove(group.rows) end
        result.hiddenByLimit=result.hiddenByLimit+group.hidden
        result.totalShown=result.totalShown+#group.rows
        group.seen=nil
    end
    table.sort(groups,function(a,b)
        if a.slot~=b.slot then return a.slot<b.slot end
        if a.isWeapon~=b.isWeapon then return a.isWeapon end
        return a.key<b.key
    end)
    return result,nil
end
