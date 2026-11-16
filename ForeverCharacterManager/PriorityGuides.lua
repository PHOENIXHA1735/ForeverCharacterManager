local _,FCM=...
FCM.PriorityGuides={}
local P=FCM.PriorityGuides

-- QA8: short, manually checked PRIORITY summaries for all 27 WoW Forever
-- specializations, with separate leveling and endgame PvE sources.
-- Icy Veins publishes ordinal guidance, not transferable per-point values.
-- This library must never be used to fabricate numerical stat weights.
local root="https://www.icy-veins.com/wow-forever/"
local priority={
    weapon={"Weapon damage / DPS (weapon speed can matter)",{"dps"}},
    feralWeapon={"Weapon DPS in forms",{"dps"}},
    hit={"Hit Chance (only to the relevant target cap)",{"hit"},true},
    spellHit={"Spell Hit (only to the relevant target cap)",{"hit","spell_hit_pct"},true},
    expertise={"Expertise (only to the relevant target cap)",{"expertise"},true},
    hitExp={"Hit Chance and Expertise (situational caps)",{"hit","expertise"},true},
    spell={"Spell Power",{"spell"}},
    spellFrost={"Spell Power / Frost Damage",{"spell","spell_frost"}},
    spellFire={"Spell Power / Fire Damage",{"spell","spell_fire"}},
    spellShadow={"Spell Power / Shadow Damage",{"spell","spell_shadow"}},
    spellArcane={"Spell Power / Arcane Damage",{"spell","spell_arcane"}},
    spellNature={"Spell Power / Nature Damage",{"spell","spell_nature"}},
    heal={"Healing Power",{"healing"}},
    crit={"Critical Strike Chance",{"crit","spell_crit_pct"}},
    haste={"Haste",{"haste"}},
    intellect={"Intellect",{"int"}},
    spirit={"Spirit",{"spi"}},
    stamina={"Stamina",{"stam"}},
    mp5={"Mana per 5 seconds",{"mp5"}},
    strength={"Strength",{"str"}},
    strengthAp={"Strength / Attack Power",{"str","ap"}},
    agility={"Agility",{"agi"}},
    agilityCrit={"Agility / Critical Strike",{"agi","crit"}},
    attackPower={"Attack Power",{"ap"}},
    spiritIntStam={"Spirit, Intellect and Stamina (resource sustain)",{"spi","int","stam"}},
    intellectStam={"Intellect and Stamina (resource sustain)",{"int","stam"}},
    armor={"Armor",{"armor"}},
    defense={"Defense (verify target before treating as capped)",{"def"},true},
    avoidance={"Dodge and Parry avoidance",{"dodge","parry"}},
    block={"Block",{"block"}},
    weaponSkill={"Weapon Skill",{"weapon_skill"}},
    spellPierce={"Spell Piercing",{"spell_pen"}},
}
local function tiers(keys)
    local result={}
    for _,key in ipairs(keys) do
        local p=assert(priority[key],"Unknown guide priority token: "..tostring(key))
        result[#result+1]={name=p[1],stats=p[2],capped=p[3] or false}
    end
    return result
end
local guides={}
local function define(class,spec,slug,role,levelKeys,pveKeys,opts)
    opts=opts or {}
    guides[class]=guides[class] or {}
    local base=spec:lower():gsub(" ","-").."-"..class:lower()
    local common={role=role or "dps",weaponContext=opts.weaponContext or false}
    local function profile(activity,keys,url,updated)
        return {role=common.role,weaponContext=common.weaponContext,
            updated=updated or "2026-11-04",url=root..url,tiers=tiers(keys),
            activity=activity}
    end
    local level=profile("leveling",levelKeys,base.."-leveling",opts.levelDate)
    local pve=profile("pve",pveKeys,slug.."-pve-stat-priority",opts.pveDate)
    if opts.levelVariants then level.variants=opts.levelVariants end
    if opts.pveVariants then pve.variants=opts.pveVariants end
    if opts.pveBuildRequired then pve.requiresBuild=true end
    guides[class][spec]={leveling=level,pve=pve}
end

-- DRUID: the Feral PvE guide has separate Cat/threat and Bear mitigation lists.
define("DRUID","Balance","balance-druid-ranged-dps","dps",
    {"intellect","spell","crit","haste","spirit","mp5"},
    {"spellHit","crit","spell","intellect"})
define("DRUID","Feral","feral-druid-melee-dps-and-tank","dps",
    {"feralWeapon","hitExp","crit","agility","strengthAp","stamina"},
    {"feralWeapon","expertise","hit","agility","strength"},
    {pveVariants={{name="Bear mitigation (reference only)",
        tiers=tiers({"armor","defense","stamina","agility","avoidance"})}}})
define("DRUID","Restoration","restoration-druid-healer","healer",
    {"spell","heal","intellect","crit","haste","spirit","mp5"},
    {"heal","intellect","spirit","mp5","crit"})

-- HUNTER: Survival is a melee build; ranged specs favor weapon top-end damage.
define("HUNTER","Beast Mastery","beast-mastery-hunter-ranged-dps","dps",
    {"weapon","hit","agility","crit","intellect","spirit","stamina"},
    {"weapon","hit","crit","agility","attackPower"},{weaponContext=true})
define("HUNTER","Marksmanship","marksmanship-hunter-ranged-dps","dps",
    {"weapon","hit","agility","crit","intellect","spirit","stamina"},
    {"weapon","hit","crit","agility","attackPower"},{weaponContext=true})
define("HUNTER","Survival","survival-hunter-melee-dps","dps",
    {"weapon","agility","crit","intellect","spirit","stamina"},
    {"weapon","hit","crit","agility","attackPower"},{weaponContext=true})

-- MAGE: leveling favors sustain differently from raid-boss gearing.
define("MAGE","Arcane","arcane-mage-ranged-dps","dps",
    {"spellArcane","intellect","spirit","crit","stamina"},
    {"spellHit","spellArcane","crit","intellect","spirit","mp5"})
define("MAGE","Fire","fire-mage-ranged-dps","dps",
    {"spellFire","crit","intellect","spirit","stamina"},
    {"spellHit","spellFire","crit","intellect","spirit","mp5"})
define("MAGE","Frost","frost-mage-ranged-dps","dps",
    {"spellHit","spellFrost","crit","spirit","intellect","stamina"},
    {"spellHit","spellFrost","crit","intellect","mp5","spirit"},
    {levelDate="2026-11-10"})

-- PALADIN: different Retribution capstone builds demand different PvE priorities.
-- No single build is assumed automatically.
define("PALADIN","Retribution","retribution-paladin-melee-dps","dps",
    {"weapon","hitExp","spell","intellect","crit","strengthAp"},
    {},{weaponContext=true,pveBuildRequired=true,
        pveVariants={
            {name="Unsealed Wrath",tiers=tiers({"weapon","hit","expertise","strength","spell"})},
            {name="Holy Shock",tiers=tiers({"weapon","hit","spell","crit","expertise"})},
        }})
define("PALADIN","Protection","protection-paladin-tank","tank",
    {"stamina","spell","strength","block","hit","defense","armor","intellect","agility"},
    {"stamina","defense","spell","intellect","strength"})
define("PALADIN","Holy","holy-paladin-healer","healer",
    {"heal","intellect","mp5","crit","haste","spirit"},
    {"heal","intellect","spirit","mp5","crit"})

-- PRIEST: healing stat order cannot be used as an offensive damage scale.
define("PRIEST","Discipline","discipline-priest-healer","healer",
    {"heal","mp5","intellect","spirit","crit"},
    {"heal","mp5","spirit","intellect","crit"})
define("PRIEST","Holy","holy-priest-healer","healer",
    {"heal","mp5","spirit","intellect","crit"},
    {"heal","mp5","spirit","intellect","crit"})
define("PRIEST","Shadow","shadow-priest-ranged-dps","dps",
    {"spellShadow","crit","spellHit","intellect","spirit","stamina","mp5"},
    {"spellHit","spellShadow","crit","spellPierce","spirit"})

-- ROGUE: at low level top-end main-hand damage and correct weapon type matter.
define("ROGUE","Assassination","assassination-rogue-melee-dps","dps",
    {"weapon","hitExp","agility","crit","strength","stamina"},
    {"expertise","hit","agility","weapon","crit"},{weaponContext=true})
define("ROGUE","Combat","combat-rogue-melee-dps","dps",
    {"weapon","hitExp","agility","crit","strength","stamina"},
    {"expertise","hit","agility","weapon","crit"},{weaponContext=true})
define("ROGUE","Subtlety","subtlety-rogue-melee-dps","dps",
    {"weapon","hitExp","agility","attackPower","crit","strength"},
    {"weapon","expertise","hit","weaponSkill","agility"},{weaponContext=true})

-- SHAMAN: Enhancement leveling follows mana/Intellect differently from PvE
-- following the November 12 Mental Dexterity hotfix.
define("SHAMAN","Elemental","elemental-shaman-ranged-dps","dps",
    {"spellNature","crit","spellHit","intellect","mp5","spirit","stamina"},
    {"spell","spellHit","crit","intellect","mp5"})
define("SHAMAN","Enhancement","enhancement-shaman-melee-dps","dps",
    {"weapon","intellect","strength","spirit","agility","stamina"},
    {"weapon","hit","expertise","strength","intellect","spell"},
    {weaponContext=true,levelDate="2026-11-13",pveDate="2026-11-13"})
define("SHAMAN","Restoration","restoration-shaman-healer","healer",
    {"heal","crit","intellect","spirit","mp5","stamina"},
    {"heal","crit","intellect","spirit","mp5"})

-- WARLOCK: general Spell Power is preferable to one-school damage for builds
-- that weave Fire and Shadow. Affliction's established QA7 ordering is retained.
define("WARLOCK","Affliction","affliction-warlock-ranged-dps","dps",
    {"spellShadow","crit","spiritIntStam"},
    {"spellHit","spellShadow","crit","haste","intellect"})
define("WARLOCK","Demonology","demonology-warlock-ranged-dps","dps",
    {"spell","crit","spellHit","intellectStam","spirit"},
    {"spellHit","spell","crit","haste","intellect"})
define("WARLOCK","Destruction","destruction-warlock-ranged-dps","dps",
    {"spellFire","spellHit","crit","intellectStam","spirit"},
    {"spellHit","spell","haste","crit","intellect"})

-- WARRIOR: Protection has separate PvE threat and survival priorities.
define("WARRIOR","Arms","arms-warrior-melee-dps","dps",
    {"weapon","hitExp","agilityCrit","strengthAp"},
    {"weapon","hit","expertise","crit","strength"},{weaponContext=true})
define("WARRIOR","Fury","fury-warrior-melee-dps","dps",
    {"weapon","hitExp","strengthAp","agilityCrit"},
    {"weapon","hit","expertise","crit","strength"},{weaponContext=true})
define("WARRIOR","Protection","protection-warrior-tank","tank",
    {"weapon","hitExp","strengthAp","agilityCrit","armor","stamina"},
    {},{weaponContext=true,pveVariants={
        {name="Threat / offensive",tiers=tiers({"expertise","hit","agility","strength","stamina"})},
        {name="Mitigation / defensive",tiers=tiers({"stamina","armor","agility","avoidance","defense"})},
    }})

-- Pure lookup for the UI and /fcm statguide, INCLUDING tank/healer/conditional
-- profiles. It is deliberately separate from automatic DPS assessment.
function P:Reference(ch,activity)
    if type(ch)~="table" then return nil end
    local act=activity or (FCM.GearActivity and FCM:GearActivity(ch)) or "leveling"
    local classGuides=guides[ch.class]
    local specGuides=classGuides and classGuides[ch.talentSpec or ""]
    return specGuides and specGuides[act] or nil
end

function P:Guide(ch,activity)
    local guide=self:Reference(ch,activity)
    if not guide or guide.role~="dps" or guide.requiresBuild then return nil end
    local act=activity or (FCM.GearActivity and FCM:GearActivity(ch)) or "leveling"
    local style=(FCM.Mode and FCM:Mode(ch,act)) or "dps"
    -- No assumed tank, healer, PvP, survival or balanced numerical profile.
    return style=="dps" and guide or nil
end

function P:Coverage()
    local specs,activities,automatic=0,0,0
    for _,classGuides in pairs(guides) do
        for _,entry in pairs(classGuides) do
            specs=specs+1
            for _,act in ipairs({"leveling","pve"}) do
                if entry[act] then
                    activities=activities+1
                    if entry[act].role=="dps" and not entry[act].requiresBuild then
                        automatic=automatic+1
                    end
                end
            end
        end
    end
    return specs,activities,automatic
end

function P:Description(ch,activity)
    local g=self:Reference(ch,activity)
    if not g then
        return "No reviewed WoW Forever priority guide for this class/spec/activity; FCM numerical estimates remain provisional."
    end
    local lines={"STAT PRIORITY - "..string.upper(g.role or "dps"),"",
        "Guide reviewed: "..g.updated,"","Higher priority first:"}
    if #g.tiers>0 then
        for index,tier in ipairs(g.tiers) do
            lines[#lines+1]=tostring(index)..". "..tier.name
        end
    end
    for _,variant in ipairs(g.variants or {}) do
        lines[#lines+1]=""
        lines[#lines+1]=variant.name.." (higher first):"
        for index,tier in ipairs(variant.tiers) do
            lines[#lines+1]=tostring(index)..". "..tier.name
        end
    end
    lines[#lines+1]=""
    lines[#lines+1]="Source: Icy Veins WoW Forever"
    lines[#lines+1]=g.url
    lines[#lines+1]=""
    lines[#lines+1]="IMPORTANT: This is an ORDER, not per-point stat weights or predicted DPS."
    if not self:Guide(ch,activity) then
        lines[#lines+1]="Reference ONLY: role, build or style is not eligible for automated DPS gear validation."
    end
    if g.weaponContext then
        lines[#lines+1]="Weapon top-end damage, hand, speed and proc effects require manual comparison."
    end
    return table.concat(lines,"\n")
end

-- Conservative dominance check; ordinal ranks cannot establish a universal
-- exchange rate between stats, nor a cap conversion from rating to percent.
-- For weapons whose guide favors top-end damage or swing speed, the client
-- snapshot's DPS alone is not sufficient for automatic item selection.
function P:Assess(ch,oldStats,newStats,activity,context)
    local g=self:Guide(ch,activity)
    if not g then return nil end
    if type(oldStats)~="table" or type(newStats)~="table" then
        return "review","Missing verified item stat tables."
    end
    if g.weaponContext and type(context)=="table" and context.weapon then
        return "review","Weapon top-end damage, speed, hand and effects are not established by the DPS stat alone."
    end
    local guideStats,cappedStats={},{}
    for _,tier in ipairs(g.tiers) do
        for _,stat in ipairs(tier.stats) do
            guideStats[stat]=true
            if tier.capped then cappedStats[stat]=true end
        end
    end
    local improvedGuide,decreased,changedCap,anyChanged=false,false,false,false
    local seen={}
    for stat in pairs(oldStats) do seen[stat]=true end
    for stat in pairs(newStats) do seen[stat]=true end
    for stat in pairs(seen) do
        local before=tonumber(oldStats[stat]) or 0
        local after=tonumber(newStats[stat]) or 0
        if after<before then decreased=true end
        if after>before and guideStats[stat] then improvedGuide=true end
        if after~=before then
            anyChanged=true
            if cappedStats[stat] then changedCap=true end
        end
    end
    if not anyChanged then return "review","Scanned item stats are tied; procs and sets are not measured." end
    if decreased then return "review","Mixed stat tradeoff: guide priorities have no universal per-point exchange rates." end
    if changedCap then return "review","Hit-cap / Expertise-cap context is unverified; do not score uncapped rating as a percent." end
    if not improvedGuide then return "review","No increase in a stat covered by this WoW Forever priority guide." end
    return "supported","No scanned stat decreased; a guide-priority stat improved. Actual DPS remains unmeasured."
end
