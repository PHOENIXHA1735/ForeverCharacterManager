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
        if can=="Yes" and ref.yellow and ref.green and ref.gray then
            state=current<ref.yellow and "ORANGE" or current<ref.green and "YELLOW" or current<ref.gray and "GREEN" or "GRAY"
            ups=(state=="GRAY" or (cap and current>=cap)) and "Not expected" or "Possible"
        end
    end
    return {
        "Required skill: "..(threshold or "Unknown").." | Character skill: "..(current or "Unknown")..
            (current and (not age or age<0 or age>86400) and " (stale or undated)" or ""),
        "|cff"..colors[state]..state.."|r | Can gather: "..can.." | Skill-up: "..ups,
        kind=="fishing" and "Pool requirements and fishing skill-ups are evaluated separately; eligibility is unverified." or nil
    },state
end

function FCM:GatherZoneLabel(mapID)
    local info=mapID and C_Map and self:Try(C_Map.GetMapInfo,mapID)
    return type(info)=="table" and type(info.name)=="string" and info.name or "Map "..tostring(mapID or "unknown")
end

local function poolType(name,ref)
    if ref then return ref.fishingSourceType end
    local lower=name:lower()
    if lower=="oil spill" then return "oil_spill" end
    if lower=="floating wreckage" then return "wreckage" end
    if lower=="oily blackmouth school" or lower=="firefin snapper school" then return "school" end
    return "unknown"
end

function FCM:GatherResourceRows(search, kind, ch, sourceType)
    local entries,byKey,refs={},{},{}
    local q=(search or ""):lower()
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
    for _,ref in ipairs(self.gatheringReference and self.gatheringReference.resources or {}) do
        if ref.category=="fishing" then refs[ref.name:lower()]=ref end
        if not sourceType or poolType(ref.name,ref)==sourceType then
            local row=add(ref.category,ref.name)
            if row then row.reference=ref end
        end
    end
    for _,point in ipairs(self:GatherNodes(kind)) do
        local typ=point.kind=="fishing" and poolType(point.name,refs[point.name:lower()])
        local row=(not sourceType or typ==sourceType) and add(point.kind,point.name)
        if row and point.kind=="fishing" and point.personal and type(point.catches)=="table" then
            local recorded=false
            for id,qty in pairs(point.catches) do
                id,qty=tonumber(id),tonumber(qty)
                if id and id>=1 and id<=10000000 and id==math.floor(id) and qty and qty>=1 and qty<=1000000000 and qty==math.floor(qty) then
                    local name=(type(GetItemInfo)=="function" and self:Try(GetItemInfo,id)) or ("Item "..id)
                    local species=add("fishing",name,"item:"..id)
                    species.itemID=id
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
    local filtered={}
    for _,row in ipairs(entries) do
        local matches=row.name:lower():find(q,1,true) or (row.itemID and tostring(row.itemID)==q)
        for _,point in ipairs(row.locations) do
            if point.name:lower():find(q,1,true) or (point.sourceType or ""):gsub("_"," "):find(q,1,true) then matches=true;break end
        end
        if (matches or (row.reference and (row.reference.fishingSourceType or ""):gsub("_"," "):find(q,1,true))) and not row.hidden then filtered[#filtered+1]=row end
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
        row.icon=self:GatherNodeIcon(row.kind,row.name,row.itemID and {[row.itemID]=row.count} or catches,ref and ref.itemID)
        row.summary=row.itemID and ("Fishing | "..row.count.." confirmed caught") or labels[row.kind].." | "..(row.minimum and "At least " or "")..row.count.." personal gathers"
        row.detail=function()
            local lines={(row.icon and ("|T"..tostring(row.icon)..":20:20|t ") or "")..row.name,row.summary}
            for _,line in ipairs(self:GatherResourceSkill(row.kind,row.name,ch)) do lines[#lines+1]=line end
            if ref then
                lines[#lines+1]="Reference confidence: "..ref.verificationStatus
                for _,loot in ipairs(ref.loot or {}) do
                    lines[#lines+1]="Reference association: "..loot.name.." (item "..(loot.itemID or "Unknown")..")"
                end
                if ref.objectID or ref.itemID then
                    lines[#lines+1]="Object ID: "..(ref.objectID or "Unknown").." | Item ID: "..(ref.itemID or "Unknown")
                end
                for _,place in ipairs(ref.locations or {}) do
                    lines[#lines+1]=place.zone.." | Reference: "..place.sourceID
                end
            end
            for _,point in ipairs(row.locations) do
                if row.itemID then
                    lines[#lines+1]=string.format("%s %.2f, %.2f | %s (%s) | x%d",
                        self:GatherZoneLabel(point.mapID),point.x/100,point.y/100,point.name,(point.sourceType or "unknown"):gsub("_"," "),point.quantity)
                else
                lines[#lines+1]=string.format("%s %.2f, %.2f | %s | %s",
                    self:GatherZoneLabel(point.mapID),point.x/100,point.y/100,point.source or "Unknown source",self:GatherCountLabel(point))
                for _,line in ipairs(self:GatherCatchLines(point.catches)) do lines[#lines+1]=line end
                end
            end
            if row.kind=="fishing" then lines[#lines+1]="Saved coordinates are the player's standing location." end
            return table.concat(lines,"\n")
        end
    end
    return entries
end
