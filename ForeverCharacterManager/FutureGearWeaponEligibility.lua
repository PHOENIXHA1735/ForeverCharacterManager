-- Future Gear Planner, opt-in QA only: character weapon proficiency evidence.
-- This checks a LIVE character's trained weapon skill and item tooltip.
-- It cannot prove future inventory ownership, drops, or successful equipping
-- above the player's current level. No SavedVariables or equip calls.
local _,FCM=...
FCM.FutureGearPlanner=FCM.FutureGearPlanner or {}
local P=FCM.FutureGearPlanner

-- WoW Classic weapon subclass codes. Never infer weapon permission from
-- character class alone; the skill must actually be exposed by this client.
local skills={
    [0]={"Axes"},[1]={"Two-Handed Axes"},[2]={"Bows"},[3]={"Guns"},
    [4]={"Maces"},[5]={"Two-Handed Maces"},[6]={"Polearms"},
    [7]={"Swords"},[8]={"Two-Handed Swords"},[10]={"Staves"},
    [13]={"Fist Weapons"},[15]={"Daggers"},[16]={"Thrown"},
    [18]={"Crossbows"},[19]={"Wands"},
}
local function normalize(s)
    return tostring(s or ""):lower():gsub("[^%w]","")
end
local function deny(message)
    return nil,message
end
local function getBuild()
    if type(GetBuildInfo)~="function" then return nil end
    local ok,_,build=pcall(GetBuildInfo)
    return ok and build and tostring(build) or nil
end
local function hasSkill(subclass)
    if type(GetNumSkillLines)~="function" or type(GetSkillLineInfo)~="function" then
        return false,"Weapon skill API unavailable"
    end
    local expected=skills[subclass]
    if not expected then return false,"Weapon subtype not supported by verified skill map" end
    local lookup={}
    for _,name in ipairs(expected) do lookup[normalize(name)]=true end
    local ok,count=pcall(GetNumSkillLines)
    if not ok or type(count)~="number" or count<1 then
        return false,"Weapon skills not returned by current client"
    end
    for i=1,math.min(count,250) do
        local valid,name,isHeader,_,rank=pcall(GetSkillLineInfo,i)
        if valid and not isHeader and lookup[normalize(name)] and
                type(rank)=="number" and rank>0 then
            return true,tostring(name)
        end
    end
    return false,"Required weapon proficiency not confirmed on current character"
end
local function tooltipRestrictions(id,localizedClass,requiredLevel)
    if type(C_TooltipInfo)~="table" or type(C_TooltipInfo.GetHyperlink)~="function" then
        return false,"Exact item tooltip API unavailable"
    end
    if type(GetLocale)=="function" then
        local ok,locale=pcall(GetLocale)
        if not ok or locale~="enUS" then
            return false,"Tooltip restriction parser requires enUS client"
        end
    else
        return false,"Client tooltip locale cannot be verified"
    end
    local ok,tooltip=pcall(C_TooltipInfo.GetHyperlink,"item:"..tostring(id))
    if not ok or type(tooltip)~="table" or
            type(tooltip.lines)~="table" or #tooltip.lines==0 then
        return false,"Exact item tooltip has not loaded"
    end
    for _,line in ipairs(tooltip.lines) do
        local text=type(line)=="table" and (line.leftText or line.text) or nil
        if type(text)=="string" then
            local plain=text:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
            local classes=plain:match("^[Cc]lasses:%s*(.+)")
            if classes then
                local found=false
                for name in classes:gmatch("[^,]+") do
                    if normalize(name)==normalize(localizedClass) then found=true end
                end
                if not found then return false,"Tooltip class restriction excludes this character" end
            end
            local required=plain:match("^[Rr]equires%s+[Ll]evel%s+(%d+)")
            if required and tonumber(required)>requiredLevel then
                return false,"Tooltip requires higher level than reference claims"
            end
            if plain:match("^[Rr]equires%s+") and not required then
                return false,"Additional tooltip requirement needs manual verification"
            end
            if plain:match("^[Oo]nly%s+usable%s+by%s+") then
                return false,"Unresolved item-specific user restriction"
            end
        end
    end
    return true,"Skill and visible item tooltip restrictions checked"
end

-- Only verify for the logged-in character, never for offline alts.
-- Positive evidence is build-scoped, created fresh in memory, and does not
-- mean the game has equipped the FUTURE-level item.
function P:WeaponProof(ch,row)
    if type(ch)~="table" or type(row)~="table" or
            type(row.itemID)~="number" or
            tonumber(row.classID)~=2 then return deny("Not an identified weapon item") end
    if not ch.key or not FCM.currentKey or ch.key~=FCM.currentKey then
        return deny("Weapon skills are only verifiable on the logged-in character")
    end
    if type(UnitClass)~="function" or type(UnitLevel)~="function" then
        return deny("Current character APIs unavailable")
    end
    local classOK,className,classToken=pcall(UnitClass,"player")
    local levelOK,level=pcall(UnitLevel,"player")
    if not classOK or not levelOK or classToken~=ch.class or level~=ch.level then
        return deny("Selected character or level does not match live player")
    end
    local build=getBuild()
    if not build then return deny("Client build unavailable") end
    local gear=FCM.Gear
    if not gear or type(gear.Info)~="function" then
        return deny("Gear item client lookup unavailable")
    end
    local ok,item=pcall(gear.Info,gear,row.itemID)
    if not ok or type(item)~="table" or tonumber(item.classID)~=2 or
            not item.equip or item.equip~=row.equip or
            type(item.subclassID)~="number" then
        return deny("Client weapon class/subtype/equip location not verified")
    end
    local expectedLevel=tonumber(row.requiredLevel)
    local clientLevel=tonumber(item.level)
    if not expectedLevel or expectedLevel<1 or not clientLevel or
            clientLevel~=expectedLevel or not tonumber(row.targetLevel) or
            expectedLevel>row.targetLevel then
        return deny("Future-level equip requirement does not match live item info")
    end
    local trained,skillName=hasSkill(item.subclassID)
    if not trained then return deny(skillName) end
    local restrictions,reason=tooltipRestrictions(row.itemID,className,expectedLevel)
    if not restrictions then return deny(reason) end
    return {
        status="verified",source="in-game",
        itemID=row.itemID,class=ch.class,equip=row.equip,
        equippableAtLevel=expectedLevel,gameBuild=build,
        proficiency=skillName,evidence=reason,
        caution="Future-level compatibility based on trained weapon skill and current tooltip; actual equip is not tested",
    },nil
end

-- Never mutate the collector rows. A failed check stays verify and is withheld
-- from the weapon shortlist; do not promote other restrictions to compatible.
function P:WithWeaponEvidence(ch,rows)
    local output,withheld={},0
    for _,original in ipairs(rows or {}) do
        if type(original)=="table" then
            local row={}
            for key,value in pairs(original) do row[key]=value end
            if tonumber(row.classID)==2 then
                local proof,reason=self:WeaponProof(ch,row)
                if proof then
                    row.weaponEligibility=proof
                    row.eligibility="compatible"
                    row.eligibilityReason=proof.evidence.."; future equip not guaranteed"
                else
                    row.weaponEligibility=nil
                    row.eligibility="verify"
                    row.eligibilityReason=reason or "Unable to verify this weapon"
                    withheld=withheld+1
                end
            end
            output[#output+1]=row
        end
    end
    return output,withheld
end
