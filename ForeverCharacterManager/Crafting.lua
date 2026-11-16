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
                        profession = recipe.profession, complex = recipe.complex, quantity = recipe.quantity or 1,
                        requiredSkill=recipe.requiredSkill, crafters = {} }
                    result[id] = row
                end
                if tonumber(recipe.requiredSkill) and
                    (not tonumber(row.requiredSkill) or tonumber(recipe.requiredSkill)>tonumber(row.requiredSkill)) then
                    row.requiredSkill=tonumber(recipe.requiredSkill)
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

-- Crafting has its own recipe-only search and profession selector. Keep this
-- independent of Item Explorer: an ordinary material must never be presented
-- as a craftable recipe just because it matches the search text.
local function recipeProfession(recipe)
    local name=tostring(recipe and recipe.profession or "")
    name=name:match("^%s*(.-)%s*$")
    if name=="" then return "Unknown profession" end
    return name
end

-- The account-wide recipe index includes both factions. Crafting is a
-- *request* screen, so limit its choices to crafters who can actually serve
-- the selected recipient. A nil recipient preserves legacy global browsing
-- for diagnostics and other non-request callers.
-- Skill prerequisites are distinct from recipe knowledge. Missing data
-- stays unverified, and last-scanned skills never claim live availability.
function FCM:RecipeSkillStatus(recipe,crafter)
    if not recipe or not crafter then return "verify","Recipe/crafter not selected" end
    local rid=tonumber(recipe.id)
    local personal=(crafter.recipes or {})[rid or ""] or
        (crafter.recipes or {})[tostring(rid or "")]
    local reference=self.externalData and self.externalData.recipes and
        (self.externalData.recipes[rid or ""] or
         self.externalData.recipes[tostring(rid or "")])
    local required=tonumber(personal and personal.requiredSkill) or
        tonumber(recipe.requiredSkill) or tonumber(reference and reference.skill)
    local profession=(personal and personal.profession) or recipe.profession
    local record=crafter.professions and crafter.professions[profession or ""]
    if not record then
        for name,data in pairs(crafter.professions or {}) do
            if tostring(name):lower()==tostring(profession or ""):lower() then
                record=data;break
            end
        end
    end
    local current=tonumber(record and (record.skill or record.skillLevel))
    if not required or required<0 then
        return "verify","Recipe skill requirement not recorded; verify in-game"
    end
    if not current then
        return "verify","Profession skill not scanned; open "..tostring(profession or "profession").." to verify (requires "..required..")"
    end
    if current<required then
        return "blocked","Requires "..tostring(profession or "profession").." "..required..
            "; last-scanned skill "..current.." - train before crafting"
    end
    return "ready",tostring(profession or "Profession").." skill "..current.."/"..required.." required (last scanned)"
end

function FCM:EligibleCraftCrafters(recipe,recipient)
    local eligible={}
    if not recipient then return eligible end
    for _,crafter in ipairs(recipe and recipe.crafters or {}) do
        if self:CanCollaborate(crafter,recipient) and
            self:RecipeSkillStatus(recipe,crafter)~="blocked" then
            eligible[#eligible+1]=crafter
        end
    end
    return eligible
end

function FCM:CraftRecipeProfessions(recipient)
    local names={}
    local seen={}
    for _,recipe in ipairs(self:AllRecipes()) do
        local name=recipeProfession(recipe)
        local key=string.lower(name)
        if not seen[key] and (not recipient or #self:EligibleCraftCrafters(recipe,recipient)>0) then
            seen[key]=true
            names[#names+1]={id=key,name=name}
        end
    end
    table.sort(names,function(a,b) return a.id<b.id end)
    return names
end

function FCM:BrowseCraftRecipes(profession,query,recipient)
    local selected=string.lower(tostring(profession or "all"))
    local needle=string.lower(tostring(query or ""):match("^%s*(.-)%s*$"))
    local matches={}
    for _,recipe in ipairs(self:AllRecipes()) do
        if (not recipient or #self:EligibleCraftCrafters(recipe,recipient)>0) and
            (selected=="all" or string.lower(recipeProfession(recipe))==selected) then
            local id=tostring(recipe.id or "")
            local name=string.lower(tostring(recipe.name or ""))
            local outputName=""
            local outputs=self.externalData and self.externalData.items
            local output=outputs and recipe.outputID and
                (outputs[tonumber(recipe.outputID)] or outputs[tostring(recipe.outputID)])
            if output then outputName=string.lower(tostring(output.name or "")) end
            if needle=="" or name:find(needle,1,true) or id:find(needle,1,true) or
                outputName:find(needle,1,true) then
                matches[#matches+1]=recipe
            end
        end
    end
    return matches
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

-- Requested quantity means desired OUTPUT ITEMS, not recipe casts. A recipe
-- that produces 2 food per cast needs 10 casts for a request of 20 food.
function FCM:ValidCraftQuantity(quantity)
    local n=tonumber(quantity)
    return n and n%1==0 and n>=1 and n<=999 and n or nil
end
function FCM:CraftRequestQuantity(request)
    return self:ValidCraftQuantity(request and request.quantity) or 1
end

-- Existing SavedVariables requests predate the choice of "Reach Total" vs
-- "Craft Additional". Preserve their original meaning (additional items).
function FCM:CraftRequestMode(request)
    return request and request.quantityMode=="total" and "total" or "additional"
end
function FCM:DefaultCraftRequestMode()
    local saved=self.db and self.db.settings and self.db.settings.craftQuantityMode
    return saved=="additional" and "additional" or "total"
end

-- Only count finished goods on the RECIPIENT, not potentially transferable
-- goods on a different toon. Bank and bag records are last-seen snapshots.
function FCM:FinishedItemStock(recipient,outputID)
    local wanted=tonumber(outputID)
    if not recipient or not wanted then
        return {owned=0,bags=0,bank=0,known=false,status="No recipient/item selected"}
    end
    local stock={owned=0,bags=0,bank=0}
    for _,where in ipairs({"bags","bank"}) do
        for _,stack in pairs(recipient[where] or {}) do
            if tonumber(stack.itemID)==wanted then
                stock[where]=stock[where]+math.max(0,math.floor(tonumber(stack.count) or 0))
            end
        end
    end
    stock.owned=stock.bags+stock.bank
    local bagStamp,bankStamp=tonumber(recipient.bagsStamp),tonumber(recipient.bankStamp)
    stock.bagsScanned=bagStamp and bagStamp>0 or false
    stock.bankScanned=bankStamp and bankStamp>0 or false
    stock.known=stock.bagsScanned and stock.bankScanned
    local now=type(self.Now)=="function" and tonumber(self:Now()) or nil
    stock.stale=stock.known and now and now>0 and
        ((now-bagStamp)>172800 or (now-bankStamp)>604800) or false
    stock.status=not stock.known and "PARTIAL SCAN: open bags and bank on recipient" or
        (stock.stale and "STALE: re-open bags and bank on recipient" or "Last-scanned bags and bank")
    return stock
end
function FCM:OwnedFinishedItems(recipient,outputID)
    local stock=self:FinishedItemStock(recipient,outputID)
    return stock.owned,stock.known,stock
end

function FCM:CraftRequestNeeded(recipe,request,recipient)
    local desired=self:CraftRequestQuantity(request)
    local mode=self:CraftRequestMode(request)
    local owned,known,stock=self:OwnedFinishedItems(recipient,recipe and recipe.outputID)
    local crafted=math.max(0,math.floor(tonumber(request and request.fulfilled) or 0))
    local delivered=math.max(0,math.floor(tonumber(request and request.deliveredCount) or 0))
    -- Additional crafts are counted exactly once. For Reach Total, only
    -- crafted-but-not-yet-delivered output reduces a recipient's stock gap;
    -- delivered goods must be counted by a fresh recipient inventory scan.
    local needed=mode=="total" and math.max(0,desired-owned-math.max(0,crafted-delivered))
        or math.max(0,desired-crafted)
    return needed,owned,known,mode,stock
end

function FCM:CraftRequestRuns(recipe,request,recipient)
    local needed,owned,known,mode,stock=self:CraftRequestNeeded(recipe,request,recipient)
    if needed==0 then
        return 0,0,math.max(1,math.floor(tonumber(recipe and recipe.quantity) or 1)),needed,owned,known,mode,stock
    end
    local runs,produced,yield=self:CraftRuns(recipe,needed)
    return runs,produced,yield,needed,owned,known,mode,stock
end

-- Read-only calculation for the Crafting tab's inline quantity field. This
-- does not change any saved request and is safe to run on every edit.
function FCM:CraftQuantityPreview(recipe,recipient,rawQuantity,mode)
    local quantity=self:ValidCraftQuantity(rawQuantity)
    if not quantity then return nil,"Enter a whole number of finished items from 1 to 999." end
    if not recipe or not recipient then return nil,"Select a recipe and recipient first." end
    if mode~="total" and mode~="additional" then
        return nil,"Choose Reach Total or Craft Additional."
    end
    local draft={quantity=quantity,quantityMode=mode}
    local casts,produced,yield,needed,owned,known,_,stock=self:CraftRequestRuns(recipe,draft,recipient)
    return {quantity=quantity,mode=mode,casts=casts,produced=produced,
        yield=yield,needed=needed,owned=owned,ownedKnown=known,stock=stock}
end
function FCM:CraftRuns(recipe, requestedQuantity)
    local quantity=self:ValidCraftQuantity(requestedQuantity) or 1
    local yield=math.max(1,math.floor(tonumber(recipe and recipe.quantity) or 1))
    local runs=math.ceil(quantity/yield)
    return runs,runs*yield,yield
end

function FCM:MaterialsFor(recipe, craftingChar, requestedQuantity)
    local result, allReady = {}, true
    local runs=self:CraftRuns(recipe,requestedQuantity)
    for _, mat in ipairs(recipe.reagents or {}) do
        local total, usable, locations = self:MaterialLocations(mat.itemID, craftingChar)
        local required=(mat.count or 0)*runs
        local missing = math.max(0, required - usable)
        if missing > 0 then allReady = false end
        result[#result + 1] = { id = mat.itemID, name = itemName(mat.itemID),
            required = required, owned = total, usable = usable, missing = missing, locations = locations }
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

function FCM:RequestEligibleCrafters(request,recipe)
    local eligible={}
    if not request or not self.db then return eligible end
    local recipient=self.db.characters[request.recipientKey or ""]
    recipe=recipe or self:RecipeByID(request.recipeID)
    local info=recipe and recipe.outputID and self.Gear and
        self.Gear:Info(recipe.outputLink or recipe.outputID)
    for _,candidate in ipairs(recipe and recipe.crafters or {}) do
        if candidate.recipes and candidate.recipes[request.recipeID] and
                candidate.recipes[request.recipeID].learned and
                self:CanCollaborate(candidate,recipient) and
                self:RecipeSkillStatus(recipe,candidate)~="blocked" and
                (not info or info.bindType~=1 or candidate.key==recipient.key) then
            eligible[#eligible+1]=candidate
        end
    end
    return eligible
end

function FCM:CanCraftRequest(request,crafter,recipe)
    if not crafter or not request or not self:IsPendingRequest(request) or
            request.status=="crafted" then return false end
    for _,candidate in ipairs(self:RequestEligibleCrafters(request,recipe)) do
        if candidate.key==crafter.key then return true end
    end
    return false
end

-- This is an ADVISORY best choice for material planning, never an assignment.
function FCM:SuggestedRequestCrafter(request,recipe)
    local choices=self:RequestEligibleCrafters(request,recipe)
    if #choices==0 then return nil end
    local recipient=self.db.characters[request.recipientKey or ""]
    local needed=self:CraftRequestNeeded(recipe,request,recipient)
    local best,bestMissing
    for _,candidate in ipairs(choices) do
        -- Legacy standalone harnesses and older installs may load Crafting
        -- before the advisory module. A valid known crafter is still usable.
        local plan=type(self.CraftAvailability)=="function" and
            self:CraftAvailability(recipe,candidate,request.key,needed) or nil
        local missing=tonumber(plan and plan.missing) or math.huge
        if not best or missing<bestMissing then best=candidate;bestMissing=missing end
    end
    return best
end

-- Kept for read-only callers; no queued request ever becomes assigned.
function FCM:ResolveRequestCrafter(request,recipe)
    return self:SuggestedRequestCrafter(request,recipe)
end

function FCM:RecipeByID(recipeID)
    for _, recipe in ipairs(self:AllRecipes()) do
        if recipe.id == recipeID then return recipe end
    end
    return nil
end

function FCM:QueueCraft(recipeID, recipientKey, crafterKey, requestedQuantity, quantityMode)
    if not self.db then return false, "Character database has not loaded." end
    if requestedQuantity==nil then requestedQuantity=1 end
    local quantity=self:ValidCraftQuantity(requestedQuantity)
    if not quantity then return false, "Quantity must be a whole number of output items from 1 to 999." end
    quantityMode=quantityMode or self:DefaultCraftRequestMode()
    if quantityMode~="total" and quantityMode~="additional" then
        return false,"Choose Reach Total or Craft Additional."
    end
    local recipient = self.db.characters[recipientKey]
    local recipe = self:RecipeByID(recipeID)
    if not recipient then return false, "Select a scanned recipient character first." end
    if not recipe then return false, "This recipe is not available in the saved recipe library." end
    if self:FindQueuedCraft(recipeID, recipientKey) then
        return false, "This character already has a request for that recipe."
    end
    -- Deprecated crafterKey argument is deliberately ignored. Requests are
    -- posted without a designated maker, even if only one crafter is known.
    local key = tostring(recipeID) .. ":" .. recipientKey
    self.db.craftingQueue[#self.db.craftingQueue + 1] = {
        key=key, recipeID=recipeID, recipientKey=recipientKey,
        quantity=quantity,quantityMode=quantityMode,boardVersion=2,
        fulfilled=0,deliveredCount=0,created=self:Now(),status="requested",
    }
    return true
end

function FCM:UpdateQueuedCraftQuantity(request,requestedQuantity,quantityMode)
    local quantity=self:ValidCraftQuantity(requestedQuantity)
    if not quantity then return false,"Quantity must be a whole number from 1 to 999." end
    if not request or not self.db then return false,"No queued craft request selected." end
    local found=false
    for _,existing in ipairs(self.db.craftingQueue or {}) do
        if existing==request then found=true;break end
    end
    if not found then return false,"That request is no longer queued." end
    if request.status=="crafted" or request.status=="delivered" or request.status=="cancelled" then
        return false,"A completed request cannot change quantity; create a new request instead."
    end
    if quantityMode and quantityMode~="total" and quantityMode~="additional" then
        return false,"Choose Reach Total or Craft Additional."
    end
    if (quantityMode or self:CraftRequestMode(request))=="additional" and
            quantity<(tonumber(request.fulfilled) or 0) then
        return false,"Requested quantity cannot be less than already recorded crafts. No history was erased."
    end
    if quantityMode and quantityMode~=self:CraftRequestMode(request) and
            (tonumber(request.fulfilled) or 0)>0 then
        return false,"Cannot change Reach Total / Craft Additional after progress is recorded."
    end
    request.quantity=quantity
    if quantityMode then request.quantityMode=quantityMode end
    request.updated=self:Now()
    if request.status=="ready" then request.status="gathering" end
    local mode=self:CraftRequestMode(request)
    return true,(mode=="total" and "Target total" or "Additional output")..
        " updated to "..quantity.." item(s)."
end

function FCM:AssignQueuedCraft(request, crafterKey)
    return false,"R6 uses an unassigned request board. Log into any eligible crafter and open Requests > Can Craft."
end

function FCM:RecordCraftProgress(request,crafterKey,quantity)
    if not self.currentKey or crafterKey~=self.currentKey then
        return false,"Log into the crafter that performed the work to record completed items."
    end
    local maker=self.db and self.db.characters[crafterKey or ""]
    local recipe=request and self:RecipeByID(request.recipeID)
    if not self:CanCraftRequest(request,maker,recipe) then
        return false,"Log into a compatible character who learned this recipe to record crafts."
    end
    local count=self:ValidCraftQuantity(quantity)
    if not count then return false,"Enter a whole number of finished items from 1 to 999." end
    local recipient=self.db.characters[request.recipientKey or ""]
    local needed=self:CraftRequestNeeded(recipe,request,recipient)
    if needed<=0 then return false,"The recorded request is already fulfilled." end
    local credited=math.min(needed,count)
    request.fulfilled=(tonumber(request.fulfilled) or 0)+credited
    request.work=request.work or {}
    request.work[#request.work+1]={crafterKey=maker.key,quantity=credited,
        at=self:Now(),source="manual confirmation"}
    request.updated=self:Now()
    request.status=credited>=needed and "crafted" or "gathering"
    return true,tostring(credited).." item(s) recorded; "..
        tostring(math.max(0,needed-credited)).." still needed. Confirm delivery separately."
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
        local crafter = self:SuggestedRequestCrafter(request, recipe)
        list[#list + 1] = { request = request, recipe = recipe,
            crafter = crafter, recipient = self.db.characters[request.recipientKey],
            eligible=self:RequestEligibleCrafters(request,recipe) }
        end
    end
    table.sort(list, function(a, b)
        local me = self.currentKey
        local ar = self:CanCraftRequest(a.request,self.db.characters[me],a.recipe) and 0 or 1
        local br = self:CanCraftRequest(b.request,self.db.characters[me],b.recipe) and 0 or 1
        if ar ~= br then return ar < br end
        return (a.request.created or 0) < (b.request.created or 0)
    end)
    return list
end

function FCM:CountAssignedRequests(key)
    local count = 0
    for _, row in ipairs(self:QueuedRequests()) do
        if self:CanCraftRequest(row.request,self.db.characters[key or ""],row.recipe) then
            count = count + 1
        end
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
                local recipient=self.db.characters[planned.recipientKey or ""]
                local runs=self:CraftRequestRuns(recipe,planned,recipient)
                for _, reagent in ipairs(recipe.reagents or {}) do
                    reserved[reagent.itemID] = (reserved[reagent.itemID] or 0) + reagent.count*runs
                end
            end
        end
    end
    return reserved
end

-- Multistep material planner. It only unfolds learned, single-reagent-choice
-- recipes. This is an estimate; it cannot perform crafts or move materials.
function FCM:ExpandedCraftingPlan(recipe, craftingChar, requestedQuantity, excludeRequestKey)
    -- The queued request's key is recipeID:recipientKey, not recipeID:crafterKey.
    -- Explicit exclusion prevents a request from reserving its own materials.
    local byOutput, reservations, stock = {}, self:ReservedMaterials(excludeRequestKey,craftingChar), {}
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
    local runs=self:CraftRuns(recipe,requestedQuantity)
    for _,r in ipairs(recipe.reagents or {}) do consume(r.itemID,r.count*runs,0,{}) end
    return plan
end
