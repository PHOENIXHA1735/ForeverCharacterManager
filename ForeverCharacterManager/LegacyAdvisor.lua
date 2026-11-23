local _, FCM = ...

-- Read-only planning advice for the three observed in-game Legacy trees.
-- Values are relative *priority-fit ranks*, not performance simulations.
-- Unlock requirements/node IDs have not been verified in the live API.
FCM.legacyTreeOrder={"all","Adventure","Professions","Resourcefulness"}
FCM.legacyTreeLabels={all="All Trees",Adventure="Adventure",
    Professions="Professions",Resourcefulness="Resourcefulness"}
FCM.legacyPriorityOrder={"leveling","travel","survival","skills","gathering",
    "crafting","gold","pve","pvp","reputation","balanced"}
FCM.legacyPriorityLabels={
    leveling="Leveling",travel="Exploration & Travel",survival="Survivability",
    skills="Skill-Ups",gathering="Gathering & Fishing",crafting="Crafting",
    gold="Gold / Savings",pve="Endgame PvE",pvp="PvP & Honor",
    reputation="Reputation",balanced="Balanced",
}
FCM.legacyPriorityShortLabels={
    travel="Travel",survival="Survival",gathering="Gathering",gold="Gold",
    pvp="PvP",reputation="Reputation",
}
-- Only goals with meaningful perks in the chosen Legacy tree are presented.
-- All Trees is the comprehensive planning view; every tree also has Balanced.
FCM.legacyPriorityByTree={
    all={"leveling","travel","survival","skills","gathering","crafting",
        "gold","pve","pvp","reputation","balanced"},
    Adventure={"leveling","travel","survival","balanced"},
    Professions={"skills","gathering","crafting","gold","balanced"},
    Resourcefulness={"pve","pvp","reputation","gold","balanced"},
}
FCM.legacyDefaultPriority={all="leveling",Adventure="leveling",
    Professions="skills",Resourcefulness="pve"}

-- Only perks with a reviewed connection to a selected goal are suggested.
-- A tree with no goal-specific perk displays an honest no-match message.
-- These are relative planning priorities, not simulated combat gains.
local priorityLists={
    leveling={"thrill-of-adventure","frequent-flier","talented","well-rested",
        "reagent-economy","bartering","field-guide","working-overtime",
        "luremaster","gourmand","permanence","dedicated-study","diplomat",
        "field-medicine","bountiful-harvest"},
    travel={"frequent-flier","field-guide","well-rested","high-alert",
        "field-medicine","thrill-of-adventure"},
    survival={"thrill-of-adventure","field-medicine","high-alert",
        "well-rested","the-quick-and-the-dead","reinforce","gourmand"},
    skills={"working-overtime","dedicated-study","bountiful-harvest",
        "luremaster","bartering"},
    gathering={"bountiful-harvest","luremaster","working-overtime",
        "frequent-flier"},
    crafting={"master-chef","working-overtime","performance-bonus",
        "dedicated-study","bartering","bountiful-harvest","luremaster"},
    gold={"bartering","bountiful-harvest","luremaster","master-chef",
        "performance-bonus","working-overtime","reagent-economy",
        "frequent-flier","dedicated-study","reinforce"},
    pve={"reagent-economy","permanence","gourmand","reinforce",
        "talented","diplomat","working-overtime","bartering",
        "the-quick-and-the-dead","dedicated-study"},
    pvp={"for-great-honor","diplomat","the-quick-and-the-dead",
        "reagent-economy","gourmand","reinforce","permanence"},
    reputation={"diplomat","frequent-flier","field-guide","bartering"},
    balanced={"thrill-of-adventure","working-overtime","bartering",
        "frequent-flier","reagent-economy","diplomat","bountiful-harvest",
        "talented","gourmand","luremaster","permanence","reinforce"},
}
local priorityPurpose={
    leveling="reduce downtime and speed up character progression",
    travel="reduce travel friction and support exploration",
    survival="reduce recovery downtime in the open world",
    skills="advance profession skills more efficiently",
    gathering="increase gathering yield and efficiency",
    crafting="support crafting output and material efficiency",
    gold="reduce spending and increase useful returns",
    pve="support dungeon and raid preparation and convenience",
    pvp="improve honor and PvP-related progression",
    reputation="reach faction reputation milestones sooner",
    balanced="provide useful benefits across several activities",
}
local perkReasons={
    ["high-alert"]="Improves stealth detection outside battlegrounds.",
    ["thrill-of-adventure"]="Restores health and mana after qualifying kills, reducing solo downtime.",
    ["talented"]="May improve talent-point progression; confirm how a purchase affects your present level.",
    ["frequent-flier"]="Reduces flight costs and travel time.",
    ["well-rested"]="Extends the rested-experience advantage when leveling between sessions.",
    ["field-medicine"]="Helps with bandage recovery between non-instance encounters.",
    ["field-guide"]="Shortens waits when adding features to camps.",
    ["reagent-economy"]="Saves class and camp reagents, which can be useful on a Mage.",
    ["gourmand"]="Extends food buffs and reduces time spent rebuffing.",
    ["diplomat"]="Accelerates reputation milestones and their unlocks.",
    ["the-quick-and-the-dead"]="Improves recovery after deaths and resurrections.",
    ["permanence"]="Extends group buffs and camp benefits.",
    ["reinforce"]="Reduces equipment repair costs after deaths.",
    ["for-great-honor"]="Adds honor gains for PvP progression.",
    ["dedicated-study"]="Adds a tradeskill point to your lowest eligible skill.",
    ["bartering"]="Reduces gold paid to vendors.",
    ["master-chef"]="Adds extra food output to some cooking crafts.",
    ["working-overtime"]="Increases the chance to gain tradeskill points.",
    ["bountiful-harvest"]="Improves the supply of Scarce mining, herbalism and skinning materials.",
    ["performance-bonus"]="Can improve Merchant's Favor rewards for crate turn-ins.",
    ["luremaster"]="Can give extra fish while a lure is active.",
}
local listWeights={}
for key,list in pairs(priorityLists) do
    local weights={}
    for index,id in ipairs(list) do weights[id]=130-index*6 end
    listWeights[key]=weights
end
local function containsProfession(ch,needle)
    if type(ch)~="table" or type(ch.professions)~="table" then return false end
    for key,record in pairs(ch.professions) do
        local name=type(record)=="table" and record.name or key
        if type(name)=="string" and name:lower():find(needle,1,true) and
            (type(record)~="table" or (tonumber(record.skill) or 0)>0) then
            return true
        end
    end
    return false
end
local function contextScore(ch,perk,priority)
    local id=perk.id
    if id=="bountiful-harvest" and
       (containsProfession(ch,"mining") or containsProfession(ch,"herbalism") or
        containsProfession(ch,"skinning")) then
        return 13,"Your saved gathering profession can benefit."
    elseif id=="luremaster" and containsProfession(ch,"fishing") then
        return 8,"Fishing is recorded on this character."
    elseif id=="master-chef" and containsProfession(ch,"cooking") then
        return 10,"Cooking is recorded on this character."
    elseif id=="reagent-economy" and type(ch)=="table" and ch.class=="MAGE" then
        return 10,"Mage class abilities can use vendor reagents."
    elseif id=="talented" and type(ch)=="table" and
        (tonumber(ch.level) or 60)<60 and priority=="leveling" then
        return 8,"You have more leveling ahead; confirm retroactive point behavior."
    end
    return 0,nil
end
function FCM:LegacyTree(ch)
    local tree=type(ch)=="table" and ch.legacyTree or nil
    return self.legacyTreeLabels[tree] and tree or "all"
end
function FCM:LegacyPriorityChoices(tree)
    return self.legacyPriorityByTree[tree] or self.legacyPriorityByTree.all
end
function FCM:LegacyPriorityAllowed(tree,priority)
    for _,id in ipairs(self:LegacyPriorityChoices(tree)) do
        if priority==id then return true end
    end
    return false
end
function FCM:LegacyPriorityLabel(tree,priority,shortLabel)
    if tree=="Resourcefulness" and priority=="gold" then return "Cost Savings" end
    if tree=="Professions" and priority=="gold" then return "Gold" end
    if shortLabel then return self.legacyPriorityShortLabels[priority] or
        self.legacyPriorityLabels[priority] or "Unknown" end
    return self.legacyPriorityLabels[priority] or "Unknown"
end
function FCM:LegacyPriority(ch)
    local tree=self:LegacyTree(ch)
    local saved=type(ch)=="table" and ch.legacyPriorities or nil
    if type(saved)=="table" and self:LegacyPriorityAllowed(tree,saved[tree]) then
        return saved[tree]
    end
    -- QA6/QA6b stored a single goal. Honor it on the original tree until
    -- the player makes a QA6c per-tree selection; do not overwrite it.
    if type(saved)~="table" and type(ch)=="table" and
        self:LegacyPriorityAllowed(tree,ch.legacyPriority) then
        return ch.legacyPriority
    end
    return self.legacyDefaultPriority[tree] or "leveling"
end
function FCM:SetLegacyTree(ch,tree)
    if type(ch)~="table" or not self.legacyTreeLabels[tree] then return false end
    local previousTree=self:LegacyTree(ch)
    if type(ch.legacyPriorities)~="table" and
        self:LegacyPriorityAllowed(previousTree,ch.legacyPriority) then
        ch.legacyPriorities={[previousTree]=ch.legacyPriority}
    end
    ch.legacyTree=tree
    return true
end
function FCM:SetLegacyPriority(ch,priority)
    if type(ch)~="table" or
        not self:LegacyPriorityAllowed(self:LegacyTree(ch),priority) then return false end
    if type(ch.legacyPriorities)~="table" then ch.legacyPriorities={} end
    ch.legacyPriorities[self:LegacyTree(ch)]=priority
    ch.legacyPriority=priority
    return true
end
function FCM:SetLegacyAccess(ch,name,state)
    local perk=self:LegacyPerk(name)
    if type(ch)~="table" or not perk or
        (state~="available" and state~="locked" and state~="unknown") then
        return false,"Use a known perk and available|locked|unknown."
    end
    ch.legacyAccess=ch.legacyAccess or {}
    if state=="unknown" then ch.legacyAccess[perk.id]=nil
    else ch.legacyAccess[perk.id]=state end
    return true,perk.name.." is marked "..state.." for this character."
end
function FCM:LegacyMatchingTrees(priority)
    priority=self.legacyPriorityLabels[priority] and priority or "leveling"
    local fit=listWeights[priority] or {}
    local result={}
    for _,tree in ipairs({"Adventure","Professions","Resourcefulness"}) do
        for _,perk in ipairs(self.legacyPerks or {}) do
            if perk.tree==tree and fit[perk.id] then
                result[#result+1]=tree
                break
            end
        end
    end
    return result
end
function FCM:LegacyRecommendations(ch,tree,priority,limit)
    if type(ch)~="table" then return {} end
    tree=self.legacyTreeLabels[tree] and tree or self:LegacyTree(ch)
    priority=self.legacyPriorityLabels[priority] and priority or self:LegacyPriority(ch)
    local spent=self:LegacySpent(ch)
    if spent>=16 then return {} end
    local rankWeights=listWeights[priority] or listWeights.leveling
    local recommendations={}
    for _,perk in ipairs(self.legacyPerks or {}) do
        if (tree=="all" or perk.tree==tree) and rankWeights[perk.id] then
            local recorded=ch.legacyRanks and ch.legacyRanks[perk.id]
            local rank=(type(recorded)=="number" and recorded>=0 and recorded<=perk.max)
                and recorded or 0
            local access=ch.legacyAccess and ch.legacyAccess[perk.id] or "unknown"
            if rank<perk.max and access~="locked" then
                local bonus,bonusWhy=contextScore(ch,perk,priority)
                local score=rankWeights[perk.id]+bonus-(rank*8)
                -- A player-confirmed available node should outrank unknown
                -- unlocks; neither score nor rank claims live API certainty.
                if access=="available" then score=score+140 end
                local reason=perkReasons[perk.id] or perk.effect
                recommendations[#recommendations+1]={
                    perk=perk,score=score,priority=priority,tree=perk.tree,
                    recordedRank=type(recorded)=="number",rank=rank,
                    nextRank=rank+1,access=access,
                    reason=reason,context=bonusWhy,
                    purpose=priorityPurpose[priority],
                }
            end
        end
    end
    table.sort(recommendations,function(a,b)
        if a.score~=b.score then return a.score>b.score end
        return a.perk.name<b.perk.name
    end)
    if type(limit)=="number" and limit>=0 then
        while #recommendations>math.floor(limit) do
            table.remove(recommendations)
        end
    end
    return recommendations
end
