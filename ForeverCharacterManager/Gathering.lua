-- FCM Gathering v1: all data lives in FCM_DB, never in GatherMate2's files.
-- GatherMate2 is an optional, read-only, one-time import source.
local _, FCM = ...

local kinds = {herbalism=true, mining=true, fishing=true, treasure=true}
local gmKinds = {herbalism="Herb Gathering", mining="Mining", fishing="Fishing", treasure="Treasure"}
local spellKinds = {[2366]="herbalism", [2575]="mining", [7620]="fishing", [131476]="fishing"}
local pending

local function number(v, min, max)
    local n=tonumber(v)
    if not n or n~=n or n<min or n>max or n~=math.floor(n) then return nil end
    return n
end

local function safeName(value)
    if type(value)~="string" or #value<2 or #value>100 then return nil end
    if value:find("[%c|]") then return nil end
    return value
end

local function exportName(name)
    return (name:gsub("[^%w%-%._ ]", function(c) return string.format("%%%02X",c:byte()) end))
end

local function rememberPersonal(kind,mapID,x,y,name)
    -- A prior community/GatherMate2 observation may later be verified in game.
    -- This independent confirmation should still be available for contribution.
    if type(FCM_GatherExport)~="table" then FCM_GatherExport={} end
    local token="FCMG1|"..kind.."|"..mapID.."|"..x.."|"..y.."|"..exportName(name)
    FCM_GatherExport[token]=true
end

function FCM:GatherDB()
    if not self.db then return nil end
    local g=self.db.gathering
    if type(g)~="table" then
        g={schema=1,nodes={},stats={}}
        self.db.gathering=g
    end
    g.nodes=type(g.nodes)=="table" and g.nodes or {}
    g.stats=type(g.stats)=="table" and g.stats or {}
    return g
end

-- x/y are normalized integer hundredths of a percent (0..10000).
-- A node can be known from several sources; personal discovery is strongest.
function FCM:AddGatherNode(kind, mapID, x, y, name, source, gmID)
    local g=self:GatherDB()
    kind=type(kind)=="string" and kind:lower() or nil
    mapID=number(mapID,1,200000)
    x,y=number(x,0,10000),number(y,0,10000)
    name=safeName(name)
    if not g or not kinds[kind] or not mapID or not x or not y or not name then return false end
    source=source=="personal" and "personal" or (source=="gathermate" and "gathermate" or "community")
    local byKind=g.nodes[kind] or {}
    g.nodes[kind]=byKind
    local byMap=byKind[mapID] or {}
    byKind[mapID]=byMap
    local key=x..":"..y..":"..name:lower()
    local existing=byMap[key]
    if existing then
        if source=="personal" then
            existing.personal=true
            existing.lastSeen=self:Now()
            self._gatherCounts=nil
            rememberPersonal(kind,mapID,x,y,name)
        end
        return false
    end
    byMap[key]={name=name,x=x,y=y,gmID=number(gmID,1,1000000),
        source=source,personal=(source=="personal"),firstSeen=source=="personal" and self:Now() or nil}
    self._gatherCounts=nil
    g.stats[source]=(g.stats[source] or 0)+1
    if source=="personal" then
        -- A separate, sanitized SavedVariable lets the companion export ONLY
        -- personally observed points, without parsing the private FCM_DB.
        rememberPersonal(kind,mapID,x,y,name)
    end
    return true
end

function FCM:GatherNodes(kind, search, maxRows)
    local g=self:GatherDB()
    local rows={}
    local q=type(search)=="string" and search:lower() or ""
    if not g then return rows end
    for category,maps in pairs(g.nodes) do
        if (not kind or category==kind) and type(maps)=="table" then
            for zone,nodes in pairs(maps) do
                for _,n in pairs(nodes) do
                    if type(n)=="table" and (q=="" or (n.name or ""):lower():find(q,1,true)) then
                        rows[#rows+1]={kind=category,mapID=tonumber(zone),name=n.name,
                            x=n.x,y=n.y,source=n.source,personal=n.personal,gmID=n.gmID}
                    end
                end
            end
        end
    end
    table.sort(rows,function(a,b)
        if a.kind~=b.kind then return a.kind<b.kind end
        if a.name~=b.name then return a.name<b.name end
        if a.mapID~=b.mapID then return (a.mapID or 0)<(b.mapID or 0) end
        if a.x~=b.x then return a.x<b.x end
        return a.y<b.y
    end)
    while maxRows and #rows>maxRows do table.remove(rows) end
    return rows
end

function FCM:GatherCounts()
    if self._gatherCounts then return self._gatherCounts end
    local count={herbalism=0,mining=0,fishing=0,treasure=0,personal=0,community=0,gathermate=0}
    local g=self:GatherDB()
    if not g then return count end
    for category,maps in pairs(g.nodes) do
        for _,nodes in pairs(maps) do
            for _,n in pairs(nodes) do
                count[category]=(count[category] or 0)+1
                count[n.source]=(count[n.source] or 0)+1
                if n.personal and n.source~="personal" then count.personal=count.personal+1 end
            end
        end
    end
    self._gatherCounts=count
    return count
end

-- GatherMate2 exposes these read-only methods; no source code or database is
-- redistributed with FCM. Import is explicit so it cannot flood login time.
function FCM:ImportGatherMate()
    local gm=_G.GatherMate2
    if type(gm)~="table" or type(gm.GetNodesForZone)~="function" or
       type(gm.GetNameForNode)~="function" or type(gm.gmdbs)~="table" then
        return nil,"GatherMate2 is not loaded. Install it, import its data, and relog before trying again."
    end
    local added,inspected=0,0
    for kind,gmKind in pairs(gmKinds) do
        local meta=gm.gmdbs[gmKind]
        if type(meta)=="table" then
            local zones={}
            local function addZones(storage)
                if type(storage)~="table" then return end
                for zone,nodes in pairs(storage) do
                    if number(zone,1,200000) and type(nodes)=="table" then zones[zone]=true end
                end
            end
            addZones(meta.__gm2_base_storage or meta)
            for _,storage in pairs(meta.__gm2_storage_map or {}) do addZones(storage) end
            for zone in pairs(zones) do
                local ok,iter,state,start=pcall(gm.GetNodesForZone,gm,zone,gmKind,true)
                if ok and type(iter)=="function" then
                    for coord,id in iter,state,start do
                        local n=number(coord,0,100000000000)
                        if n then
                            local x=math.floor(n/1000000)
                            local y=math.floor(n%1000000/100)
                            local name=FCM:Try(gm.GetNameForNode,gm,gmKind,id)
                            inspected=inspected+1
                            if self:AddGatherNode(kind,zone,x,y,name,"gathermate",id) then added=added+1 end
                        end
                    end
                end
            end
        end
    end
    local g=self:GatherDB()
    g.lastGatherMateImport=self:Now()
    return added,"Imported "..added.." new nodes ("..inspected.." examined)."
end

function FCM:MergeCommunityGathering()
    local community=self.communityGathering
    local g=self:GatherDB()
    if not g or type(community)~="table" or type(community.nodes)~="table" then return 0 end
    local version=number(community.version,0,1000000) or 0
    if version <= (number(g.communityVersion,0,1000000) or 0) then return 0 end
    local added=0
    for _,n in ipairs(community.nodes) do
        if type(n)=="table" and self:AddGatherNode(n.kind,n.mapID,n.x,n.y,n.name,"community") then
            added=added+1
        end
    end
    g.communityVersion=version
    return added
end

-- The client supplies a node name with UNIT_SPELLCAST_SENT on some builds.
-- Missing/secret names are deliberately skipped rather than inventing a node.
function FCM:GatherEvent(event,...)
    if event=="UNIT_SPELLCAST_SENT" then
        local unit,target,castGUID,spellID=...
        if unit~="player" or type(spellID)~="number" then return end
        local kind=spellKinds[spellID]
        if not kind then return end
        if type(issecretvalue)=="function" and issecretvalue(target) then return end
        pending={kind=kind,name=safeName(target),guid=castGUID,spellID=spellID,at=self:Now()}
    elseif event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" then
        local unit,castGUID=...
        if unit=="player" and pending and pending.guid==castGUID then pending=nil end
    elseif event=="UNIT_SPELLCAST_SUCCEEDED" then
        local unit,castGUID,spellID=...
        if unit~="player" or not pending or pending.spellID~=spellID or
           pending.guid~=castGUID then return end
        local found=pending
        pending=nil
        if self:Now()-found.at>20 or not found.name then return end
        -- Fishing in open water is not proof of a fishing pool; record only
        -- an explicitly named school/pool, never any generic fishing catch.
        if found.kind=="fishing" and not found.name:lower():find("school",1,true) and
           not found.name:lower():find("pool",1,true) then return end
        if not C_Map or type(C_Map.GetBestMapForUnit)~="function" or
           type(C_Map.GetPlayerMapPosition)~="function" then return end
        local zone=self:Try(C_Map.GetBestMapForUnit,"player")
        if not number(zone,1,200000) then return end
        local pos=self:Try(C_Map.GetPlayerMapPosition,zone,"player")
        if not pos then return end
        local xx,yy
        -- Try returns multiple values; avoid relying on a secret return.
        xx,yy=self:Try(pos.GetXY,pos)
        if type(xx)~="number" or type(yy)~="number" then return end
        local added=self:AddGatherNode(found.kind,zone,math.floor(xx*10000+0.5),
            math.floor(yy*10000+0.5),found.name,"personal")
        if added and self.Refresh and self.window and self.window:IsShown() then self:Refresh() end
    end
end
