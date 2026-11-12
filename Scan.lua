local _, FCM = ...
local function safe(func, ...) return FCM:Try(func, ...) end

function FCM:ScanBasic()
    local ch = self:Current()
    if not ch then return end
    local name, realm = safe(UnitFullName, "player")
    ch.name = name or (UnitName and UnitName("player")) or ch.name or "Unknown"
    ch.realm = realm or ch.realm or (GetRealmName and GetRealmName()) or "Unknown"
    local _, class = safe(UnitClass, "player")
    ch.class = class or ch.class
    ch.race = safe(UnitRace, "player") or ch.race
    ch.faction = safe(UnitFactionGroup, "player") or ch.faction
    ch.level = safe(UnitLevel, "player") or ch.level or 1
    ch.gold = safe(GetMoney) or ch.gold or 0
    ch.xp = safe(UnitXP, "player") or ch.xp or 0
    ch.xpMax = safe(UnitXPMax, "player") or ch.xpMax or 0
    ch.restedXP = safe(GetXPExhaustion) or 0
    ch.lastSeen = self:Now()
    if self.TrackSession then self:TrackSession() end
end

local function containerSnapshot(bagIndices)
    local result, available = {},false
    if not C_Container or not C_Container.GetContainerNumSlots then return result,available end
    for _, bag in ipairs(bagIndices) do
        local slots = safe(C_Container.GetContainerNumSlots, bag) or 0
        if slots > 0 then available=true end
        for slot = 1, math.min(slots, 120) do
            local info = safe(C_Container.GetContainerItemInfo, bag, slot)
            if info and info.itemID then
                local id = tonumber(info.itemID)
                local quantity = tonumber(info.stackCount) or 1
                local key = tostring(bag) .. ":" .. tostring(slot)
                result[key] = { itemID = id, count = quantity, name = info.itemName,
                    link = info.hyperlink, bound = info.isBound == true, bag = bag, slot = slot }
            end
        end
    end
    return result,available
end

function FCM:ScanBags()
    local ch = self:Current()
    if not ch then return end
    local bags={0,1,2,3,4}
    if Enum and Enum.BagIndex and type(Enum.BagIndex.ReagentBag)=="number" then
        bags[#bags+1]=Enum.BagIndex.ReagentBag
    end
    ch.bags = containerSnapshot(bags)
    ch.bagsStamp = self:Now()
end

function FCM:ScanBank()
    if not self.bankOpen then return end
    local ch = self:Current()
    if not ch then return end
    -- Try legacy bank indices and the bank indices exported by the modern client.
    local indices, seen={-1,5,6,7,8,9,10,11},{}
    for _,id in ipairs(indices) do seen[id]=true end
    if Enum and Enum.BagIndex then
        for name,id in pairs(Enum.BagIndex) do
            if type(name)=="string" and type(id)=="number" and
                    (string.find(name,"Bank",1,true) or string.find(name,"Reagent",1,true))
                    and not seen[id] then indices[#indices+1]=id;seen[id]=true end
        end
    end
    local snapshot,accessible=containerSnapshot(indices)
    if accessible then
        ch.bank=snapshot;ch.bankStamp=self:Now()
    elseif self.RecordError then
        self:RecordError("Bank", "Bank is open, but its container slots were not exposed. Previous snapshot preserved.")
    end
end

function FCM:ScanGear()
    local ch = self:Current()
    if not ch then return end
    local gear = {}
    for slot = 1, 19 do
        local link = safe(GetInventoryItemLink, "player", slot)
        if link then
            local id = tonumber(link:match("item:(%d+)"))
            gear[slot] = { itemID = id, link = link, slot = slot }
        end
    end
    ch.gear = gear
    ch.gearStamp = self:Now()
end

function FCM:ScanProfessions()
    local ch = self:Current()
    if not ch then return end
    -- GetProfessionInfo remains available on many mainline client builds.
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local positions = { safe(GetProfessions) }
        for slot = 1, 5 do
            local index = positions[slot]
            if index then
                local name, _, level, maximum, _, _, line = safe(GetProfessionInfo, index)
                if name and level then
                    ch.professions[name] = { name = name, skill = level, maxSkill = maximum, line = line, scan = self:Now() }
                end
            end
        end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionSkillLineID and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        for id = 0, 11 do
            local line = safe(C_TradeSkillUI.GetProfessionSkillLineID, id)
            if line then
                local info = safe(C_TradeSkillUI.GetProfessionInfoBySkillLineID, line)
                if info and info.professionName and (info.skillLevel or 0) > 0 then
                    ch.professions[info.professionName] = {
                        name = info.professionName, skill = info.skillLevel,
                        maxSkill = info.maxSkillLevel, line = line, scan = self:Now() }
                end
            end
        end
    end
end

function FCM:ScanReputations()
    if not C_Reputation or not C_Reputation.GetNumFactions then return end
    local ch = self:Current()
    if not ch then return end
    local count = safe(C_Reputation.GetNumFactions) or 0
    local current = ch.reputations or {}
    for i = 1, math.min(count, 500) do
        local f = safe(C_Reputation.GetFactionDataByIndex, i)
        if f and f.factionID and f.name and (not f.isHeader or f.isHeaderWithRep) then
            current[f.factionID] = { id = f.factionID, name = f.name, reaction = f.reaction,
                value = f.currentStanding, low = f.currentReactionThreshold,
                high = f.nextReactionThreshold, accountWide = f.isAccountWide,
                updated = self:Now() }
        end
    end
    ch.reputations = current
    ch.reputationStamp = self:Now()
end

function FCM:ScanTalents()
    if not C_Traits then return end
    local ch = self:Current()
    if not ch then return end
    -- Unspent points may be available even when the talent tree isn't open.
    -- Don't infer points from level: Forever can award additional talent points.
    if type(GetNumUnspentTalentPoints)=="function" then
        local unspent=safe(GetNumUnspentTalentPoints)
        if type(unspent)=="number" then ch.unspentTalentPoints=math.max(0,unspent) end
    end
    local config = C_ClassTalents and safe(C_ClassTalents.GetActiveConfigID)
    if not config and C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup and GetCombatConfigIDForSpecGroup then
        local group=safe(C_SpecializationInfo.GetActiveSpecGroup)
        if group then config=safe(GetCombatConfigIDForSpecGroup,group) end
    end
    if not config then return end
    local configInfo = safe(C_Traits.GetConfigInfo, config)
    if not configInfo or type(configInfo.treeIDs) ~= "table" then return end
    local selected = {}
    local nodeCount = 0
    for _, tree in ipairs(configInfo.treeIDs) do
        local nodes = safe(C_Traits.GetTreeNodes, tree)
        if type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local node = safe(C_Traits.GetNodeInfo, config, nodeID)
                if node then
                    local rank = tonumber(node.activeRank or node.ranksPurchased or 0) or 0
                    local entry = node.activeEntry
                    if rank > 0 and entry then
                        local entryID = type(entry) == "table" and entry.entryID or entry
                        local definitionID = entry.definitionID
                        if not definitionID and entryID then
                            local entryInfo = safe(C_Traits.GetEntryInfo, config, entryID)
                            definitionID = entryInfo and entryInfo.definitionID
                        end
                        local definition = definitionID and safe(C_Traits.GetDefinitionInfo, definitionID)
                        local spellID = definition and definition.spellID
                        local spellInfo = spellID and C_Spell and safe(C_Spell.GetSpellInfo, spellID)
                        selected[nodeID] = { name = (spellInfo and spellInfo.name) or ("Talent node " .. nodeID),
                            rank = rank, spellID = spellID, nodeID = nodeID }
                        nodeCount = nodeCount + 1
                    end
                end
            end
        end
    end
    ch.talents = selected
    ch.talentConfigID = config
    ch.talentCount = nodeCount
    ch.talentStamp = self:Now()
end
