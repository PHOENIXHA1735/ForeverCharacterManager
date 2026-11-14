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
            self._gatherMinimapDirty=true
            rememberPersonal(kind,mapID,x,y,name)
        end
        return false
    end
    byMap[key]={name=name,x=x,y=y,gmID=number(gmID,1,1000000),
        source=source,personal=(source=="personal"),firstSeen=source=="personal" and self:Now() or nil}
    self._gatherCounts=nil
    self._gatherMinimapDirty=true
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

-- Translate world-space node and player positions into offsets from the
-- minimap center. C_Minimap.GetViewRadius supplies the visible radius in
-- world units; map-coordinate percentages alone cannot provide that scale.
-- This pure helper also covers rotating minimaps, and can be regression-tested
-- without starting a WoW client.
function FCM:GatherMinimapOffset(playerX,playerY,nodeX,nodeY,radius,facing,rotating)
    if type(playerX)~="number" or type(playerY)~="number" or
       type(nodeX)~="number" or type(nodeY)~="number" or
       type(radius)~="number" or radius<=0 then return nil end
    local dx,dy=playerX-nodeX,playerY-nodeY
    local distance=math.sqrt(dx*dx+dy*dy)
    -- Pin centers stay inside the round minimap edge instead of clipping.
    if distance>radius*0.89 then return nil end
    if rotating then
        if type(facing)~="number" then return nil end
        local sin,cos=math.sin(facing),math.cos(facing)
        dx,dy=dx*cos-dy*sin,dx*sin+dy*cos
    end
    return dx/radius,-dy/radius,distance
end

local gatherPinColors={
    herbalism={0.48,1,0.45}, mining={1,0.83,0.35},
    fishing={0.45,0.78,1}, treasure={1,0.55,0.4},
}

local function gatherWorldPosition(mapID,x,y)
    if not C_Map or type(C_Map.GetWorldPosFromMapPos)~="function" then return nil end
    local vec=type(CreateVector2D)=="function" and CreateVector2D(x,y) or {x=x,y=y}
    local ok,continent,pos=pcall(C_Map.GetWorldPosFromMapPos,mapID,vec)
    if not ok or not pos then return nil end
    local wx,wy=pos.x,pos.y
    if type(wx)~="number" or type(wy)~="number" then
        if type(pos.GetXY)=="function" then
            local got,a,b=pcall(pos.GetXY,pos)
            if got then wx,wy=a,b end
        end
    end
    if type(wx)~="number" or type(wy)~="number" then return nil end
    return continent,wx,wy
end

function FCM:HideGatherMinimapPins()
    for _,pin in ipairs(self._gatherMiniPins or {}) do pin:Hide() end
end

local function gatherPin(index)
    local pin=CreateFrame("Button",nil,Minimap)
    pin:SetSize(13,13)
    pin:SetFrameStrata(Minimap:GetFrameStrata())
    pin:SetFrameLevel(Minimap:GetFrameLevel()+6)
    local icon=pin:CreateTexture(nil,"ARTWORK")
    icon:SetTexture("Interface\\AddOns\\ForeverCharacterManager\\Media\\FCM_Emblem")
    icon:SetAllPoints(pin)
    pin.icon=icon
    pin:SetScript("OnEnter",function(btn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(btn,"ANCHOR_LEFT")
        GameTooltip:AddLine(btn.nodeName or "Gathering location",1,0.88,0.35)
        GameTooltip:AddLine((btn.nodeKind or "Node").." | "..
            string.format("%.2f, %.2f",(btn.nodeX or 0)/100,(btn.nodeY or 0)/100),0.75,0.9,1)
        GameTooltip:AddLine(btn.nodePersonal and "Personally gathered" or "Saved reference location",0.65,1,0.65)
        GameTooltip:AddLine("Previously reported; spawn not guaranteed",0.9,0.85,0.7)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    pin:Hide()
    return pin
end

-- Only the current map and locations inside the minimap's actual world-space
-- radius receive markers. No GatherMate2 tables are read after import.
function FCM:UpdateGatherMinimap()
    if not self.db or not Minimap or not Minimap:IsShown() or
       (self.db.settings and self.db.settings.gatherPins==false) then
        self:HideGatherMinimapPins()
        return
    end
    if not C_Map or type(C_Map.GetBestMapForUnit)~="function" or
       type(C_Map.GetPlayerMapPosition)~="function" then
        self:HideGatherMinimapPins()
        return
    end
    local mapID=self:Try(C_Map.GetBestMapForUnit,"player")
    local pos=mapID and self:Try(C_Map.GetPlayerMapPosition,mapID,"player")
    if not pos or type(pos.GetXY)~="function" then
        self:HideGatherMinimapPins()
        return
    end
    local x,y=self:Try(pos.GetXY,pos)
    -- Ascension-based clients may expose Minimap:GetViewRadius(), while newer
    -- retail-derived clients expose C_Minimap.GetViewRadius(). Both report
    -- actual yards, unlike fixed zoom-table guesses.
    local radius=type(Minimap.GetViewRadius)=="function" and
        self:Try(Minimap.GetViewRadius,Minimap) or nil
    if type(radius)~="number" and C_Minimap and
       type(C_Minimap.GetViewRadius)=="function" then
        radius=self:Try(C_Minimap.GetViewRadius)
    end
    if type(x)~="number" or type(y)~="number" or
       type(radius)~="number" or radius<=0 then
        self:HideGatherMinimapPins()
        return
    end
    local continent,px,py=gatherWorldPosition(mapID,x,y)
    if not px then self:HideGatherMinimapPins(); return end
    local turning=(type(GetCVar)=="function" and GetCVar("rotateMinimap")=="1") or
        (C_CVar and type(C_CVar.GetCVar)=="function" and C_CVar.GetCVar("rotateMinimap")=="1")
    local facing=turning and type(GetPlayerFacing)=="function" and GetPlayerFacing() or nil
    if turning and type(facing)~="number" then self:HideGatherMinimapPins(); return end

    local g=self:GatherDB()
    local matches={}
    local worldW,worldH
    if type(C_Map.GetMapWorldSize)=="function" then
        worldW,worldH=self:Try(C_Map.GetMapWorldSize,mapID)
    end
    for kind,maps in pairs(g.nodes) do
        local nodes=type(maps)=="table" and (maps[mapID] or maps[tostring(mapID)])
        if type(nodes)=="table" then
            for _,node in pairs(nodes) do
                if type(node)=="table" and type(node.x)=="number" and
                   type(node.y)=="number" and type(node.name)=="string" then
                    local nx,ny=node.x/10000,node.y/10000
                    -- Coarse check avoids world-position API calls for the
                    -- many distant nodes in a large imported zone database.
                    local close=true
                    if type(worldW)=="number" and worldW>0 then
                        close=math.abs(nx-x)*worldW<=radius*1.1
                    end
                    if close and type(worldH)=="number" and worldH>0 then
                        close=math.abs(ny-y)*worldH<=radius*1.1
                    end
                    if close then
                        local nodeContinent,wx,wy=gatherWorldPosition(mapID,nx,ny)
                        if wx and nodeContinent==continent then
                            local ox,oy,dist=self:GatherMinimapOffset(px,py,wx,wy,radius,facing,turning)
                            if ox then
                                matches[#matches+1]={ox=ox,oy=oy,dist=dist,kind=kind,
                                    name=node.name,x=node.x,y=node.y,personal=node.personal}
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(matches,function(a,b) return a.dist<b.dist end)
    self._gatherMiniPins=self._gatherMiniPins or {}
    local maxPins=math.min(#matches,60)
    local width,height=Minimap:GetWidth()/2,Minimap:GetHeight()/2
    for i=1,maxPins do
        local node=matches[i]
        local pin=self._gatherMiniPins[i]
        if not pin then pin=gatherPin(i); self._gatherMiniPins[i]=pin end
        pin.nodeName,pin.nodeKind=node.name,node.kind
        pin.nodeX,pin.nodeY=node.x,node.y
        pin.nodePersonal=node.personal
        local tint=gatherPinColors[node.kind] or {1,1,1}
        pin.icon:SetVertexColor(tint[1],tint[2],tint[3],1)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER",Minimap,"CENTER",node.ox*width,node.oy*height)
        pin:Show()
    end
    for i=maxPins+1,#self._gatherMiniPins do self._gatherMiniPins[i]:Hide() end
    self._gatherMinimapDirty=nil
end

function FCM:StartGatherMinimap()
    if self._gatherMiniController or type(CreateFrame)~="function" or not Minimap then return end
    local controller=CreateFrame("Frame",nil,Minimap)
    controller.elapsed=0
    controller:SetScript("OnUpdate",function(frame,elapsed)
        frame.elapsed=frame.elapsed+(tonumber(elapsed) or 0)
        if frame.elapsed<0.35 and not FCM._gatherMinimapDirty then return end
        frame.elapsed=0
        -- Future client builds may restrict map calls during transitions.
        -- Keep the rest of the addon running if a display update fails.
        local ok,err=pcall(FCM.UpdateGatherMinimap,FCM)
        if not ok then
            FCM:HideGatherMinimapPins()
            if not frame.failureReported then
                frame.failureReported=true
                if FCM.RecordError then FCM:RecordError("Gathering minimap",err) end
            end
        else frame.failureReported=nil end
    end)
    self._gatherMiniController=controller
    self._gatherMinimapDirty=true
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
