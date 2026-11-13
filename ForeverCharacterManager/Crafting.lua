local _, FCM = ...
local function safe(func, ...) return FCM:Try(func, ...) end
local function itemName(id)
    if id and C_Item and C_Item.GetItemInfo then
        local name = safe(C_Item.GetItemInfo, id)
        if name then return name end
    end
    return "Item #" .. tostring(id or "?")
end
FCM.ItemName = itemName

local function validProfession(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    local lower = string.lower(name)
    if name == "" or lower == "unknown" or lower == "unknown profession" then return nil end
    return name
end

-- Forever's trade skill API can expose recipes from several professions while
-- the open pane still reports one base profession. Attribute each spell to its
-- own skill line instead of applying the pane name to every returned recipe.
-- The companion's recipe reference is a fallback when that API is unavailable.
-- An unverified fallback is never used to rewrite existing saved records.
function FCM:RecipeProfession(recipeID, fallback)
    local id = tonumber(recipeID)
    local trade = C_TradeSkillUI
    if id and trade and type(trade.GetProfessionInfoByRecipeID) == "function" then
        -- Some client builds throw for unavailable recipe IDs; leave the
        -- existing record intact instead of emitting one error per recipe.
        local ok, info = pcall(trade.GetProfessionInfoByRecipeID, id)
        local name = ok and type(info) == "table" and validProfession(info.professionName)
        if name then return name, true end
    end
    local refs = self.externalData and self.externalData.recipes
    local ref = refs and id and (refs[id] or refs[tostring(id)])
    local name = ref and validProfession(ref.profession)
    if name then return name, true end
    return validProfession(fallback) or "Unknown profession", false
end

-- SavedVariables survive upgrades. Heal known bad classifications in place,
-- including offline characters and unlearned recipe discoveries. Never erase
-- recipes or infer a new profession from another open profession window.
function FCM:RepairRecipeProfessions()
    if not self.db then return 0 end
    local corrected = 0
    for _, ch in ipairs(self:Characters()) do
        for _, collection in ipairs({ch.recipes or {}, ch.unlearnedRecipes or {}}) do
            for key, recipe in pairs(collection) do
                if type(recipe) == "table" then
                    local name, verified = self:RecipeProfession(recipe.id or key)
                    if verified and name ~= recipe.profession then
                        recipe.profession = name
                        corrected = corrected + 1
                    end
                end
            end
        end
    end
    if corrected > 0 then self.allRecipesCache = nil end
    return corrected
end

function FCM:ScanRecipes()
    local trade = C_TradeSkillUI
    if not trade or not trade.GetAllRecipeIDs or not trade.GetRecipeInfo then return end
    local ids = safe(trade.GetAllRecipeIDs)
    if type(ids) ~= "table" or #ids == 0 then return end
    local professionInfo = safe(trade.GetBaseProfessionInfo) or {}
    local child = safe(trade.GetChildProfessionInfo) or {}
    local profession = validProfession(professionInfo.professionName) or
        validProfession(child.professionName) or "Unknown profession"
    local skill = child.skillLevel or professionInfo.skillLevel
    local ch = self:Current()
    if not ch then return end
    if profession ~= "Unknown profession" and skill then
        ch.professions[profession] = { name = profession, skill = skill,
            maxSkill = child.maxSkillLevel or professionInfo.maxSkillLevel,
            line = professionInfo.professionID, scan = self:Now() }
        ch.professionsStamp = self:Now()
    end
    local learnedCount = 0
    ch.unlearnedRecipes=ch.unlearnedRecipes or {}
    for _, recipeID in ipairs(ids) do
        local info = safe(trade.GetRecipeInfo, recipeID)
        local recipeProfession = self:RecipeProfession(recipeID, profession)
        if info and info.learned then
            local schematic = safe(trade.GetRecipeSchematic, recipeID, false)
            local output = safe(trade.GetRecipeOutputItemData, recipeID)
            local outputID = (schematic and schematic.outputItemID) or (output and output.itemID)
            local outputLink = output and output.hyperlink
            if not outputLink and trade.GetRecipeItemLink then outputLink = safe(trade.GetRecipeItemLink, recipeID) end
            local r = { id = recipeID, name = info.name or (schematic and schematic.name) or ("Recipe #" .. recipeID),
                profession = recipeProfession, learned = true, outputID = outputID, outputLink = outputLink,
                reagents = {}, quantity = math.max(1, tonumber(schematic and schematic.quantityMin) or 1),
                complex = false, scanned = self:Now(),
                source = safe(trade.GetRecipeSourceText, recipeID),
                difficulty = info.difficulty, requiredSkill = info.requiredSkill }
            if schematic and schematic.reagentSlotSchematics then
                for _, reagentSlot in ipairs(schematic.reagentSlotSchematics) do
                    if reagentSlot.required ~= false and (reagentSlot.quantityRequired or 0) > 0 then
                        local choices = reagentSlot.reagents or {}
                        if #choices ~= 1 or not choices[1].itemID then
                            r.complex = true
                        else
                            r.reagents[#r.reagents + 1] = { itemID = choices[1].itemID,
                                count = reagentSlot.quantityRequired }
                        end
                    end
                end
            else
                r.complex = true
            end
            ch.recipes[recipeID] = r
            ch.unlearnedRecipes[recipeID] = nil
            learnedCount = learnedCount + 1
        elseif info and info.learned == false then
            -- The client may expose unlearned recipes in the profession window.
            -- This is a discovery hint, not proof that a vendor sells the recipe.
            local schematic = safe(trade.GetRecipeSchematic,recipeID,false)
            local output = safe(trade.GetRecipeOutputItemData,recipeID)
            ch.unlearnedRecipes[recipeID]={id=recipeID,
                name=info.name or ("Recipe #"..recipeID),profession=recipeProfession,
                outputID=(schematic and schematic.outputItemID) or (output and output.itemID),
                source=safe(trade.GetRecipeSourceText,recipeID),
                scan=self:Now(),status="Visible, not learned"}
            -- Do not erase recipes recorded from another profession.
            if ch.recipes[recipeID] and ch.recipes[recipeID].profession == recipeProfession then
                ch.recipes[recipeID] = nil
            end
        end
    end
    ch.recipeStamp = self:Now()
    ch.lastProfession = profession
    ch.lastRecipeCount = learnedCount
    self.allRecipesCache = nil
end

function FCM:UnlearnedRecipes()
    local all={}
    local known={}
    for _,recipe in ipairs(self:AllRecipes()) do known[recipe.id]=true end
    for _,ch in ipairs(self:Characters()) do
        for id,recipe in pairs(ch.unlearnedRecipes or {}) do
            if not known[id] then
                if not all[id] then
                    all[id]={id=id,name=recipe.name,profession=recipe.profession,
                        outputID=recipe.outputID,source=recipe.source,seenOn={}}
                end
                all[id].seenOn[#all[id].seenOn+1]=ch
            end
        end
    end
    local rows={}
    for _,rec in pairs(all) do rows[#rows+1]=rec end
    table.sort(rows,function(a,b)return (a.name or "")<(b.name or "") end)
    return rows
end

-- The Enchants tab means enchantments APPLIED to equipment, not every
-- craft learned by a character with Enchanting. Some historical saved scans
-- erroneously tagged Tailoring crafts as Enchanting; verify against the
-- imported profession reference when available and require an enchant spell.
function FCM:IsEquipmentEnchantRecipe(recipe)
    if type(recipe)~="table" then return false end
    local profession=string.lower(tostring(recipe.profession or ""))
    if not profession:find("enchant",1,true) then return false end
    local ref=self.externalData and self.externalData.recipes and
        self.externalData.recipes[tonumber(recipe.id)]
    if ref and ref.profession and tostring(ref.profession)~="" and
       not string.lower(tostring(ref.profession)):find("enchant",1,true) then return false end
    local name=string.lower(tostring(recipe.name or ""))
    return name:find("^enchant[%s:%-]") ~= nil or name=="enchant"
end

function FCM:AllRecipes()
    if self.allRecipesCache then return self.allRecipesCache end
    local result = {}
    for _, ch in ipairs(self:Characters()) do
        for id, recipe in pairs(ch.recipes or {}) do
            if recipe.learned then
                local row = result[id]
                if not row then
                    row = { id = id, name = recipe.name, outputID = recipe.outputID,
                        outputLink = recipe.outputLink, reagents = recipe.reagents,
                        profession = recipe.profession, complex = recipe.complex, quantity = recipe.quantity or 1, crafters = {} }
                    result[id] = row
                end
                if not row.outputID and recipe.outputID then row.outputID = recipe.outputID end
                if (not row.reagents or #row.reagents == 0) and recipe.reagents then row.reagents = recipe.reagents end
                if not row.outputLink and recipe.outputLink then row.outputLink = recipe.outputLink end
                row.complex = row.complex or recipe.complex
                row.crafters[#row.crafters + 1] = ch
            end
        end
    end
    local list = {}
    for _, r in pairs(result) do list[#list + 1] = r end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    self.allRecipesCache = list
    return list
end

function FCM:MaterialLocations(itemID, receivingChar)
    local locations, total, accessible = {}, 0, 0
    for _, ch in ipairs(self:Characters()) do
        for _, source in ipairs({"bags", "bank"}) do
            for stackKey, item in pairs(ch[source] or {}) do
                if item.itemID == itemID then
                    local count = item.count or 0
                    total = total + count
                    local sameCharacter = receivingChar and ch.key == receivingChar.key
                    -- Different faction/ruleset stock is visible for accounting,
                    -- but NEVER counted as usable for this recipient.
                    local sameSide = receivingChar and self:CanCollaborate(ch,receivingChar)
                    local transferable = sameCharacter or (item.bound == false and sameSide == true)
                    if transferable then accessible = accessible + count end
                    locations[#locations + 1] = { name = self:DisplayCharacter(ch),
                        where = source, count = count, bound = item.bound, usable = transferable,
                        ownerKey=ch.key, stackKey=stackKey,
                        lastScan = ch[source == "bags" and "bagsStamp" or "bankStamp"] }
                end
            end
        end
    end
    table.sort(locations, function(a,b) return a.name < b.name end)
    return total, accessible, locations
end

function FCM:MaterialsFor(recipe, craftingChar)
    local result, allReady = {}, true
    for _, mat in ipairs(recipe.reagents or {}) do
        local total, usable, locations = self:MaterialLocations(mat.itemID, craftingChar)
        local missing = math.max(0, (mat.count or 0) - usable)
        if missing > 0 then allReady = false end
        result[#result + 1] = { id = mat.itemID, name = itemName(mat.itemID),
            required = mat.count, owned = total, usable = usable, missing = missing, locations = locations }
    end
    if recipe.complex then allReady = false end
    return result, allReady
end

function FCM:ReputationGate(recipeID,char)
    local gate = self.db and self.db.gates and self.db.gates[recipeID]
    if gate then
        local data = char and char.reputations and char.reputations[gate.factionID]
        local have = data and data.reaction or nil
        return { factionID = gate.factionID, faction = (data and data.name) or ("Faction #" .. gate.factionID),
            required = gate.standing, current = have, unlocked = have and have >= gate.standing or false,
            source="Manually registered gate"}
    end
    -- Fall back only for specifically sourced catalogue entries with a known
    -- name and reputation. Do not extrapolate by Favor price.
    local recipe=self:RecipeByID(recipeID)
    if recipe and char and self.ReputationForCatalog then
        for _,record in ipairs(self.recipeCatalog or {}) do
            if string.lower(record.name)==string.lower(recipe.name or "") and record.standing then
                local rep=self:ReputationForCatalog(char,record)
                if rep then rep.source=record.source;return rep end
            end
        end
    end
    return nil
end

function FCM:RecipeForOutput(itemID)
    for _, recipe in ipairs(self:AllRecipes()) do
        if recipe.outputID == itemID then return recipe end
    end
    return nil
end

-- All request information lives in account-wide SavedVariables. No server-side
-- messages are sent; the request is visible when the other toon next logs in.
function FCM:FindQueuedCraft(recipeID, recipientKey)
    if not self.db then return nil end
    for _, request in ipairs(self.db.craftingQueue or {}) do
        if request.recipeID == recipeID and request.recipientKey == recipientKey then
            return request
        end
    end
    return nil
end

function FCM:ResolveRequestCrafter(request, recipe)
    if not request then return nil end
    local recipient=self.db.characters[request.recipientKey]
    if request.crafterKey and self.db.characters[request.crafterKey] then
        local c = self.db.characters[request.crafterKey]
        if c.recipes and c.recipes[request.recipeID] and c.recipes[request.recipeID].learned
                and self:CanCollaborate(c,recipient) then
            return c
        end
    end
    request.crafterKey = nil
    recipe = recipe or self:RecipeByID(request.recipeID)
    -- Migrate unassigned requests only if exactly one eligible, same-side crafter.
    local eligible={}
    for _,c in ipairs(recipe and recipe.crafters or {}) do
        if self:CanCollaborate(c,recipient) then eligible[#eligible+1]=c end
    end
    if #eligible==1 then
        request.crafterKey=eligible[1].key
        return eligible[1]
    end
    return nil -- unassigned: visible to everyone until a crafter is selected
end

function FCM:RecipeByID(recipeID)
    for _, recipe in ipairs(self:AllRecipes()) do
        if recipe.id == recipeID then return recipe end
    end
    return nil
end

function FCM:QueueCraft(recipeID, recipientKey, crafterKey)
    if not self.db then return false, "Character database has not loaded." end
    local recipient = self.db.characters[recipientKey]
    local recipe = self:RecipeByID(recipeID)
    if not recipient then return false, "Select a scanned recipient character first." end
    if not recipe then return false, "This recipe is not available in the saved recipe library." end
    if self:FindQueuedCraft(recipeID, recipientKey) then
        return false, "This character already has a request for that recipe."
    end
    local eligible={}
    for _,c in ipairs(recipe.crafters or {}) do
        if self:CanCollaborate(c,recipient) then eligible[#eligible+1]=c end
    end
    if crafterKey then
        local valid = false
        for _,c in ipairs(eligible) do
            if c.key==crafterKey then valid=true;break end
        end
        if not valid then return false,"Crafter is unlearned, opposing-faction, or on another ruleset." end
    elseif #eligible==1 then
        crafterKey=eligible[1].key
    elseif #eligible==0 then
        return false,"No same-faction, same-ruleset crafter is recorded for this recipe."
    end
    local info = recipe.outputID and self.Gear and self.Gear:Info(recipe.outputLink or recipe.outputID)
    if info and info.bindType == 1 and crafterKey ~= recipientKey then
        return false, "This item appears bind-on-pickup and cannot be requested from another crafter."
    end
    local key = tostring(recipeID) .. ":" .. recipientKey
    self.db.craftingQueue[#self.db.craftingQueue + 1] = {
        key=key, recipeID=recipeID, recipientKey=recipientKey,
        crafterKey=crafterKey, created=self:Now(), status="requested",
    }
    return true
end

function FCM:AssignQueuedCraft(request, crafterKey)
    local recipe = request and self:RecipeByID(request.recipeID)
    local crafter = self.db and self.db.characters[crafterKey]
    if not request or not recipe or not crafter then return false, "Request or crafter not found." end
    local valid = false
    for _, c in ipairs(recipe.crafters) do if c.key == crafterKey then valid = true; break end end
    if not valid then return false, "Crafter has not learned that recipe." end
    local recipient=self.db.characters[request.recipientKey]
    local can,reason=self:CanCollaborate(crafter,recipient)
    if not can then return false,"Cannot assign a cross-faction/ruleset craft: "..reason end
    local info = recipe.outputID and self.Gear and self.Gear:Info(recipe.outputLink or recipe.outputID)
    if info and info.bindType == 1 and crafterKey ~= request.recipientKey then
        return false, "A bind-on-pickup result cannot be assigned to another character."
    end
    request.crafterKey = crafterKey
    return true
end

function FCM:RemoveQueuedCraft(recipeID, recipientKey)
    if not self.db then return false end
    for index, r in ipairs(self.db.craftingQueue) do
        if r.recipeID == recipeID and r.recipientKey == recipientKey then
            table.remove(self.db.craftingQueue, index)
            return true
        end
    end
    return false
end

function FCM:QueuedRequests()
    local list = {}
    if not self.db then return list end
    for _, request in ipairs(self.db.craftingQueue or {}) do
        if self.IsPendingRequest and self:IsPendingRequest(request) then
        local recipe = self:RecipeByID(request.recipeID)
        local crafter = self:ResolveRequestCrafter(request, recipe)
        list[#list + 1] = { request = request, recipe = recipe,
            crafter = crafter, recipient = self.db.characters[request.recipientKey] }
        end
    end
    table.sort(list, function(a, b)
        local me = self.currentKey
        local ar = a.crafter and a.crafter.key == me and 0 or (a.crafter and 2 or 1)
        local br = b.crafter and b.crafter.key == me and 0 or (b.crafter and 2 or 1)
        if ar ~= br then return ar < br end
        return (a.request.created or 0) < (b.request.created or 0)
    end)
    return list
end

function FCM:CountAssignedRequests(key)
    local count = 0
    for _, row in ipairs(self:QueuedRequests()) do
        if row.crafter and row.crafter.key == key then count = count + 1 end
    end
    return count
end

function FCM:NotifyCraftRequests()
    local count = self:CountAssignedRequests(self.currentKey)
    if count > 0 then
        self:Say("You have " .. count .. " pending craft request(s). Open /fcm > Requests to review them.")
    end
end

function FCM:ReservedMaterials(exceptKey, craftingChar)
    local reserved, byID = {}, {}
    for _, recipe in ipairs(self:AllRecipes()) do byID[recipe.id]=recipe end
    for _, planned in ipairs(self.db.craftingQueue) do
        local assigned=self.db.characters[planned.crafterKey or ""] or self.db.characters[planned.recipientKey or ""]
        if planned.key ~= exceptKey and (not self.NeedsRequestMaterials or self:NeedsRequestMaterials(planned))
                and (not craftingChar or self:CanCollaborate(assigned,craftingChar)) then
            local recipe = byID[planned.recipeID]
            if recipe then
                for _, reagent in ipairs(recipe.reagents or {}) do
                    reserved[reagent.itemID] = (reserved[reagent.itemID] or 0) + reagent.count
                end
            end
        end
    end
    return reserved
end

-- Multistep material planner. It only unfolds learned, single-reagent-choice
-- recipes. This is an estimate; it cannot perform crafts or move materials.
function FCM:ExpandedCraftingPlan(recipe, craftingChar)
    local byOutput, reservations, stock = {}, self:ReservedMaterials(tostring(recipe.id)..":"..(craftingChar and craftingChar.key or ""),craftingChar), {}
    for _, r in ipairs(self:AllRecipes()) do
        if r.outputID and not r.complex and r.outputID ~= recipe.outputID then
            byOutput[r.outputID] = byOutput[r.outputID] or r
        end
    end
    local plan = {missing={}, intermediates={}, unresolved=recipe.complex and true or false}
    local function getStock(id)
        if stock[id] == nil then
            local _, usable = self:MaterialLocations(id,craftingChar)
            stock[id] = math.max(0, usable - (reservations[id] or 0))
        end
        return stock[id]
    end
    local consume
    consume = function(itemID, quantity, depth, inPath)
        if not itemID or quantity <= 0 then return end
        local have = getStock(itemID)
        local using = math.min(have,quantity)
        stock[itemID] = have - using
        local needed = quantity - using
        if needed <= 0 then return end
        local sub = byOutput[itemID]
        if depth < 4 and sub and not inPath[itemID] then
            local eligible = false
            for _, c in ipairs(sub.crafters or {}) do
                if craftingChar and self:CanCollaborate(c,craftingChar) then eligible = true end
            end
            local bindInfo = self.Gear and self.Gear:Info(itemID)
            if bindInfo and bindInfo.bindType == 1 then
                eligible = false
                for _,c in ipairs(sub.crafters or {}) do
                    if craftingChar and c.key == craftingChar.key then eligible = true end
                end
            end
            if eligible then
                local outputQuantity = math.max(1, tonumber(sub.quantity) or 1)
                local count = math.ceil(needed / outputQuantity)
                plan.intermediates[#plan.intermediates+1] = {recipe=sub.name, count=count, itemID=itemID}
                stock[itemID] = stock[itemID] + count*outputQuantity-needed
                inPath[itemID] = true
                for _, reagent in ipairs(sub.reagents or {}) do
                    consume(reagent.itemID, reagent.count*count,depth+1,inPath)
                end
                inPath[itemID] = nil
                return
            end
        end
        plan.missing[itemID] = (plan.missing[itemID] or 0)+needed
    end
    for _,r in ipairs(recipe.reagents or {}) do consume(r.itemID,r.count,0,{}) end
    return plan
end
