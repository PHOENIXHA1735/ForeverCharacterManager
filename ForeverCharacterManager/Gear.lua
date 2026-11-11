local _, FCM = ...
FCM.Gear = {}
local G = FCM.Gear
local safe = function(func, ...) return FCM:Try(func, ...) end

local caster = { MAGE=true, WARLOCK=true, PRIEST=true }
local physical = { WARRIOR=true, ROGUE=true, HUNTER=true, SHAMAN=true, DRUID=true, PALADIN=true }
local stats = {
    str = {"ITEM_MOD_STRENGTH_SHORT"}, agi = {"ITEM_MOD_AGILITY_SHORT"},
    int = {"ITEM_MOD_INTELLECT_SHORT"}, stam = {"ITEM_MOD_STAMINA_SHORT"},
    spi = {"ITEM_MOD_SPIRIT_SHORT"}, armor = {"RESISTANCE0_NAME", "ITEM_MOD_ARMOR_SHORT", "ITEM_MOD_BONUS_ARMOR_SHORT"},
    spell = {"ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE", "ITEM_MOD_SPELL_HEALING_DONE_SHORT"},
    ap = {"ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT"},
    crit = {"ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_SPELL_CRIT_RATING_SHORT"},
    hit = {"ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_SPELL_HIT_RATING_SHORT"},
    haste = {"ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_SPELL_HASTE_RATING_SHORT"},
    dps = {"ITEM_MOD_DAMAGE_PER_SECOND_SHORT"},
    mp5 = {"ITEM_MOD_MANA_REGENERATION_SHORT"},
    def = {"ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "ITEM_MOD_DODGE_RATING_SHORT", "ITEM_MOD_PARRY_RATING_SHORT"},
    resist = {"ITEM_MOD_FIRE_RESISTANCE_SHORT", "ITEM_MOD_FROST_RESISTANCE_SHORT", "ITEM_MOD_NATURE_RESISTANCE_SHORT", "ITEM_MOD_SHADOW_RESISTANCE_SHORT", "ITEM_MOD_ARCANE_RESISTANCE_SHORT"},
}

-- Activities modify the existing secondary styles. These are rough stat-priority
-- heuristics, NOT DPS simulation, hit-cap modeling or an Icy Veins weight export.
local activityFactors = {
    leveling = {
        caster = {int=1.08,spi=1.2,stam=1.22,mp5=1.15,hit=0.9,haste=0.92},
        physical = {dps=1.12,agi=1.06,stam=1.22,armor=1.13,hit=0.9},
    },
    pvp = {
        caster = {stam=1.95,armor=1.3,resist=1.75,def=1.3,crit=1.12,hit=0.85},
        physical = {stam=1.95,armor=1.35,resist=1.75,def=1.3,crit=1.12,hit=0.85},
    },
    pve = {
        caster = {spell=1.12,hit=1.18,haste=1.12,crit=1.09,stam=0.62,armor=0.55,resist=0.55},
        physical = {ap=1.1,dps=1.15,hit=1.18,haste=1.12,crit=1.09,stam=0.62,armor=0.55,resist=0.55},
    },
}

local casterSpecs = {
    SHAMAN={Elemental=true,Restoration=true},
    DRUID={Balance=true,Restoration=true},
    PALADIN={Holy=true},
}

local weights = {
    dps = {
        caster = {spell=3.5,int=1.0,spi=0.25,stam=0.15,crit=1.1,hit=1.3,haste=1.0,mp5=0.3,def=0.0,armor=0.001},
        physical = {str=1.4,agi=1.8,ap=0.8,crit=1.2,hit=1.3,haste=1.0,dps=4.0,stam=0.2,armor=0.001},
    },
    balanced = {
        caster = {spell=2.3,int=1.0,spi=0.45,stam=1.0,crit=0.8,hit=0.9,haste=0.7,mp5=0.7,armor=0.006,resist=0.08,def=0.15},
        physical = {str=1.0,agi=1.3,ap=0.5,crit=0.9,hit=0.9,haste=0.7,dps=2.7,stam=1.1,armor=0.006,resist=0.08,def=0.2},
    },
    survival = {
        caster = {spell=0.6,int=0.35,spi=0.7,stam=2.8,crit=0.1,hit=0.1,mp5=0.9,armor=0.012,resist=0.3,def=0.8},
        physical = {str=0.45,agi=0.75,ap=0.15,stam=2.8,armor=0.014,resist=0.3,def=1.0,dps=0.7},
    },
}

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

-- These are heuristic weights, not an output of the Icy Veins simulator.
-- A selected character build modifies the category weights without claiming
-- to know a full talent-specific DPS model.
local specFactors={
    MAGE={Frost={spell=1.08,hit=1.10,crit=1.06},Fire={spell=1.10,crit=1.12},Arcane={int=1.12,spell=1.05}},
    WARLOCK={Affliction={spell=1.10,hit=1.10,spi=1.05},Demonology={spell=1.04,stam=1.07},Destruction={spell=1.09,crit=1.10}},
    PRIEST={Shadow={spell=1.12,hit=1.08,spi=1.05},Discipline={int=1.1,mp5=1.1},Holy={spi=1.1,int=1.06}},
    SHAMAN={Enhancement={ap=1.10,str=1.06,agi=1.06,dps=1.08},Elemental={spell=1.12,int=1.06}},
    HUNTER={["Beast Mastery"]={agi=1.08,ap=1.08,dps=1.09},Marksmanship={agi=1.10,crit=1.08}},
    DRUID={Feral={agi=1.10,str=1.04,dps=1.08},Balance={spell=1.12,int=1.08}},
}
-- Only treat absent stats as zero when BOTH equipped and candidate items have
-- successfully returned an actual client stats table. A missing table is unknown.
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
    if type(raw)~="table" then return nil end
    local result={}
    for category,keys in pairs(stats) do
        local value=0
        for _,key in ipairs(keys) do value=value+(tonumber(raw[key]) or 0) end
        if value~=0 then result[category]=value end
    end
    -- Empty or unrecognized API data does NOT establish a real zero-stat item.
    if not next(result) then return nil end
    return result
end

G.statLabels={str="Strength",agi="Agility",int="Intellect",stam="Stamina",
    spi="Spirit",spell="Spell Power",ap="Attack Power",crit="Critical Strike",
    hit="Hit Rating",haste="Haste Rating",dps="Weapon DPS",mp5="Mana Regeneration",
    armor="Armor",def="Defense",resist="Resistance"}
G.statAliases={intellect="int",stamina="stam",strength="str",agility="agi",
    spirit="spi",spellpower="spell",attackpower="ap",critical="crit",
    criticalstrike="crit",hitrate="hit",hitrating="hit",
    haste_rating="haste"}
-- Users can set custom baseline weights per character and activity with
-- /fcm gearweight spell 5 (or reset). Specialization/activity factors still apply.
function G:Weight(category,ch,mode,activity)
    local class=type(ch)=="table" and ch.class or ch
    local spec=type(ch)=="table" and ch.talentSpec or nil
    local profile=(caster[class] or (casterSpecs[class] and casterSpecs[class][spec])) and "caster" or "physical"
    local activityKey=activity or (type(ch)=="table" and FCM:GearActivity(ch)) or "leveling"
    if not activityFactors[activityKey] then activityKey="leveling" end
    local modeKey=mode or (type(ch)=="table" and FCM:Mode(ch,activityKey)) or "dps"
    local base=(weights[modeKey] or weights.dps)[profile][category] or 0
    local custom=type(ch)=="table" and ch.gearCustomWeights and ch.gearCustomWeights[activityKey]
    if type(custom)=="table" and type(custom[category])=="number" then base=custom[category] end
    local factor=type(ch)=="table" and specFactors[class] and specFactors[class][spec or ""]
    return base*((factor and factor[category]) or 1)*((activityFactors[activityKey][profile] or {})[category] or 1)
end
function G:SetCustomWeight(ch,category,value,activity)
    if not ch or not stats[category] then return false end
    local key=activity or FCM:GearActivity(ch)
    if not activityFactors[key] then return false end
    if value~=nil and (type(value)~="number" or value<0 or value>100) then return false end
    ch.gearCustomWeights=ch.gearCustomWeights or {}
    ch.gearCustomWeights[key]=ch.gearCustomWeights[key] or {}
    ch.gearCustomWeights[key][category]=value
    return true
end

function G:ScoreParts(item,ch,mode,activity)
    local values=self:StatValues(item)
    if not values then return nil end
    local result,total={},0
    for category,value in pairs(values) do
        local weighted=value*self:Weight(category,ch,mode,activity)
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
function G:CompareActivities(item, ch, oldItem, slot, equip)
    local result={}
    for _,activity in ipairs(FCM.gearActivityOrder or {"leveling","pvp","pve"}) do
        local mode=FCM:Mode(ch,activity)
        local value=self:Score(item,ch,mode,activity)
        local oldScore=nil
        if oldItem then oldScore=self:Score(oldItem,ch,mode,activity)
        elseif ch and ch.gearStamp then oldScore=0 end -- scanned empty slot
        if oldScore and equip=="INVTYPE_2HWEAPON" and ch and ch.gear and slot==16 then
            local off=ch.gear[17]
            if off and (off.link or off.itemID) then
                local offScore=self:Score(off.link or off.itemID,ch,mode,activity)
                if offScore then oldScore=oldScore+offScore else oldScore=nil end
            end
        end
        result[#result+1]={activity=activity,label=FCM.gearActivityLabels[activity],
            style=mode,score=value,currentScore=oldScore,
            delta=(type(value)=="number" and type(oldScore)=="number") and (value-oldScore) or nil}
    end
    return result
end
function G:Explain(candidate,ch)
    if not candidate or not ch then return "No recommendation selected." end
    local oldlink=candidate.current and candidate.current.link
    local _,newStats=self:ScoreParts(candidate.info.link or candidate.recipe.outputID,ch,candidate.mode)
    local _,oldStats=self:ScoreParts(oldlink,ch,candidate.mode)
    local old={}
    for _,p in ipairs(oldStats or {}) do old[p.name]=p.value end
    local changes={}
    for _,p in ipairs(newStats or {}) do
        local delta=p.value-(old[p.name] or 0)
        if delta~=0 then changes[#changes+1]={stat=p.name,change=delta,impact=math.abs(p.weighted)} end
        old[p.name]=nil
    end
    for name,amount in pairs(old) do changes[#changes+1]={stat=name,change=-amount,impact=0} end
    table.sort(changes,function(a,b)return a.impact>b.impact end)
    local lines={"Why this item ranks higher (estimated score):"}
    for i=1,math.min(7,#changes) do
        local stat=changes[i]
        lines[#lines+1]="  "..stat.stat..": "..(stat.change>0 and "+" or "")..string.format("%.1f",stat.change)
    end
    lines[#lines+1]="NOTE: weighted stat score is not actual DPS. Special effects, set bonuses, class restrictions and weapon combinations must be verified."
    return table.concat(lines,"\n")
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
function G:CompareItem(item,ch,preferredSlot)
    if not ch then return {status="unknown",reason="Select a character to compare equipment."} end
    local info=self:Info(item)
    if not info or not info.equip or not slots[info.equip] then
        return {status="not-equipment"}
    end
    if not self:IsPotentiallyWearable(info,ch) then
        return {status="ineligible",reason="Item level, armor type, or equipment restrictions may prevent use."}
    end
    if not ch.gearStamp or type(ch.gear)~="table" then
        return {status="unknown",reason="Equipment has not been scanned for this character."}
    end
    local candidateStats=self:StatValues(item)
    if not candidateStats then
        return {status="unknown",reason="Candidate stats are not available from the game client."}
    end
    local activity=FCM:GearActivity(ch)
    local mode=FCM:Mode(ch,activity)
    local newScore=self:Score(item,ch,mode,activity)
    if type(newScore)~="number" then return {status="unknown",reason="Candidate score is unavailable."} end
    local options=slots[info.equip]
    local choice=nil
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
            local oldRef=old and (old.link or old.itemID)
            local oldStats,oldScore={},0
            local oldName="Empty slot"
            if oldRef then
                oldStats=self:StatValues(oldRef)
                oldScore=self:Score(oldRef,ch,mode,activity)
                local oldInfo=self:Info(oldRef)
                oldName=(oldInfo and oldInfo.name) or old.name or ("Item #"..tostring(old.itemID or "?"))
                if not oldStats or type(oldScore)~="number" then valid=false end
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
                if not choice or delta>choice.delta then
                    choice={status="ok",info=info,slot=slot,oldName=oldName,oldStats=oldStats,
                        newStats=candidateStats,newScore=newScore,oldScore=oldScore,delta=delta,
                        activity=activity,style=mode,empty=not oldRef}
                end
            end
        end
    end
    if not choice then return {status="unknown",reason="Equipped item stats or a valid replacement slot are unavailable."} end
    local keys,changes={},{}
    for key in pairs(choice.newStats) do keys[key]=true end
    for key in pairs(choice.oldStats) do keys[key]=true end
    for key in pairs(keys) do
        local before=choice.oldStats[key] or 0
        local after=choice.newStats[key] or 0
        local change=after-before
        if change~=0 then
            local percent=before~=0 and (change/math.abs(before))*100 or nil
            local impact=change*self:Weight(key,ch,mode,activity)
            changes[#changes+1]={key=key,label=self.statLabels[key] or key,before=before,after=after,
                change=change,percent=percent,impact=impact,weight=self:Weight(key,ch,mode,activity)}
        end
    end
    table.sort(changes,function(a,b)
        if math.abs(a.impact)==math.abs(b.impact) then return a.label<b.label end
        return math.abs(a.impact)>math.abs(b.impact)
    end)
    choice.changes=changes
    if choice.oldScore>0 then choice.scorePct=choice.delta/choice.oldScore*100 end
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
-- Color-coded arrows, per-stat absolute and percentage changes, and a short
-- narrative. These strings work both in the standard pane and Dungeon Explorer.
function G:ComparisonLines(comparison)
    if not comparison or comparison.status=="not-equipment" then return {} end
    local lines={tint("SMART GEAR COMPARISON","ffd76d")}
    if comparison.status~="ok" then
        lines[#lines+1]=tint(comparison.reason or "Comparison not available.","f0d27b")
        return lines
    end
    lines[#lines+1]="Compared with: "..comparison.oldName
    for _,c in ipairs(comparison.changes) do
        local up=c.change>0
        local hex=up and "76e59a" or "ff8888"
        local arrow=up and "▲" or "▼"
        local pct=c.percent and string.format(" (%+.0f%%)",c.percent) or (up and " (NEW)" or "")
        lines[#lines+1]=tint(arrow.." "..c.label.." "..signed(c.change)..pct,hex)
            .."  "..string.format("%g",c.before).." > "..string.format("%g",c.after)
    end
    if #comparison.changes==0 then lines[#lines+1]="Known stats match." end
    local delta=comparison.delta
    local outcome=delta>0.01 and "▲ Upgrade" or (delta< -0.01 and "▼ Downgrade" or "— Equal score")
    local hex=delta>0.01 and "76e59a" or (delta< -0.01 and "ff8888" or "c9d1de")
    lines[#lines+1]=tint(outcome..": "..signed(delta).." weighted points"..(comparison.scorePct and string.format(" (%+.1f%%)",comparison.scorePct) or " (new slot)"),hex)
    lines[#lines+1]="Why: "..comparison.reason
    lines[#lines+1]=tint("Estimated weights for "..(FCM.gearActivityLabels[comparison.activity] or comparison.activity)..
        " / "..(FCM.modeLabels[comparison.style] or comparison.style).."; not actual DPS.","aab8ca")
    lines[#lines+1]=tint("Not modeled: caps, procs, sets, PvP effects, unique restrictions.","aab8ca")
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
    local results, mode = {}, FCM:Mode(ch)
    for _, recipe in ipairs(FCM:AllRecipes()) do
        if recipe.outputID then
            local info = self:Info(recipe.outputLink or recipe.outputID) or self:Info(recipe.outputID)
            if self:IsPotentiallyWearable(info, ch) then
                for _, slot in ipairs(slots[info.equip] or {}) do
                    -- Unknown gear is not an empty equipped slot. Wait for a
                    -- successful equipment scan before claiming an improvement.
                    local baseline = ch.gearStamp and 0 or nil
                    local old = ch.gear and ch.gear[slot]
                    if old and (old.link or old.itemID) then baseline = self:Score(old.link or old.itemID, ch, mode) end
                    if old and baseline==nil then baseline=nil end
                    if info.equip == "INVTYPE_2HWEAPON" then
                        local off = ch.gear and ch.gear[17]
                        if off and (off.link or off.itemID) then
                            local offScore=self:Score(off.link or off.itemID, ch, mode)
                            if baseline and offScore then baseline=baseline+offScore else baseline=nil end
                        end
                    end
                    local candidateScore = self:Score(info.link or recipe.outputID, ch, mode)
                    if candidateScore and baseline and candidateScore > baseline + (FCM.db.settings.minimumUpgrade or 1) then
                        local usableCrafters = {}
                        for _, crafter in ipairs(recipe.crafters or {}) do
                            -- Binds on Pickup is only craftable for the recipient's own use.
                            if FCM:CanCollaborate(crafter,ch) and
                                (info.bindType ~= 1 or crafter.key == ch.key) then
                                usableCrafters[#usableCrafters+1]=crafter
                            end
                        end
                        if #usableCrafters > 0 then
                            local row = { recipe=recipe, info=info, slot=slot, current=old,
                                currentScore=baseline, score=candidateScore, delta=candidateScore-baseline,
                                mode=mode, crafters=usableCrafters,
                                tradeabilityConfirmed=(info.bindType == 2) }
                            results[#results+1] = row
                        end
                    end
                end
            end
        end
    end
    table.sort(results, function(a,b) return a.delta > b.delta end)
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
                local score=self:Score(info.link or entry.outputID,ch,mode)
                if score then
                    for _,slot in ipairs(self.slots[info.equip] or {}) do
                        local old=ch.gear and ch.gear[slot]
                        local oldScore=(old and old.link and self:Score(old.link,ch,mode)) or 0
                        if score>oldScore+(FCM.db.settings.minimumUpgrade or 1) then
                            rows[#rows+1]={entry=entry,info=info,delta=score-oldScore,slot=slot}
                        end
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

-- Dungeon recommendations use source-reported loot IDs but only recommend an
-- item when the installed WoW client provides both equip info and item stats.
-- They do NOT assume that every ForeverDB record is obtainable at launch.
function G:DungeonCandidates(ch)
    local results,seen={},{}
    if not ch then return results end
    local dungeons=FCM.externalData and FCM.externalData.dungeons or {}
    for _,dungeon in pairs(dungeons) do
        for _,lootID in ipairs(dungeon.lootIDs or {}) do
            local id=tonumber(lootID)
            if id and not seen[id] then
                seen[id]=true
                local comparison=self:CompareItem(id,ch)
                local threshold=FCM.db and FCM.db.settings and FCM.db.settings.minimumUpgrade or 1
                if comparison.status=="ok" and comparison.delta>threshold then
                    results[#results+1]={itemID=id,info=comparison.info,
                        delta=comparison.delta,slot=comparison.slot,
                        source=dungeon.name or "Unknown dungeon"}
                end
            end
        end
    end
    table.sort(results,function(x,y)return x.delta>y.delta end)
    return results
end
