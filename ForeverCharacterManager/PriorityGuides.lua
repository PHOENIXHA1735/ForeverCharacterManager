local _,FCM=...
FCM.PriorityGuides={}
local P=FCM.PriorityGuides

-- QA8: short, manually checked PRIORITY summaries for all 27 WoW Forever
-- specializations, with separate leveling and endgame PvE sources.
-- Icy Veins publishes ordinal guidance, not transferable per-point values.
-- This library must never be used to fabricate numerical stat weights.
local root="https://www.icy-veins.com/wow-forever/"
local sourceDates={
    ["balance-druid-leveling"]="2026-11-04",
    ["balance-druid-ranged-dps-pve-stat-priority"]="2026-11-04",
    ["feral-druid-leveling"]="2026-11-04",
    ["feral-druid-melee-dps-and-tank-pve-stat-priority"]="2026-11-04",
    ["restoration-druid-leveling"]="2026-11-04",
    ["restoration-druid-healer-pve-stat-priority"]="2026-11-04",
    ["beast-mastery-hunter-leveling"]="2026-11-04",
    ["beast-mastery-hunter-ranged-dps-pve-stat-priority"]="2026-11-04",
    ["marksmanship-hunter-leveling"]="2026-11-04",
    ["marksmanship-hunter-ranged-dps-pve-stat-priority"]="2026-11-04",
    ["survival-hunter-leveling"]="2026-11-04",
    ["survival-hunter-melee-dps-pve-stat-priority"]="2026-11-04",
    ["arcane-mage-leveling"]="2026-11-04",
    ["arcane-mage-ranged-dps-pve-stat-priority"]="2026-11-04",
    ["fire-mage-leveling"]="2026-11-04",
    ["fire-mage-ranged-dps-pve-stat-priority"]="2026-11-04",
    ["frost-mage-leveling"]="2026-11-10",
    ["frost-mage-ranged-dps-pve-stat-priority"]="2026-11-04",
    ["retribution-paladin-leveling"]="2026-11-04",
    ["retribution-paladin-melee-dps-pve-stat-priority"]="2026-11-04",
    ["protection-paladin-leveling"]="2026-11-04",
    ["protection-paladin-tank-pve-stat-priority"]="2026-11-04",
    ["holy-paladin-leveling"]="2026-11-04",
    ["holy-paladin-healer-pve-stat-priority"]="2026-11-04",
    ["discipline-priest-leveling"]="2026-11-10",
    ["discipline-priest-healer-pve-stat-priority"]="2026-11-04",
    ["holy-priest-leveling"]="2026-11-10",
    ["holy-priest-healer-pve-stat-priority"]="2026-11-04",
    ["shadow-priest-leveling"]="2026-11-04",
    ["shadow-priest-ranged-dps-pve-stat-priority"]="2026-11-04",
    ["assassination-rogue-leveling"]="2026-11-04",
    ["assassination-rogue-melee-dps-pve-stat-priority"]="2026-11-04",
    ["combat-rogue-leveling"]="2026-11-04",
    ["combat-rogue-melee-dps-pve-stat-priority"]="2026-11-04",
    ["subtlety-rogue-leveling"]="2026-11-04",
    ["subtlety-rogue-melee-dps-pve-stat-priority"]="2026-11-04",
    ["elemental-shaman-leveling"]="2026-11-04",
    ["elemental-shaman-ranged-dps-pve-stat-priority"]="2026-11-04",
    ["enhancement-shaman-leveling"]="2026-11-13",
    ["enhancement-shaman-melee-dps-pve-stat-priority"]="2026-11-13",
    ["restoration-shaman-leveling"]="2026-11-04",
    ["restoration-shaman-healer-pve-stat-priority"]="2026-11-04",
    ["affliction-warlock-leveling"]="2026-11-04",
    ["affliction-warlock-ranged-dps-pve-stat-priority"]="2026-11-04",
    ["demonology-warlock-leveling"]="2026-11-04",
    ["demonology-warlock-ranged-dps-pve-stat-priority"]="2026-11-04",
    ["destruction-warlock-leveling"]="2026-11-04",
    ["destruction-warlock-ranged-dps-pve-stat-priority"]="2026-11-04",
    ["arms-warrior-leveling"]="2026-11-04",
    ["arms-warrior-melee-dps-pve-stat-priority"]="2026-11-04",
    ["fury-warrior-leveling"]="2026-11-04",
    ["fury-warrior-melee-dps-pve-stat-priority"]="2026-11-04",
    ["protection-warrior-leveling"]="2026-11-04",
    ["protection-warrior-tank-pve-stat-priority"]="2026-11-04",
}
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
    attackPower={"Attack Power",{"ap","rap"}},
    spiritIntStam={"Spirit, Intellect and Stamina (resource sustain)",{"spi","int","stam"}},
    intellectStam={"Intellect and Stamina (resource sustain)",{"int","stam"}},
    armor={"Armor",{"armor"}},
    defense={"Defense (verify target before treating as capped)",{"def","defense_skill"},true},
    avoidance={"Dodge and Parry avoidance",{"dodge","parry"}},
    block={"Block",{"block"}},
    weaponSkill={"Weapon Skill",{"weapon_skill","weapon_skill_rating"}},
    spellPierce={"Spell Piercing (not resistance penetration)",{"spell_pierce"}},
}
local function tiers(keys)
    local result={}
    for _,key in ipairs(keys) do
        local p=assert(priority[key],"Unknown guide priority token: "..tostring(key))
        result[#result+1]={name=p[1],stats=p[2],capped=p[3] or false}
    end
    return result
end
local classNotes={
    DRUID="Balance values spell output and mana resources. Feral weapon DPS works in forms in Forever; Cat/threat and Bear mitigation are separate source lists. Restoration values healing and mana sustain; healing guidance does not measure damage builds.",
    HUNTER="Ranged weapon top-end damage, speed and pet interactions need manual review; weapon DPS alone is insufficient for ranged builds. Survival is a melee PvE build, while the leveling page retains ranged/beta references: verify the actual build before applying weapon advice.",
    MAGE="Generic Spell Power and school-restricted damage are distinct. Frost crit interactions and Spirit sustain differ from Arcane mana management and Fire crit builds. Level-60 spell-hit targets must not be applied unchanged to same-level leveling enemies.",
    PALADIN="Retribution endgame priorities depend on the selected capstone build. Holy uses healing/mana guidance, not a DPS scale. Protection threat, stamina and defense context require the target and block mechanics to be checked.",
    PRIEST="Discipline/Holy healing guides prioritize throughput and mana sustain; they do not establish offensive DPS weights. Shadow has separate spell-output priorities. Spirit effectiveness depends on casting and talents.",
    ROGUE="Weapon type, main/off hand, top-end damage and speed matter. Subtlety adds Weapon Skill context; it is not interchangeable with Hit or Expertise. Target level and facing change avoidance requirements.",
    SHAMAN="Enhancement leveling prioritizes Intellect/resource sustain differently from endgame after the November 12 Mental Dexterity change. Elemental uses spell output; Restoration uses healing. Spell Piercing and resistance penetration are not treated as the same stat.",
    WARLOCK="Spell Power supports mixed schools; school-specific bonuses affect only matching spells. Affliction, Demonology and Destruction have different spell/channel and crit/haste interactions. Mana/health sustain remains situational while leveling.",
    WARRIOR="Weapon speed and rage mechanics require context; more damage does not imply proportionally more rage in Forever. Protection offensive/threat and defensive lists stay separate. Dual-wield auto attacks and special attacks do not share one hit target.",
}
local guides={}
local function define(class,spec,slug,role,levelKeys,pveKeys,opts)
    opts=opts or {}
    guides[class]=guides[class] or {}
    local base=spec:lower():gsub(" ","-").."-"..class:lower()
    local common={role=role or "dps",weaponContext=opts.weaponContext or false}
    local function profile(activity,keys,url,updated)
        return {role=common.role,weaponContext=common.weaponContext,
            updated=sourceDates[url] or updated or "date unavailable",url=root..url,tiers=tiers(keys),
            activity=activity,notes=classNotes[class],game='WoW Forever',reviewedAt='2026-11-16',
            levelMin=activity=='pve' and 60 or 1,levelMax=60,
            applicability=activity=='pve' and 'Level 60 PvE; source beta/theorycraft caveats apply' or 'Leveling 1-60; priorities may change with talents and resources'}
    end
    local level=profile("leveling",levelKeys,base.."-leveling",opts.levelDate)
    local pve=profile("pve",pveKeys,slug.."-pve-stat-priority",opts.pveDate)
    if role=='healer' then
        pve.capNotes='Healing guidance does not establish a universal offensive hit cap or numerical healing weights.'
    elseif class=='MAGE' or class=='WARLOCK' or (class=='PRIEST' and spec=='Shadow') or (class=='DRUID' and spec=='Balance') or (class=='SHAMAN' and spec=='Elemental') then
        pve.capNotes='Source raid context: 17% total spell Hit versus level-63 bosses; include applicable talents. This is not 17 item rating.'
    elseif class=='ROGUE' then
        pve.capNotes='Source boss context: 8% Hit for specials and 6.5% dodge reduction with Expertise when attacking from behind. Weapon Skill and target facing require separate review.'
    elseif class=='WARRIOR' then
        pve.capNotes='Source level-63 context: 8% Hit for specials/weapon-and-shield/two-handed attacks; 27% for dual-wield auto attacks before talents. Expertise dodge reduction 6.5% from behind; front-facing parry reduction 14%. Protection source discusses 440 total Defense and Shield Block separately.'
    elseif class=='DRUID' and spec=='Feral' then
        pve.capNotes='Source level-63 context: 8% Hit; Expertise dodge reduction 6.5% from behind or parry reduction 14% from the front. Bear mitigation source discusses 440 total Defense; do not equate it to Defense rating.'
    elseif class=='PALADIN' and spec=='Protection' then
        pve.capNotes='Source describes 440 total Defense. Block/combined avoidance and crush context require manual review; Defense rating is not total Defense skill.'
    elseif class=='HUNTER' and spec~='Survival' then
        pve.capNotes='Source boss context: 8% total Hit. Verify talents and ranged weapon context; no item-rating conversion is assumed.'
    else pve.capNotes='Build, target and ability context must be checked in the linked source; no universal cap is assumed.' end
    if class=='MAGE' and spec=='Frost' then level.capNotes='Source same-level leveling context: 4% spell Hit, with Precision/target-level context. The level-63 raid target is not a universal leveling cap.' end
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
    {"spell","intellect","spirit","crit","stamina"},
    {"spellHit","spellArcane","crit","intellect","spirit","mp5"})
define("MAGE","Fire","fire-mage-ranged-dps","dps",
    {"spell","crit","intellect","spirit","stamina"},
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
    {"spell","crit","spellHit","intellect","spirit","stamina","mp5"},
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
guides.PRIEST.Discipline.pvp={role='healer',activity='pvp',game='WoW Forever',levelMin=1,levelMax=60,
    updated='2026-11-15',reviewedAt='2026-11-16',sourceName='Mobalytics / Hydramist (Hydra)',
    url='https://mobalytics.gg/wow-forever/classes/priest-pvp-guide',requiresBuild=true,
    applicability='General Discipline PvP reference only; source does not validate a specific level bracket',
    tiers={{name='Stamina and Intellect: early survival and resources',stats={'stam','int'}},
        {name='Healing, Spirit and MP5: longer-fight throughput',stats={'healing','spi','mp5'}}},
    notes='These priorities are specific to Hydra\'s Discipline PvP discussion. They are not a Holy/Shadow, PvE or numerical healing model.',
    capNotes='No universal numerical hit-rating cap is inferred from this source; talents and opponent context must be checked.'}
function P:Reference(ch,activity)
    if type(ch)~="table" then return nil end
    local act=activity or (FCM.GearActivity and FCM:GearActivity(ch)) or "leveling"
    local classGuides=guides[ch.class]
    local specGuides=classGuides and classGuides[ch.talentSpec or ""]
    local guide=specGuides and specGuides[act]
    if not guide or type(ch.level)~='number' or ch.level<guide.levelMin or ch.level>guide.levelMax then return nil end
    return guide
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
        return "No reviewed WoW Forever priority guide for this class/spec/level/activity. PvE and leveling are not substituted for PvP. Numerical weights unavailable."
    end
    local lines={"STAT PRIORITY - "..string.upper(g.role or "dps"),"",
        'Game: '..g.game..' | '..g.applicability,
        'Source updated: '..g.updated..' | FCM reviewed: '..g.reviewedAt,'',
        'Primary '..(g.role=='dps' and 'offensive' or 'role')..' stats: '..table.concat({g.tiers[1] and g.tiers[1].name or 'Build-dependent',g.tiers[2] and g.tiers[2].name or ''},'; '),
        'Secondary stats follow in the ordered reference; there is no universal exchange rate.','',"Higher priority first:"}
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
    lines[#lines+1]='Source: '..(g.sourceName or 'Icy Veins WoW Forever')
    lines[#lines+1]=g.url
    lines[#lines+1]=""
    lines[#lines+1]="IMPORTANT: This is an ORDER, not per-point stat weights or predicted DPS."
    lines[#lines+1]='Defensive/survival context: Stamina supplies health; Armor addresses physical damage. Tank threat and mitigation are separate decisions.'
    lines[#lines+1]='Caps are character/target/talent dependent. Published percentages are not item-rating thresholds; FCM does not invent conversions.'
    if g.capNotes then lines[#lines+1]=g.capNotes end
    if g.notes then lines[#lines+1]=g.notes end
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
