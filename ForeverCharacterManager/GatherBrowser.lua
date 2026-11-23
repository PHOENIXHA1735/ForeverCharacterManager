local _, FCM = ...
local labels={herbalism="Herbalism",mining="Mining",fishing="Fishing",treasure="Treasure"}
local colors={RED="ff5959",ORANGE="ff9933",YELLOW="ffff00",GREEN="60d860",GRAY="a0a0a0",UNKNOWN="cccccc"}

function FCM:GatherResourceSkill(kind, name, ch)
    local refs=self.gatheringReference and self.gatheringReference.resources or {}
    local ref
    for _,row in ipairs(refs) do
        if row.category==kind and row.name:lower()==name:lower() then ref=row;break end
    end
    local current,stamp,cap
    for key,row in pairs(ch and ch.professions or {}) do
        local label=type(row)=="table" and tostring(row.name or key):lower()
        if label==kind or (kind=="herbalism" and label=="herb gathering") then
            current,stamp,cap=tonumber(row.skill),tonumber(row.scan or ch.professionsStamp),tonumber(row.maxSkill)
            break
        end
    end
    local state,can,ups="UNKNOWN","Unknown","Unknown"
    local threshold=ref and ref.verificationStatus=="reference_reviewed" and ref.orange or nil
    local age=stamp and self:Now()-stamp
    if kind=="fishing" then threshold=nil end
    if threshold and current and age and age>=0 and age<=86400 then
        state=current<threshold and "RED" or "UNKNOWN"
        can=current<threshold and "No" or "Yes"
        if can=="Yes" then
            if ref.gray and current>=ref.gray then
                state="GRAY"
            elseif ref.yellow and current<ref.yellow then
                state="ORANGE"
            elseif ref.green and ref.yellow and ref.gray then
                state=current<ref.green and "YELLOW" or "GREEN"
            end
            if state=="GRAY" or (cap and cap>0 and current>=cap) then ups="Not expected"
            elseif ref.gray and current<ref.gray then ups="Possible" end
        elseif can=="No" then
            ups="Not expected"
        end
    end
    return {
        "Required skill: "..(threshold or "Unknown").." | Character skill: "..(current or "Unknown")..
            (current and (not age or age<0 or age>86400) and " (stale or undated)" or ""),
        threshold and ("Orange / Yellow / Green / Gray: "..table.concat({ref.orange or "Unknown",
            ref.yellow or "Unknown",ref.green or "Unknown",ref.gray or "Unknown"}," / ")) or
            (kind=="fishing" and ("Effective fishing skill: "..tostring(self:GatherEffectiveFishingSkill(ch) or "Unknown"))
                or "Verified difficulty thresholds: Unknown"),
        "|cff"..colors[state]..state.."|r | Can gather: "..can.." | Skill-up: "..ups,
        kind=="fishing" and "Pool requirements and fishing skill-ups are evaluated separately; eligibility is unverified." or nil
    },state,{required=threshold,current=current,can=can,ups=ups,ref=ref,age=age,color=state}
end

function FCM:GatherEffectiveFishingSkill(ch)
    -- The client exposes bonuses for the logged-in character only.
    if not ch or not self.Current or ch~=self:Current() or
       type(GetProfessions)~="function" or type(GetProfessionInfo)~="function" then return end
    local _,_,_,index=self:Try(GetProfessions)
    if not index then return end
    local _,_,level,_,_,_,line,bonus=self:Try(GetProfessionInfo,index)
    if line==356 and type(level)=="number" and level>0 and type(bonus)=="number" then return level+bonus end
end

function FCM:GatherZoneLabel(mapID)
    local info=mapID and C_Map and self:Try(C_Map.GetMapInfo,mapID)
    return type(info)=="table" and type(info.name)=="string" and info.name or "Map "..tostring(mapID or "unknown")
end

local function fishingLabel(name,itemID)
    if not itemID then return "Fishing source" end
    local n=name:lower()
    if n:find("pattern:",1,true) or n:find("recipe:",1,true) or
       n:find("potion",1,true) or n:find("trunk",1,true) or
       n:find("crate",1,true) or n:find("footlocker",1,true) or
       n:find("flotsam",1,true) or n:find("chest",1,true) or
       n:find("scroll",1,true) then return "Fishing loot" end
    if n:match("^raw ") or n:match("^bloated ") or n:match("^oily blackmouth") or
       n:match("^firefin snapper") or n:match("^stonescale eel") or
       n:match("^deviate fish") or n:match("^whimsyfin") or
       n:match("^sagefish") or n:match("catfish$") or
       n:match("^%d+ pound mud snapper$") or
       n=="lightning eel" or n=="darkshore grouper" or
       n=="spotted sunfish" or n=="sickly looking fish" then return "Fish" end
    return "Fishing item"
end

local function limitedLines(lines,limit,expanded,subject)
    if expanded or #lines<=limit then return lines end
    local summary={}
    for i=1,limit do summary[#summary+1]=lines[i] end
    summary[#summary+1]="+"..(#lines-limit).." more "..subject.." (Show All Details below)"
    return summary
end

local function poolType(name,ref)
    if ref then return ref.fishingSourceType end
    local lower=name:lower()
    if lower=="oil spill" then return "oil_spill" end
    if lower=="floating wreckage" then return "wreckage" end
    if lower=="oily blackmouth school" or lower=="firefin snapper school" then return "school" end
    return "unknown"
end

function FCM:GatherResourceRows(search, kind, ch, sourceType, skillRange)
    local entries,byKey,refs={},{},{}
    local q=(search or ""):lower()
    local function sourceAllowed(typ)
        -- The Fish filter is an item-only view across every water/source type.
        -- Construct all known item rows first, then exclude non-fish below.
        if not sourceType or sourceType=='fish' then return true end
        if sourceType=='school_pool' then return typ=='school' or typ=='pool' end
        if sourceType=='spill_wreckage' then return typ=='oil_spill' or typ=='wreckage' end
        return typ==sourceType
    end
    local referenceByName={}
    for _,r in ipairs(self.gatheringReference and self.gatheringReference.resources or {}) do
        referenceByName[r.category..':'..r.name:lower()]=r
    end
    local function add(category,name,identity)
        if not labels[category] or (kind and kind~=category) then return end
        local key=category..":"..(identity or name:lower())
        local row=byKey[key]
        if not row then
            row={id="gather:"..key,name=name,kind=category,locations={},count=0}
            byKey[key]=row;entries[#entries+1]=row
        end
        return row
    end
    local sourceNames={}
    for _,source in ipairs(self.gatheringReference and self.gatheringReference.sources or {}) do
        sourceNames[source.id]=source.name
    end
    local function addFishingItem(id,name)
        local row=add("fishing",name,"item:"..id)
        if row then row.itemID=id end
        return row
    end
    for _,ref in ipairs(self.gatheringReference and self.gatheringReference.resources or {}) do
        if ref.category=="fishing" then refs[ref.name:lower()]=ref end
        local typ=poolType(ref.name,ref)
        if sourceAllowed(typ) then
            if ref.category=="fishing" and #((ref.loot) or {})>0 and (not kind or kind=="fishing") then
                for _,item in ipairs(ref.loot) do
                    if item.itemID then
                        local species=addFishingItem(item.itemID,item.name)
                        species.referenceWaters=species.referenceWaters or {}
                        -- Retain the item-level evidence so display updates when the
                        -- normalized ForeverDB snapshot gains explicit water/season facts.
                        -- A zone-level catch still does not establish an exact pool.
                        species.referenceWaters[#species.referenceWaters+1]={
                            water=ref,sourceID=item.sourceID,type=typ,itemEvidence=item}
                    end
                end
            else
                local row=add(ref.category,ref.name)
                if row then row.reference=ref end
            end
        end
    end
    for _,point in ipairs(self:GatherNodes(kind)) do
        local typ=point.kind=="fishing" and poolType(point.name,refs[point.name:lower()])
        local row=sourceAllowed(typ) and add(point.kind,point.name)
        if row and point.kind=="fishing" and point.personal and type(point.catches)=="table" then
            local recorded=false
            for id,qty in pairs(point.catches) do
                id,qty=tonumber(id),tonumber(qty)
                if id and id>=1 and id<=10000000 and id==math.floor(id) and qty and qty>=1 and qty<=1000000000 and qty==math.floor(qty) then
                    local name=(type(GetItemInfo)=="function" and self:Try(GetItemInfo,id)) or ("Item "..id)
                    local species=addFishingItem(id,name)
                    species.count=species.count+qty
                    species.locations[#species.locations+1]={name=point.name,mapID=point.mapID,x=point.x,y=point.y,quantity=qty,sourceType=typ}
                    recorded=true
                end
            end
            if recorded and row and not row.reference and #row.locations==0 then row.hidden=true end
            if recorded then row=nil end
        end
        if row then
            row.hidden=false
            row.locations[#row.locations+1]=point
            if point.personal then
                row.count=row.count+(tonumber(point.gatherCount) or 1)
                row.minimum=row.minimum or point.gatherCountMinimum or point.gatherCount==nil
            end
        end
    end
    local db=(not sourceType or sourceType=='unknown' or sourceType=='fish') and
        (not kind or kind=="fishing") and self:GatherDB()
    local unattributed=db and db.unattributedFishing
    for id,qty in pairs(type(unattributed)=="table" and unattributed or {}) do
        id,qty=tonumber(id),tonumber(qty)
        if id and id>=1 and id<=10000000 and id==math.floor(id) and qty and qty>=1 and qty<=1000000000 and qty==math.floor(qty) then
            local name=(type(GetItemInfo)=="function" and self:Try(GetItemInfo,id)) or ("Item "..id)
            local species=addFishingItem(id,name)
            species.unattributed=qty
            species.count=species.count+qty
        end
    end
    local filtered={}
    for _,row in ipairs(entries) do
        local function has(value)
            return value~=nil and tostring(value):lower():gsub("_"," "):find(q,1,true)
        end
        local ref=row.reference
        local matches=has(row.name) or has(row.itemID)
        local function inRange(skill)
            if not skillRange then return true end
            if skillRange=="unknown" then return not skill end
            return skill and skill>=skillRange[1] and skill<=skillRange[2]
        end
        local skillMatch=inRange(ref and (ref.minimumSkill or ref.fishingMinimum))
        if ref then
            matches=matches or has(ref.itemID) or has(ref.fishingSourceType)
            for _,src in ipairs(ref.materialSources or {}) do matches=matches or has(src) end
            for _,place in ipairs(ref.locations or {}) do matches=matches or has(place.zone) end
            for _,item in ipairs(ref.loot or {}) do matches=matches or has(item.name) or has(item.itemID) end
        end
        if row.referenceWaters then
            skillMatch=false
            for _,water in ipairs(row.referenceWaters) do
                skillMatch=skillMatch or inRange(water.water.fishingMinimum)
                matches=matches or has(water.water.name) or has(water.type)
                for _,place in ipairs(water.water.locations or {}) do matches=matches or has(place.zone) end
            end
        end
        for _,point in ipairs(row.locations) do
            matches=matches or has(point.name) or has(point.sourceType) or has(self:GatherZoneLabel(point.mapID))
        end
        local fishOnly=sourceType~='fish' or
            (row.kind=='fishing' and row.itemID and fishingLabel(row.name,row.itemID)=='Fish')
        if matches and skillMatch and fishOnly and not row.hidden then filtered[#filtered+1]=row end
    end
    entries=filtered
    table.sort(entries,function(a,b)
        if a.kind==b.kind and a.name~=b.name then return a.name<b.name end
        return a.id<b.id
    end)
    for _,row in ipairs(entries) do
        local ref=row.reference
        local catches={}
        for _,point in ipairs(row.locations) do
            for id,qty in pairs(type(point.catches)=="table" and point.catches or {}) do
                id,qty=tonumber(id),tonumber(qty)
                if id and qty and id>=1 and id<=10000000 and id==math.floor(id) and qty>=1 and qty<=1000000000 then
                    catches[id]=(catches[id] or 0)+qty
                end
            end
        end
        row.icon=self:GatherNodeIcon(row.kind,row.name,row.itemID and {[row.itemID]=row.count} or catches,row.itemID or (ref and ref.itemID))
        row.summary=ref and ref.material and (ref.materialType.." | Item "..tostring(ref.itemID or "Unknown")) or
            (row.kind=="fishing" and (fishingLabel(row.name,row.itemID).." | "..row.count..
                (row.itemID and " confirmed caught" or " personal observations")..
                (row.referenceWaters and " | Catalog" or "")) or
             labels[row.kind].." | "..(row.minimum and "At least " or "")..row.count.." personal gathers")
        row.hasExtraDetails=false
        if ref and #(ref.locations or {})>8 then row.hasExtraDetails=true end
        if ref and ref.material then
            for _,sourceName in ipairs(ref.materialSources or {}) do
                local source=referenceByName[row.kind..":"..sourceName:lower()]
                if source and #((source.locations) or {})>6 then row.hasExtraDetails=true end
            end
        end
        if row.referenceWaters and #row.referenceWaters>6 then row.hasExtraDetails=true end
        if ref and #(ref.sourceIDs or {})>0 then row.hasExtraDetails=true end
        if row.referenceWaters and #row.referenceWaters>0 then row.hasExtraDetails=true end
        row.detail=function(expanded,structured)
            local blocks,sections={},{}
            local function block(title,lines)
                if #lines>0 then
                    if structured then sections[#sections+1]={title=title,lines=lines}
                    else blocks[#blocks+1]=title.."\n"..table.concat(lines,"\n") end
                end
            end
            local main={(row.icon and ("|T"..tostring(row.icon)..":24:24|t ") or "")..row.name,
                row.summary}
            if ref and ref.environment and not ref.material then main[#main+1]=ref.environment end
            blocks[#blocks+1]=table.concat(main,"\n")
            local skillLines={}
            if ref and ref.material then
                skillLines[#skillLines+1]="This is a collected material, not a gatherable node."
                skillLines[#skillLines+1]="Required skill: Depends on source node"
                skillLines[#skillLines+1]="Can gather: See each source below"
                skillLines[#skillLines+1]="Skill-up: Determined by source node"
            elseif row.kind=="fishing" then
                local effective=self:GatherEffectiveFishingSkill(ch)
                skillLines[#skillLines+1]="Your effective Fishing: "..tostring(effective or "Unknown")
                skillLines[#skillLines+1]="Minimum and no-escape skill depend on the water."
                skillLines[#skillLines+1]="RED: below minimum | YELLOW: escapes possible"
                skillLines[#skillLines+1]="GREEN: no escapes expected | UNKNOWN: unverified"
                skillLines[#skillLines+1]="Fishing skill-up chance is separate from escape risk."
            elseif row.kind~="treasure" then
                local _,state,info=self:GatherResourceSkill(row.kind,row.name,ch)
                info=info or {}
                skillLines[#skillLines+1]="Required skill: "..tostring(info.required or "Unknown")
                skillLines[#skillLines+1]="Your "..labels[row.kind]..": "..tostring(info.current or "Unknown")..
                    ((info.current and (not info.age or info.age<0 or info.age>86400)) and " (stale)" or "")
                local can=info.can=="Yes" and "YES" or (info.can=="No" and "NO" or "UNKNOWN")
                local gain=info.ups=="Possible" and "YES - possible" or (info.ups=="Not expected" and "NO" or "UNKNOWN")
                skillLines[#skillLines+1]="Can gather: "..can
                skillLines[#skillLines+1]="Can gain skill: "..gain
                local refSkill=info.ref
                if refSkill then
                    skillLines[#skillLines+1]="Orange: "..tostring(refSkill.orange or "Unknown")..
                        "   Yellow: "..tostring(refSkill.yellow or "Unknown")
                    skillLines[#skillLines+1]="Green: "..tostring(refSkill.green or "Unknown")..
                        "   Gray: "..tostring(refSkill.gray or "Unknown")
                end
                skillLines[#skillLines+1]="Current difficulty: |cff"..(colors[state] or colors.UNKNOWN)..tostring(state).."|r"
            end
            block("PROFESSION SKILL",skillLines)
            if ref and ref.material then
                local sources={}
                local seen={}
                for _,name in ipairs(ref.materialSources or {}) do
                    if not seen[name] then
                        seen[name]=true
                        local source=referenceByName[row.kind..":"..name:lower()]
                        local _,_,info=self:GatherResourceSkill(row.kind,name,ch)
                        local required=source and (source.minimumSkill or source.orange) or nil
                        local eligibility=info and info.can or "Unknown"
                        sources[#sources+1]=name.." - required "..tostring(required or "Unknown")..
                            " - Meets reference node skill: "..eligibility
                    end
                end
                if #sources==0 then sources[1]="Verified source nodes not yet documented" end
                block("SOURCE NODES",sources)
            end
            local function uniqueZones(locations)
                local result,seen={},{}
                for _,place in ipairs(locations or {}) do
                    local zone=place.zone
                    if type(zone)=="string" and zone~="" and not seen[zone:lower()] then
                        seen[zone:lower()]=true
                        result[#result+1]=zone..
                            (place.verificationStatus=="reported_reference" and " (reported)" or "")
                    end
                end
                table.sort(result)
                return result
            end
            if ref and ref.material then
                local derived={}
                for _,name in ipairs(ref.materialSources or {}) do
                    local source=referenceByName[row.kind..":"..name:lower()]
                    local zones=uniqueZones(source and source.locations)
                    derived[#derived+1]=name.." (source node)"
                    if #zones==0 then
                        derived[#derived+1]="  Zones not verified"
                    else
                        for _,line in ipairs(limitedLines(zones,6,expanded,"source zones")) do
                            derived[#derived+1]="  "..line
                        end
                    end
                end
                if #derived>0 then
                    block(row.kind=="herbalism" and "POTENTIAL SOURCE-HERB ZONES" or
                        "POTENTIAL SOURCE-DEPOSIT ZONES",derived)
                end
            else
                local combined={}
                for _,place in ipairs(ref and ref.locations or {}) do combined[#combined+1]=place end
                for _,entry in ipairs(row.referenceWaters or {}) do
                    for _,place in ipairs(entry.water.locations or {}) do combined[#combined+1]=place end
                end
                local places=uniqueZones(combined)
                if #places==0 then places[1]="No verified zone locations yet" end
                block(row.kind=="fishing" and "REPORTED FISHING WATERS" or "REFERENCE ZONES",
                    limitedLines(places,8,expanded,"zones"))
            end
            if ref and ref.material and ref.environment then
                block("HOW IT IS OBTAINED",{ref.environment})
            end
            if row.referenceWaters then
                -- Group repeated provider zone references by source type and
                -- thresholds without fabricating observed fish/loot locations.
                local groups,ordered={},{}
                local effective=self:GatherEffectiveFishingSkill(ch)
                for _,entry in ipairs(row.referenceWaters) do
                    local water=entry.water
                    local min,noEscape=water.fishingMinimum,water.fishingNoGetAways
                    local status="UNKNOWN"
                    if effective and min and effective<min then status="RED"
                    elseif effective and min and noEscape and noEscape>=min then
                        status=effective<noEscape and "YELLOW" or "GREEN"
                    end
                    local isZone=water.name:match("^Zone fishing reference:") or
                        water.name:match("^Open water:")
                    local typ=(entry.type or "unknown"):gsub("_"," ")
                    local key=(isZone and "zone" or water.name)..":"..typ..":"..
                        tostring(min)..":"..tostring(noEscape)..":"..status
                    local group=groups[key]
                    if not group then
                        group={name=isZone and typ.." reference waters" or water.name..
                            " ("..typ..")",minimum=min,noEscape=noEscape,status=status,count=0}
                        groups[key]=group
                        ordered[#ordered+1]=group
                    end
                    group.count=group.count+1
                end
                table.sort(ordered,function(a,b)return a.name<b.name end)
                local waters={}
                for _,group in ipairs(ordered) do
                    local qty=group.count>1 and (" | "..group.count.." references") or ""
                    waters[#waters+1]=group.name..qty..
                        "\n  Minimum: "..tostring(group.minimum or "Unknown")..
                        " | No escape: "..tostring(group.noEscape or "Unknown")..
                        "\n  Your status: |cff"..(colors[group.status] or colors.UNKNOWN)..
                        group.status.."|r"
                end
                if #waters>0 then
                    waters[#waters+1]="Thresholds are reference hints; Forever-specific verification is pending."
                    block("FISHING SOURCES",limitedLines(waters,7,expanded,"source groups"))
                end
            end
            if ref and not ref.material and #((ref.loot) or {})>0 then
                local yields={}
                for _,loot in ipairs(ref.loot) do
                    yields[#yields+1]=loot.name.." (item "..tostring(loot.itemID or "Unknown")..")"
                end
                block("POSSIBLE YIELDS",yields)
            end
            local observations={}
            for _,point in ipairs(row.locations) do
                if row.itemID then
                    observations[#observations+1]=string.format(
                        "%s - %.2f, %.2f | %s | x%d",
                        self:GatherZoneLabel(point.mapID),point.x/100,point.y/100,
                        point.name,point.quantity)
                else
                    observations[#observations+1]=string.format(
                        "%s - %.2f, %.2f | %s",
                        self:GatherZoneLabel(point.mapID),point.x/100,point.y/100,
                        self:GatherCountLabel(point))
                end
            end
            if row.unattributed then observations[#observations+1]="Confirmed catch; pool and location unverified: x"..row.unattributed end
            if #observations==0 then observations[1]="No personal discoveries recorded" end
            block("YOUR GATHERING HISTORY",observations)
            if row.kind=="fishing" and #row.locations>0 then
                block("LOCATION NOTES",{"Map coordinates show the player's standing position, not the pool."})
            end
            local refsOut,seenRef={},{}
            local function addRef(id)
                local name=sourceNames[id] or id
                if name and not seenRef[name] then seenRef[name]=true;refsOut[#refsOut+1]=name end
            end
            for _,id in ipairs(ref and ref.sourceIDs or {}) do addRef(id) end
            for _,entry in ipairs(row.referenceWaters or {}) do addRef(entry.sourceID) end
            if #refsOut>0 and expanded then
                table.sort(refsOut)
                block("REFERENCE SOURCES",refsOut)
            end
            if structured then return sections end
            return table.concat(blocks,"\n\n")
        end
    end
    return entries
end
