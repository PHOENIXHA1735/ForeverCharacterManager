local _, FCM = ...
-- FCM's curated/reference data, reviewed 2026-11-09 against Icy Veins WoW Forever.
-- These notes are NOT a live feed or a complete export of IV's interactive build calculators.
-- "sequence" only contains point order confirmed explicitly by the written source.
-- "goals" are named milestones/targets, NOT instructions to spend a point at that level.
FCM.talentGuideEdition = "2026-11-09 (reference snapshot)"
FCM.talentSpecChoices = {
    MAGE={"Frost","Fire","Arcane"}, WARLOCK={"Affliction","Demonology","Destruction"},
    PRIEST={"Shadow","Discipline","Holy"}, SHAMAN={"Enhancement","Elemental","Restoration"},
    HUNTER={"Beast Mastery","Marksmanship","Survival"}, DRUID={"Feral","Balance","Restoration"},
    WARRIOR={"Arms","Fury","Protection"}, ROGUE={"Combat","Assassination","Subtlety"},
    PALADIN={"Retribution","Protection","Holy"}
}
FCM.talentGuides = {
    MAGE = { Frost = {
        name="Frost Mage", levelingURL="https://www.icy-veins.com/wow-forever/frost-mage-leveling",
        pveURL="https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-spec-builds-talents",
        levelingSummary="Starts with two Precision points, then Arcane's Wand Specialization toward Missile Barrage. Frostbite follows before finishing Improved Frostbolt.",
        pveSummary="Icy Veins describes Deep Frost for general play (9/0/42) and two Cone of Cold raid variants (18/0/33 or 10/5/36). Choose the raid version for your actual content.",
        sequence={[10]={name="Precision",rank=1},[11]={name="Precision",rank=2}},
        goals={{level=12,text="Next route: Wand Specialization toward Missile Barrage (point order must be verified on IV)."},
            {level=27,text="Ice Lance is a leveling milestone in the guide's build."},
            {level=37,text="Fingers of Frost is a build milestone."},
            {level=47,text="Ice Barrier is a build milestone."}},
        pveGoals={"Deep Frost 9/0/42: general world/dungeons", "Cone of Cold 18/0/33: raid mana-sustain option", "Cone of Cold 10/5/36: raid damage option"},
    }},
    WARLOCK = { Affliction = {
        name="Affliction Warlock", levelingURL="https://www.icy-veins.com/wow-forever/affliction-warlock-leveling",
        pveURL="https://www.icy-veins.com/wow-forever/affliction-warlock-ranged-dps-pve-spec-builds-talents",
        levelingSummary="The first four points go into Suppression. Next the guide improves DoTs including instant Corruption, Nightfall and Siphon Life; it later diverts into Demonology.",
        pveSummary="Icy Veins recommends a Wrack-focused 33 Affliction / 0 Demonology / 18 Destruction build for dungeons and raids.",
        sequence={[10]={name="Suppression",rank=1},[11]={name="Suppression",rank=2},[12]={name="Suppression",rank=3},[13]={name="Suppression",rank=4},
            [14]={name="Improved Corruption",rank=1},[15]={name="Improved Corruption",rank=2},[16]={name="Improved Corruption",rank=3},
            [17]={name="Improved Corruption",rank=4},[18]={name="Improved Corruption",rank=5},
            [19]={name="Improved Life Tap",rank=1},
            [22]={name="Pandemic",rank=1},[23]={name="Pandemic",rank=2},[24]={name="Pandemic",rank=3},
            [25]={name="Nightfall",rank=1},[26]={name="Nightfall",rank=2},
            [30]={name="Siphon Life",rank=1},[41]={name="Demonic Sacrifice",rank=1},
            [44]={name="Grim Reach",rank=1},[45]={name="Grim Reach",rank=2},
            [51]={name="Wrack",rank=1},[52]={name="Improved Life Tap",rank=2},
            [53]={name="Amplify Curse",rank=1},[54]={name="Curse of Exhaustion",rank=1}},
        goals={{level=14,text="Develop instant Corruption, then Nightfall and Siphon Life (check exact sequence on IV)."},
            {level=31,text="After 30, invest in Demonology toward Demonic Sacrifice."},
            {level=41,text="Demonic Sacrifice is the route's level-41 goal."}},
        pveGoals={"Wrack build 33/0/18", "Soul Siphon increases channel damage with Affliction effects active"},
    }},
    PRIEST = { Shadow = {
        name="Shadow Priest", levelingURL="https://www.icy-veins.com/wow-forever/shadow-priest-leveling",
        pveURL="https://www.icy-veins.com/wow-forever/shadow-priest-ranged-dps-pve-spec-builds-talents",
        levelingSummary="Icy Veins prioritizes Wand Specialization early for efficient leveling damage. Exact point-by-point timing is not bundled.",
        pveSummary="Icy Veins' Shadow PvE template focuses on Shadowform in Shadow and Meditation in Discipline, with several flexible choices.",
        sequence={},
        goals={{level=10,text="First talent priority: Wand Specialization. Verify point order on Icy Veins."},
            {level=40,text="Mana economy improves; Shadowform remains a major destination."}},
        pveGoals={"Shadowform in Shadow", "Meditation in Discipline", "Twilight Focus, Shadow Weaving and Silence are flex choices"},
    }},
    SHAMAN = { Enhancement = {
        name="Enhancement Shaman", levelingURL="https://www.icy-veins.com/wow-forever/enhancement-shaman-leveling",
        pveURL="https://www.icy-veins.com/wow-forever/enhancement-shaman-melee-dps-pve-spec-builds-talents",
        levelingSummary="Icy Veins aims for Stormstrike as early as possible. The guide discusses an optional respec at 25 and Mana-sustain choices.",
        pveSummary="Standard PvE centers on Stormstrike / Improved Stormstrike, Maelstrom Weapon and Rage of the Farseer; a solo/dungeon alternative trades some damage tools for Mana sustain.",
        sequence={},
        goals={{level=20,text="Shamanistic Focus lowers Shock cost."},
            {level=25,text="Optional respec on IV to rush Stormstrike."},
            {level=30,text="Improved Stormstrike for Mana recovery."},
            {level=38,text="Mindfulness is a Mana-sustain milestone."},
            {level=42,text="Water Shield is a Mana-sustain milestone."}},
        pveGoals={"Stormstrike and Improved Stormstrike", "Maelstrom Weapon and Rage of the Farseer", "Solo/dungeon build may instead favor Mindfulness"},
    }},
    HUNTER = { ["Beast Mastery"] = {
        name="Beast Mastery Hunter", levelingURL="https://www.icy-veins.com/wow-forever/beast-mastery-hunter-leveling",
        pveURL="https://www.icy-veins.com/wow-forever/beast-mastery-hunter-ranged-dps-pve-spec-builds-talents",
        levelingSummary="The guide prioritizes damage early, particularly Deadly Aspects. Pathfinding and Improved Revive Pet are useful leveling utilities.",
        pveSummary="Icy Veins' standard PvE build uses 31 points in Beast Mastery and 20 in Marksmanship, reaching Bestial Wrath and Mortal Shots.",
        sequence={},
        goals={{level=10,text="Early priority: Deadly Aspects, not an exact point-order claim."},
            {level=40,text="Continue down Beast Mastery to reach Bestial Wrath."}},
        pveGoals={"Beast Mastery 31 points: Bestial Wrath", "Marksmanship 20 points: Mortal Shots", "Mana-vs-DPS flex in Marksmanship"},
        -- Exact displayed ranks for the standard level-60 PvE build on IV, not its level-up order.
        pveTarget={ ["Deadly Aspects"]=5,["Endurance Training"]=1,["Focused Fire"]=2,
            ["Improved Revive Pet"]=2,["Bestial Swiftness"]=1,["Unleashed Fury"]=5,
            ["Ferocity"]=5,["Summon Hawk"]=1,["Intimidation"]=1,
            ["Bestial Discipline"]=2,["Frenzy"]=5,["Bestial Wrath"]=1,
            ["Lethal Attacks"]=5,["Improved Stings"]=3,["Careful Aim"]=5,
            ["Rapid Killing"]=2,["Mortal Shots"]=5 },
    }},
    DRUID = { Feral = {
        name="Feral Druid", levelingURL="https://www.icy-veins.com/wow-forever/feral-druid-leveling",
        pveURL="https://www.icy-veins.com/wow-forever/feral-druid-melee-dps-and-tank-pve-spec-builds-talents",
        levelingSummary="Begin with Ferocity to reduce ability costs, then Feral Instinct and Feral Swiftness for cat-form efficiency after level 20.",
        pveSummary="Icy Veins separates hybrid Bear/Cat, Bear-only Tank and Cat DPS level-60 options; choose the build matching your role.",
        sequence={},
        goals={{level=10,text="Start with Ferocity; confirm rank order on IV."},
            {level=20,text="Cat Form unlock; Feral Instinct and Feral Swiftness become valuable."}},
        pveGoals={"Select Cat DPS for damage role", "Hybrid Bear/Cat and Bear Tank are separate alternatives"},
    }},
}

-- v0.7.1 talent profile registry. A source link is NOT a verified rank-by-rank build.
-- All specs keep the three original IDs for compatibility; source-verified
-- alternate playstyles can add further profiles in a spec-specific order.
-- Full individual talent ranks are NOT inferred from a named guide variant.
FCM.talentProfileIDs = {"leveling", "sustain", "output"}
FCM.talentProfileNames = {
    leveling="Leveling",
    sustain="Endgame - Sustain",
    output="Endgame - Output",
}
FCM.talentGuideEdition = "2026-11-10 (IV alternate builds reviewed; exact point paths mostly incomplete)"
FCM.talentReferenceIndex = {
    DRUID = {
        ["Balance"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/balance-druid-leveling",pveURL="https://www.icy-veins.com/wow-forever/balance-druid-ranged-dps-pve-spec-builds-talents"},
        ["Feral"]={role="hybrid",levelingURL="https://www.icy-veins.com/wow-forever/feral-druid-leveling",pveURL="https://www.icy-veins.com/wow-forever/feral-druid-melee-dps-and-tank-pve-spec-builds-talents"},
        ["Restoration"]={role="healer",levelingURL="https://www.icy-veins.com/wow-forever/restoration-druid-leveling",pveURL="https://www.icy-veins.com/wow-forever/restoration-druid-healer-pve-spec-builds-talents"},
    },
    HUNTER = {
        ["Beast Mastery"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/beast-mastery-hunter-leveling",pveURL="https://www.icy-veins.com/wow-forever/beast-mastery-hunter-ranged-dps-pve-spec-builds-talents"},
        ["Marksmanship"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/marksmanship-hunter-leveling",pveURL="https://www.icy-veins.com/wow-forever/marksmanship-hunter-ranged-dps-pve-spec-builds-talents"},
        ["Survival"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/survival-hunter-leveling",pveURL="https://www.icy-veins.com/wow-forever/survival-hunter-melee-dps-pve-spec-builds-talents"},
    },
    MAGE = {
        ["Arcane"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/arcane-mage-leveling",pveURL="https://www.icy-veins.com/wow-forever/arcane-mage-ranged-dps-pve-spec-builds-talents"},
        ["Fire"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/fire-mage-leveling",pveURL="https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-spec-builds-talents"},
        ["Frost"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/frost-mage-leveling",pveURL="https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-spec-builds-talents"},
    },
    PALADIN = {
        ["Retribution"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/retribution-paladin-leveling",pveURL="https://www.icy-veins.com/wow-forever/retribution-paladin-melee-dps-pve-spec-builds-talents"},
        ["Protection"]={role="tank",levelingURL="https://www.icy-veins.com/wow-forever/protection-paladin-leveling",pveURL="https://www.icy-veins.com/wow-forever/protection-paladin-tank-pve-spec-builds-talents"},
        ["Holy"]={role="healer",levelingURL="https://www.icy-veins.com/wow-forever/holy-paladin-leveling",pveURL="https://www.icy-veins.com/wow-forever/holy-paladin-healer-pve-spec-builds-talents"},
    },
    PRIEST = {
        ["Discipline"]={role="healer",levelingURL="https://www.icy-veins.com/wow-forever/discipline-priest-leveling",pveURL="https://www.icy-veins.com/wow-forever/discipline-priest-healer-pve-spec-builds-talents"},
        ["Holy"]={role="healer",levelingURL="https://www.icy-veins.com/wow-forever/holy-priest-leveling",pveURL="https://www.icy-veins.com/wow-forever/holy-priest-healer-pve-spec-builds-talents"},
        ["Shadow"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/shadow-priest-leveling",pveURL="https://www.icy-veins.com/wow-forever/shadow-priest-ranged-dps-pve-spec-builds-talents"},
    },
    ROGUE = {
        ["Assassination"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/assassination-rogue-leveling",pveURL="https://www.icy-veins.com/wow-forever/assassination-rogue-melee-dps-pve-spec-builds-talents"},
        ["Combat"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/combat-rogue-leveling",pveURL="https://www.icy-veins.com/wow-forever/combat-rogue-melee-dps-pve-spec-builds-talents"},
        ["Subtlety"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/subtlety-rogue-leveling",pveURL="https://www.icy-veins.com/wow-forever/subtlety-rogue-melee-dps-pve-spec-builds-talents"},
    },
    SHAMAN = {
        ["Elemental"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/elemental-shaman-leveling",pveURL="https://www.icy-veins.com/wow-forever/elemental-shaman-ranged-dps-pve-spec-builds-talents"},
        ["Enhancement"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/enhancement-shaman-leveling",pveURL="https://www.icy-veins.com/wow-forever/enhancement-shaman-melee-dps-pve-spec-builds-talents"},
        ["Restoration"]={role="healer",levelingURL="https://www.icy-veins.com/wow-forever/restoration-shaman-leveling",pveURL="https://www.icy-veins.com/wow-forever/restoration-shaman-healer-pve-spec-builds-talents"},
    },
    WARLOCK = {
        ["Affliction"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/affliction-warlock-leveling",pveURL="https://www.icy-veins.com/wow-forever/affliction-warlock-ranged-dps-pve-spec-builds-talents"},
        ["Demonology"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/demonology-warlock-leveling",pveURL="https://www.icy-veins.com/wow-forever/demonology-warlock-ranged-dps-pve-spec-builds-talents"},
        ["Destruction"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/destruction-warlock-leveling",pveURL="https://www.icy-veins.com/wow-forever/destruction-warlock-ranged-dps-pve-spec-builds-talents"},
    },
    WARRIOR = {
        ["Arms"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/arms-warrior-leveling",pveURL="https://www.icy-veins.com/wow-forever/arms-warrior-melee-dps-pve-spec-builds-talents"},
        ["Fury"]={role="dps",levelingURL="https://www.icy-veins.com/wow-forever/fury-warrior-leveling",pveURL="https://www.icy-veins.com/wow-forever/fury-warrior-melee-dps-pve-spec-builds-talents"},
        ["Protection"]={role="tank",levelingURL="https://www.icy-veins.com/wow-forever/protection-warrior-leveling",pveURL="https://www.icy-veins.com/wow-forever/protection-warrior-tank-pve-spec-builds-talents"},
    },
}
local roleLabel = {
    dps={"Endgame - Mana/Sustain", "Endgame - Maximum DPS"},
    healer={"Endgame - Mana Efficiency", "Endgame - Healing Throughput"},
    tank={"Endgame - Survivability", "Endgame - Threat/Damage"},
    hybrid={"Endgame - Bear Tank", "Endgame - Cat DPS"},
}
for class, specs in pairs(FCM.talentReferenceIndex) do
    FCM.talentGuides[class] = FCM.talentGuides[class] or {}
    for spec, reference in pairs(specs) do
        local guide = FCM.talentGuides[class][spec]
        if not guide then
            guide={name=spec .. " " .. string.sub(class,1,1) .. string.lower(string.sub(class,2)),
                sequence={},goals={},pveGoals={}}
            FCM.talentGuides[class][spec]=guide
        end
        guide.levelingURL=reference.levelingURL
        guide.pveURL=reference.pveURL
        guide.role=reference.role
        local variants=roleLabel[reference.role] or roleLabel.dps
        local levelSummary=guide.levelingSummary or
            "Icy Veins leveling reference linked. Its complete level-by-level point order has not been transcribed or verified in FCM."
        local endSummary=guide.pveSummary or
            "Icy Veins PvE reference linked. Do not assume both proposed endgame profiles have independently verified allocations."
        guide.profiles={
            leveling={id="leveling",title="Leveling - Efficient Route", sourceURL=guide.levelingURL,
                summary=levelSummary, sequence=guide.sequence or {}, goals=guide.goals or {},
                evidence=(next(guide.sequence or {}) and "partial" or "reference"), source="Icy Veins",verifiedDate="2026-11-10",
                notes="No automatic respec. Use only verified steps; missing levels are deliberately left blank."},
            sustain={id="sustain",title=variants[1], sourceURL=guide.pveURL,
                summary=endSummary, goals=guide.pveGoals or {}, evidence="reference",
                source="Icy Veins",verifiedDate="2026-11-10",
                notes="Profile slot prepared. A specific alternate talent allocation must be verified before exact rank advice can be given."},
            output={id="output",title=variants[2], sourceURL=guide.pveURL,
                summary=endSummary, goals=guide.pveGoals or {}, evidence="reference",
                source="Icy Veins",verifiedDate="2026-11-10",
                notes="Profile slot prepared. A specific alternate talent allocation must be verified before exact rank advice can be given."},
        }
        -- The generic existing PvE target is retained in the guide but not
        -- silently attributed to one of the new variants.
    end
end

-- Concrete Icy Veins builds from the Frost Mage guide, checked 2026-11-10.
-- Allocation triple is Arcane / Fire / Frost, NOT a complete list of talent ranks.
do
    local frost=FCM.talentGuides.MAGE.Frost
    frost.profiles.leveling.title="Leveling - Efficient Frost"
    frost.profiles.leveling.evidence="partial"
    frost.profiles.leveling.sequence={
        [10]={name="Precision",rank=1,reason="Reduce early spell misses; a resisted spell wastes time and Mana."},
        [11]={name="Precision",rank=2,reason="Complete the guide's early at-level hit priority."},
    }
    frost.profiles.leveling.summary="Start with two Precision points; then develop Wand Specialization and Missile Barrage for Mana efficiency before Frostbite, Ice Shards, Shatter and Fingers of Frost. The interactive calculator's full point order is not yet verified in FCM."
    frost.profiles.leveling.notes="Leveling and dungeons; no routine respec. The guide discusses an optional Arcane-to-Frost respec around level 30, but it is not the default."
    frost.profiles.sustain.title="Endgame - Mana Efficiency (Arcane Meditation)"
    frost.profiles.sustain.allocation={18,0,33}
    frost.profiles.sustain.evidence="variant"
    frost.profiles.sustain.summary="IV Cone of Cold raiding variant 18/0/33. Favors Arcane Meditation for passive regeneration during longer progression encounters; exact individual ranks are not bundled."
    frost.profiles.sustain.notes="Use for progression or when running out of Mana. IV notes this build lacks Frost Channeling."
    frost.profiles.output.title="Endgame - Maximum DPS (Incineration)"
    frost.profiles.output.allocation={10,5,36}
    frost.profiles.output.evidence="variant"
    frost.profiles.output.summary="IV Cone of Cold raid variant 10/5/36. Trades Arcane mana talents for Incineration and Frost Channeling to improve damage and reduce threat; exact individual ranks are not bundled."
    frost.profiles.output.notes="Use when Mana is already comfortable; does not guarantee highest DPS for every gear/fight combination."
    frost.alternativeBuilds={"Deep Frost 9/0/42 - useful in overworld and dungeons; not one of the chosen three primary profiles."}
end

-- IV explicitly describes hybrid Bear/Cat, Bear Tank Only, and Cat DPS.
-- The user's three chosen primary profiles use leveling, Bear Tank, and Cat DPS.
do
    local feral=FCM.talentGuides.DRUID.Feral
    feral.profiles.sustain.title="Endgame - Bear Tank"
    feral.profiles.sustain.evidence="variant"
    feral.profiles.sustain.summary="IV Bear Tank Only talent build specializes in Bear Form mitigation and tanking, sacrificing Cat Form DPS. Individual final ranks remain unverified."
    feral.profiles.output.title="Endgame - Cat DPS"
    feral.profiles.output.evidence="variant"
    feral.profiles.output.summary="IV Cat DPS talent build specializes in Cat Form damage instead of Bear utility. Individual final ranks remain unverified."
    feral.alternativeBuilds={"Hybrid Bear and Cat: combines tank and damage tools for flexibility; not one of the three selected profiles."}
end

-- v0.7.2: Explicit extra Icy Veins variants for specializations with
-- additional, substantively distinct documented builds. They do not get
-- fabricated rank-by-rank allocations or a false 'complete' status.
-- Stable IDs also keep per-character manual overrides independent.
do
    local frost=FCM.talentGuides.MAGE.Frost
    frost.profiles.deepfrost={
        id="deepfrost",title="Endgame - Deep Frost (General PvE)",shortTitle="Deep Frost",
        sourceURL=frost.pveURL,source="Icy Veins",verifiedDate="2026-11-10",evidence="variant",
        allocation={9,0,42},
        summary="IV's Deep Frost 9/0/42 build for overworld play, dungeon utility and general PvE. Trades some maximum raid damage and Mana efficiency for flexibility.",
        notes="A complete tree point allocation is documented, but exact individual talent ranks have not yet been verified in FCM."}
    frost.profileOrder={"leveling","sustain","output","deepfrost"}
    frost.alternativeBuilds=nil -- now selectable, not a dead reference

    local feral=FCM.talentGuides.DRUID.Feral
    feral.profiles.hybrid={
        id="hybrid",title="Endgame - Hybrid Bear / Cat",shortTitle="Hybrid Bear/Cat",
        sourceURL=feral.pveURL,source="Icy Veins",verifiedDate="2026-11-10",evidence="variant",
        summary="IV's hybrid Feral build mixes Bear mitigation and Cat damage so one talent allocation can tank and contribute DPS. It sacrifices some specialized output in each role.",
        notes="Select this for flexible Bear/Cat play without an additional respec. Exact individual ranks are not yet verified in FCM."}
    feral.profileOrder={"leveling","sustain","output","hybrid"}
    feral.alternativeBuilds=nil

    local survival=FCM.talentGuides.HUNTER.Survival
    survival.profiles.sustain.title="Endgame - Dedicated Melee"
    survival.profiles.sustain.shortTitle="Melee"
    survival.profiles.sustain.evidence="variant"
    survival.profiles.sustain.summary="IV dedicated melee Hunter variant, focusing most combat in melee range with occasional ranged abilities. Exact ranks are not yet verified in FCM."
    survival.profiles.output.title="Endgame - Ranged Only"
    survival.profiles.output.shortTitle="Ranged"
    survival.profiles.output.evidence="variant"
    survival.profiles.output.summary="IV classic ranged-only Survival playstyle. Simpler to execute than melee weaving, though IV expects lower throughput. Exact ranks are unverified."
    survival.profiles.meleeweave={
        id="meleeweave",title="Endgame - Ranged / Melee Weaving",shortTitle="Melee Weave",
        sourceURL=survival.pveURL,source="Icy Veins",verifiedDate="2026-11-10",evidence="variant",
        summary="IV's ranged-focused rotation that deliberately enters melee to use Raptor Strike and Strider Kick for additional damage.",
        notes="This is a separate IV talent build, not simply a change to the Ranged Only profile. Individual talent ranks are not yet bundled."}
    survival.profileOrder={"leveling","sustain","meleeweave","output"}

    local marks=FCM.talentGuides.HUNTER.Marksmanship
    marks.profiles.sustain.title="Endgame - Pet PvE"
    marks.profiles.sustain.shortTitle="Pet PvE"
    marks.profiles.sustain.evidence="variant"
    marks.profiles.sustain.summary="IV pet-focused PvE build, foregoing Lone Wolf to improve pet damage and take Beast Mastery talents. Exact ranks are not yet verified in FCM."
    marks.profiles.output.title="Endgame - Lone Wolf PvE"
    marks.profiles.output.shortTitle="Lone Wolf"
    marks.profiles.output.evidence="variant"
    marks.profiles.output.summary="IV's recommended dungeon/raid damage build without a pet using Lone Wolf. Exact ranks are unverified in FCM."
    marks.profiles.world={
        id="world",title="World / PvP / Leveling (Alternate)",shortTitle="World / PvP",
        sourceURL=marks.pveURL,source="Icy Veins",verifiedDate="2026-11-10",evidence="variant",purpose="world",
        summary="IV documents a separate world, PvP and leveling-oriented Marksmanship talent build. This is not the default point-by-point leveling guide.",
        notes="The source contains a separate calculator; complete rank allocations are not yet verified in FCM."}
    marks.profileOrder={"leveling","sustain","output","world"}

    local elemental=FCM.talentGuides.SHAMAN.Elemental
    elemental.profiles.sustain.title="Endgame - Raid Support (Mana Tide)"
    elemental.profiles.sustain.shortTitle="Raid Support"
    elemental.profiles.sustain.evidence="variant"
    elemental.profiles.sustain.summary="IV's raid support alternative takes Mana Tide Totem while retaining the essential Elemental DPS talents. Exact ranks not yet verified."
    elemental.profiles.output.title="Endgame - Maximum Throughput"
    elemental.profiles.output.shortTitle="Max Output"
    elemental.profiles.output.evidence="variant"
    elemental.profiles.output.summary="IV's pure throughput setup skips Mana Tide Totem and emphasizes personal DPS and Mana-related talents. Exact ranks not yet verified."
    elemental.profiles.world={
        id="world",title="World / PvP / Leveling (Alternate)",shortTitle="World / PvP",
        sourceURL=elemental.pveURL,source="Icy Veins",verifiedDate="2026-11-10",evidence="variant",purpose="world",
        summary="IV's distinct outdoor, leveling and PvP-oriented Elemental build, with utility choices such as Earthbound and Elemental Warding.",
        notes="Different from a raid build. Exact ranks in the interactive calculator remain unverified in FCM."}
    elemental.profileOrder={"leveling","sustain","output","world"}
end

-- One independently documented role-specific pair: Balance Druid may trade
-- Genesis damage points for Reflection (Mana) or Subtlety (threat) as needed.
do
    local balance=FCM.talentGuides.DRUID.Balance
    balance.profiles.sustain.title="Endgame - Mana Flex (Reflection)"
    balance.profiles.sustain.evidence="variant"
    balance.profiles.sustain.summary="IV describes substituting optional Genesis points with Reflection when Mana is limiting. Exact final ranks are not provided in FCM."
    balance.profiles.output.title="Endgame - Damage Flex (Genesis)"
    balance.profiles.output.evidence="variant"
    balance.profiles.output.summary="IV's default Balance build favors optional Genesis points for a small DPS increase. No exact point-by-point ranks are bundled."
end
