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
    -- A referenced source-node item is not automatically an observed Forever
    -- drop. Keep provenance and distinguish provider listing from observation.
    local dropRank=0
    local function materialDropEvidence(source,itemID)
        local rank=0
        for _,item in ipairs(source and source.loot or {}) do
            if tonumber(item.itemID)==tonumber(itemID) and
                type(item.sourceID)=="string" and item.sourceID:match("^foreverdb%-") then
                if item.verificationStatus=="forever_observed" then
                    rank=math.max(rank,2)
                elseif item.verificationStatus~="classic_reference" then
                    rank=math.max(rank,1)
                end
            end
        end
        return rank==2 and "ForeverDB observed" or
            rank==1 and "ForeverDB listed" or "Unverified",rank
    end
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
            local status,rank=materialDropEvidence(source,model.itemID)
            dropRank=math.max(dropRank,rank)
            model.sources[#model.sources+1]={
                name=sourceName,required=threshold or "Unknown",
                eligibility=recent and info.can or "Unknown",
                dropStatus=status
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
    -- Candidate source-node skill does not prove the specific item drops.
    -- These labels are recalculated from every refreshed provider snapshot.
    model.canGather="Unknown"
    model.dropStatus=dropRank==2 and "ForeverDB observed" or
        dropRank==1 and "ForeverDB listed" or "Unverified"
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
    model.verificationNote=dropRank==2 and
        "ForeverDB reports an observed item drop at a named source. Verify the report in game." or
        dropRank==1 and
        "ForeverDB lists this item at a candidate source; this is not a confirmed personal drop." or
        "No ForeverDB item-specific source evidence yet. Meeting the node skill does not prove the item drops."
    return model
end


-- Curated *Classic* fishing guidance, separate from the ForeverDB snapshot.
-- Item IDs identify the fish, never the source node. No gameplay observation
-- or WoW Forever seasonal/drop verification is implied by these notes.
local classicFishNotes={
    [13755]={water="Ocean / coastal open water",season="September 23 - March 19",
        methods={"Open water (coastal / ocean; Classic reference)"},
        reference="Warcraft Wiki: Winter Squid; Icy Veins Classic fishing guide"},
    [13756]={water="Ocean / coastal open water",season="March 20 - September 22",
        methods={"Open water (coastal / ocean; Classic reference)"},
        reference="Warcraft Tavern: Classic Fishing Fish List"},
    [6358]={water="Coastal water; other recorded waters require verification",
        methods={"Oily Blackmouth School (Classic candidate)","Open water (Classic reference)"},
        reference="Warcraft Wiki: Oily Blackmouth"},
    [6359]={water="Coastal and some inland waters (Classic reference)",
        methods={"Firefin Snapper School (Classic candidate)",
            "Oil Spill (Classic candidate)","Open water (Classic reference)"},
        reference="Warcraft Wiki: Firefin Snapper"}
}
local fishingMethodLabels={
    open_water="Open water",school="Fish schools",pool="Fishing pools",
    oil_spill="Oil spills",wreckage="Floating wreckage",unknown="Zone references (method unknown)"
}
local fishingMethodOrder={"open_water","school","pool","oil_spill","wreckage","unknown"}

local waterLabels={ocean="Ocean",coastal="Coastal / ocean",freshwater="Freshwater",
    lake="Lake (freshwater)",river="River (freshwater)"}
local months={"January","February","March","April","May","June","July","August",
    "September","October","November","December"}
local function seasonLabel(window)
    if type(window)~="table" or type(window.start)~="string" or
        type(window["end"])~="string" then return nil end
    local function day(value)
        local month,date=value:match("^(%d%d)%-(%d%d)$")
        month,date=tonumber(month),tonumber(date)
        if not month or not months[month] or not date or date<1 or date>31 then return nil end
        return months[month].." "..date
    end
    local first,last=day(window.start),day(window["end"])
    return first and last and (first.." - "..last) or nil
end

local function fishEvidence(row)
    local observedCount=0
    local observedWaters,referenceWaters,observedSeasons,referenceSeasons={},{},{},{}
    for _,entry in ipairs(row.referenceWaters or {}) do
        local item=entry.itemEvidence or {}
        local observed=item.verificationStatus=="forever_observed" or
            entry.sourceID=="foreverdb-fishing-observed"
        if observed then observedCount=observedCount+1 end
        local water=waterLabels[item.waterType]
        if water then
            local target=observed and observedWaters or referenceWaters
            target[water]=true
        end
        local season=seasonLabel(item.seasonWindow)
        if season then
            -- Even an observed catch does not independently verify an
            -- exclusive annual season. Treat seasonal windows as references.
            local target=observed and observedSeasons or referenceSeasons
            target[season]=true
        end
    end
    local function choose(verified,other)
        local names={}
        for value in pairs(verified) do names[#names+1]=value end
        if #names>1 then return "Conflicting ForeverDB evidence - review","conflict" end
        if #names==1 then return names[1],"forever" end
        names={}
        for value in pairs(other) do names[#names+1]=value end
        if #names>1 then return "Conflicting reference values - review","conflict" end
        if #names==1 then return names[1],"reference" end
        return nil,nil
    end
    local water,waterOrigin=choose(observedWaters,referenceWaters)
    local season,seasonOrigin=choose(observedSeasons,referenceSeasons)
    return {observed=observedCount,water=water,waterOrigin=waterOrigin,
        season=season,seasonOrigin=seasonOrigin}
end

function FCM:GatherFishCatchSections(row,expanded)
    if not row or row.kind~="fishing" or not row.itemID or
        not tostring(row.summary or ""):find("^Fish |",1) then return nil end
    local notes=classicFishNotes[tonumber(row.itemID)]
    local evidence=fishEvidence(row)
    local details={}
    local waterAndSeason={}
    if evidence.water then
        waterAndSeason[#waterAndSeason+1]=(evidence.waterOrigin=="forever" and
            "Water (ForeverDB reported): " or "Water (reference): ")..evidence.water
    elseif notes then
        waterAndSeason[#waterAndSeason+1]="Water (Classic): "..notes.water
    else
        waterAndSeason[#waterAndSeason+1]="Ocean / freshwater: not established by current references."
    end
    if evidence.season then
        -- A listed season is not proven by one successful catch.
        waterAndSeason[#waterAndSeason+1]="Season (ForeverDB reference; not verified): "..evidence.season
    elseif notes and notes.season then
        waterAndSeason[#waterAndSeason+1]="Season (Classic): "..notes.season
    else
        waterAndSeason[#waterAndSeason+1]="No verified seasonal restriction documented."
    end
    if evidence.observed>0 then
        waterAndSeason[#waterAndSeason+1]="ForeverDB reports a WoW Forever catch (zone-level only)."
    else
        waterAndSeason[#waterAndSeason+1]="ForeverDB catch verification: not documented."
    end
    waterAndSeason[#waterAndSeason+1]="Exact Forever water/method and seasonal rules require separate evidence."
    details[#details+1]={title="WATER TYPE & SEASON",lines=waterAndSeason}
    local groups={}
    local function addGroup(method)
        method=fishingMethodLabels[method] and method or "unknown"
        local group=groups[method]
        if not group then
            group={count=0,names={},zones={},seenName={},seenZone={}}
            groups[method]=group
        end
        return group
    end
    for _,entry in ipairs(row.referenceWaters or {}) do
        local group=addGroup(entry.type)
        group.count=group.count+1
        local name=type(entry.water.name)=="string" and entry.water.name or ""
        if name~="" and not name:match("^Zone fishing reference:") and
            not name:match("^Open water:") and not group.seenName[name] then
            group.seenName[name]=true
            group.names[#group.names+1]=name
        end
        for _,place in ipairs(entry.water.locations or {}) do
            local zone=place.zone
            if type(zone)=="string" and zone~="" and not group.seenZone[zone:lower()] then
                group.seenZone[zone:lower()]=true
                group.zones[#group.zones+1]=zone
            end
        end
    end
    for _,point in ipairs(row.locations or {}) do
        local method=point.sourceType
        if method and fishingMethodLabels[method] and method~="unknown" then
            -- These are the user's real observations, independent of catalog sources.
            local group=addGroup(method)
            local observed="Personal catch source: "..tostring(point.name or method)
            if not group.seenName[observed] then
                group.seenName[observed]=true
                group.names[#group.names+1]=observed
            end
        end
    end
    local methods={}
    for _,method in ipairs(fishingMethodOrder) do
        local group=groups[method]
        if group then
            table.sort(group.names)
            table.sort(group.zones)
            methods[#methods+1]=fishingMethodLabels[method].." — "..group.count..
                " reference association"..(group.count==1 and "" or "s")
            local nameCount=expanded and #group.names or math.min(2,#group.names)
            for i=1,nameCount do methods[#methods+1]="  "..group.names[i] end
            if #group.names>nameCount then
                methods[#methods+1]="  +"..(#group.names-nameCount).." more named sources"
            end
        end
    end
    if notes then
        for _,name in ipairs(notes.methods or {}) do methods[#methods+1]="Classic: "..name end
    end
    if #methods==0 then methods[1]="No source method documented for this fish." end
    methods[#methods+1]="Catalog and Classic associations are not confirmed Forever drops."
    details[#details+1]={title="Fishing Sources",lines=methods}

    local zones,seen={},{}
    for _,method in ipairs(fishingMethodOrder) do
        local group=groups[method]
        if group then
            for _,zone in ipairs(group.zones) do
                local key=zone:lower()
                if not seen[key] then seen[key]=true;zones[#zones+1]=zone end
            end
        end
    end
    table.sort(zones)
    local limit=expanded and #zones or math.min(#zones,5)
    local zoneLines={}
    for i=1,limit do zoneLines[#zoneLines+1]=zones[i].." (reference)" end
    if #zones>limit then
        zoneLines[#zoneLines+1]="+"..(#zones-limit).." more zones — Show All Details below"
    end
    if #zoneLines==0 then zoneLines[1]="No source-specific zone references documented." end
    details[#details+1]={title="REFERENCE FISHING ZONES",lines=zoneLines}
    if notes and expanded then
        details[#details+1]={title="CLASSIC REFERENCE",lines={
            notes.reference,
            "WoW Forever availability, locations and seasonality require in-game confirmation."
        }}
    end
    return details
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
            {"Forever drop",model.dropStatus}}
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
        local fishSections=self:GatherFishCatchSections(row,expanded)
        if fishSections then
            model.itemType="Fish"
            for _,section in ipairs(fishSections) do
                model.sections[#model.sections+1]=section
            end
            for _,section in ipairs(sections) do
                if section.title=="YOUR GATHERING HISTORY" or section.title=="LOCATION NOTES" or
                    (expanded and (section.title=="PROFESSION SKILL" or
                    section.title=="FISHING SOURCES" or section.title=="REFERENCE SOURCES")) then
                    model.sections[#model.sections+1]=section
                end
            end
            return model
        end
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
