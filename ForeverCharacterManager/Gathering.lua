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
function FCM:AddGatherNode(kind, mapID, x, y, name, source, gmID, catches)
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
    local function addCatches(node)
        if not catches then return end
        node.catches=type(node.catches)=="table" and node.catches or {}
        for id,count in pairs(catches) do
            node.catches[id]=math.min(1000000000,(tonumber(node.catches[id]) or 0)+count)
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
            addCatches(existing)
            existing.personal=true
            existing.firstSeen=existing.firstSeen or self:Now()
            existing.lastSeen=self:Now()
            self._gatherCounts=nil
            self._gatherMinimapDirty=true
            self._gatherWorldMapDirty=true
            rememberPersonal(kind,mapID,existing.x,existing.y,existing.name)
        end
        return false,existing
    end
    byMap[key]={name=name,x=x,y=y,gmID=number(gmID,1,1000000),
        source=source,personal=(source=="personal"),
        gatherCount=source=="personal" and 1 or nil,
        firstSeen=source=="personal" and self:Now() or nil,
        lastSeen=source=="personal" and self:Now() or nil}
    addCatches(byMap[key])
    self._gatherCounts=nil
    self._gatherMinimapDirty=true
    self._gatherWorldMapDirty=true
    g.stats[source]=(g.stats[source] or 0)+1
    if source=="personal" then
        -- A separate, sanitized SavedVariable lets the companion export ONLY
        -- personally observed points, without parsing the private FCM_DB.
        rememberPersonal(kind,mapID,x,y,name)
    end
    return true,byMap[key]
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
                            gatherCount=n.gatherCount,gatherCountMinimum=n.gatherCountMinimum,catches=n.catches}
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

function FCM:GatherCatchLines(catches)
    local ids,lines={},{}
    for id,count in pairs(type(catches)=="table" and catches or {}) do
        if number(id,1,10000000) and number(count,1,1000000000) then ids[#ids+1]=tonumber(id) end
    end
    table.sort(ids)
    for _,id in ipairs(ids) do
        local name=type(GetItemInfo)=="function" and self:Try(GetItemInfo,id)
        lines[#lines+1]=(name or ("Item "..id)).." x"..(catches[id] or catches[tostring(id)])
    end
    return lines
end

function FCM:GatherNodeIcon(kind,name,catches,referenceID)
    local item=referenceID
    if kind=="fishing" then
        item=nil
        for id,count in pairs(type(catches)=="table" and catches or {}) do
            id=number(id,1,10000000)
            if id and number(count,1,1000000000) and (not item or id<item) then item=id end
        end
    end
    if item then
        local icon=(C_Item and self:Try(C_Item.GetItemIconByID,item)) or
            (type(GetItemIcon)=="function" and self:Try(GetItemIcon,item))
        if icon then return icon end
    end
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
    if kind~="fishing" and lower~="" and type(GetItemInfo)=="function" then
        local _,_,_,_,_,_,_,_,_,icon=self:Try(GetItemInfo,name)
        if type(icon)=="number" or (type(icon)=="string" and icon~="") then
            return icon
        end
    end
    return gatherDefaultIcons[kind] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function gatherWorldPosition(mapID,x,y)
    if not C_Map or type(C_Map.GetWorldPosFromMapPos)~="function" then return nil end
    if not number(mapID,1,200000) or type(x)~="number" or type(y)~="number" or
       x~=x or y~=y or x<0 or x>1 or y<0 or y>1 then return nil end
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
    if continent==nil or type(wx)~="number" or type(wy)~="number" or
       not (math.abs(wx)<math.huge and math.abs(wy)<math.huge) then return nil end
    return continent,wx,wy
end

function FCM:HideGatherMinimapPins()
    for _,pin in ipairs(self._gatherMiniPins or {}) do pin:Hide() end
end

function FCM:GatherDistance(mapID,x,y)
    local current=C_Map and self:Try(C_Map.GetBestMapForUnit,"player")
    local player=current and self:Try(C_Map.GetPlayerMapPosition,current,"player")
    if not player or type(player.GetXY)~="function" then return end
    local px,py=self:Try(player.GetXY,player)
    local a,wx,wy=gatherWorldPosition(current,px,py)
    local b,nx,ny=gatherWorldPosition(mapID,x,y)
    if a and a==b then return math.sqrt((wx-nx)^2+(wy-ny)^2) end
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
    local function showTooltip(btn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(btn,"ANCHOR_LEFT")
        GameTooltip:AddLine(btn.nodeName or "Gathering location",1,0.88,0.35)
        GameTooltip:AddLine((btn.nodeKind or "Node").." | "..
            string.format("%.2f, %.2f",(btn.nodeX or 0)/100,(btn.nodeY or 0)/100),0.75,0.9,1)
        GameTooltip:AddLine(btn.nodePersonal and "Personally gathered" or "Saved reference location",0.65,1,0.65)
        GameTooltip:AddLine(FCM:GatherCountLabel(btn.nodeCount),0.85,1,0.85)
        local node=btn.nodeCount
        if node then
            if FCM.GatherZoneLabel then GameTooltip:AddLine(FCM:GatherZoneLabel(node.mapID)) end
            local distance=FCM:GatherDistance(node.mapID,node.x/10000,node.y/10000)
            GameTooltip:AddLine(distance and string.format("Distance: %.0f yd",distance) or "Distance unavailable")
            for _,line in ipairs(FCM:GatherCatchLines(node.catches)) do GameTooltip:AddLine(line) end
            local ch=FCM.Current and FCM:Current()
            if FCM.GatherResourceSkill then
                for _,line in ipairs(FCM:GatherResourceSkill(node.kind,node.name,ch)) do GameTooltip:AddLine(line) end
            end
            if node.kind=="fishing" then GameTooltip:AddLine("Player standing location") end
        end
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
    end
    pin:SetScript("OnEnter",function(btn) btn.tooltipElapsed=0;btn.gatherHovered=true;showTooltip(btn) end)
    pin:SetScript("OnUpdate",function(btn,elapsed)
        if not btn.gatherHovered then return end
        btn.tooltipElapsed=(btn.tooltipElapsed or 0)+elapsed
        if btn.tooltipElapsed>=0.5 and GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()==btn then
            btn.tooltipElapsed=0;showTooltip(btn)
        end
    end)
    pin:SetScript("OnLeave",function(btn)
        if btn then btn.gatherHovered=nil end
        if GameTooltip then GameTooltip:Hide() end
    end)
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
                                    gatherCountMinimum=node.gatherCountMinimum,catches=node.catches,mapID=mapID}
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
        local texture=self:GatherNodeIcon(node.kind,node.name,node.catches)
        if pin.nodeTexture~=texture then pin.icon:SetTexture(texture);pin.nodeTexture=texture end
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
local worldGatherKinds={
    {key="herbalism",label="Herbs"},
    {key="mining",label="Ore"},
    {key="fishing",label="Fish"},
    {key="treasure",label="Chests"},
}
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

-- These controls live on the game's map itself. The Gathering tab and slash
-- command still offer the same master switch; the four independent filters
-- only affect the world-map display, not saved nodes or the minimap.
function FCM:UpdateGatherWorldMapControls()
    local world=_G.WorldMapFrame
    if not world or type(world.IsShown)~="function" or not world:IsShown() then
        for _,button in ipairs(self._gatherWorldMapControls or {}) do button:Hide() end
        return
    end
    if not self.db or not self.db.settings then return end
    if not self._gatherWorldMapControls then
        local controls={}
        local function control(label,width,previous,callback)
            local button=CreateFrame("Button",nil,world,"UIPanelButtonTemplate")
            button:SetSize(width,22)
            button:SetFrameStrata("FULLSCREEN_DIALOG")
            button:SetFrameLevel(world:GetFrameLevel()+150)
            if previous then
                button:SetPoint("RIGHT",previous,"LEFT",-4,0)
            else
                button:SetPoint("TOPRIGHT",world,"TOPRIGHT",-44,-38)
            end
            button:SetText(label)
            button:SetScript("OnClick",callback)
            controls[#controls+1]=button
            return button
        end
        local master=control("FCM Pins: On",112,nil,function()
            local settings=FCM.db and FCM.db.settings
            if not settings then return end
            settings.gatherWorldMapPins=not (settings.gatherWorldMapPins~=false)
            FCM._gatherWorldMapDirty=true
            FCM:UpdateGatherWorldMap()
            if FCM.UI and FCM.UI.tab=="Gathering" and FCM.Refresh then FCM:Refresh() end
        end)
        for _,entry in ipairs(worldGatherKinds) do
            control(entry.label..": On",81,controls[#controls],function()
                local settings=FCM.db and FCM.db.settings
                if not settings then return end
                settings.gatherWorldMapKinds=settings.gatherWorldMapKinds or {}
                local kinds=settings.gatherWorldMapKinds
                kinds[entry.key]=not (kinds[entry.key]~=false)
                FCM._gatherWorldMapDirty=true
                FCM:UpdateGatherWorldMap()
            end)
        end
        self._gatherWorldMapControls=controls
    end
    local controls=self._gatherWorldMapControls
    controls[1]:SetText(self.db.settings.gatherWorldMapPins~=false and "FCM Pins: On" or "FCM Pins: Off")
    controls[1]:Show()
    for i,entry in ipairs(worldGatherKinds) do
        local enabled=not self.db.settings.gatherWorldMapKinds or
            self.db.settings.gatherWorldMapKinds[entry.key]~=false
        controls[i+1]:SetText(entry.label..(enabled and ": On" or ": Off"))
        controls[i+1]:Show()
    end
end

function FCM:UpdateGatherWorldMap()
    self:UpdateGatherWorldMapControls()
    if not self.db or (self.db.settings and self.db.settings.gatherWorldMapPins==false) then
        self._gatherWorldDiagnostic="World-map gathering pins disabled"
        self:HideGatherWorldMapPins()
        return
    end
    local canvas,mapID,width,height=gatherWorldMapSurface()
    if not canvas then
        self._gatherWorldDiagnostic=self._gatherWorldLastOpenDiagnostic and
            (self._gatherWorldLastOpenDiagnostic.." | map now closed") or tostring(mapID)
        self:HideGatherWorldMapPins()
        return
    end
    local g=self:GatherDB()
    if not g then self:HideGatherWorldMapPins(); return end
    local iconSize=math.max(8,math.min(32,
        math.floor(tonumber(self.db.settings and self.db.settings.gatherPinSize) or 16)))
    local host=_G.WorldMapFrame or canvas
    local canvasScale=type(canvas.GetEffectiveScale)=="function" and canvas:GetEffectiveScale() or 1
    local hostScale=type(host.GetEffectiveScale)=="function" and host:GetEffectiveScale() or 1
    if type(canvasScale)~="number" or canvasScale<=0 then canvasScale=1 end
    if type(hostScale)~="number" or hostScale<=0 then hostScale=1 end
    -- When panning or zooming, the map scroll child's own transform carries
    -- all anchored pins. Rebuilding hundreds of pins every half second is
    -- unnecessary unless the map/geometry/settings/data actually changed.
    if not self._gatherWorldMapDirty and self._gatherWorldRenderedMapID==mapID and
       self._gatherWorldRenderedCanvas==canvas and
       self._gatherWorldRenderedWidth==width and
       self._gatherWorldRenderedHeight==height and
       self._gatherWorldRenderedCanvasScale==canvasScale and
       self._gatherWorldRenderedHostScale==hostScale and
       self._gatherWorldRenderedSize==iconSize then return end
    local matches={}
    local allMatches=0
    for kind,maps in pairs(g.nodes) do
        for _,zone in ipairs(gatherZoneMaps(maps,mapID)) do
            for _,node in pairs(zone) do
                if type(node)=="table" and type(node.name)=="string" and
                   type(node.x)=="number" and type(node.y)=="number" and
                   node.x>=0 and node.x<=10000 and node.y>=0 and node.y<=10000 then
                    allMatches=allMatches+1
                    if not self.db.settings.gatherWorldMapKinds or
                       self.db.settings.gatherWorldMapKinds[kind]~=false then
                        matches[#matches+1]={kind=kind,name=node.name,x=node.x,y=node.y,
                            personal=node.personal,gatherCount=node.gatherCount,
                            gatherCountMinimum=node.gatherCountMinimum,catches=node.catches,mapID=mapID}
                    end
                end
            end
        end
    end
    self._gatherWorldLastOpenDiagnostic="Map "..mapID.." | "..#matches.."/"..allMatches..
        " enabled saved locations | stored map IDs: "..gatherMapIDs(g)..
        " | canvas "..width.."x"..height.." | scales "..canvasScale.."/"..hostScale
    self._gatherWorldDiagnostic=self._gatherWorldLastOpenDiagnostic
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
    -- These buttons must be hosted above Forever's map detail art to be
    -- visible. The host and ScrollContainer.Child can have different effective
    -- scales (the live map showed about 1.5x). WoW SetPoint offsets use the
    -- PIN's scale, so raw canvas offsets shift pins up-left. Convert offsets
    -- to host units and re-evaluate if the canvas zoom scale changes.
    for i=1,maxPins do
        local node=matches[i]
        local pin=self._gatherWorldPins[i]
        if not pin then pin=gatherPin(host);self._gatherWorldPins[i]=pin end
        if pin.nodeCanvas~=canvas or pin.nodeWorldHost~=host then
            pin:SetParent(host)
            pin:SetFrameStrata("FULLSCREEN_DIALOG")
            pin:SetFrameLevel(math.max(host:GetFrameLevel(),canvas:GetFrameLevel())+100)
            pin.nodeCanvas=canvas
            pin.nodeWorldHost=host
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
        local texture=self:GatherNodeIcon(node.kind,node.name,node.catches)
        if pin.nodeTexture~=texture then pin.icon:SetTexture(texture);pin.nodeTexture=texture end
        pin.icon:SetVertexColor(1,1,1,1)
        if pin.clusterBadge then pin.clusterBadge:Hide() end
        pin:ClearAllPoints()
        pin:SetPoint("CENTER",canvas,"TOPLEFT",node.x*width/10000*canvasScale/hostScale,
            -node.y*height/10000*canvasScale/hostScale)
        pin:Show()
        self._gatherWorldPinsVisible=true
    end
    for i=maxPins+1,#self._gatherWorldPins do self._gatherWorldPins[i]:Hide() end
    self._gatherWorldRenderedMapID=mapID
    self._gatherWorldRenderedCanvas=canvas
    self._gatherWorldRenderedWidth=width
    self._gatherWorldRenderedHeight=height
    self._gatherWorldRenderedCanvasScale=canvasScale
    self._gatherWorldRenderedHostScale=hostScale
    self._gatherWorldRenderedSize=iconSize
    self._gatherWorldMapDirty=nil
    local first=self._gatherWorldPins[1]
    local visibility=(maxPins>0 and first and type(first.IsVisible)=="function") and
        tostring(first:IsVisible()) or "unavailable"
    self._gatherWorldLastOpenDiagnostic=self._gatherWorldLastOpenDiagnostic..
        " | "..maxPins.." pins drawn (world overlay) | first visible: "..visibility
    self._gatherWorldDiagnostic=self._gatherWorldLastOpenDiagnostic
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
    if ok then
        self:RememberTreasureHover(name)
        self:RememberFishingHover(name)
    end
end

local lootObjectEvidence

-- A named pool tooltip is evidence of a possible fishing school, not a
-- completed gathering event. Keep it only briefly and require a subsequent
-- Fishing cast and real loot before recording the player's standing location.
function FCM:RememberFishingHover(value)
    if type(issecretvalue)=="function" and issecretvalue(value) then return end
    local name=safeName(value)
    if not name then return end
    local lower=name:lower()
    local known={["oil spill"]=true,["floating wreckage"]=true,
        ["oily blackmouth school"]=true,["firefin snapper school"]=true}
    for _,row in ipairs(self.gatheringReference and self.gatheringReference.resources or {}) do
        if row.category=="fishing" and (row.fishingSourceType=="pool" or row.fishingSourceType=="school" or
           row.fishingSourceType=="wreckage" or row.fishingSourceType=="oil_spill") and lower==row.name:lower() then
            known[lower]=true;break
        end
    end
    if not known[lower] then return end
    self._fishingHover={name=name,at=self:Now()}
end

function FCM:FishingStatus()
    local lines={"Fishing school diagnostics"}
    if self._fishingHover then
        lines[#lines+1]="Tooltip: "..self._fishingHover.name
    else
        lines[#lines+1]="Tooltip: no verified named school"
    end
    if self._fishingCast then
        lines[#lines+1]="Cast: "..self._fishingCast.name
    end
    if self._fishingLastSpellID then
        lines[#lines+1]="Last spell ID: "..tostring(self._fishingLastSpellID)
    end
    if self._fishingLastResult then
        lines[#lines+1]=self._fishingLastResult
    end
    return table.concat(lines," | ")
end

local function isFishingSpell(spellID)
    if spellKinds[spellID]=="fishing" then return true end
    if C_Spell and type(C_Spell.GetSpellName)=="function" then
        local ok,name=pcall(C_Spell.GetSpellName,spellID)
        if ok and type(name)=="string" and name:lower()=="fishing" then return true end
    end
    return false
end

local function playerGatherPosition()
    if not C_Map or type(C_Map.GetBestMapForUnit)~="function" or
       type(C_Map.GetPlayerMapPosition)~="function" then return end
    local mapID=FCM:Try(C_Map.GetBestMapForUnit,"player")
    if not number(mapID,1,200000) then return end
    local pos=FCM:Try(C_Map.GetPlayerMapPosition,mapID,"player")
    if not pos or type(pos.GetXY)~="function" then return end
    local x,y=FCM:Try(pos.GetXY,pos)
    if type(x)~="number" or type(y)~="number" or x<0 or x>1 or y<0 or y>1 then return end
    return mapID,math.floor(x*10000+0.5),math.floor(y*10000+0.5)
end

function FCM:RecordFishingSchoolLoot()
    local cast=self._fishingCast
    if not cast then return end
    -- A single loot event can be raised twice: consume this cast immediately.
    self._fishingCast=nil
    if self:Now()-(cast.at or 0)>120 then
        self._fishingLastResult="Fishing cast expired; no school recorded"
        return
    end
    if not lootObjectEvidence or lootObjectEvidence()~=true or
       (type(IsFishingLoot)=="function" and self:Try(IsFishingLoot)~=true) then
        self._fishingLastResult="Creature loot; no fishing school recorded"
        return
    end
    if not cast.mapID or not cast.x or not cast.y then
        self._fishingLastResult="Fishing map position unavailable; no marker recorded"
        return
    end
    local slotsByID={}
    if type(GetLootSlotLink)=="function" and type(GetLootSlotInfo)=="function" and type(GetNumLootItems)=="function" then
        local slots=number(self:Try(GetNumLootItems),1,1000) or 0
        for slot=1,slots do
            local link=self:Try(GetLootSlotLink,slot)
            local _,_,qty=self:Try(GetLootSlotInfo,slot)
            local id=type(link)=="string" and number(link:match("|Hitem:(%d+)"),1,10000000)
            qty=number(qty,1,1000000)
            if id and qty then slotsByID[slot]={item=id,count=qty} end
        end
    end
    if next(slotsByID) then
        self._fishingLoot={cast=cast,slots=slotsByID}
    end
end

function FCM:ConfirmFishingLootSlot(slot)
    local loot=self._fishingLoot
    local catch=loot and loot.slots[slot]
    if not catch then return end
    if self:Now()-loot.cast.at>120 then self._fishingLoot=nil;return end
    loot.slots[slot]=nil
    local cast=loot.cast
    local catches={[catch.item]=catch.count}
    if not loot.node then
        local _,node=self:AddGatherNode("fishing",cast.mapID,cast.x,cast.y,cast.name,"personal",nil,catches)
        loot.node=node
    else
        local counts=loot.node.catches
        counts[catch.item]=math.min(1000000000,(counts[catch.item] or 0)+catch.count)
        self._gatherMinimapDirty=true
        self._gatherWorldMapDirty=true
    end
    self._fishingLastResult="Recorded "..cast.name.." at player standing location"
    if self.Refresh and self.window and self.window:IsShown() then self:Refresh() end
end

function FCM:StartTreasureTracking()
    if self._treasureTooltipHooked or not GameTooltip or
       type(GameTooltip.HookScript)~="function" then return end
    local ok=pcall(GameTooltip.HookScript,GameTooltip,"OnShow",function()
        FCM:CaptureTreasureTooltip()
    end)
    if ok then
        self._treasureTooltipHooked=true
        -- Some Forever builds populate a game-object tooltip title after
        -- OnShow. Recheck while it is displayed so a named fishing pool is
        -- observed before the next cast; hover alone never creates a node.
        pcall(GameTooltip.HookScript,GameTooltip,"OnUpdate",function(_,elapsed)
            FCM._gatherTooltipElapsed=(FCM._gatherTooltipElapsed or 0)+
                (tonumber(elapsed) or 0)
            if FCM._gatherTooltipElapsed<0.15 then return end
            FCM._gatherTooltipElapsed=0
            FCM:CaptureTreasureTooltip()
        end)
    end
end

lootObjectEvidence=function()
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
        if isFishingSpell(spellID) then
            self._fishingLastSpellID=spellID
            self._fishingCast=nil
            self._fishingLoot=nil
            local hover=self._fishingHover
            if hover and self:Now()-(hover.at or 0)<=8 then
                local mapID,x,y=playerGatherPosition()
                self._fishingHover=nil
                self._fishingCast={name=hover.name,at=self:Now(),guid=castGUID,
                    spellID=spellID,mapID=mapID,x=x,y=y}
                self._fishingLastResult="Cast: "..hover.name.." (awaiting bobber loot)"
            else
                self._fishingLastResult="Fishing cast without a recent named school tooltip"
            end
            return
        end
        if not kind then return end
        if type(issecretvalue)=="function" and issecretvalue(target) then return end
        pending={kind=kind,name=safeName(target),guid=castGUID,spellID=spellID,at=self:Now()}
    elseif event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" then
        local unit,castGUID=...
        if unit=="player" and pending and pending.guid==castGUID then pending=nil end
        if unit=="player" and event=="UNIT_SPELLCAST_FAILED" and
            self._fishingCast and self._fishingCast.guid==castGUID then
            self._fishingCast=nil
            self._fishingLastResult="Fishing cast failed; no school recorded"
        end
    elseif event=="LOOT_SLOT_CLEARED" then
        self:ConfirmFishingLootSlot(...)
    elseif event=="LOOT_CLOSED" then
        self._fishingLoot=nil
    elseif event=="LOOT_READY" or event=="LOOT_OPENED" then
        self:RecordTreasureLoot()
        self:RecordFishingSchoolLoot()
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
