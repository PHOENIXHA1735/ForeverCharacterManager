-- FCM v0.7.0: cross-character advisory layer.
-- Read-only planning. Offline bags/banks and external references are snapshots.
local _, FCM = ...
local Advisor = {}
FCM.Advisor = Advisor

local function num(v) return math.max(0, tonumber(v) or 0) end
local function sortedKeys(t)
    local out={}
    for k in pairs(t or {}) do out[#out+1]=k end
    table.sort(out,function(a,b)return tostring(a)<tostring(b) end)
    return out
end
local function availableFor(recipe, crafter, excludeKey)
    local reservations=FCM:ReservedMaterials(excludeKey,crafter)
    local rows,transfers,complete={}, {}, true
    if not recipe or recipe.complex or not recipe.reagents or #recipe.reagents==0 then
        return {ready=false,uncertain=true,lines={},transfers={},missing=0,reason="Incomplete, optional or unresolved recipe ingredients"}
    end
    local totalMissing=0
    for _,reagent in ipairs(recipe.reagents) do
        local id=tonumber(reagent.itemID or reagent.id)
        local requested=num(reagent.count or reagent.qty)
        if not id or requested==0 then
            complete=false
        else
            local total,usable,locations=FCM:MaterialLocations(id,crafter)
            local reserved=num(reservations[id])
            local usableUnreserved=math.max(0,usable-reserved)
            local missing=math.max(0,requested-usableUnreserved)
            totalMissing=totalMissing+missing
            if missing>0 then complete=false end
            rows[#rows+1]={id=id,name=FCM.ItemName and FCM.ItemName(id) or ("Item #"..id),
                required=requested,total=total,usable=usable,unreserved=usableUnreserved,
                reserved=reserved,missing=missing,locations=locations}
            -- Transfer quantities are capped by the needed quantity, never by total stored.
            local need=requested
            -- Consume the crafter's own stock first; a transfer is only needed for the remainder.
            for _,loc in ipairs(locations) do
                if crafter and loc.usable and loc.ownerKey==crafter.key then
                    need=math.max(0,need-math.max(0,num(loc.count)-reserved))
                    reserved=math.max(0,reserved-num(loc.count))
                end
            end
            for _,loc in ipairs(locations) do
                if need<=0 then break end
                if loc.usable and crafter and loc.ownerKey~=crafter.key then
                    local count=math.min(need,math.max(0,num(loc.count)-reserved))
                    if count>0 then
                        transfers[#transfers+1]={itemID=id,name=FCM.ItemName and FCM.ItemName(id) or ("Item #"..id),
                            count=count,from=loc.name,where=loc.where,scan=loc.lastScan}
                        need=need-count
                    end
                    reserved=math.max(0,reserved-num(loc.count))
                end
            end
        end
    end
    return {ready=complete,uncertain=not complete and totalMissing==0,lines=rows,
        transfers=transfers,missing=totalMissing,
        reason=complete and "Recorded materials are sufficient, subject to snapshot/trade restrictions" or "Shortages or unverified ingredients"}
end

function FCM:CraftAvailability(recipe, crafter, excludeKey)
    return availableFor(recipe,crafter,excludeKey)
end

function FCM:SmartUpgradeRows(ch)
    local rows={}
    if not ch or not self.Gear then return rows end
    local seen={}
    for _,candidate in ipairs(self.Gear:Candidates(ch) or {}) do
        local id=candidate.info and candidate.info.name or tostring(candidate.recipe.id)
        local key=tostring(candidate.slot).."/"..id
        if not seen[key] then
            seen[key]=true
            local best=nil
            for _,crafter in ipairs(candidate.crafters or {}) do
                local plan=self:CraftAvailability(candidate.recipe,crafter)
                if not best or (plan.ready and not best.plan.ready) or
                    (plan.ready==best.plan.ready and plan.missing<best.plan.missing) then
                    best={crafter=crafter,plan=plan}
                end
            end
            if best then
                rows[#rows+1]={kind="crafted",candidate=candidate,recipient=ch,recipe=candidate.recipe,
                    itemID=candidate.recipe.outputID,crafter=best.crafter,plan=best.plan,
                    score=candidate.delta,ready=best.plan.ready,
                    status=best.plan.ready and "Recorded materials ready" or
                        (best.plan.uncertain and "Check recipe data" or ("Missing "..best.plan.missing.." reagents"))}
            end
        end
    end
    table.sort(rows,function(a,b)
        if a.ready~=b.ready then return a.ready end
        return (a.score or 0)>(b.score or 0)
    end)
    return rows
end

function FCM:ProfessionPlan(ch)
    local rows={}
    if not ch then return rows end
    for _,recipe in pairs(ch.recipes or {}) do
        if recipe.learned and recipe.profession and recipe.reagents and #recipe.reagents>0 then
            local plan=self:CraftAvailability(recipe,ch)
            local ref=self.externalData and self.externalData.recipes and
                (self.externalData.recipes[recipe.id] or self.externalData.recipes[tostring(recipe.id)])
            local skill=(ref and tonumber(ref.skill)) or tonumber(recipe.requiredSkill)
            local prof=ch.professions and ch.professions[recipe.profession]
            local current=prof and tonumber(prof.skill)
            local hint="Training value unavailable"
            if current and skill then
                if current<skill then hint="Skill requirement not yet met"
                elseif current>skill+35 then hint="Likely poor skill-up option; verify recipe color"
                else hint="Potential skill-up; check in-game difficulty color" end
            end
            rows[#rows+1]={recipe=recipe,character=ch,plan=plan,
                skill=skill,current=current,hint=hint,ready=plan.ready,
                cost=self.CraftPriceEstimate and self:CraftPriceEstimate(recipe,ch) or nil}
        end
    end
    table.sort(rows,function(a,b)
        if a.ready~=b.ready then return a.ready end
        if a.skill and b.skill and a.skill~=b.skill then return a.skill<b.skill end
        return tostring(a.recipe.name)<tostring(b.recipe.name)
    end)
    return rows
end

function FCM:ItemRelations(itemID)
    local id=tonumber(itemID)
    local result={usedIn={},producedBy={},owned={},requests={},source=""}
    if not id then return result end
    local source=self.externalData and self.externalData.items and self.externalData.items[id]
    result.source=source and (source.metadataSource or source.source or source.sourceStatus) or "No imported source"
    local seenUsed,seenMade={},{}
    local function scan(r, rid, provenance)
        if not r then return end
        local output=tonumber(r.outputID or r.resultID)
        local name=r.name or ("Recipe #"..tostring(rid or "?"))
        if output==id and not seenMade[name] then
            result.producedBy[#result.producedBy+1]={name=name,profession=r.profession,source=provenance,recipe=r}
            seenMade[name]=true
        end
        for _,m in ipairs(r.reagents or {}) do
            if tonumber(m.itemID or m.id)==id and not seenUsed[name] then
                result.usedIn[#result.usedIn+1]={name=name,profession=r.profession,
                    count=num(m.count or m.qty),source=provenance,recipe=r}
                seenUsed[name]=true
            end
        end
    end
    for _,r in ipairs(self:AllRecipes()) do scan(r,r.id,"Known by one or more of your characters") end
    for recipeID,r in pairs((self.externalData and self.externalData.recipes) or {}) do
        scan(r,recipeID,r.source or "Imported reference; availability unverified")
    end
    for _,ch in ipairs(self:Characters()) do
        local count=0
        for _,sourceName in ipairs({"bags","bank"}) do
            for _,item in pairs(ch[sourceName] or {}) do
                if tonumber(item.itemID)==id then
                    result.owned[#result.owned+1]={char=ch,location=sourceName,count=num(item.count),
                        stamp=ch[sourceName=="bags" and "bagsStamp" or "bankStamp"]}
                    count=count+num(item.count)
                end
            end
        end
        result.total=(result.total or 0)+count
    end
    for _,req in ipairs(self.db and self.db.craftingQueue or {}) do
        if self:IsPendingRequest(req) then
            local recipe=self:RecipeByID(req.recipeID)
            if recipe then
                local relevant=tonumber(recipe.outputID)==id
                for _,m in ipairs(recipe.reagents or {}) do
                    if tonumber(m.itemID)==id then relevant=true end
                end
                if relevant then result.requests[#result.requests+1]=req end
            end
        end
    end
    table.sort(result.usedIn,function(a,b)return a.name<b.name end)
    table.sort(result.producedBy,function(a,b)return a.name<b.name end)
    return result
end

function FCM:ExpandedItemDetails(itemID)
    local lines={self:ExplorerDetails(itemID),"","|cffffd983FCM CHARACTER & CRAFT RELATIONSHIPS|r"}
    local refs=self:ItemRelations(itemID)
    lines[#lines+1]="Recorded stock: "..tostring(refs.total or 0).." items (offline scans may be stale)"
    for _,loc in ipairs(refs.owned) do
        lines[#lines+1]="  "..self:DisplayCharacter(loc.char).." / "..loc.location..": "..loc.count.." ("..self:Age(loc.stamp)..")"
    end
    if #refs.usedIn>0 then
        lines[#lines+1]=""
        lines[#lines+1]="Known crafting uses: "..#refs.usedIn
        for i=1,math.min(18,#refs.usedIn) do
            local r=refs.usedIn[i]
            lines[#lines+1]="  "..r.name.." ["..(r.profession or "?").."] requires "..r.count
        end
    end
    if #refs.producedBy>0 then
        lines[#lines+1]=""
        lines[#lines+1]="Recipes that produce this item: "..#refs.producedBy
        for i=1,math.min(12,#refs.producedBy) do
            local r=refs.producedBy[i]
            lines[#lines+1]="  "..r.name.." ["..(r.profession or "?").."]"
        end
    end
    lines[#lines+1]=""
    lines[#lines+1]="Active crafting requests mentioning item: "..#refs.requests
    lines[#lines+1]="Acquisition sources are reference data, not guaranteed live availability."
    return table.concat(lines,"\n")
end

function FCM:AdvisorDiagnostics()
    local characters=#self:Characters()
    local recipes=#self:AllRecipes()
    local data=self.externalData or {}
    local function count(t) local x=0;for _ in pairs(t or {}) do x=x+1 end;return x end
    return "Characters: "..characters.." | learned recipe types: "..recipes..
        "\nImported items: "..count(data.items).." | reference recipes: "..count(data.recipes)..
        "\nDungeon records: "..count(data.dungeons).." | auction snapshots: "..count(data.prices)..
        "\nExternal data edition: "..tostring(data.edition or "Not synced")..
        "\nSource credit: ForeverDB.net — https://foreverdb.net"
end
