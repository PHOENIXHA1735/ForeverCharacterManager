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

-- Treasure objects have no reliable gathering spell on every Forever client.
-- Only treat a named chest-like object as a candidate, and require a loot
-- event before recording it. Merely hovering over a chest never saves a pin.
local treasureLabels={"chest", "coffer", "strongbox", "footlocker", "trunk", "cache", "treasure"}
local function treasureName(value)
    local valid=safeName(value)
    if not valid then return nil end
    local lower=valid:lower()
    for _,word in ipairs(treasureLabels) do
        if lower:find(word,1,true) then return valid end
    end
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
    if not existing and source=="personal" and C_Map and
       type(C_Map.GetMapWorldSize)=="function" then
        -- The cast reports the player's position, not the object's GUID.
        -- Standing a few yards to one side on a later harvest should count
        -- as the same spot, but nearby different herbs never get merged.
        local width,height=self:Try(C_Map.GetMapWorldSize,mapID)
        if type(width)=="number" and width>0 and
           type(height)=="number" and height>0 then
            local closest,closestDistance=nil,8*8
            for _,n in pairs(byMap) do
                if type(n)=="table" and type(n.name)=="string" and
                   n.name:lower()==name:lower() and type(n.x)=="number" and
                   type(n.y)=="number" then
                    local dx=(x-n.x)*width/10000
                    local dy=(y-n.y)*height/10000
                    local squared=dx*dx+dy*dy
                    if squared<closestDistance then
                        closest,closestDistance=n,squared
                    end
                end
            end
            existing=closest
        end
    end
    if existing then
        if source=="personal" then
            -- Old releases recorded discovery but not repeat harvests. Keep
            -- their earlier unknown frequency honest as a minimum count.
            local prior=number(existing.gatherCount,1,1000000000)
            if prior then
                existing.gatherCount=math.min(1000000000,prior+1)
            elseif existing.personal then
                existing.gatherCount=2
                existing.gatherCountMinimum=true
            else
                existing.gatherCount=1
            end
            existing.personal=true
            existing.firstSeen=existing.firstSeen or self:Now()
            existing.lastSeen=self:Now()
            self._gatherCounts=nil
            self._gatherMinimapDirty=true
            self._gatherWorldMapDirty=true
            rememberPersonal(kind,mapID,existing.x,existing.y,existing.name)
        end
        return false
    end
    byMap[key]={name=name,x=x,y=y,gmID=number(gmID,1,1000000),
        source=source,personal=(source=="personal"),
        gatherCount=source=="personal" and 1 or nil,
        firstSeen=source=="personal" and self:Now() or nil,
        lastSeen=source=="personal" and self:Now() or nil}
    self._gatherCounts=nil
    self._gatherMinimapDirty=true
    self._gatherWorldMapDirty=true
    g.stats[source]=(g.stats[source] or 0)+1
    if source=="personal" then
        -- A separate, sanitized SavedVariable lets the companion export ONLY
        -- personally observed points, without parsing the private FCM_DB.
        rememberPersonal(kind,mapID,x,y,name)
    end
    return true
end

function FCM:GatherCountLabel(node)
    if type(node)~="table" then return "No personal gathers recorded" end
    local count=number(node.gatherCount,1,1000000000)
    local minimum=node.gatherCountMinimum==true
    if not count and node.personal then
        count,minimum=1,true
    end
    if not count then return "No personal gathers recorded" end
    return (minimum and "At least " or "")..count..
        (count==1 and " personal gather" or " personal gathers")..
        (minimum and " (older history unknown)" or "")
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
                            x=n.x,y=n.y,source=n.source,personal=n.personal,gmID=n.gmID,
                            gatherCount=n.gatherCount,gatherCountMinimum=n.gatherCountMinimum}
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
function FCM:GatherMinimapOffset(playerX,playerY,nodeX,nodeY,radius,facing,rotating,hideWithinYards)
    if type(playerX)~="number" or type(playerY)~="number" or
       type(nodeX)~="number" or type(nodeY)~="number" or
       type(radius)~="number" or radius<=0 then return nil end
    local dx,dy=playerX-nodeX,playerY-nodeY
    local distance=math.sqrt(dx*dx+dy*dy)
    if type(hideWithinYards)=="number" and hideWithinYards>0 and
       distance<=hideWithinYards then return nil end
    -- Pin centers stay inside the round minimap edge instead of clipping.
    if distance>radius*0.89 then return nil end
    if rotating then
        if type(facing)~="number" then return nil end
        local sin,cos=math.sin(facing),math.cos(facing)
        dx,dy=dx*cos-dy*sin,dx*sin+dy*cos
    end
    return dx/radius,-dy/radius,distance
end

-- Relocate distant historical resource markers to a compact directional
-- compass on the minimap rim. Close markers retain their actual map offsets.
-- Sixteen rim sectors prevent neighboring herbs from covering one another;
-- when several point the same way, display the nearest plus a count.
local function rimAngle(x,y)
    if math.atan2 then return math.atan2(y,x) end
    if x>0 then return math.atan(y/x) end
    if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi) end
    return y>=0 and math.pi/2 or -math.pi/2
end

function FCM:LayoutGatherRimPins(matches,approachYards)
    local cutoff=tonumber(approachYards) or 45
    if cutoff<=0 then return matches end
    local rendered,buckets={},{}
    local sectors=16
    for _,node in ipairs(matches or {}) do
        if type(node.dist)=="number" and node.dist>cutoff and
           type(node.ox)=="number" and type(node.oy)=="number" then
            local angle=rimAngle(node.ox,node.oy)
            local bucket=math.floor(((angle+math.pi)/(math.pi*2))*sectors+0.5)%sectors
            local near=buckets[bucket]
            if near then
                near.clusterCount=(near.clusterCount or 1)+1
            else
                local bearing=(bucket/sectors)*math.pi*2-math.pi
                node.rim=true
                node.clusterCount=1
                node.ox,node.oy=math.cos(bearing),math.sin(bearing)
                buckets[bucket]=node
                rendered[#rendered+1]=node
            end
        else
            rendered[#rendered+1]=node
        end
    end
    return rendered
end

-- Node names can differ from the item they yield (e.g. "Wilted Peacebloom").
-- Prefer the client's native item image and keep a known native texture path
-- for when that item has not yet entered the local item cache.
local herbItemIcons={
    peacebloom={2447,"Interface\\Icons\\INV_Misc_Flower_02"},
    silverleaf={765,"Interface\\Icons\\INV_Misc_Herb_10"},
}
local gatherDefaultIcons={
    herbalism="Interface\\Icons\\INV_Misc_Herb_01",
    mining="Interface\\Icons\\INV_Ore_Copper_01",
    fishing="Interface\\Icons\\INV_Misc_Fish_02",
    treasure="Interface\\Icons\\INV_Misc_Bag_08",
}

function FCM:GatherNodeIcon(kind,name)
    local lower=type(name)=="string" and name:lower() or ""
    if kind=="herbalism" then
        for key,info in pairs(herbItemIcons) do
            if lower:find(key,1,true) then
                local itemID,fallback=info[1],info[2]
                local icon=C_Item and self:Try(C_Item.GetItemIconByID,itemID) or nil
                if not icon and type(GetItemIcon)=="function" then
                    icon=self:Try(GetItemIcon,itemID)
                end
                return icon or fallback
            end
        end
    end
    -- For other herbs and resources, WoW may know the yielded item by name.
    -- This is only a display lookup, never a source of gathering coordinates.
    if lower~="" and type(GetItemInfo)=="function" then
        local _,_,_,_,_,_,_,_,_,icon=self:Try(GetItemInfo,name)
        if type(icon)=="number" or (type(icon)=="string" and icon~="") then
            return icon
        end
    end
    return gatherDefaultIcons[kind] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

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

local function gatherPin(parent)
    parent=parent or Minimap
    local pin=CreateFrame("Button",nil,parent)
    pin:SetSize(16,16)
    pin:SetFrameStrata(parent:GetFrameStrata())
    pin:SetFrameLevel(parent:GetFrameLevel()+6)
    local icon=pin:CreateTexture(nil,"ARTWORK")
    icon:SetAllPoints(pin)
    pin.icon=icon
    -- The client-native alpha mask clips every item image into a real circle;
    -- item icons stay distinct instead of replacing them with one FCM emblem.
    -- Older clients without MaskTexture keep their working unmasked markers.
    if type(pin.CreateMaskTexture)=="function" and
       type(icon.AddMaskTexture)=="function" then
        pcall(function()
            local mask=pin:CreateMaskTexture()
            mask:SetTexture("Interface\\AddOns\\ForeverCharacterManager\\Media\\FCM_GatherCircleMask")
            mask:SetAllPoints(pin)
            icon:AddMaskTexture(mask)
            pin.roundMask=mask
        end)
    end
    if type(pin.CreateFontString)=="function" then
        local badge=pin:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        badge:SetPoint("BOTTOMRIGHT",pin,"BOTTOMRIGHT",4,-3)
        badge:SetTextColor(1,0.9,0.25)
        badge:Hide()
        pin.clusterBadge=badge
    end
    pin:SetScript("OnEnter",function(btn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(btn,"ANCHOR_LEFT")
        GameTooltip:AddLine(btn.nodeName or "Gathering location",1,0.88,0.35)
        GameTooltip:AddLine((btn.nodeKind or "Node").." | "..
            string.format("%.2f, %.2f",(btn.nodeX or 0)/100,(btn.nodeY or 0)/100),0.75,0.9,1)
        GameTooltip:AddLine(btn.nodePersonal and "Personally gathered" or "Saved reference location",0.65,1,0.65)
        GameTooltip:AddLine(FCM:GatherCountLabel(btn.nodeCount),0.85,1,0.85)
        if btn.nodeRim then
            GameTooltip:AddLine("Direction marker | Nearest saved point ~"..
                tostring(math.floor((btn.nodeDistance or 0)+0.5)).." yd away",1,0.84,0.3)
            if (btn.nodeCluster or 1)>1 then
                GameTooltip:AddLine(tostring(btn.nodeCluster-1)..
                    " additional saved spots in this direction",1,0.84,0.3)
            end
        end
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
                            local near=(self.db.settings and self.db.settings.gatherPinHideYards)
                                or 15
                            local ox,oy,dist=self:GatherMinimapOffset(px,py,wx,wy,
                                radius,facing,turning,near)
                            if ox then
                                matches[#matches+1]={ox=ox,oy=oy,dist=dist,kind=kind,
                                    name=node.name,x=node.x,y=node.y,personal=node.personal,
                                    gatherCount=node.gatherCount,
                                    gatherCountMinimum=node.gatherCountMinimum}
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(matches,function(a,b) return a.dist<b.dist end)
    matches=self:LayoutGatherRimPins(matches,
        self.db.settings and self.db.settings.gatherPinRimYards or 45)
    self._gatherMiniPins=self._gatherMiniPins or {}
    local maxPins=math.min(#matches,60)
    local width,height=Minimap:GetWidth()/2,Minimap:GetHeight()/2
    local selectedSize=math.max(8,math.min(32,
        math.floor(tonumber(self.db.settings and self.db.settings.gatherPinSize) or 16)))
    for i=1,maxPins do
        local node=matches[i]
        local pin=self._gatherMiniPins[i]
        if not pin then pin=gatherPin(); self._gatherMiniPins[i]=pin end
        -- Rim markers should resemble the small book symbols on WoW's
        -- perimeter, not sit as detached buttons outside the circle. The
        -- chosen Size still scales both, with edge icons at about 75%.
        local iconSize=node.rim and math.min(selectedSize,
            math.max(10,math.floor(selectedSize*0.75+0.5)))
            or selectedSize
        if pin.nodeIconSize~=iconSize then
            pin:SetSize(iconSize,iconSize)
            pin.nodeIconSize=iconSize
        end
        pin.nodeName,pin.nodeKind=node.name,node.kind
        pin.nodeX,pin.nodeY=node.x,node.y
        pin.nodePersonal=node.personal
        pin.nodeCount=node
        pin.nodeDistance=node.dist
        pin.nodeRim=node.rim
        pin.nodeCluster=node.clusterCount or 1
        if pin.iconName~=node.name or pin.iconKind~=node.kind then
            pin.icon:SetTexture(self:GatherNodeIcon(node.kind,node.name))
            pin.iconName,pin.iconKind=node.name,node.kind
        end
        -- Known item icons retain their original coloration. Other resource
        -- types still remain distinct by their fallback category artwork.
        pin.icon:SetVertexColor(1,1,1,1)
        if pin.clusterBadge then
            if (node.clusterCount or 1)>1 then
                pin.clusterBadge:SetText(tostring(node.clusterCount))
                pin.clusterBadge:Show()
            else pin.clusterBadge:Hide() end
        end
        pin:ClearAllPoints()
        -- Center the icon directly ON the rim: half its art sits in the map
        -- and half outside, just like the book markers in the user screenshot.
        pin:SetPoint("CENTER",Minimap,"CENTER",
            node.ox*width,node.oy*height)
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
        if FCM.CaptureTreasureTooltip then FCM:CaptureTreasureTooltip() end
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

-- The world map is separate from the minimap: it displays every saved
-- location in the selected zone, regardless of distance from the player.
-- Prefer Blizzard's scaled map canvas so pins follow map zoom and panning;
-- older Forever clients can instead expose the legacy WorldMapButton.
local function gatherWorldMapSurface()
    local world=_G.WorldMapFrame
    if not world or type(world.IsShown)~="function" or not world:IsShown() then
        return nil,"World map not open"
    end
    local scroll=world.ScrollContainer
    local canvas=scroll and scroll.Child
    if not canvas and scroll and type(scroll.GetCanvas)=="function" then
        local ok,value=pcall(scroll.GetCanvas,scroll)
        if ok then canvas=value end
    end
    canvas=canvas or world.MapCanvas or _G.WorldMapButton or _G.WorldMapDetailFrame
    if not canvas or type(canvas.GetWidth)~="function" or
       type(canvas.GetHeight)~="function" then return nil,"Map canvas unavailable" end
    local mapID
    if type(world.GetMapID)=="function" then
        local ok,value=pcall(world.GetMapID,world)
        if ok then mapID=value end
    end
    if not mapID and scroll and type(scroll.GetMapID)=="function" then
        local ok,value=pcall(scroll.GetMapID,scroll)
        if ok then mapID=value end
    end
    if not mapID then mapID=world.mapID end
    if not mapID and type(_G.GetCurrentMapAreaID)=="function" then
        local ok,value=pcall(_G.GetCurrentMapAreaID)
        if ok then mapID=value end
    end
    mapID=tonumber(mapID)
    if not mapID or mapID<1 or mapID~=math.floor(mapID) then
        return nil,"Selected map ID unavailable"
    end
    local width,height=canvas:GetWidth(),canvas:GetHeight()
    if type(width)~="number" or type(height)~="number" or
       width<=0 or height<=0 then return nil,"Map canvas has no usable size" end
    return canvas,mapID,width,height
end

-- Some Forever integrations expose Teldrassil as map 41, while the modern
-- player-position API records its zone as 1438. The same saved coordinates
-- must remain readable through either zone-map ID. Avoid converting other
-- zones until a verified mapping is available.
local gatheringMapAliases={[41]={1438},[1438]={41}}
local function gatherZoneMaps(nodes,mapID)
    local result={}
    local wanted={[mapID]=true}
    for _,alias in ipairs(gatheringMapAliases[mapID] or {}) do wanted[alias]=true end
    for id in pairs(wanted) do
        local zone=type(nodes)=="table" and (nodes[id] or nodes[tostring(id)])
        if type(zone)=="table" then result[#result+1]=zone end
    end
    return result
end

local function gatherMapIDs(g)
    local ids={}
    for _,maps in pairs(g.nodes or {}) do
        if type(maps)=="table" then
            for mapID in pairs(maps) do
                local id=tonumber(mapID)
                if id and id>0 then ids[id]=true end
            end
        end
    end
    local sorted={}
    for id in pairs(ids) do sorted[#sorted+1]=id end
    table.sort(sorted)
    local names={}
    for i=1,math.min(#sorted,10) do names[#names+1]=tostring(sorted[i]) end
    if #sorted>10 then names[#names+1]="..." end
    return #sorted>0 and table.concat(names,",") or "none"
end

function FCM:HideGatherWorldMapPins()
    if not self._gatherWorldRenderedMapID and not self._gatherWorldPinsVisible then return end
    for _,pin in ipairs(self._gatherWorldPins or {}) do pin:Hide() end
    self._gatherWorldRenderedMapID=nil
    self._gatherWorldRenderedCanvas=nil
    self._gatherWorldPinsVisible=nil
end

function FCM:UpdateGatherWorldMap()
    if not self.db or (self.db.settings and self.db.settings.gatherWorldMapPins==false) then
        self:HideGatherWorldMapPins()
        return
    end
    local canvas,mapID,width,height=gatherWorldMapSurface()
    if not canvas then
        self._gatherWorldDiagnostic=tostring(mapID)
        self:HideGatherWorldMapPins()
        return
    end
    local g=self:GatherDB()
    if not g then self:HideGatherWorldMapPins(); return end
    local iconSize=math.max(8,math.min(32,
        math.floor(tonumber(self.db.settings and self.db.settings.gatherPinSize) or 16)))
    -- When panning or zooming, the map scroll child's own transform carries
    -- all anchored pins. Rebuilding hundreds of pins every half second is
    -- unnecessary unless the map/geometry/settings/data actually changed.
    if not self._gatherWorldMapDirty and self._gatherWorldRenderedMapID==mapID and
       self._gatherWorldRenderedCanvas==canvas and
       self._gatherWorldRenderedWidth==width and
       self._gatherWorldRenderedHeight==height and
       self._gatherWorldRenderedSize==iconSize then return end
    local matches={}
    for kind,maps in pairs(g.nodes) do
        for _,zone in ipairs(gatherZoneMaps(maps,mapID)) do
            for _,node in pairs(zone) do
                if type(node)=="table" and type(node.name)=="string" and
                   type(node.x)=="number" and type(node.y)=="number" and
                   node.x>=0 and node.x<=10000 and node.y>=0 and node.y<=10000 then
                    matches[#matches+1]={kind=kind,name=node.name,x=node.x,y=node.y,
                        personal=node.personal,gatherCount=node.gatherCount,
                        gatherCountMinimum=node.gatherCountMinimum}
                end
            end
        end
    end
    self._gatherWorldDiagnostic="Map "..mapID.." | "..#matches..
        " matching saved locations | stored map IDs: "..gatherMapIDs(g)..
        " | canvas "..width.."x"..height
    -- Prefer personally discovered nodes if an unusually large imported zone
    -- exceeds the safety cap. This is display-only; no records are deleted.
    table.sort(matches,function(a,b)
        if (a.personal==true)~=(b.personal==true) then return a.personal==true end
        if a.kind~=b.kind then return a.kind<b.kind end
        if a.name~=b.name then return a.name<b.name end
        if a.x~=b.x then return a.x<b.x end
        return a.y<b.y
    end)
    self._gatherWorldPins=self._gatherWorldPins or {}
    local maxPins=math.min(#matches,500)
    for i=1,maxPins do
        local node=matches[i]
        local pin=self._gatherWorldPins[i]
        if not pin then pin=gatherPin(canvas);self._gatherWorldPins[i]=pin end
        if pin.nodeCanvas~=canvas then
            pin:SetParent(canvas)
            pin:SetFrameStrata(canvas:GetFrameStrata())
            pin:SetFrameLevel(canvas:GetFrameLevel()+6)
            pin.nodeCanvas=canvas
        end
        if pin.nodeIconSize~=iconSize then
            pin:SetSize(iconSize,iconSize)
            pin.nodeIconSize=iconSize
        end
        pin.nodeName,pin.nodeKind=node.name,node.kind
        pin.nodeX,pin.nodeY=node.x,node.y
        pin.nodePersonal=node.personal
        pin.nodeCount=node
        pin.nodeRim=nil
        pin.nodeDistance=nil
        pin.nodeCluster=1
        if pin.iconName~=node.name or pin.iconKind~=node.kind then
            pin.icon:SetTexture(self:GatherNodeIcon(node.kind,node.name))
            pin.iconName,pin.iconKind=node.name,node.kind
        end
        pin.icon:SetVertexColor(1,1,1,1)
        if pin.clusterBadge then pin.clusterBadge:Hide() end
        pin:ClearAllPoints()
        pin:SetPoint("CENTER",canvas,"TOPLEFT",node.x*width/10000,-node.y*height/10000)
        pin:Show()
        self._gatherWorldPinsVisible=true
    end
    for i=maxPins+1,#self._gatherWorldPins do self._gatherWorldPins[i]:Hide() end
    self._gatherWorldRenderedMapID=mapID
    self._gatherWorldRenderedCanvas=canvas
    self._gatherWorldRenderedWidth=width
    self._gatherWorldRenderedHeight=height
    self._gatherWorldRenderedSize=iconSize
    self._gatherWorldMapDirty=nil
end

function FCM:StartGatherWorldMap()
    if self._gatherWorldController or type(CreateFrame)~="function" then return end
    -- The world map may not be loaded until the player presses M. A small
    -- passive controller lets that lazy-loaded frame appear without requiring
    -- a reload or modifying Blizzard map scripts.
    local controller=CreateFrame("Frame",nil,UIParent)
    controller.elapsed=0
    controller:SetScript("OnUpdate",function(frame,elapsed)
        frame.elapsed=frame.elapsed+(tonumber(elapsed) or 0)
        if frame.elapsed<0.5 and not FCM._gatherWorldMapDirty then return end
        frame.elapsed=0
        local ok,err=pcall(FCM.UpdateGatherWorldMap,FCM)
        if not ok then
            FCM:HideGatherWorldMapPins()
            if not frame.failureReported then
                frame.failureReported=true
                if FCM.RecordError then FCM:RecordError("Gathering world map",err) end
            end
        else frame.failureReported=nil end
    end)
    self._gatherWorldController=controller
end

function FCM:RememberTreasureHover(value)
    if type(issecretvalue)=="function" and issecretvalue(value) then return end
    local name=treasureName(value)
    if name then self._treasureHover={name=name,at=self:Now()} end
end

function FCM:CaptureTreasureTooltip()
    if not GameTooltip or type(GameTooltip.IsShown)~="function" or
       not GameTooltip:IsShown() then return end
    -- Avoid treating FCM's own saved-node tooltips as new loot candidates.
    local owner=type(GameTooltip.GetOwner)=="function" and GameTooltip:GetOwner() or nil
    if owner and owner.nodeKind then return end
    local label=GameTooltipTextLeft1
    if not label or type(label.GetText)~="function" then return end
    local ok,name=pcall(label.GetText,label)
    if ok then self:RememberTreasureHover(name) end
end

function FCM:StartTreasureTracking()
    if self._treasureTooltipHooked or not GameTooltip or
       type(GameTooltip.HookScript)~="function" then return end
    local ok=pcall(GameTooltip.HookScript,GameTooltip,"OnShow",function()
        FCM:CaptureTreasureTooltip()
    end)
    if ok then self._treasureTooltipHooked=true end
end

local function lootObjectEvidence()
    if type(GetLootSourceInfo)~="function" or type(GetNumLootItems)~="function" then
        return nil -- Older clients can still use the named-tooltip fallback.
    end
    local ok,slots=pcall(GetNumLootItems)
    if not ok or type(slots)~="number" then return nil end
    local seenOther=false
    for slot=1,math.min(math.max(slots,0),40) do
        local got,guid=pcall(GetLootSourceInfo,slot)
        if got and type(issecretvalue)=="function" and issecretvalue(guid) then
            return nil
        end
        if got and type(guid)=="string" then
            if guid:find("GameObject-",1,true)==1 then return true end
            seenOther=true
        end
    end
    if seenOther then return false end
    return nil
end

function FCM:RecordTreasureLoot()
    self:CaptureTreasureTooltip()
    local candidate=self._treasureHover
    if not candidate then return end
    local now=self:Now()
    if now-(candidate.at or 0)>8 or not treasureName(candidate.name) then
        self._treasureHover=nil
        return
    end
    -- When the client provides a source GUID, reject NPC/corpse looting.
    -- A valid chest-like hover followed by an actual loot event is required.
    if lootObjectEvidence()==false then
        self._treasureHover=nil
        return
    end
    self._treasureHover=nil
    if not C_Map or type(C_Map.GetBestMapForUnit)~="function" or
       type(C_Map.GetPlayerMapPosition)~="function" then return end
    local zone=self:Try(C_Map.GetBestMapForUnit,"player")
    if not number(zone,1,200000) then return end
    local pos=self:Try(C_Map.GetPlayerMapPosition,zone,"player")
    if not pos or type(pos.GetXY)~="function" then return end
    local x,y=self:Try(pos.GetXY,pos)
    if type(x)~="number" or type(y)~="number" then return end
    local px,py=math.floor(x*10000+0.5),math.floor(y*10000+0.5)
    local recent=self._treasureLootRecorded
    if recent and now-recent.at<3 and recent.zone==zone and
       recent.name==candidate.name then return end
    self._treasureLootRecorded={at=now,zone=zone,name=candidate.name}
    local added=self:AddGatherNode("treasure",zone,px,py,candidate.name,"personal")
    if added and self.Say then
        self:Say("Saved treasure location: "..candidate.name..". The marker follows your nearby-pin distance setting.")
    end
    if added and self.Refresh and self.window and self.window:IsShown() then self:Refresh() end
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
        -- A chest name reported by the interaction cast can supplement a
        -- tooltip that disappears when the player clicks the game object.
        if type(issecretvalue)~="function" or not issecretvalue(target) then
            self:RememberTreasureHover(target)
        end
        local kind=spellKinds[spellID]
        if not kind then return end
        if type(issecretvalue)=="function" and issecretvalue(target) then return end
        pending={kind=kind,name=safeName(target),guid=castGUID,spellID=spellID,at=self:Now()}
    elseif event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" then
        local unit,castGUID=...
        if unit=="player" and pending and pending.guid==castGUID then pending=nil end
    elseif event=="LOOT_READY" or event=="LOOT_OPENED" then
        self:RecordTreasureLoot()
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
