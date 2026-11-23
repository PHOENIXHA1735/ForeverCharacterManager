local _, FCM = ...

-- Only confirmed talent point order is used for next-point prompts. Milestones
-- remain qualitative hints, never fabricated exact instructions.
function FCM:TalentReminder(ch)
    if not ch or not ch.level or not self.TalentReport then return nil end
    local r = self:TalentReport(ch)
    if r and #r.gaps>0 then
        return "Your allocated talents differ from reviewed guide steps; check the Talent Advisor before spending gold"
    end
    if r and r.nextStep and r.nextStep.name and r.nextStep.level <= (ch.level or 0) then
        return "Reviewed talent step: " .. r.nextStep.name .. (r.nextStep.rank and (" rank " .. r.nextStep.rank) or "") ..
            " (guide step at level " .. tostring(r.nextStep.level) .. ")"
    end
    return nil
end

function FCM:TrackSession()
    local ch=self:Current()
    if not ch then return end
    local now=self:Now()
    if not ch.sessionAnchor then
        ch.sessionAnchor=now; ch.sessionXP=ch.xp or 0; ch.sessionLevel=ch.level or 1
        ch.sessionXPMax=ch.xpMax or 0
    end
    -- Track XP gained only where change is computable; no assumptions about prior level caps.
    if (ch.level or 0)==(ch.sessionLevel or 0) then
        ch.sessionGain=math.max(0,(ch.xp or 0)-(ch.sessionXP or 0))
    else
        ch.sessionGain=math.max(0,(ch.sessionXPMax or 0)-(ch.sessionXP or 0))+(ch.xp or 0)
        ch.sessionLevel=ch.level
        ch.sessionXP=0
        ch.sessionXPMax=ch.xpMax
    end
end

function FCM:LevelingSummary(ch)
    if not ch then return "No character selected." end
    local parts={"Character: "..self:DisplayCharacter(ch), "Level: "..tostring(ch.level or "?"),
        "XP: "..((tonumber(ch.xpMax) or 0)>0 and
            (tostring(ch.xp or 0).." / "..tostring(ch.xpMax)) or "Not yet scanned"),
        "Rested XP: "..tostring(ch.restedXP or "Not recorded")}
    if ch.sessionAnchor and ch.sessionGain then
        local hours=math.max(1/60,(self:Now()-ch.sessionAnchor)/3600)
        local rate=math.floor(ch.sessionGain/hours)
        parts[#parts+1]="Session XP recorded: "..ch.sessionGain
        parts[#parts+1]="Approx. XP / hour: "..rate
        if rate>0 and (ch.xpMax or 0)>(ch.xp or 0) then
            parts[#parts+1]="Approx. time to next level: "..string.format("%.1f",(ch.xpMax-ch.xp)/rate).." hours"
        end
    else parts[#parts+1]="XP/session tracking begins on your next login." end
    parts[#parts+1]="Offline estimates use the last recorded snapshot."
    return table.concat(parts,"\n")
end

-- Reference catalog cross-checked against the user's first-point Legacy tree
-- video and the Mobalytics WoW Forever guide (updated November 12, 2026).
-- This is informational. The live Legacy client API and node IDs have NOT been
-- verified; do not fake in-game purchases, rank reads, or account balances.
FCM.legacyGuideUrl="https://mobalytics.gg/wow-forever/guides/legacy-system-guide"
FCM.legacyPerks={
    {tree="Adventure",id="high-alert",name="High Alert",max=2,
        effect="Improves detection of nearby stealthed targets as though your level were higher; not effective in battlegrounds.",bonus="+1 stealth-detection level per rank"},
    {tree="Adventure",id="thrill-of-adventure",name="Thrill of Adventure",max=5,
        effect="After a killing blow on a meaningful enemy, regain health and mana over 10 seconds; not active in dungeons, raids or battlegrounds.",bonus="1/2/3/4/5% maximum Health and Mana"},
    {tree="Adventure",id="talented",name="Talented",max=1,
        effect="Start gaining talent points at level 9 instead of 10; the total is still capped at 51.",bonus="One earlier talent point"},
    {tree="Adventure",id="frequent-flier",name="Frequent Flier",max=1,
        effect="Flight paths cost less and flight-path mounts travel faster.",bonus="50% lower fare; 20% faster"},
    {tree="Adventure",id="well-rested",name="Well Rested",max=5,
        effect="Rested experience accumulates faster and has a higher cap.",bonus="+4/8/12/16/20% accumulation and cap"},
    {tree="Adventure",id="field-medicine",name="Field Medicine",max=2,
        effect="Shortens the Recently Bandaged restriction; not active in dungeons, raids or battlegrounds.",bonus="-5/-10 seconds"},
    {tree="Adventure",id="field-guide",name="Field Guide",max=3,
        effect="Shortens the cooldown for adding camp features.",bonus="-8/-17/-25% cooldown"},
    {tree="Resourcefulness",id="reagent-economy",name="Reagent Economy",max=1,
        effect="Removes vendor-purchased reagent costs from class abilities and Tier 1 camp features.",bonus="No qualifying vendor reagent cost"},
    {tree="Resourcefulness",id="gourmand",name="Gourmand",max=3,
        effect="Extends beneficial effects from food.",bonus="+33/67/100% duration"},
    {tree="Resourcefulness",id="diplomat",name="Diplomat",max=5,
        effect="Increases reputation earned.",bonus="+2/4/6/8/10% reputation"},
    {tree="Resourcefulness",id="the-quick-and-the-dead",name="The Quick and the Dead",max=2,
        effect="Run faster while dead; after a resurrection, helpful abilities cost no resources until combat or a short timer expires.",bonus="+5/10% ghost speed; 1/2 min free helpful spells"},
    {tree="Resourcefulness",id="permanence",name="Permanence",max=2,
        effect="Extends long-duration group attribute buffs and camp rest benefits.",bonus="+50/100% duration"},
    {tree="Resourcefulness",id="reinforce",name="Reinforce",max=5,
        effect="Reduces equipment durability lost when you die.",bonus="-8/16/24/32/40% durability loss"},
    {tree="Resourcefulness",id="for-great-honor",name="For Great Honor",max=5,
        effect="Increases honor earned.",bonus="+2/4/6/8/10% honor"},
    {tree="Professions",id="dedicated-study",name="Dedicated Study",max=1,
        effect="Grants skill in your lowest tradeskill, or elemental essence after all eligible tradeskills reach 300.",bonus="+1 lowest skill or 2-4 elemental essence"},
    {tree="Professions",id="bartering",name="Bartering",max=2,
        effect="Lowers vendor purchase prices.",bonus="-5/-10% gold price"},
    {tree="Professions",id="master-chef",name="Master Chef",max=5,
        effect="Cooking can produce an additional item.",bonus="10/20/30/40/50% chance"},
    {tree="Professions",id="working-overtime",name="Working Overtime",max=5,
        effect="Raises skill-up probability for primary, secondary and class tradeskills.",bonus="+4/8/12/16/20% chance"},
    {tree="Professions",id="bountiful-harvest",name="Bountiful Harvest",max=5,
        effect="Find more Scarce gathering materials from Mining, Herbalism and Skinning.",bonus="+20/40/60/80/100%"},
    {tree="Professions",id="performance-bonus",name="Performance Bonus",max=3,
        effect="Chance for an increased Merchant's Favor crate reward.",bonus="5/10/15% chance of 100% bonus"},
    {tree="Professions",id="luremaster",name="Luremaster",max=2,
        effect="Chance to catch an additional fish while using a lure.",bonus="25/50% chance"},
}
local function legacyNameKey(value)
    return type(value)=="string" and value:lower():gsub("[^%w]","") or ""
end
function FCM:LegacyPerk(idOrName)
    local key=legacyNameKey(idOrName)
    for _,perk in ipairs(self.legacyPerks) do
        if key==legacyNameKey(perk.id) or key==legacyNameKey(perk.name) then return perk end
    end
    return nil
end
-- Each class reaching 25, 45 and 60 for the first time is a published
-- milestone. Treat this as scanned evidence, not an observed spendable total:
-- other challenges, account caps and previously completed/deleted toons are
-- outside the available SavedVariables.
function FCM:LegacyClassMilestoneEstimate()
    local highest={}
    for _,ch in ipairs(self:Characters()) do
        local name=type(ch.class)=="string" and ch.class:upper() or nil
        local level=tonumber(ch.level) or 0
        if name and level>(highest[name] or 0) then highest[name]=level end
    end
    local total,details=0,{}
    for class,level in pairs(highest) do
        for _,threshold in ipairs({25,45,60}) do
            if level>=threshold then
                total=total+1
                details[#details+1]=class.." "..threshold
            end
        end
    end
    table.sort(details)
    return total,details
end
function FCM:LegacySpent(ch)
    local spent=0
    for _,perk in ipairs(self.legacyPerks) do
        local rank=ch and ch.legacyRanks and ch.legacyRanks[perk.id]
        if type(rank)=="number" and rank>=0 and rank<=perk.max then spent=spent+rank end
    end
    return spent
end
function FCM:SetLegacyAvailable(ch,available)
    if type(ch)~="table" or type(available)~="number" or available%1~=0 or
        available<0 or available>16 then return false end
    ch.legacyAvailable=available
    ch.legacyAvailableRecorded=self:Now()
    return true
end
function FCM:SetLegacyRank(ch,name,rank)
    local perk=self:LegacyPerk(name)
    if not perk or type(ch)~="table" or type(rank)~="number" or
        rank%1~=0 or rank<0 or rank>perk.max then
        return false,"Unknown perk or rank exceeds the listed maximum."
    end
    local old=ch.legacyRanks and ch.legacyRanks[perk.id] or 0
    if self:LegacySpent(ch)-old+rank>16 then
        return false,"The reference guide lists a 16-point per-character spending limit."
    end
    ch.legacyRanks=ch.legacyRanks or {}
    ch.legacyRanks[perk.id]=rank
    return true,perk.name.." now recorded as rank "..rank.."/"..perk.max.." (manual note)."
end

-- Keep user-set goals without presenting guessed amounts as live points.
function FCM:LegacyGoal(ch)
    return ch and ch.legacyGoal or "No Legacy goal set. Use /fcm legacygoal <goal>."
end
