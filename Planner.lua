local _, FCM = ...
local activeStatus={requested=true,gathering=true,ready=true,crafted=true}
local reservableStatus={requested=true,gathering=true,ready=true}
local allowedStatus={requested=true,gathering=true,ready=true,crafted=true,delivered=true,cancelled=true}

function FCM:IsPendingRequest(req)
    return req and activeStatus[req.status or "requested"] == true
end

function FCM:NeedsRequestMaterials(req)
    return req and reservableStatus[req.status or "requested"] == true
end

function FCM:ChangeRequestStatus(req, status)
    if not req or not allowedStatus[status] or not self.db then return false,"Invalid request status" end
    req.status=status
    req.updated=self:Now()
    if status=="delivered" or status=="cancelled" then
        self.db.requestHistory=self.db.requestHistory or {}
        self.db.requestHistory[#self.db.requestHistory+1]={
            recipeID=req.recipeID,recipientKey=req.recipientKey,crafterKey=req.crafterKey,
            itemName=(self:RecipeByID(req.recipeID) or {}).name,
            status=status,updated=req.updated,created=req.created,
        }
        while #self.db.requestHistory>60 do table.remove(self.db.requestHistory,1) end
        for i=#self.db.craftingQueue,1,-1 do
            if self.db.craftingQueue[i]==req then table.remove(self.db.craftingQueue,i) break end
        end
    end
    if self.Refresh then self:Refresh() end
    return true
end

-- Each request consumes a shared material pool once, so a reagent in two
-- pending requests is never counted twice in this list. Stock is conservative:
-- materials inaccessible to the assigned crafter are not assumed accessible.
function FCM:ShoppingList(factionView)
    local allocated, result, unresolved={}, {}, {}
    local queue={}
    for _, req in ipairs(self.db and self.db.craftingQueue or {}) do
        local recipient=self.db and self.db.characters[req.recipientKey or ""]
        if self:NeedsRequestMaterials(req) and recipient and
            (not factionView or factionView=="all" or self:NormalizeFaction(recipient.faction)==factionView) then
            queue[#queue+1]=req
        end
    end
    table.sort(queue,function(a,b)return (a.created or 0)<(b.created or 0) end)
    for _,req in ipairs(queue) do
        local recipe=self:RecipeByID(req.recipeID)
        local crafter=self:ResolveRequestCrafter(req,recipe)
        if recipe and crafter and not recipe.complex then
            for _,mat in ipairs(recipe.reagents or {}) do
                local id=mat.itemID
                if id then
                    local needed=tonumber(mat.count) or 0
                    local outstanding=needed
                    local _,_,locations=self:MaterialLocations(id,crafter)
                    for _,loc in ipairs(locations) do
                        if outstanding<=0 then break end
                        if loc.usable then
                            local key=tostring(loc.ownerKey).."/"..tostring(loc.where).."/"..tostring(loc.stackKey).."/"..tostring(id)
                            local remaining=math.max(0,(loc.count or 0)-(allocated[key] or 0))
                            local used=math.min(outstanding,remaining)
                            allocated[key]=(allocated[key] or 0)+used
                            outstanding=outstanding-used
                        end
                    end
                    local row=result[id] or {id=id,name=self.ItemName(id),required=0,available=0,missing=0,requests=0,transfers={}}
                    row.required=row.required+needed
                    row.available=row.available+(needed-outstanding)
                    row.missing=row.missing+outstanding
                    row.requests=row.requests+1
                    result[id]=row
                end
            end
        else
            unresolved[#unresolved+1]=(recipe and recipe.name or ("Recipe #"..tostring(req.recipeID))) ..
                (not recipe and " (recipe not scanned)" or (not crafter and " (no crafter)" or " (complex reagents)"))
        end
    end
    local list={}
    for _,r in pairs(result) do list[#list+1]=r end
    table.sort(list,function(a,b)
        if (a.missing>0)~=(b.missing>0) then return a.missing>0 end
        return a.name<b.name
    end)
    return list,unresolved
end

function FCM:TransferSuggestions(recipe,crafter)
    local rows={}
    if not recipe or not crafter then return rows end
    for _,mat in ipairs(recipe.reagents or {}) do
        local _,_,locations=self:MaterialLocations(mat.itemID,crafter)
        for _,loc in ipairs(locations) do
            if loc.usable and loc.name~=self:DisplayCharacter(crafter) then
                rows[#rows+1]={name=self.ItemName(mat.itemID),itemID=mat.itemID,
                    from=loc.name,where=loc.where,count=math.min(mat.count or 0,loc.count or 0),
                    age=loc.lastScan}
            end
        end
    end
    return rows
end

function FCM:UpgradeDashboard()
    local rows={}
    for _,ch in ipairs(self:VisibleCharacters()) do
        local suggestions=(self.SmartUpgradeRows and self:SmartUpgradeRows(ch)) or {}
        local unique, added={}, 0
        for _,entry in ipairs(suggestions) do
            local candidate=entry.candidate
            local id=tostring(candidate.slot)..":"..tostring(candidate.recipe.outputID)
            if not unique[id] and added<3 then
                unique[id]=true
                added=added+1
                local crafter=entry.crafter
                rows[#rows+1]={kind="upgrade",ch=ch,candidate=candidate,
                    title=ch.name..": "..candidate.info.name,
                    summary="+"..self.Gear:ScoreLabel(candidate.delta).." weighted points | "..(crafter and crafter.name or "Unknown")..
                        " | "..entry.status,
                    score=candidate.delta or 0,ready=entry.ready,crafter=crafter,plan=entry.plan}
            end
        end
        local missing=(self.Gear and self.Gear.UnlearnedCandidates) and self.Gear:UnlearnedCandidates(ch) or {}
        for i=1,math.min(2,#missing) do
            local opportunity=missing[i]
            rows[#rows+1]={kind="opportunity",ch=ch,opportunity=opportunity,
                title=ch.name..": potential unlearned craft",
                summary=opportunity.info.name.." | recipe not known by a scanned crafter | +"..self.Gear:ScoreLabel(opportunity.delta).." est. points",
                score=-0.1}
        end
        local talent=self:TalentAdvice(ch)
        if talent and talent.report and talent.report.nextStep then
            rows[#rows+1]={kind="talent",ch=ch,title=ch.name..": next talent point",
                summary=talent.next,score=0}
        end
        for _,p in pairs(ch.professions or {}) do
            if p.skill and p.maxSkill and p.maxSkill>0 and p.skill<p.maxSkill then
                local milestone= p.skill<150 and 150 or (p.skill<225 and 225 or (p.skill<300 and 300 or nil))
                if milestone and p.maxSkill>=milestone then
                    rows[#rows+1]={kind="profession",ch=ch,
                        title=ch.name..": "..p.name.." milestone "..milestone,
                        summary="Skill "..p.skill.." / "..milestone.." | "..(milestone-p.skill).." skill to go",
                        score=-1}
                end
            end
        end
    end
    table.sort(rows,function(a,b)
        if a.score~=b.score then return a.score>b.score end
        return a.title<b.title
    end)
    return rows
end

function FCM:TotalGold()
    local total=0
    for _,ch in ipairs(self:Characters()) do total=total+(tonumber(ch.gold) or 0) end
    return total
end
