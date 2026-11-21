-- Structured, read-only view data for the Gathering visual-detail prototype.
-- This module never changes gathering history, map pins, reference records or skill snapshots.
local _,FCM=...
local sourceHeadings={herbalism="Possible Source Herbs",mining="Possible Source Deposits",
    fishing="Fishing Sources",treasure="Treasure Sources"}
local professionNames={herbalism="Herbalism",mining="Mining",fishing="Fishing",treasure="Treasure"}

local function zonesFor(source,expanded)
    local zones,seen={},{}
    for _,place in ipairs(source and source.locations or {}) do
        local name=place.zone
        if type(name)=="string" and name~="" and not seen[name:lower()] then
            seen[name:lower()]=true
            zones[#zones+1]={name=name,reported=place.verificationStatus=="reported_reference"}
        end
    end
    table.sort(zones,function(a,b)return a.name<b.name end)
    local shown={}
    local count=expanded and #zones or math.min(#zones,4)
    for i=1,count do shown[#shown+1]=zones[i] end
    return shown,#zones-count,#zones
end

function FCM:GatherMaterialDetailModel(row,ch,expanded)
    local ref=row and row.reference
    if not ref or not ref.material then return nil end
    local byName={}
    for _,entry in ipairs(self.gatheringReference and self.gatheringReference.resources or {}) do
        if type(entry.name)=="string" and type(entry.category)=="string" then
            byName[entry.category..":"..entry.name:lower()]=entry
        end
    end
    local model={
        name=row.name, icon=row.icon, itemID=ref.itemID or row.itemID,
        itemType=ref.materialType or "Material", profession=professionNames[row.kind] or row.kind,
        kind=row.kind, sourceHeading=sourceHeadings[row.kind], sources={}, zoneGroups={}, history={},
        required="Varies",current="Unknown",cap=nil,canGather="Unknown",
        explanation=ref.environment or "Potential source mapping; WoW Forever drop verification pending.",
        expanded=not not expanded
    }
    local firstThreshold,consistent,hasThreshold=nil,true,false
    local current,cap
    local seenSources={}
    for _,sourceName in ipairs(ref.materialSources or {}) do
        local normalized=sourceName:lower()
        if not seenSources[normalized] then
            seenSources[normalized]=true
            local source=byName[row.kind..":"..normalized]
            local threshold=tonumber(source and (source.minimumSkill or source.orange))
            if not threshold then
                consistent=false
            elseif not hasThreshold then
                firstThreshold=threshold
                hasThreshold=true
            elseif firstThreshold~=threshold then
                consistent=false
            end
            local _,_,info=self:GatherResourceSkill(row.kind,sourceName,ch)
            info=info or {}
            local recent=info.current and info.age and info.age>=0 and info.age<=86400
            if recent and not current then
                current=tonumber(info.current)
                cap=ch and ch.professions and (function()
                    for key,v in pairs(ch.professions) do
                        local k=type(v)=="table" and tostring(v.name or key):lower()
                        if k==row.kind or (row.kind=="herbalism" and k=="herb gathering") then
                            return tonumber(v.maxSkill)
                        end
                    end
                end)()
            end
            model.sources[#model.sources+1]={
                name=sourceName,required=threshold or "Unknown",
                eligibility=recent and info.can or "Unknown",
                verified=false
            }
            local list,remaining,total=zonesFor(source,expanded)
            model.zoneGroups[#model.zoneGroups+1]={
                name=sourceName,locations=list,remaining=remaining,total=total
            }
        end
    end
    if consistent and hasThreshold then model.required=tostring(firstThreshold)
    elseif not hasThreshold then model.required="Unknown" end
    if current then
        model.current=tostring(current)
        model.cap=cap
    end
    -- Candidate Classic item drops are not the same as a validated Forever
    -- gathering rule. Never infer a material drop from the player's Mining skill.
    model.canGather="Unknown"
    if #model.sources==0 then
        model.sources[1]={name="No verified candidate source documented",required="Unknown",eligibility="Unknown"}
    end
    if #model.zoneGroups==0 then
        model.zoneGroups[1]={name="Unverified",locations={},remaining=0,total=0}
    end
    for _,point in ipairs(row.locations or {}) do
        if point.personal then
            local label=self:GatherZoneLabel(point.mapID)
            model.history[#model.history+1]=label.." — "..self:GatherCountLabel(point)
        end
    end
    if #model.history==0 then model.history[1]="No personal discoveries recorded." end
    model.verificationNote="These source nodes are candidates. A character meeting the node skill does not verify the specific WoW Forever item drop."
    return model
end

function FCM:GatherDetailModel(row,ch,expanded)
    if not row or not sourceHeadings[row.kind] or type(row.detail)~="function" then return end
    local material=self:GatherMaterialDetailModel(row,ch,expanded)
    local model=material or {
        name=row.name,icon=row.icon,kind=row.kind,profession=professionNames[row.kind],
        itemID=row.itemID or (row.reference and row.reference.itemID),
        itemType=row.kind=="treasure" and "Treasure" or row.kind=="fishing" and
            (row.summary or "Fishing") or "Gathering node",
        sections={}
    }
    local sections=row.detail(expanded,true)
    if material then
        model.metrics={{"Source node skill",model.required},{"Your skill",model.current..(model.cap and ("/"..model.cap) or "")},
            {"Forever drop","Unverified"}}
        if expanded then
            for _,section in ipairs(sections) do
                if section.title=="REFERENCE SOURCES" then model.referenceSection=section end
            end
        end
    elseif row.kind=="herbalism" or row.kind=="mining" then
        local _,_,skill=self:GatherResourceSkill(row.kind,row.name,ch)
        local fresh=skill.age and skill.age>=0 and skill.age<=86400
        model.metrics={{"Required skill",skill.required or "Unknown"},{"Your skill",fresh and skill.current or "Unknown"},
            {"Can gather node",skill.can}}
    elseif row.kind=="fishing" then
        model.metrics={{"Effective Fishing",self:GatherEffectiveFishingSkill(ch) or "Unknown"}}
    end
    if not material then
        local hasFishingSources=false
        for _,section in ipairs(sections) do
            if section.title=="FISHING SOURCES" then hasFishingSources=true end
        end
        for _,section in ipairs(sections) do
            if section.title=="FISHING SOURCES" or
                (section.title=="REPORTED FISHING WATERS" and not hasFishingSources) or
                section.title=="REFERENCE ZONES" then
                section.title=sourceHeadings[row.kind]
            end
            model.sections[#model.sections+1]=section
        end
    end
    return model
end
