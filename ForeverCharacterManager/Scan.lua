local _, FCM = ...
local function safe(func, ...) return FCM:Try(func, ...) end

function FCM:ScanBasic()
    local ch = self:Current()
    if not ch then return end
    local first, surname = safe(UnitFullName, "player")
    ch.name = first or (UnitName and UnitName("player")) or ch.name or "Unknown"
    if type(surname)=="string" and surname~="" then ch.surname=surname end
    -- Never store the surname in realm or use a backend server identifier
    -- to decide whether two Forever characters can exchange gear.
    local detectedRule=self:CurrentRuleset()
    if detectedRule then ch.ruleset=detectedRule end
    local detectedRegion=self:CurrentRegion()
    if detectedRegion then ch.region=detectedRegion end
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

-- Read soulbound state only from a valid item *instance*.  ItemLocation's
-- constructor is a colon method: omitting its implicit self parameter can
-- construct an invalid location and flood the API error log at every scan.
local function itemBoundAt(bag, slot, onError)
    if not (ItemLocation and type(ItemLocation.CreateFromBagAndSlot)=="function" and
            C_Item and type(C_Item.IsBound)=="function") then return nil end
    local ok,location=pcall(ItemLocation.CreateFromBagAndSlot,ItemLocation,bag,slot)
    if not ok or not location then
        if not ok then onError("ItemLocation creation failed",location) end
        return nil
    end
    -- Clients differ in the guards exposed on ItemLocation.  If present,
    -- validate before invoking the strict C_Item.IsBound(itemLocation) API.
    for _,method in ipairs({"HasAnyLocation","IsValid"}) do
        if type(location[method])=="function" then
            local validOK,valid=pcall(location[method],location)
            if not validOK or not valid then return nil end
        end
    end
    if type(C_Item.DoesItemExist)=="function" then
        local existsOK,exists=pcall(C_Item.DoesItemExist,location)
        if not existsOK or not exists then return nil end
    end
    local boundOK,bound=pcall(C_Item.IsBound,location)
    if not boundOK then
        onError("C_Item.IsBound failed",bound)
        return nil
    end
    if type(bound)=="boolean" then return bound end
    return nil
end

local function containerSnapshot(bagIndices)
    local result, available = {},false
    local bindingErrorRecorded=false
    local function bindingError(problem,detail)
        -- Report the first binding error from each bag/bank pass, instead of
        -- allowing a bad client API response to bury other diagnostics.
        if bindingErrorRecorded then return end
        bindingErrorRecorded=true
        if FCM.RecordError then
            FCM:RecordError("Binding",tostring(problem)..": "..tostring(detail))
        end
    end
    if not C_Container or not C_Container.GetContainerNumSlots then return result,available end
    for _, bag in ipairs(bagIndices) do
        local exposed = safe(C_Container.GetContainerNumSlots, bag)
        local slots = tonumber(exposed) or 0
        if type(exposed)=="number" and (bag==0 or slots>0) then available=true end
        for slot = 1, math.min(slots, 120) do
            local info = safe(C_Container.GetContainerItemInfo, bag, slot)
            if info and info.itemID then
                local id = tonumber(info.itemID)
                local quantity = tonumber(info.stackCount) or 1
                local key = tostring(bag) .. ":" .. tostring(slot)
                -- A Lua `a and false or nil` expression discards the valid
                -- false value.  Retain it: false means this copy is unbound.
                local bound=nil
                if type(info.isBound)=="boolean" then bound=info.isBound end
                -- Some Forever clients omit isBound on container snapshots.
                -- Never convert a failed location lookup into an unbound claim.
                if bound==nil then
                    local detected=itemBoundAt(bag,slot,function(problem,detail)
                        bindingError("Bag "..tostring(bag).." slot "..tostring(slot).." "..problem,detail)
                    end)
                    if type(detected)=="boolean" then bound=detected end
                end
                result[key] = { itemID = id, count = quantity, name = info.itemName,
                    link = info.hyperlink, bound = bound,
                    bag = bag, slot = slot }
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
    local previous=ch.bags
    local snapshot,accessible=containerSnapshot(bags)
    if not accessible then
        if self.RecordError then self:RecordError("Bags", "Bag slots unavailable; preserving previous scan.") end
        return
    end
    ch.bags = snapshot
    ch.bagsStamp = self:Now()
    -- No "new item" notifications on login; only compare actual subsequent
    -- bag changes in this session. Notifications never perform item actions.
    if self._boeBagBaselineReady and type(self.AnnounceNewBoE) == "function" then
        self:AnnounceNewBoE(ch,previous,snapshot)
    end
    self._boeBagBaselineReady=true
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
    if not ch or type(GetInventoryItemLink)~="function" then return end
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
    local captured=false
    -- GetProfessionInfo remains available on many mainline client builds.
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local positions = { safe(GetProfessions) }
        for slot = 1, 5 do
            local index = positions[slot]
            if index then
                local name, _, level, maximum, _, _, line = safe(GetProfessionInfo, index)
                if name and level then
                    captured=true
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
                    captured=true
                    ch.professions[info.professionName] = {
                        name = info.professionName, skill = info.skillLevel,
                        maxSkill = info.maxSkillLevel, line = line, scan = self:Now() }
                end
            end
        end
    end
    if captured then ch.professionsStamp=self:Now() end
end

function FCM:ScanReputations()
    if not C_Reputation or not C_Reputation.GetNumFactions then return end
    local ch = self:Current()
    if not ch then return end
    local count = safe(C_Reputation.GetNumFactions) or 0
    if count<=0 then return end -- unsupported/incomplete scan, preserve old stamp
    local captured=false
    local current = ch.reputations or {}
    for i = 1, math.min(count, 500) do
        local f = safe(C_Reputation.GetFactionDataByIndex, i)
        if f and f.factionID and f.name and (not f.isHeader or f.isHeaderWithRep) then
            captured=true
            current[f.factionID] = { id = f.factionID, name = f.name, reaction = f.reaction,
                value = f.currentStanding, low = f.currentReactionThreshold,
                high = f.nextReactionThreshold, accountWide = f.isAccountWide,
                updated = self:Now() }
        end
    end
    if captured then
        ch.reputations = current
        ch.reputationStamp = self:Now()
    end
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
    local treeDataAvailable=false
    for _, tree in ipairs(configInfo.treeIDs) do
        local nodes = safe(C_Traits.GetTreeNodes, tree)
        if type(nodes) == "table" then
            treeDataAvailable=true
            for _, nodeID in ipairs(nodes) do
                local node = safe(C_Traits.GetNodeInfo, config, nodeID)
                if node then
                    local rank = tonumber(node.activeRank or node.ranksPurchased or 0) or 0
                    local entry = node.activeEntry
                    if rank > 0 and entry then
                        local entryID = type(entry) == "table" and entry.entryID or entry
                        local definitionID = type(entry)=="table" and entry.definitionID or nil
                        if not definitionID and entryID then
                            local entryInfo = safe(C_Traits.GetEntryInfo, config, entryID)
                            definitionID = entryInfo and entryInfo.definitionID
                        end
                        local definition = definitionID and safe(C_Traits.GetDefinitionInfo, definitionID)
                        local spellID = definition and definition.spellID
                        local spellInfo = spellID and C_Spell and safe(C_Spell.GetSpellInfo, spellID)
                        local spellName=type(spellInfo)=="table" and spellInfo.name or nil
                        if not spellName and spellID and type(GetSpellInfo)=="function" then
                            spellName=safe(GetSpellInfo,spellID)
                        end
                        selected[nodeID] = { name = spellName or ("Talent node " .. nodeID),
                            rank = rank, spellID = spellID, nodeID = nodeID }
                        nodeCount = nodeCount + 1
                    end
                end
            end
        end
    end
    -- A missing/unsupported tree response is NOT a successful empty scan.
    -- Preserve the previous talent snapshot until a client exposes the tree.
    if not treeDataAvailable then return end
    ch.talents = selected
    ch.talentConfigID = config
    ch.talentCount = nodeCount
    ch.talentStamp = self:Now()
end
