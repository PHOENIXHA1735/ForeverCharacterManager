local _, FCM = ...
FCM.Gear = {}
local G = FCM.Gear
local safe = function(func, ...) return FCM:Try(func, ...) end



local stats = {
    str = {"ITEM_MOD_STRENGTH_SHORT"}, agi = {"ITEM_MOD_AGILITY_SHORT"},
    int = {"ITEM_MOD_INTELLECT_SHORT"}, stam = {"ITEM_MOD_STAMINA_SHORT"},
    spi = {"ITEM_MOD_SPIRIT_SHORT"}, armor = {"RESISTANCE0_NAME", "ITEM_MOD_ARMOR_SHORT", "ITEM_MOD_BONUS_ARMOR_SHORT"},
    -- These client keys can describe the SAME spell-damage bonus.  Do not
    -- sum them: some Forever clients report both generic and spell-specific
    -- aliases for one bonus. Healing-only bonuses are not DPS spell power.
    spell = {"ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE"},
    ap = {"ITEM_MOD_ATTACK_POWER_SHORT"}, rap = {"ITEM_MOD_RANGED_ATTACK_POWER_SHORT"},
    crit = {"ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_SPELL_CRIT_RATING_SHORT"},
    hit = {"ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_SPELL_HIT_RATING_SHORT"},
    haste = {"ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_SPELL_HASTE_RATING_SHORT"},
    dps = {"ITEM_MOD_DAMAGE_PER_SECOND_SHORT"},
    mp5 = {"ITEM_MOD_MANA_REGENERATION_SHORT"},
    -- Direct item bonuses only.  Intellect/stamina already affect the character's
    -- mana/health pools, but we do not invent a second bonus for those effects.
    mana = {"ITEM_MOD_MANA_SHORT"},
    health = {"ITEM_MOD_HEALTH_SHORT"},
    health_regen = {"ITEM_MOD_HEALTH_REGENERATION_SHORT", "ITEM_MOD_HEALTH_REGEN_SHORT"},
    spell_pen = {"ITEM_MOD_SPELL_PENETRATION_SHORT"},
    def = {"ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"},
    defense_skill = {"ITEM_MOD_DEFENSE_SKILL_SHORT"},
    dodge = {"ITEM_MOD_DODGE_RATING_SHORT"}, parry = {"ITEM_MOD_PARRY_RATING_SHORT"},
    block = {"ITEM_MOD_BLOCK_RATING_SHORT"}, block_value = {"ITEM_MOD_BLOCK_VALUE_SHORT"},
    expertise = {"ITEM_MOD_EXPERTISE_RATING_SHORT"},
    healing = {"ITEM_MOD_HEALING_DONE_SHORT", "ITEM_MOD_HEALING_DONE"},
    weapon_skill = {"ITEM_MOD_WEAPON_SKILL_SHORT"},
    weapon_skill_rating = {"ITEM_MOD_WEAPON_SKILL_RATING_SHORT"},
    resist_fire={"ITEM_MOD_FIRE_RESISTANCE_SHORT"},resist_frost={"ITEM_MOD_FROST_RESISTANCE_SHORT"},
    resist_nature={"ITEM_MOD_NATURE_RESISTANCE_SHORT"},resist_shadow={"ITEM_MOD_SHADOW_RESISTANCE_SHORT"},resist_arcane={"ITEM_MOD_ARCANE_RESISTANCE_SHORT"},
}

-- Activity/style selectors carry no fabricated numerical multipliers.
local activities={leveling=true,pve=true,pvp=true}
local styles={dps=true,balanced=true,survival=true,healing=true,tank=true}
-- Icy Veins Forever publishes stat priorities, not universal per-point
-- coefficients. Never misrepresent its ordering as a numerical stat scale.
function G:DefaultReferenceProfile(ch,mode,activity)
    -- Reserved for a future verified, explicitly selected numerical model.
    return nil
end

function G:Info(item)
    if not C_Item then return nil end
    local name, link, quality, ilvl, minlevel, itemType, subType, stack, equip, icon,
        price, classID, subclassID, bindType = safe(C_Item.GetItemInfo, item)
    if not name and C_Item.GetItemInfoInstant then
        local itemID, instantType, instantSubType, instantEquip, instantIcon,
            instantClass, instantSubclass = safe(C_Item.GetItemInfoInstant, item)
        if itemID then
            name = "Item #" .. tostring(itemID)
            link = type(item)=="string" and item or nil
            itemType, subType, equip, icon = instantType, instantSubType, instantEquip, instantIcon
            classID, subclassID = instantClass, instantSubclass
        end
    end
    if not name then return nil end
    return {name=name, link=link, quality=quality, ilvl=ilvl, level=minlevel or 0,
        equip=equip, icon=icon, itemType=itemType, subType=subType, classID=classID, subclassID=subclassID, bindType=bindType}
end

-- Only treat absent stats as zero when BOTH equipped and candidate items have
-- successfully returned an actual client stats table. A missing table is unknown.
-- Classic/Forever GetItemStats can collapse school-only bonuses into generic
-- spell damage, or omit an item's equip effect entirely. Inspect the actual
-- tooltip *for this exact item link* before comparing spell-school gear.
-- Do not infer school-specific values from an item ID (which loses suffixes).
local spellSchools={frost=true,fire=true,shadow=true,arcane=true,nature=true,holy=true}
local suffixSchools={
    ["of frozen wrath"]="frost", ["of fiery wrath"]="fire",
    ["of shadow wrath"]="shadow", ["of arcane wrath"]="arcane",
    ["of nature's wrath"]="nature", ["of holy wrath"]="holy",
}
local function spellTooltip(item)
    local lines={}
    if C_TooltipInfo and type(C_TooltipInfo.GetHyperlink)=="function" then
        local reference=type(item)=="number" and ("item:"..item) or item
        local info=safe(C_TooltipInfo.GetHyperlink,reference)
        if info and type(info.lines)=="table" then
            for _,row in ipairs(info.lines) do
                local content=row.leftText or row.text
                if type(content)=="string" then lines[#lines+1]=content end
            end
        end
    end
    return lines
end
local function scanSpellEffects(item)
    local effects={specific={},generic=0,hasExplicit=false,hasTooltip=false,
        spellHitPct=0,spellCritPct=0}
    local lines=spellTooltip(item)
    effects.hasTooltip=#lines>0
    for _,line in ipairs(lines) do
        local cleaned=line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            :gsub("|T.-|t", ""):lower()
        -- Old-style equip bonuses can be percentage points in the tooltip,
        -- whereas GetItemStats may expose only *rating*. Do not equate them.
        local hitPct=cleaned:match("chance to hit with spells by%s+([%d%.]+)%%") or
            cleaned:match("spell hit chance by%s+([%d%.]+)%%")
        local critPct=cleaned:match("chance to get a critical strike with spells by%s+([%d%.]+)%%") or
            cleaned:match("critical strike chance of your spells by%s+([%d%.]+)%%") or
            cleaned:match("spell critical strike chance by%s+([%d%.]+)%%")
        if hitPct then effects.spellHitPct=effects.spellHitPct+(tonumber(hitPct) or 0) end
        if critPct then effects.spellCritPct=effects.spellCritPct+(tonumber(critPct) or 0) end
        local school,amount=cleaned:match("damage done by%s+(%a+)%s+spells.-by up to%s+([%d,]+)")
        if school and spellSchools[school] and amount then
            effects.specific[school]=math.max(effects.specific[school] or 0,
                tonumber((amount:gsub(",", ""))) or 0)
            effects.hasExplicit=true
        else
            local general=cleaned:match("damage and healing done by magical spells.-by up to%s+([%d,]+)") or
                cleaned:match("damage done by magical spells.-by up to%s+([%d,]+)") or
                cleaned:match("spell damage.-by up to%s+([%d,]+)")
            if general then
                effects.generic=effects.generic+(tonumber((general:gsub(",", ""))) or 0)
                effects.hasExplicit=true
            end
        end
    end
    return effects
end
local function suffixSchool(item)
    local name
    if C_Item and type(C_Item.GetItemInfo)=="function" then
        name=safe(C_Item.GetItemInfo,item)
    end
    if not name and type(item)=="string" then
        name=item:match("%[([^%]]+)%]")
    end
    name=type(name)=="string" and name:lower() or ""
    for suffix,school in pairs(suffixSchools) do
        if name:sub(-#suffix)==suffix then return school end
    end
    return nil
end

function G:StatValues(item)
    if not item then return nil end
    local raw=nil
    local references={item}
    if type(item)=="number" then references[#references+1]="item:"..tostring(item) end
    local function getStats(method)
        if type(method)~="function" then return nil end
        for _,ref in ipairs(references) do
            local data=safe(method,ref)
            if type(data)=="table" and next(data) then return data end
        end
        return nil
    end
    if C_Item then raw=getStats(C_Item.GetItemStats) end
    if type(raw)~="table" then raw=getStats(GetItemStats) end
    if type(raw)~="table" then raw={} end
    local result={}
    -- Fields in these groups are alternate client representations for the
    -- same bonus, not independent stats.  Taking the greatest magnitude
    -- prevents inflated scores when GetItemStats returns both representations.
    -- Distinct armor and school resistances remain additive.
    local aliasGroups={spell=true,healing=true,armor=true,crit=true,hit=true,haste=true}
    for category,keys in pairs(stats) do
        local value=0
        if aliasGroups[category] then
            local chosen=0
            for _,key in ipairs(keys) do
                local amount=tonumber(raw[key]) or 0
                if math.abs(amount)>math.abs(chosen) then chosen=amount end
            end
            value=chosen
        else
            for _,key in ipairs(keys) do value=value+(tonumber(raw[key]) or 0) end
        end
        if value~=0 then result[category]=value end
    end
    -- Real Forever client sample (Frosty, level 25, build 70938) exposes
    -- +4 Frost damage as ITEM_MOD_FROST_DAMAGE_DONE_SHORT on item 14167.
    -- These explicitly school-scoped raw fields must be recognized even when
    -- tooltip APIs are unavailable; they are not generic Spell Power.
    local rawSchools,rawSchoolCount,onlySchoolAmount={},0,nil
    for school in pairs(spellSchools) do
        local name=string.upper(school)
        local a=tonumber(raw["ITEM_MOD_"..name.."_DAMAGE_DONE_SHORT"]) or 0
        local b=tonumber(raw["ITEM_MOD_"..name.."_DAMAGE_DONE"]) or 0
        local amount=math.abs(a)>=math.abs(b) and a or b
        if amount~=0 then
            rawSchools[school]=amount
            rawSchoolCount=rawSchoolCount+1
            onlySchoolAmount=amount
        end
    end
    local effects=scanSpellEffects(item)
    if effects.spellHitPct~=0 then result.spell_hit_pct=effects.spellHitPct end
    if effects.spellCritPct~=0 then result.spell_crit_pct=effects.spellCritPct end
    if effects.hasExplicit then
        -- Explicit tooltip effects are more reliable than the generic stats API:
        -- the latter often labels +4 Frost damage as +4 generic spell power.
        result.spell=effects.generic~=0 and effects.generic or nil
        for school,amount in pairs(effects.specific) do
            if amount~=0 then result["spell_"..school]=amount end
        end
    elseif rawSchoolCount==0 then
        local school=suffixSchool(item)
        if school then
            -- Without readable tooltip text, do not pretend a suffix item's
            -- school-restricted bonus works for every spell school.
            if not result.spell then return nil end
            result["spell_"..school]=result.spell
            result.spell=nil
        end
    end
    for school,amount in pairs(rawSchools) do
        -- Tooltip-specific values take precedence for the same school;
        -- raw fields fill holes without double-counting aliases.
        if result["spell_"..school]==nil then result["spell_"..school]=amount end
    end
    if not effects.hasExplicit and rawSchoolCount==1 and
        result.spell==onlySchoolAmount then
        -- The older stats API can echo a school-only damage bonus again as
        -- generic Spell Power. Conservatively prevent duplicate scoring.
        result.spell=nil
    end
    -- Empty or unrecognized API data does NOT establish a real zero-stat item.
    local recognized={}
    for _,keys in pairs(stats) do for _,key in ipairs(keys) do recognized[key]=true end end
    for school in pairs(spellSchools) do
        recognized['ITEM_MOD_'..school:upper()..'_DAMAGE_DONE_SHORT']=true
        recognized['ITEM_MOD_'..school:upper()..'_DAMAGE_DONE']=true
    end
    local unknown={}
    for key,value in pairs(raw) do
        if type(value)=='number' and value~=0 and not recognized[key] then unknown[#unknown+1]=tostring(key) end
    end
    table.sort(unknown)
    if not next(result) then return nil,{unknown=unknown} end
    return result,{unknown=unknown}
end

G.statLabels={str="Strength",agi="Agility",int="Intellect",stam="Stamina",
    spi="Spirit",spell="Spell Power",ap="Attack Power",crit="Critical Strike Rating",
    hit="Hit Rating",haste="Haste Rating",dps="Weapon DPS",mp5="Mana Regeneration",
    armor="Armor",def="Defense Rating",mana="Mana",health="Health",
    health_regen="Health Regeneration",spell_pen="Resistance Penetration",spell_pierce="Spell Piercing (capture unavailable)",
    spell_hit_pct="Spell Hit %",spell_crit_pct="Spell Crit %",
    spell_frost="Frost Spell Damage",spell_fire="Fire Spell Damage",
    spell_shadow="Shadow Spell Damage",spell_arcane="Arcane Spell Damage",
    spell_nature="Nature Spell Damage",spell_holy="Holy Spell Damage"}
G.statAliases={intellect="int",stamina="stam",strength="str",agility="agi",
    spirit="spi",spellpower="spell",attackpower="ap",critical="crit",
    criticalstrike="crit",hitrate="hit",hitrating="hit",
    haste_rating="haste"}
for key,label in pairs({rap='Ranged Attack Power',healing='Healing Power',expertise='Expertise Rating',
    dodge='Dodge Rating',parry='Parry Rating',block='Block Rating',block_value='Block Value',
    defense_skill='Defense Skill',weapon_skill='Weapon Skill',weapon_skill_rating='Weapon Skill Rating'}) do G.statLabels[key]=label end
for _,school in ipairs({'fire','frost','nature','shadow','arcane'}) do G.statLabels['resist_'..school]=school..' Resistance' end
-- Pawn is a separate project. Importing a user-supplied v1 scale does not
-- bundle or redistribute Pawn's copyrighted class/spec weight tables.
-- A scale's numerical values must never be multiplied by our heuristic
-- activity/spec factors: the original model has already assigned the units.
local pawnStatKeys={
    strength="str",agility="agi",intellect="int",stamina="stam",spirit="spi",
    spellpower="spell",spelldamage="spell",spellpowerfromequip="spell",
    frostspelldamage="spell_frost",firespelldamage="spell_fire",
    shadowspelldamage="spell_shadow",arcanespelldamage="spell_arcane",
    naturespelldamage="spell_nature",holyspelldamage="spell_holy",
    attackpower="ap",rangedattackpower="rap",
    critrating="crit",spellcritrating="crit",meleecritrating="crit",
    hitrating="hit",spellhitrating="hit",meleehitrating="hit",
    hasterating="haste",
    spellhasterating="haste",meleehasterating="haste",
    dps="dps",meleedps="dps",rangeddps="dps",weapondps="dps",
    manaper5="mp5",mp5="mp5",manaregenper5="mp5",
    armor="armor",bonusarmor="armor",defenserating="def",
    dodgerating="dodge",parryrating="parry",blockrating="block",blockvalue="block_value",
    expertiserating="expertise",healing="healing",healingpower="healing",
    fireresist='resist_fire',frostresist='resist_frost',natureresist='resist_nature',shadowresist='resist_shadow',arcaneresist='resist_arcane',
}
-- Do not silently discard Pawn attributes that FCM cannot score from its
-- current in-game item-stat scanner. Unsupported nonzero fields reject import.
local pawnMetadata={class=true,spec=true,scalecolor=true}
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local function profileBracket(level)
    level=tonumber(level)
    if not level or level<1 or level>60 then return nil,nil end
    if level<40 then return 1,39 end
    if level<60 then return 40,59 end
    return 60,60
end
local function normalKey(value)
    return type(value)=="string" and value:lower():gsub("[^%w]","") or ""
end
function G:ParsePawnScale(text)
    if type(text)~="string" or #text>4096 then return nil,"Pawn scale must be text no longer than 4096 characters." end
    if text:lower():find('zygor',1,true) then return nil,'Deprecated Zygor numerical profiles are not supported.' end
    local name,body=text:match('^%s*%(%s*Pawn:%s*v1:%s*"([^"\n\r]+)"%s*:%s*([%s%S]-)%)%s*$')
    if not name or not body then return nil,'Paste a complete ( Pawn: v1: "Name": Stat=number, ... ) export.' end
    if #name>100 or #name==0 then return nil,"Scale name is invalid." end
    local result={name=name,weights={},class=nil,spec=nil}
    local count=0
    for part in (body..","):gmatch("(.-),") do
        part=trim(part)
        if part~="" then
            local field,value=part:match("^([%a][%w_]*)%s*=%s*(.-)%s*$")
            if not field then return nil,"Invalid Pawn field: "..part:sub(1,70) end
            local key=normalKey(field)
            value=trim(value)
            if key=="class" or key=="spec" then
                if not value:match("^[%w ]+$") then return nil,"Invalid Pawn "..field.." value." end
                result[key]=value
            elseif pawnMetadata[key] then
                -- Color is scale decoration, not a measured item stat.
            else
                local numeric=tonumber(value)
                if not numeric or numeric~=numeric or numeric==math.huge or numeric== -math.huge or
                    not value:match("^[%+%-]?[%d%.]+[eE]?[%+%-]?%d*$") or
                    numeric < -10000 or numeric > 10000 then
                    return nil,"Invalid numeric Pawn weight for "..field.."."
                end
                local stat=pawnStatKeys[key]
                if not stat then
                    if numeric~=0 then return nil,"Unsupported nonzero Pawn stat: "..field..". No partial import was saved." end
                elseif result.weights[stat]~=nil and math.abs(result.weights[stat]-numeric)>0.00001 then
                    return nil,"Conflicting Pawn values for "..stat.." ("..field.."). No import was saved."
                else
                    result.weights[stat]=numeric
                    count=count+1
                end
            end
        end
    end
    if count==0 then return nil,"No FCM-readable numerical weights were found." end
    return result
end
function G:ImportPawnScale(ch,text,activity,style)
    if type(ch)~="table" then return false,"No active character." end
    local parsed,err=self:ParsePawnScale(text)
    if not parsed then return false,err end
    local currentClass=normalKey(ch.class)
    local currentSpec=normalKey(ch.talentSpec)
    if currentClass=="" or currentSpec=="" then
        return false,"Choose this character's specialization on the Talents tab first."
    end
    if parsed.class and normalKey(parsed.class)~=currentClass then
        return false,"Pawn class does not match the selected character ("..tostring(ch.class)..")."
    end
    if parsed.spec and normalKey(parsed.spec)~=currentSpec then
        return false,"Pawn spec does not match the selected character ("..tostring(ch.talentSpec)..")."
    end
    local lower,upper=profileBracket(ch.level)
    if not lower then return false,"Character level is missing or outside 1-60." end
    local activityKey=activity or FCM:GearActivity(ch)
    local modeKey=style or FCM:Mode(ch,activityKey)
    if not activities[activityKey] or not styles[modeKey] then return false,"Invalid gear activity or style." end
    local _,build
    if type(GetBuildInfo)=='function' then _,build=safe(GetBuildInfo) end
    if not build then return false,'Game build unavailable; numerical import was not activated.' end
    local saved={name=parsed.name,weights=parsed.weights,class=ch.class,spec=ch.talentSpec,
        activity=activityKey,style=modeKey,levelMin=lower,levelMax=upper,
        source="Pawn v1 user import",sourceType="user-import",policyVersion=2,gameBuild=tostring(build),
        importedAt=(FCM.Now and FCM:Now()) or 0}
    local list=ch.gearImportedWeightProfiles or {}
    -- Replace only the matching context, never character inventory, other
    -- builds, previous activity profiles or manual gearCustomWeights.
    for i=#list,1,-1 do
        local p=list[i]
        if p.class==saved.class and p.spec==saved.spec and p.activity==activityKey and
            p.style==modeKey and p.levelMin==lower and p.levelMax==upper then
            table.remove(list,i)
        end
    end
    list[#list+1]=saved
    while #list>30 do table.remove(list,1) end
    ch.gearImportedWeightProfiles=list
    return true,"Imported PROVISIONAL scale '"..parsed.name.."' for "..ch.class.."/"..ch.talentSpec..
        ", "..activityKey.."/"..modeKey..", levels "..lower.."-"..upper.."."
end
function G:ActiveWeightProfile(ch,mode,activity)
    if type(ch)~="table" then return nil end
    local activityKey=activity or FCM:GearActivity(ch)
    local modeKey=mode or FCM:Mode(ch,activityKey)
    local _,build
    if type(GetBuildInfo)=='function' then _,build=safe(GetBuildInfo) end
    for i=#(ch.gearImportedWeightProfiles or {}),1,-1 do
        local p=ch.gearImportedWeightProfiles[i]
        local origin=type(p)=='table' and (tostring(p.name)..' '..tostring(p.source)..' '..tostring(p.sourceType)):lower() or ''
        local valid=type(p)=='table' and type(p.weights)=='table'
        if valid then
            for key,value in pairs(p.weights) do
                if not self.statLabels[key] or type(value)~='number' or value~=value or math.abs(value)==math.huge then valid=false end
            end
        end
        if type(p)=="table" and type(p.weights)=="table" and p.policyVersion==2 and
            valid and type(p.levelMin)=='number' and type(p.levelMax)=='number' and
            p.sourceType=='user-import' and not origin:find('zygor',1,true) and
            build and p.gameBuild==tostring(build) and
            p.class==ch.class and p.spec==ch.talentSpec and
            p.activity==activityKey and p.style==modeKey and
            type(ch.level)=="number" and
            ch.level>=(p.levelMin or 61) and ch.level<=(p.levelMax or 0) then
            return p
        end
    end
    return nil
end
function G:WeightSource(ch,mode,activity)
    activity=activity or (type(ch)=='table' and FCM:GearActivity(ch)) or 'leveling'
    mode=mode or (type(ch)=='table' and FCM:Mode(ch,activity)) or 'dps'
    local model=self:VerifiedStatProfile(ch,mode,activity)
    if model then return 'Verified Forever numerical model: '..model.source..' | '..model.sourceURL..' | '..model.methodology..' | reviewed '..model.reviewedAt..'; normalized '..model.normalization.referenceStat..'=1' end
    if self:CustomWeightContext(ch,mode,activity) then return 'PROVISIONAL manual coefficients (not a published or simulated model)' end
    local imported=self:ActiveWeightProfile(ch,mode,activity)
    if imported then return 'PROVISIONAL user Pawn scale: '..imported.name..' ('..imported.class..'/'..imported.spec..', levels '..imported.levelMin..'-'..imported.levelMax..', build '..imported.gameBuild..'; unverified coefficients, not published guide weights)' end
    local guide=FCM.PriorityGuides and FCM.PriorityGuides:Reference(ch,activity)
    if guide then return (guide.sourceName or 'Icy Veins WoW Forever')..' ordinal guidance only; numerical weights unavailable | '..guide.url end
    return 'Numerical weights unavailable for this class/spec/level/activity/build; no fallback coefficients'
end
function G:ResetImportedWeightProfile(ch,mode,activity)
    if type(ch)~="table" then return false end
    local activityKey=activity or FCM:GearActivity(ch)
    local modeKey=mode or FCM:Mode(ch,activityKey)
    local low,high=profileBracket(ch.level)
    local list=ch.gearImportedWeightProfiles or {}
    local removed=false
    for i=#list,1,-1 do
        local p=list[i]
        if p.class==ch.class and p.spec==ch.talentSpec and p.activity==activityKey and
            p.style==modeKey and p.levelMin==low and p.levelMax==high then
            table.remove(list,i);removed=true
        end
    end
    return removed
end
-- Optional cap handling uses numerical HIT RATING units only, not hit percent.
-- Without a trustworthy client-derived total and cap, guessing conversions by
-- level or treating 17% as 17 rating would create misleading recommendations.
function G:SetManualHitRating(ch,current,cap,activity)
    if type(ch)~="table" then return false end
    if type(current)~="number" or type(cap)~="number" or current<0 or cap<=0 or
        current>10000 or cap>10000 or current~=current or cap~=cap or
        not tonumber(ch.level) then return false end
    ch.gearHitRatingContext={current=current,cap=cap,activity=activity or FCM:GearActivity(ch),
        class=ch.class,spec=ch.talentSpec,level=ch.level,
        recordedAt=(FCM.Now and FCM:Now()) or 0}
    return true
end
function G:HitRatingContext(ch,activity)
    if type(ch)~="table" then return nil end
    local c=ch.gearHitRatingContext
    if type(c)=="table" and c.class==ch.class and c.spec==ch.talentSpec and
        c.level==ch.level and c.activity==(activity or FCM:GearActivity(ch)) and
        type(c.current)=="number" and type(c.cap)=="number" and c.cap>0 then return c end
    return nil
end
function G:CappedHitImpact(ch,oldStats,newStats,mode,activity)
    local c=self:HitRatingContext(ch,activity)
    if not c then return nil end
    local changed=(newStats.hit or 0)-(oldStats.hit or 0)
    local before=math.min(c.cap,math.max(0,c.current))
    local after=math.min(c.cap,math.max(0,c.current+changed))
    local weight=self:Weight("hit",ch,mode,activity)
    if type(weight)~='number' then return nil end
    return (after-before)*weight,changed*weight
end

-- V1 model adapter. An externally verified catalog is optional: without one,
-- comparisons without an applicable numerical model remain unscored.
-- Do not apply a profile from another game build or invent a character's
-- overall Hit/Expertise/Defense totals from isolated item stats.
function G:VerifiedStatProfile(ch,mode,activity)
    local engine=FCM.StatWeightEngine
    if not engine or type(engine.VerifiedProfile)~="function" or
        not FCM.statWeightCatalog or type(GetBuildInfo)~="function" then return nil end
    -- Existing explicit player choices always outrank a downloaded default.
    if self:ActiveWeightProfile(ch,mode,activity) then return nil end
    if self:CustomWeightContext(ch,mode,activity) then return nil end
    local _,build=safe(GetBuildInfo)
    return engine:VerifiedProfile(FCM.statWeightCatalog,ch,mode,activity,build)
end
function G:ModelSwapScore(ch,oldStats,newStats,profile,mode,activity)
    local engine=FCM.StatWeightEngine
    if not engine or type(profile)~="table" then return nil,"No verified model." end
    local current=ch and ch.gearStatContext
    local context={caps=profile.caps}
    if type(current)=="table" and current.class==ch.class and
        current.spec==ch.talentSpec and current.level==ch.level and
        current.activity==activity and current.style==mode and
        type(current.values)=="table" then
        context.current=current.values
    end
    local result,err=engine:ScoreChanges(oldStats,newStats,profile,context)
    if not result then return nil,err end
    if not result.complete then
        return nil,"Unmodelled stats: "..table.concat(result.unknown,",")
    end
    return result
end
-- Users can set custom baseline weights per character and activity with
-- /fcm gearweight spell 5 (or reset). No inferred activity/spec multipliers apply.
local schoolBySpec={
    MAGE={Frost={frost=true},Fire={fire=true},Arcane={arcane=true}},
    PRIEST={Shadow={shadow=true},Holy={holy=true},Discipline={holy=true}},
    WARLOCK={Affliction={shadow=true},Demonology={shadow=true,fire=true},Destruction={fire=true,shadow=true}},
    DRUID={Balance={nature=true,arcane=true},Restoration={nature=true}},
    SHAMAN={Elemental={nature=true,fire=true},Restoration={nature=true}},
    PALADIN={Holy={holy=true}},
}
function G:CustomWeightContext(ch,mode,activity)
    local context=type(ch)=='table' and ch.gearCustomWeightContexts and ch.gearCustomWeightContexts[activity]
    local _,build
    if type(GetBuildInfo)=='function' then _,build=safe(GetBuildInfo) end
    if type(context)~='table' or type(context.levelMin)~='number' or type(context.levelMax)~='number' or type(ch.gearCustomPolicyWeights)~='table' or context.policyVersion~=2 or context.class~=ch.class or context.spec~=ch.talentSpec or
        context.style~=mode or not build or context.gameBuild~=tostring(build) or
        type(ch.level)~='number' or ch.level<context.levelMin or ch.level>context.levelMax then return nil end
    return context
end
function G:Weight(category,ch,mode,activity)
    activity=activity or (type(ch)=='table' and FCM:GearActivity(ch)) or 'leveling'
    mode=mode or (type(ch)=='table' and FCM:Mode(ch,activity)) or 'dps'
    local custom=self:CustomWeightContext(ch,mode,activity)
    if custom then return (ch.gearCustomPolicyWeights[activity] or {})[category] end
    local imported=self:ActiveWeightProfile(ch,mode,activity)
    if imported then return imported.weights[category] or 0 end
    local model=self:VerifiedStatProfile(ch,mode,activity)
    local entry=model and model.weights[category]
    return entry and entry.value or nil
end
function G:SetCustomWeight(ch,category,value,activity)
    if not ch or not (stats[category] or self.statLabels[category]) then return false end
    local key=activity or FCM:GearActivity(ch)
    if not activities[key] then return false end
    if value~=nil and (type(value)~="number" or value~=value or value<0 or value>100) then return false end
    local lower,upper=profileBracket(ch.level)
    local _,build
    if type(GetBuildInfo)=='function' then _,build=safe(GetBuildInfo) end
    if value~=nil and (not build or not lower or not ch.talentSpec) then return false end
    ch.gearCustomWeights=ch.gearCustomWeights or {}
    ch.gearCustomWeights[key]=ch.gearCustomWeights[key] or {}
    ch.gearCustomWeights[key][category]=value
    ch.gearCustomPolicyWeights=ch.gearCustomPolicyWeights or {}
    ch.gearCustomPolicyWeights[key]=ch.gearCustomPolicyWeights[key] or {}
    ch.gearCustomPolicyWeights[key][category]=value
    ch.gearCustomWeightContexts=ch.gearCustomWeightContexts or {}
    if value~=nil then
        ch.gearCustomWeightContexts[key]={policyVersion=2,class=ch.class,spec=ch.talentSpec,
            style=FCM:Mode(ch,key),levelMin=lower,levelMax=upper,gameBuild=tostring(build)}
    end
    return true
end

function G:ScoreParts(item,ch,mode,activity)
    activity=activity or (type(ch)=='table' and FCM:GearActivity(ch)) or 'leveling'
    mode=mode or (type(ch)=='table' and FCM:Mode(ch,activity)) or 'dps'
    if not self:ActiveWeightProfile(ch,mode,activity) and not self:CustomWeightContext(ch,mode,activity) and
        not self:VerifiedStatProfile(ch,mode,activity) then return nil end
    local values,diagnostics=self:StatValues(item)
    if not values or (diagnostics and #diagnostics.unknown>0) then return nil end
    local result,total={},0
    for category,value in pairs(values) do
        local weight=self:Weight(category,ch,mode,activity)
        if type(weight)~='number' or weight~=weight or math.abs(weight)==math.huge then return nil end
        local weighted=value*weight
        result[#result+1]={name=category,value=value,weighted=weighted}
        total=total+weighted
    end
    table.sort(result,function(a,b)return math.abs(a.weighted)>math.abs(b.weighted) end)
    return total,result
end
function G:Score(item, classOrChar, mode, activity)
    return self:ScoreParts(item,classOrChar,mode,activity)
end

-- Always show all three perspectives for an inspected item. The current slot
-- and source must be supplied; missing item stats are explicitly 'unavailable'.
function G:CompareActivities(item,ch,oldItem,slot,equip)
    local result={}
    for _,activity in ipairs(FCM.gearActivityOrder or {'leveling','pvp','pve'}) do
        local comparison=self:CompareItem(item,ch,slot,{activity=activity})
        result[#result+1]={activity=activity,label=FCM.gearActivityLabels[activity],style=FCM:Mode(ch,activity),
            score=comparison.newScore,currentScore=comparison.oldScore,delta=comparison.delta,
            weightSource=comparison.weightSource or self:WeightSource(ch,nil,activity),
            confidence=comparison.confidence or 'NO NUMERICAL MODEL',reason=comparison.reason}
    end
    return result
end
function G:Explain(candidate,ch)
    if not candidate or not ch then return 'No recommendation selected.' end
    local reference=(candidate.info and candidate.info.link) or (candidate.recipe and candidate.recipe.outputID)
    return table.concat(self:ComparisonLines(self:CompareItem(reference,ch,candidate.slot)),'\n')
end
local slots = {
    INVTYPE_HEAD={1}, INVTYPE_NECK={2}, INVTYPE_SHOULDER={3}, INVTYPE_CLOAK={15},
    INVTYPE_CHEST={5}, INVTYPE_ROBE={5}, INVTYPE_WAIST={6}, INVTYPE_LEGS={7},
    INVTYPE_FEET={8}, INVTYPE_WRIST={9}, INVTYPE_HAND={10},
    INVTYPE_FINGER={11,12}, INVTYPE_TRINKET={13,14},
    INVTYPE_WEAPON={16,17}, INVTYPE_WEAPONMAINHAND={16}, INVTYPE_WEAPONOFFHAND={17},
    INVTYPE_2HWEAPON={16}, INVTYPE_SHIELD={17}, INVTYPE_HOLDABLE={17},
    INVTYPE_RANGED={18}, INVTYPE_RANGEDRIGHT={18}, INVTYPE_THROWN={18}, INVTYPE_RELIC={18},
}
G.slots = slots

-- All item-backed modules share this comparison. For two rings or trinkets,
-- select the best legitimate replacement (largest weighted improvement), not
-- simply the first occupied slot. Two-handed weapons include removed offhand.
function G:CompareItem(item,ch,preferredSlot,options)
    if not ch then return {status="unknown",reason="Select a character to compare equipment."} end
    local info=self:Info(item)
    if not info or not info.equip or not slots[info.equip] then
        return {status="not-equipment"}
    end
    -- Future-upgrade assessments are explicitly opt-in. Normal gear screens
    -- continue to reject items above the recipient's current level.
    -- Even in future mode, armor/class restrictions are still enforced.
    local wearableAs=ch
    if options and options.allowFutureLevel and tonumber(info.level) and
            tonumber(ch.level) and info.level>ch.level then
        wearableAs={class=ch.class,level=info.level}
    end
    if not self:IsPotentiallyWearable(info,wearableAs) then
        return {status="ineligible",reason="Item level, armor type, or equipment restrictions may prevent use."}
    end
    if not ch.gearStamp or type(ch.gear)~="table" then
        return {status="unknown",reason="Equipment has not been scanned for this character."}
    end
    local candidateStats,diagnostics=self:StatValues(item)
    if not candidateStats then
        return {status="unknown",reason="Candidate stats are not available from the game client."}
    end
    if diagnostics and #diagnostics.unknown>0 then
        return {status='unknown',reason='Unrecognized client stat identifiers: '..table.concat(diagnostics.unknown,', '),weightSource=self:WeightSource(ch)}
    end
    local activity=(options and options.activity) or FCM:GearActivity(ch)
    -- Don't rank school-specific gear without knowing the character's
    -- specialization: a bonus that works for Frost may be worthless for Fire.
    local function unknownSchool(v)
        if schoolBySpec[ch.class] and not (schoolBySpec[ch.class][ch.talentSpec or ""]) then
            for key in pairs(v or {}) do
                if type(key)=="string" and key:match("^spell_%a+$") then return true end
            end
        end
        return false
    end
    if unknownSchool(candidateStats) then
        return {status="unknown",reason="Character spell specialization is not confirmed for this school-specific item."}
    end
    local mode=FCM:Mode(ch,activity)
    local verifiedModel=self:VerifiedStatProfile(ch,mode,activity)
    local imported=self:ActiveWeightProfile(ch,mode,activity)
    local hasCustom=self:CustomWeightContext(ch,mode,activity)~=nil
    if not verifiedModel and not imported and not hasCustom then
        local source=self:WeightSource(ch,mode,activity)
        local selected=preferredSlot or slots[info.equip][1]
        local old=ch.gear[selected]
        local oldStats=old and self:StatValues(old.link or old.itemID) or {}
        local verdict,reason
        if FCM.PriorityGuides then verdict,reason=FCM.PriorityGuides:Assess(ch,oldStats,candidateStats,activity,{weapon=info.classID==2,slot=selected}) end
        return {status='unknown',confidence='ORDINAL GUIDANCE ONLY',weightSource=source,
            reason='Numerical weights unavailable; no score or upgrade percentage. '..tostring(reason or 'Review the role/build-specific stat guide.'),
            guideVerdict=verdict,newStats=candidateStats,oldStats=oldStats,slot=selected}
    end
    local newScore=self:Score(item,ch,mode,activity)
    if type(newScore)~="number" then return {status="unknown",reason="Candidate score is unavailable."} end
    local options=slots[info.equip]
    local choice=nil
    local modelError=nil
    for _,slot in ipairs(options) do
        if not preferredSlot or slot==preferredSlot then
            local valid=true
            -- Replacing an equipped two-hander with an offhand alone is not
            -- a legal isolated comparison; cannot infer the missing main-hand.
            if slot==17 and info.equip~="INVTYPE_2HWEAPON" then
                local main=ch.gear[16]
                local mainInfo=main and self:Info(main.link or main.itemID)
                if mainInfo and mainInfo.equip=="INVTYPE_2HWEAPON" then valid=false end
            end
            local old=ch.gear[slot]
            -- Current character: a live equipped item link takes precedence over
            -- the SavedVariables snapshot. Otherwise a stale empty-slot record
            -- can produce a false +score when an item is already equipped.
            if ch.key and FCM.currentKey and ch.key==FCM.currentKey and
                    type(GetInventoryItemLink)=="function" then
                local actual=safe(GetInventoryItemLink,"player",slot)
                if type(actual)=="string" and actual:find("item:",1,true) then
                    old={link=actual,itemID=tonumber(actual:match("item:(%d+)")),slot=slot}
                end
            end
            local oldRef=old and (old.link or old.itemID)
            local oldStats,oldScore={},0
            local oldName="Empty slot"
            if oldRef then
                oldStats=self:StatValues(oldRef)
                oldScore=self:Score(oldRef,ch,mode,activity)
                local oldInfo=self:Info(oldRef)
                oldName=(oldInfo and oldInfo.name) or old.name or ("Item #"..tostring(old.itemID or "?"))
                if not oldStats or type(oldScore)~="number" or unknownSchool(oldStats) then valid=false end
            end
            if info.equip=="INVTYPE_2HWEAPON" and slot==16 then
                local off=ch.gear[17]
                local offRef=off and (off.link or off.itemID)
                if offRef then
                    local extraStats=self:StatValues(offRef)
                    local extraScore=self:Score(offRef,ch,mode,activity)
                    if not extraStats or type(extraScore)~="number" then
                        valid=false
                    else
                        for key,n in pairs(extraStats) do oldStats[key]=(oldStats[key] or 0)+n end
                        oldScore=oldScore+extraScore
                        local extraInfo=self:Info(offRef)
                        oldName=oldName.." + "..((extraInfo and extraInfo.name) or off.name or "Offhand")
                    end
                end
            end
            if valid then
                local delta=newScore-oldScore
                local modelResult=nil
                local capped,uncapped=nil,nil
                if verifiedModel then
                    modelResult,modelError=self:ModelSwapScore(ch,oldStats,candidateStats,
                        verifiedModel,mode,activity)
                    if modelResult then delta=modelResult.score else valid=false end
                else
                    capped,uncapped=self:CappedHitImpact(ch,oldStats,candidateStats,mode,activity)
                    if capped then delta=delta-uncapped+capped end
                end
                if valid and (not choice or delta>choice.delta) then
                    choice={status="ok",info=info,slot=slot,oldName=oldName,oldStats=oldStats,
                        newStats=candidateStats,newScore=newScore,oldScore=oldScore,delta=delta,
                        activity=activity,style=mode,empty=not oldRef,
                        modelResult=modelResult,modelProfile=modelResult and verifiedModel or nil,
                        hitCapAdjusted=capped~=nil and uncapped~=0}
                end
            end
        end
    end
    if not choice then return {status="unknown",reason=modelError or
        "Equipped item stats or a valid replacement slot are unavailable."} end
    local keys,changes={},{}
    local modelImpacts={}
    for _,part in ipairs((choice.modelResult and choice.modelResult.changes) or {}) do
        modelImpacts[part.key]=part
    end
    for key in pairs(choice.newStats) do keys[key]=true end
    for key in pairs(choice.oldStats) do keys[key]=true end
    for key in pairs(keys) do
        local before=choice.oldStats[key] or 0
        local after=choice.newStats[key] or 0
        local change=after-before
        if change~=0 then
            local percent=before~=0 and (change/math.abs(before))*100 or nil
            local modelPart=choice.modelResult and modelImpacts[key]
            local impact=modelPart and modelPart.impact or change*self:Weight(key,ch,mode,activity)
            if not choice.modelResult and key=="hit" and choice.hitCapAdjusted then
                impact=self:CappedHitImpact(ch,choice.oldStats,choice.newStats,mode,activity) or impact
            end
            changes[#changes+1]={key=key,label=self.statLabels[key] or key,before=before,after=after,
                change=change,percent=percent,impact=impact,
                weight=modelPart and (choice.modelProfile.weights[key] or {}).value or
                    self:Weight(key,ch,mode,activity)}
        end
    end
    table.sort(changes,function(a,b)
        if math.abs(a.impact)==math.abs(b.impact) then return a.label<b.label end
        return math.abs(a.impact)>math.abs(b.impact)
    end)
    choice.changes=changes
    choice.confidence=choice.modelProfile and "VERIFIED NUMERIC MODEL" or
        (imported and "PROVISIONAL USER-IMPORTED SCALE") or
        (hasCustom and "PROVISIONAL CUSTOM ESTIMATE") or "NO NUMERICAL MODEL"
    choice.weightSource=choice.modelProfile and
        ("FCM verified model: "..choice.modelProfile.source) or self:WeightSource(ch,mode,activity)
    -- A tiny old score yields nonsensical five-digit percentages. Keep the
    -- actual weighted-point delta, but omit unstable ratios near zero.
    -- Never turn a provisional or normalized stat score into an upgrade percentage.
    local plus,minus=nil,nil
    for _,c in ipairs(changes) do
        if c.impact>0 and (not plus or c.impact>plus.impact) then plus=c end
        if c.impact<0 and (not minus or c.impact<minus.impact) then minus=c end
    end
    choice.bestGain=plus
    choice.biggestLoss=minus
    if choice.delta>0.01 then
        choice.reason=(plus and (plus.label.." gains "..string.format("%.1f",plus.impact).." weighted points") or "The offensive/defensive stat mix")..
            (minus and (", outweighing the loss of "..minus.label.." ("..string.format("%.1f",math.abs(minus.impact)).." points).") or ".")
    elseif choice.delta< -0.01 then
        choice.reason=(minus and ("Losing "..minus.label.." costs "..string.format("%.1f",math.abs(minus.impact)).." weighted points") or "The lost stats")..
            (plus and (", more than the gain from "..plus.label.." ("..string.format("%.1f",plus.impact).." points).") or ".")
    else
        choice.reason="The known weighted stats are effectively tied under this profile."
    end
    return choice
end

local function signed(n) return string.format("%+.1f",n) end
local function tint(s,hex) return "|cff"..hex..s.."|r" end
-- Client fonts on Forever may not include Unicode triangles. Use familiar
-- built-in scroll-arrow textures, plus ASCII GAIN/LOSS as a visible fallback.
local upTexture="|TInterface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up:12:12|t"
local downTexture="|TInterface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up:12:12|t"
local function scoreStatsLine(statsMap)
    local parts={}
    for key,value in pairs(statsMap or {}) do
        if value~=0 then
            parts[#parts+1]={name=G.statLabels[key] or key,value=value}
        end
    end
    table.sort(parts,function(a,b)return a.name<b.name end)
    if #parts==0 then return "None recorded" end
    local names={}
    for _,p in ipairs(parts) do names[#names+1]=p.name.." "..signed(p.value) end
    return table.concat(names,", ")
end
-- Layout is shared by the standard item pane and Dungeon Explorer.
-- Keep each change short enough to fit the narrow right column; calculations
-- are sourced from the same normalized client stat table as item scoring.
function G:ComparisonLines(comparison)
    if not comparison or comparison.status=="not-equipment" then return {} end
    local lines={tint("SMART GEAR COMPARISON","ffd76d")}
    if comparison.status~="ok" then
        lines[#lines+1]=tint(comparison.reason or "Comparison not available.","f0d27b")
        lines[#lines+1]='Active source: '..tostring(comparison.weightSource or 'Numerical model unavailable')
        if comparison.newStats then
            lines[#lines+1]='Known candidate stats: '..scoreStatsLine(comparison.newStats)
            lines[#lines+1]='Known equipped stats (slot '..tostring(comparison.slot)..'): '..scoreStatsLine(comparison.oldStats or {})
        end
        return lines
    end
    lines[#lines+1]="Equipped: "..comparison.oldName
    lines[#lines+1]=tint("Confidence: "..(comparison.confidence or "REVIEW REQUIRED"),"6fe3d0")
    local delta=comparison.delta
    local outcome=delta>0.01 and "GAIN" or (delta< -0.01 and "LOSS" or "TIE")
    local shade=delta>0.01 and "76e59a" or (delta< -0.01 and "ff8888" or "c9d1de")
    local marker=delta>0.01 and upTexture or (delta< -0.01 and downTexture or "=")
    lines[#lines+1]=tint(marker.." "..outcome..": "..signed(delta).." est. weighted pts",shade)
    lines[#lines+1]=tint('Model points are NOT an upgrade percentage or predicted DPS.','aab8ca')
    lines[#lines+1]=tint("STAT DIFFERENCES (equipped -> new)","ffd76d")
    for _,c in ipairs(comparison.changes) do
        local up=c.change>0
        local hex=up and "76e59a" or "ff8888"
        local arrow=up and upTexture or downTexture
        local pct=c.percent and string.format(" (%+.0f%%)",c.percent) or (up and " (NEW)" or "")
        lines[#lines+1]=tint(arrow.." "..c.label.." "..signed(c.change)..pct,hex)
        lines[#lines+1]=tint("  "..string.format("%g",c.before).."  ->  "..string.format("%g",c.after).." (equipped -> new)","afc3d7")
    end
    if #comparison.changes==0 then lines[#lines+1]="Known stats match." end
    lines[#lines+1]=tint("EQUIPPED KNOWN STATS","ffd76d")
    lines[#lines+1]=scoreStatsLine(comparison.oldStats)
    lines[#lines+1]=tint("CANDIDATE KNOWN STATS","ffd76d")
    lines[#lines+1]=scoreStatsLine(comparison.newStats)
    lines[#lines+1]="Why: "..comparison.reason
    lines[#lines+1]=tint("Estimated: "..(FCM.gearActivityLabels[comparison.activity] or comparison.activity)..
        " / "..(FCM.modeLabels[comparison.style] or comparison.style).."; not DPS.","aab8ca")
    lines[#lines+1]=tint("Weight source: "..(comparison.weightSource or "Unspecified"),"aab8ca")
    if comparison.modelResult then
        lines[#lines+1]=tint("Verified model: explicit units and supplied cap snapshots used.","aab8ca")
    elseif comparison.hitCapAdjusted then
        lines[#lines+1]=tint("Hit cap: manual rating snapshot used; refresh after changing gear.","aab8ca")
    else
        lines[#lines+1]=tint("Hit cap: unknown (no validated rating snapshot).","aab8ca")
    end
    lines[#lines+1]=tint("Not modeled: procs, sets, PvP effects, unique restrictions.","aab8ca")
    return lines
end

local allowedArmor = { MAGE=1, WARLOCK=1, PRIEST=1, ROGUE=2, DRUID=2,
    HUNTER=3, SHAMAN=3, WARRIOR=4, PALADIN=4 }

function G:IsPotentiallyWearable(itemInfo, ch)
    if not itemInfo or not itemInfo.equip or not slots[itemInfo.equip] then return false end
    if itemInfo.level and (ch.level or 0) < itemInfo.level then return false end
    if itemInfo.classID == 4 and itemInfo.subclassID and itemInfo.subclassID >= 1 and itemInfo.subclassID <= 4 then
        if itemInfo.subclassID > (allowedArmor[ch.class] or 4) then return false end
    end
    return true
end

function G:Candidates(ch)
    if not ch then return {} end
    local results,mode={},FCM:Mode(ch)
    for _,recipe in ipairs(FCM:AllRecipes()) do
        local info=recipe.outputID and (self:Info(recipe.outputLink or recipe.outputID) or self:Info(recipe.outputID))
        if self:IsPotentiallyWearable(info,ch) then
            for _,slot in ipairs(slots[info.equip] or {}) do
                local assessment=self:CompareItem(info.link or recipe.outputID,ch,slot)
                if assessment.status=='ok' and assessment.delta>(FCM.db.settings.minimumUpgrade or 1) then
                    local crafters={}
                    for _,crafter in ipairs(recipe.crafters or {}) do
                        if FCM:CanCollaborate(crafter,ch) and (info.bindType~=1 or crafter.key==ch.key) then crafters[#crafters+1]=crafter end
                    end
                    if #crafters>0 then results[#results+1]={recipe=recipe,info=info,slot=slot,current=ch.gear and ch.gear[slot],
                        currentScore=assessment.oldScore,score=assessment.newScore,delta=assessment.delta,
                        comparisonConfidence=assessment.confidence,weightSource=assessment.weightSource,
                        explanation=assessment.reason,mode=mode,crafters=crafters,tradeabilityConfirmed=info.bindType==2} end
                end
            end
        end
    end
    table.sort(results,function(a,b)return a.delta>b.delta end)
    return results
end

function G:ScoreLabel(score)
    return score and string.format("%.1f", score) or "Unavailable"
end

function G:FutureCandidates(ch,lookahead)
    if not ch then return {} end
    local target=(ch.level or 1)+(lookahead or 10)
    local rows={}
    for _,r in ipairs(FCM:AllRecipes()) do
        if r.outputID then
            local eligible=false
            for _,crafter in ipairs(r.crafters or {}) do
                if FCM:CanCollaborate(crafter,ch) then eligible=true;break end
            end
            local info=eligible and self:Info(r.outputLink or r.outputID)
            if info and info.bindType==1 then
                eligible=false
                for _,crafter in ipairs(r.crafters or {}) do
                    if crafter.key==ch.key then eligible=true;break end
                end
            end
            if eligible and info and info.level and info.level>(ch.level or 1) and info.level<=target
                    and self.slots[info.equip] and self:IsPotentiallyWearable(info,{level=target,class=ch.class}) then
                rows[#rows+1]={recipe=r,info=info}
            end
        end
    end
    table.sort(rows,function(a,b)return (a.info.level or 0)<(b.info.level or 0) end)
    return rows
end

-- Optional opportunities based on unlearned recipes visible in the game's
-- profession window. Never labels an unlearned pattern as immediately craftable.
function G:UnlearnedCandidates(ch)
    if not ch or not FCM.UnlearnedRecipes then return {} end
    local rows={}
    local mode=FCM:Mode(ch)
    for _,entry in ipairs(FCM:UnlearnedRecipes()) do
        local seenSameSide=false
        for _,observer in ipairs(entry.seenOn or {}) do
            if FCM:CanCollaborate(observer,ch) then seenSameSide=true;break end
        end
        if entry.outputID and seenSameSide then
            local info=self:Info(entry.outputID)
            if self:IsPotentiallyWearable(info,ch) then
                for _,slot in ipairs(self.slots[info.equip] or {}) do
                    local comparison=self:CompareItem(info.link or entry.outputID,ch,slot)
                    if comparison.status=='ok' and comparison.delta>(FCM.db.settings.minimumUpgrade or 1) then
                        rows[#rows+1]={entry=entry,info=info,delta=comparison.delta,slot=slot,
                            comparisonConfidence=comparison.confidence,weightSource=comparison.weightSource,
                            explanation=comparison.reason}
                    end
                end
            end
        end
    end
    table.sort(rows,function(a,b)return a.delta>b.delta end)
    return rows
end

-- Do not label a boss drop as an upgrade without client-provided stats and
-- a current equipped-item baseline. These are only weighted estimates.
function G:DungeonUpgradeAssessment(itemID,ch)
    local comparison=self:CompareItem(tonumber(itemID),ch)
    if comparison.status~="ok" then
        return {state="unknown",reason=comparison.reason or "equipment data unavailable"}
    end
    local minimum=(FCM.db and FCM.db.settings and tonumber(FCM.db.settings.minimumUpgrade)) or 1
    return {state=comparison.delta>minimum and "upgrade" or "not-upgrade",
        delta=comparison.delta,slot=comparison.slot,mode=comparison.style}
end

-- v0.9.0: retain every source association for a possible upgrade, rather
-- than discarding the second dungeon (or second boss) with the same item ID.
-- Boss labels come only from ForeverDB-linked rows. Flat legacy indices are
-- called "boss unknown"; no association is fabricated or verified in-game.
function G:DungeonCandidates(ch)
    local results,allSources={},{}
    if not ch then return results end
    local function addSource(id,name,boss)
        id=tonumber(id)
        if not id or id<=0 then return end
        local entry=allSources[id]
        if not entry then entry={labels={},seen={}};allSources[id]=entry end
        local label=tostring(name or "Unknown dungeon")..
            (boss and (" / "..tostring(boss).." (source-linked)") or " (boss unknown)")
        if not entry.seen[label] then
            entry.seen[label]=true
            entry.labels[#entry.labels+1]=label
        end
    end
    for _,dungeon in pairs((FCM.externalData and FCM.externalData.dungeons) or {}) do
        if type(dungeon)=="table" then
            local name=dungeon.name or "Unknown dungeon"
            local mapped={}
            for _,boss in ipairs(dungeon.bosses or {}) do
                local bossName=tostring(boss.name or "")
                local validName=bossName~="" and not bossName:find("name unavailable",1,true)
                    and not bossName:find("name not supplied",1,true)
                for _,drop in ipairs(boss.loot or {}) do
                    local id=tonumber(drop.id)
                    if id then
                        addSource(id,name,validName and bossName or nil)
                        mapped[id]=true
                    end
                end
            end
            for _,drop in ipairs(dungeon.dungeonLoot or {}) do
                local id=tonumber(drop.id)
                if id then addSource(id,name,nil);mapped[id]=true end
            end
            for _,itemID in ipairs(dungeon.lootIDs or {}) do
                local id=tonumber(itemID)
                if id and not mapped[id] then addSource(id,name,nil) end
            end
        end
    end
    local minimum=(FCM.db and FCM.db.settings and tonumber(FCM.db.settings.minimumUpgrade)) or 1
    for id,sourceData in pairs(allSources) do
        local comp=self:CompareItem(id,ch)
        if comp.status=="ok" and comp.delta>minimum then
            table.sort(sourceData.labels)
            local preview={}
            for i=1,math.min(#sourceData.labels,2) do preview[#preview+1]=sourceData.labels[i] end
            local brief=table.concat(preview,"; ")
            if #sourceData.labels>2 then brief=brief.." (and "..(#sourceData.labels-2).." more)" end
            results[#results+1]={itemID=id,info=comp.info,delta=comp.delta,
                slot=comp.slot,source=brief,sources=sourceData.labels,
                comparisonConfidence=comp.confidence,weightSource=comp.weightSource,explanation=comp.reason}
        end
    end
    table.sort(results,function(a,b)
        if a.delta~=b.delta then return a.delta>b.delta end
        return a.itemID<b.itemID
    end)
    return results
end
