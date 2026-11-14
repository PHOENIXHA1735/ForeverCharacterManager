-- FCM gathering regression harness: no WoW client, external network or SavedVariables needed.
local function eq(actual,expected,context)
    if actual~=expected then error((context or "mismatch")..": "..tostring(actual).." expected "..tostring(expected),2) end
end
local FCM={db={},communityGathering={schema=1,version=2,nodes={}}}
function FCM:Now() return 12345 end
function FCM:Try(fn,...)
    local ok,a,b,c=pcall(fn,...)
    if ok then return a,b,c end
end
assert(loadfile('ForeverCharacterManager/Gathering.lua'))('ForeverCharacterManager',FCM)

eq(FCM:AddGatherNode('mining',37,4590,6780,'Copper Vein','personal'),true,'first discovery')
eq(FCM:AddGatherNode('mining',37,4590,6780,'Copper Vein','personal'),false,'duplicate')
eq(FCM:AddGatherNode('mining',37,-1,6780,'Copper Vein','personal'),false,'invalid coordinate')
eq(FCM:AddGatherNode('mining',37,4590,6780,'Copper|Vein','personal'),false,'invalid node name')
eq(FCM:GatherCounts().mining,1,'local count')
eq(FCM:GatherCounts().personal,1,'personal count')
eq(FCM:GatherNodes('mining')[1].gatherCount,2,'same saved node counts repeated gathers')
eq(FCM:GatherCountLabel(FCM:GatherNodes('mining')[1]),'2 personal gathers','repeat count label')
eq(type(FCM_GatherExport),'table','companion export markers')
local token=next(FCM_GatherExport)
eq(token,'FCMG1|mining|37|4590|6780|Copper Vein','export contains only node fields')

-- GM2's public GetNodesForZone returns packed map coordinates, node ID.
local gm={gmdbs={['Herb Gathering']={__gm2_base_storage={[41]={}}}}}
function gm:GetNodesForZone(zone,kind,all)
    eq(zone,41);eq(kind,'Herb Gathering');eq(all,true)
    return pairs({[2314000000+452100]='257'})
end
function gm:GetNameForNode(kind,id) return kind=='Herb Gathering' and id=='257' and 'Silverleaf' or nil end
_G.GatherMate2=gm
local count=FCM:ImportGatherMate()
eq(count,1,'gm import')
eq(FCM:ImportGatherMate(),0,'idempotent import')
eq(FCM:GatherCounts().herbalism,1,'GM2 herb count')
eq(FCM:GatherCountLabel(FCM:GatherNodes('herbalism')[1]),
    'No personal gathers recorded','imported locations have no invented personal count')
_G.GatherMate2=nil
eq(FCM:GatherCounts().herbalism,1,'import persists without GM2')

FCM.communityGathering.nodes={{kind='mining',mapID=37,x=4590,y=6780,name='Copper Vein'},
  {kind='fishing',mapID=37,x=1234,y=5678,name='School of Fish'},
  {kind='mining',mapID=37,x=100001,y=0,name='Untrusted'}}
eq(FCM:MergeCommunityGathering(),1,'community merge ignores duplicates and rejects invalid')
eq(FCM:MergeCommunityGathering(),0,'community merge idempotent')
eq(FCM:GatherCounts().fishing,1,'fishing counted')
eq(FCM.db.gathering.communityVersion,2,'community version')
eq(FCM:AddGatherNode('fishing',37,1234,5678,'School of Fish','personal'),false,
    'personal confirmation of existing community point is not a duplicate')
eq(FCM_GatherExport['FCMG1|fishing|37|1234|5678|School of Fish'],true,
    'personal confirmation is exportable independently of community data')
eq(FCM:GatherCountLabel(FCM:GatherNodes('fishing')[1]),'1 personal gather',
    'first actual gather of a previously imported location is count one')

-- Preserve older account-wide nodes without retroactively guessing how often
-- they were harvested before this build began recording repeats.
local old={name='Old Herb',x=2500,y=3500,source='personal',personal=true}
FCM.db.gathering.nodes.herbalism[99]={['2500:3500:old herb']=old}
eq(FCM:GatherCountLabel(old),'At least 1 personal gather (older history unknown)',
    'legacy node with no count shows honest lower bound')
eq(FCM:AddGatherNode('herbalism',99,2500,3500,'Old Herb','personal'),false,'legacy repeat')
eq(FCM:GatherCountLabel(old),'At least 2 personal gathers (older history unknown)',
    'legacy repeat advances minimum without claiming exact history')

C_Map={GetBestMapForUnit=function()return 77 end,
    GetPlayerMapPosition=function()return {GetXY=function()return .4421,.7612 end} end}
FCM:GatherEvent('UNIT_SPELLCAST_SENT','player','Peacebloom','cast42',2366)
FCM:GatherEvent('UNIT_SPELLCAST_SUCCEEDED','player','cast42',2366)
eq(FCM:GatherCounts().herbalism,3,'independent herbalism recording')
FCM:GatherEvent('UNIT_SPELLCAST_SENT','player','Peacebloom','cast42b',2366)
FCM:GatherEvent('UNIT_SPELLCAST_SUCCEEDED','player','cast42b',2366)
local foundPeacebloom
for _,node in ipairs(FCM:GatherNodes('herbalism')) do
    if node.name=='Peacebloom' then foundPeacebloom=node end
end
eq(foundPeacebloom.gatherCount,2,'successive successful herb gathers increment saved count')
FCM:GatherEvent('UNIT_SPELLCAST_SENT','player',nil,'cast43',2575)
FCM:GatherEvent('UNIT_SPELLCAST_SUCCEEDED','player','cast43',2575)
eq(FCM:GatherCounts().mining,1,'unknown target must not invent a node')
FCM:GatherEvent('UNIT_SPELLCAST_SENT','player','Fishing','cast44',7620)
FCM:GatherEvent('UNIT_SPELLCAST_SUCCEEDED','player','cast44',7620)
eq(FCM:GatherCounts().fishing,1,'open-water fishing is not a pool')
FCM:GatherEvent('UNIT_SPELLCAST_SENT','player','Rich Thorium Vein','cast45',2575)
FCM:GatherEvent('UNIT_SPELLCAST_INTERRUPTED','player','cast45',2575)
FCM:GatherEvent('UNIT_SPELLCAST_SUCCEEDED','player','cast45',2575)
eq(FCM:GatherCounts().mining,1,'interrupted cast not recorded')

-- Minimap node positions must be based on client-supplied world coordinates,
-- not map percentages or the location of FCM's round launcher icon.
local ax,ay,distance=FCM:GatherMinimapOffset(550,460,540,450,100,nil,false)
eq(math.floor(ax*100+.5),10,'right of player minimap position')
eq(math.floor(ay*100+.5),-10,'above/below map axis orientation')
eq(math.floor(distance+.5),14,'world distance')
eq(FCM:GatherMinimapOffset(550,460,350,450,100,nil,false),nil,'hide distant node')
eq(FCM:GatherMinimapOffset(550,460,540,450,100,nil,false,15),nil,
    'saved marker hidden when within 15 yards of its tracked location')
eq(FCM:GatherMinimapOffset(550,460,540,450,100,nil,false,10)~=nil,true,
    'saved marker still shown outside configured hiding distance')
local rx,ry=FCM:GatherMinimapOffset(550,460,540,460,100,math.pi/2,true)
eq(math.abs(rx)<0.0001,true,'rotating minimap rotates x')
eq(math.floor(ry*100+.5),-10,'rotating minimap rotates y')
local rimTest=FCM:LayoutGatherRimPins({
    {ox=.30,oy=.60,dist=60,name='Peacebloom'},
    {ox=.32,oy=.59,dist=65,name='Silverleaf'},
    {ox=-.50,oy=.20,dist=70,name='Copper Vein'},
    {ox=.12,oy=.10,dist=20,name='Nearby Herb'},
},45)
eq(#rimTest,3,'sixteen direction sectors collapse overlapping distant resources')
eq(rimTest[1].rim,true,'distant herbs move to the minimap compass ring')
eq(rimTest[1].clusterCount,2,'grouped directional nodes retain their count')
eq(math.abs(rimTest[1].ox*rimTest[1].ox+rimTest[1].oy*rimTest[1].oy-1)<.001,
    true,'rim direction uses unit-circle coordinates')
eq(rimTest[3].rim,nil,'nearby node keeps original minimap location')
eq(rimTest[3].ox,.12,'nearby node x remains in map')
eq(#FCM:LayoutGatherRimPins({{ox=.8,oy=.1,dist=70}},0),1,
    'zero distance disables ring relocation')
eq(FCM:GatherNodeIcon('herbalism','Wilted Peacebloom'),
    'Interface\\Icons\\INV_Misc_Flower_02','uncached Wilted Peacebloom has recognizable flower icon')
eq(FCM:GatherNodeIcon('herbalism','Stunted Silverleaf'),
    'Interface\\Icons\\INV_Misc_Herb_10','uncached Silverleaf has recognizable leaf icon')

local function frame()
    local f={shown=true,scripts={}}
    function f:SetSize(width,height) self.width,self.height=width,height end
    function f:SetFrameStrata(value) self.strata=value end
    function f:SetFrameLevel(value) self.level=value end
    function f:SetText(value) self.text=value end
    function f:GetText() return self.text end
    function f:SetScript(event,fn) self.scripts[event]=fn end
    function f:SetPoint(_,anchor,_,x,y) self.anchor,self.x,self.y=anchor,x,y end
    function f:ClearAllPoints() end
    function f:SetParent(parent) self.parent=parent end
    function f:CreateTexture()
        return {SetTexture=function(texture,path)texture.path=path end,
            SetAllPoints=function()end,SetVertexColor=function()end,
            AddMaskTexture=function(texture,mask)texture.mask=mask end}
    end
    function f:CreateMaskTexture()
        return {SetTexture=function(mask,path)mask.path=path end,
            SetAllPoints=function()end}
    end
    function f:Show() self.shown=true end
    function f:Hide() self.shown=false end
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown end
    function f:GetFrameStrata() return 'MEDIUM' end
    function f:GetFrameLevel() return 3 end
    function f:GetWidth() return 180 end
    function f:GetHeight() return 180 end
    function f:GetEffectiveScale()
        if self.scale then return self.scale end
        return self.parent and self.parent:GetEffectiveScale() or 1
    end
    return f
end
Minimap=frame()
CreateFrame=function() return frame() end
GetCVar=function() return '0' end
C_Minimap={GetViewRadius=function() return 100 end}
C_Map={
    GetBestMapForUnit=function() return 1438 end,
    GetPlayerMapPosition=function() return {GetXY=function() return 0.544,0.464 end} end,
    GetWorldPosFromMapPos=function(mapID,p)
        eq(mapID,1438,'same map for player and saved node')
        return 1,{x=p.x*1000,y=p.y*1000}
    end,
    GetMapWorldSize=function() return 1000,1000 end,
}
FCM.db.settings={gatherPins=true,gatherPinHideYards=0}
FCM:AddGatherNode('herbalism',1438,5438,4635,'Wilted Peacebloom','personal')
FCM:AddGatherNode('herbalism',1438,5519,4594,'Wilted Peacebloom','personal')
FCM:AddGatherNode('herbalism',1438,5440,4650,'Silverleaf','personal')
FCM:AddGatherNode('herbalism',1438,5438,4635,'Wilted Peacebloom','personal')
eq(FCM:AddGatherNode('herbalism',1438,5439,4636,'Wilted Peacebloom','personal'),false,
    'same herb from a slightly different standing position counts as same location')
FCM:StartGatherMinimap()
FCM._gatherMiniController.scripts.OnUpdate(FCM._gatherMiniController,0.40)
eq(#FCM._gatherMiniPins,3,'both Peacebloom nodes and Silverleaf render')
eq(FCM._gatherMiniPins[1]:IsShown(),true,'nearest saved node shown')
eq(FCM._gatherMiniPins[1].width,16,'original default marker is 16 pixels')
eq(FCM._gatherMiniPins[1].icon.mask.path,
    'Interface\\AddOns\\ForeverCharacterManager\\Media\\FCM_GatherCircleMask',
    'gathering item icons are clipped with circular mask, not replaced by emblem')
local textures={}
for _,pin in ipairs(FCM._gatherMiniPins) do textures[pin.nodeName]=pin.icon.path end
eq(textures['Wilted Peacebloom']~=textures['Silverleaf'],true,'different herb icons on minimap')
GameTooltip={lines={}}
function GameTooltip:SetOwner() self.lines={} end
function GameTooltip:AddLine(line) self.lines[#self.lines+1]=line end
function GameTooltip:Show() end
function GameTooltip:Hide() end
local countedPin
for _,pin in ipairs(FCM._gatherMiniPins) do
    if pin.nodeX==5438 and pin.nodeY==4635 then countedPin=pin end
end
countedPin.scripts.OnEnter(countedPin)
local hasCount=false
for _,line in ipairs(GameTooltip.lines) do
    if line=='3 personal gathers' then hasCount=true end
end
eq(hasCount,true,'minimap hover tooltip shows repeat and nearby gather count')
eq(FCM_GatherExport['FCMG1|herbalism|1438|5439|4636|Wilted Peacebloom'],nil,
    'nearby repeated casts do not create duplicate contribution nodes')
FCM.db.settings.gatherPinHideYards=15
FCM:UpdateGatherMinimap()
eq(FCM._gatherMiniPins[1]:IsShown(),false,'close-range hiding frees the game tracking dot')
FCM.db.settings.gatherPinHideYards=0
FCM:UpdateGatherMinimap()
eq(FCM._gatherMiniPins[1]:IsShown(),true,'zero-yard setting restores saved marker')
FCM.db.settings.gatherPins=false
FCM:UpdateGatherMinimap()
eq(FCM._gatherMiniPins[1]:IsShown(),false,'off toggle hides FCM nodes')
FCM.db.settings.gatherPins=true
C_Minimap=nil
FCM:UpdateGatherMinimap()
eq(FCM._gatherMiniPins[2]:IsShown(),false,'missing radius API hides rather than misplaces nodes')
Minimap.GetViewRadius=function() return 100 end
FCM:UpdateGatherMinimap()
eq(FCM._gatherMiniPins[2]:IsShown(),true,'Ascension-style Minimap:GetViewRadius fallback')

-- Chest locations require actual loot and a recent chest-like target name.
-- A GameObject source helps distinguish treasure from ordinary corpse loot.
GetNumLootItems=function() return 1 end
GetLootSourceInfo=function() return 'GameObject-0-0-0-0-12345-00001',1 end
GameTooltip.IsShown=function() return true end
GameTooltip.GetOwner=function() return nil end
GameTooltipTextLeft1={GetText=function() return 'Battered Chest' end}
FCM:CaptureTreasureTooltip()
GameTooltip.IsShown=function() return false end
eq(FCM:GatherCounts().treasure,0,'hover alone never marks a treasure chest')
FCM:GatherEvent('LOOT_READY')
eq(FCM:GatherCounts().treasure,1,'loot event records named treasure chest')
eq(FCM:GatherNodes('treasure')[1].name,'Battered Chest','chest name retained')
FCM:GatherEvent('LOOT_OPENED')
eq(FCM:GatherNodes('treasure')[1].gatherCount,1,
    'loot ready and loot opened cannot double count one chest')
GetLootSourceInfo=function() return 'Creature-0-0-0-0-6789-00001',1 end
FCM:RememberTreasureHover('Sturdy Chest')
FCM:GatherEvent('LOOT_READY')
eq(FCM:GatherCounts().treasure,1,'NPC looting cannot create a chest marker')
FCM:RememberTreasureHover('Forest Bear')
GetLootSourceInfo=function() return 'GameObject-0-0-0-0-12345-00001',1 end
FCM:GatherEvent('LOOT_READY')
eq(FCM:GatherCounts().treasure,1,'unnamed treasure or ordinary loot is ignored')
-- Some client builds omit GetLootSourceInfo; actual loot plus a fresh named
-- chest tooltip is the supported conservative fallback on those builds.
GetLootSourceInfo=nil
FCM:RememberTreasureHover('Dusty Coffer')
FCM:GatherEvent('LOOT_READY')
eq(FCM:GatherCounts().treasure,2,'named chest saved when source GUID API is absent')
FCM:UpdateGatherMinimap()
local chestVisible=false
for _,pin in ipairs(FCM._gatherMiniPins) do
    if pin:IsShown() and pin.nodeKind=='treasure' and pin.nodeName=='Battered Chest' then
        chestVisible=true
    end
end
eq(chestVisible,true,'recorded chest appears as a resource pin on minimap')
FCM.db.settings.gatherPinRimYards=45
FCM:AddGatherNode('herbalism',1438,6120,4640,'Far Silverleaf','personal')
FCM:UpdateGatherMinimap()
local ringNode
for _,pin in ipairs(FCM._gatherMiniPins) do
    if pin:IsShown() and pin.nodeName=='Far Silverleaf' then ringNode=pin end
end
eq(ringNode~=nil,true,'distant saved herb receives a ring marker')
eq(ringNode.nodeRim,true,'distant herb marker is placed on outside ring')
eq(ringNode.width,12,'book-style rim icon uses about 75 percent of default size')
eq(math.abs(math.sqrt(ringNode.x*ringNode.x+ringNode.y*ringNode.y)-90)<.01,true,
    'book-style icon is centered on the minimap circumference')
FCM.db.settings.gatherPinRimYards=0
FCM:UpdateGatherMinimap()
local restored
for _,pin in ipairs(FCM._gatherMiniPins) do
    if pin:IsShown() and pin.nodeName=='Far Silverleaf' then restored=pin end
end
eq(restored~=nil,true,'herb remains displayed after disabling rim mode')
eq(restored.nodeRim,nil,'turning rim mode off restores normal in-map placement')
eq(math.abs(restored.x)<90 and math.abs(restored.y)<90,true,
    'restored saved herb is inside the minimap area')
FCM.db.settings.gatherPinRimYards=45
FCM.db.settings.gatherPinSize=24
FCM:UpdateGatherMinimap()
local resized
for _,pin in ipairs(FCM._gatherMiniPins) do
    if pin:IsShown() and pin.nodeName=='Far Silverleaf' then resized=pin end
end
eq(resized.width,18,'rim art scales to 75 percent of selected 24 pixels')
eq(resized.height,18,'height tracks book-style rim marker width')
eq(resized.nodeRim,true,'icon remains on the rim when resized')
eq(math.abs(math.sqrt(resized.x*resized.x+resized.y*resized.y)-90)<.01,true,
    'larger rim icon remains centered on border instead of moving outward')
local inside
for _,pin in ipairs(FCM._gatherMiniPins) do
    if pin:IsShown() and pin.nodeName=='Silverleaf' and not pin.nodeRim then inside=pin end
end
eq(inside.width,24,'nearby in-map icon retains full selected 24-pixel size')
FCM.db.settings.gatherPinSize=10
FCM:UpdateGatherMinimap()
local smaller
for _,pin in ipairs(FCM._gatherMiniPins) do
    if pin:IsShown() and pin.nodeName=='Far Silverleaf' then smaller=pin end
end
eq(smaller.width,10,'rim icon shrinks with user size setting but stays legible')

-- The full world map gets its own overlay, at exact normalized zone
-- coordinates. It must not use minimap view radius or near-hide settings.
WorldMapFrame=nil
UIParent=frame()
FCM:StartGatherWorldMap()
FCM._gatherWorldController.scripts.OnUpdate(FCM._gatherWorldController,.55)
eq(FCM._gatherWorldPins==nil,true,'lazy-loaded world map is optional at login')
local worldCanvas=frame()
worldCanvas.GetWidth=function() return 1000 end
worldCanvas.GetHeight=function() return 800 end
WorldMapFrame=frame()
WorldMapFrame.ScrollContainer={Child=worldCanvas}
local selectedMapID=1438
WorldMapFrame.GetMapID=function() return selectedMapID end
FCM.db.settings.gatherWorldMapPins=true
FCM.db.settings.gatherPinSize=16
FCM.db.settings.gatherPinHideYards=50
FCM._gatherWorldController.scripts.OnUpdate(FCM._gatherWorldController,.55)
local worldFar
for _,pin in ipairs(FCM._gatherWorldPins or {}) do
    if pin:IsShown() and pin.nodeName=='Far Silverleaf' then worldFar=pin end
end
eq(worldFar~=nil,true,'distant herb appears on zone world map without radius cutoff')
eq(worldFar.parent,WorldMapFrame,'world overlay pins parent to visible world-map frame')
eq(worldFar.anchor,worldCanvas,'map pin positions remain attached to scrolling canvas')
eq(worldFar.strata,'FULLSCREEN_DIALOG','overlay draws above Forever map detail tiles')
eq(worldFar.level>worldCanvas:GetFrameLevel(),true,'overlay draws above map layers')
eq(worldFar.x,612,'world map x uses recorded normalized zone coordinate')
eq(math.abs(worldFar.y+371.2)<.001,true,'world map y is measured down from top')
eq(worldFar.width,16,'world map icon uses configured full item size')
eq(worldFar.nodeRim,nil,'world map pins do not use minimap compass')
eq(#FCM._gatherWorldMapControls,5,'map header has master and four gathering-type controls')
eq(FCM._gatherWorldMapControls[1].text,'FCM Pins: On','full world map provides a direct master toggle')
eq(FCM._gatherWorldDiagnostic:find('pins drawn (world overlay)',1,true)~=nil,true,
    'world map debug confirms how many actual icon buttons were drawn')
eq(FCM._gatherWorldDiagnostic:find('first visible: true',1,true)~=nil,true,
    'world map debug verifies first icon is visible according to client')
local importedTeldrassil=false
for _,pin in ipairs(FCM._gatherWorldPins) do
    if pin:IsShown() and pin.nodeName=='Silverleaf' and pin.nodeX==2314 then
        importedTeldrassil=true
    end
end
eq(importedTeldrassil,true,'legacy Teldrassil map 41 imports appear on modern map 1438')
eq(FCM._gatherWorldDiagnostic:find('Map 1438',1,true)~=nil,true,
    'world-map diagnostic records selected client map ID')
-- Real Forever draws the scroll canvas at a different scale than the map
-- frame. Pin offsets must be converted into the host frame's units: otherwise
-- Shadowglen nodes render northwest near Oracle Glade.
worldCanvas.scale=1.5
FCM:UpdateGatherWorldMap()
eq(worldFar.x,918,'scaled world map uses canvas pixels in host units')
eq(math.abs(worldFar.y+556.8)<.001,true,'scaled world map y uses same conversion')
eq(FCM._gatherWorldDiagnostic:find('scales 1.5/1',1,true)~=nil,true,
    'diagnostics show effective canvas/host scales')
worldCanvas.scale=1
FCM:UpdateGatherWorldMap()
eq(worldFar.x,612,'map rescaling reapplies correct coordinates without changing records')
-- Each kind can be hidden from the world map independently of the minimap.
FCM._gatherWorldMapControls[2].scripts.OnClick()
eq(FCM.db.settings.gatherWorldMapKinds.herbalism,false,'Herbs filter saved')
local anyWorldHerb=false
for _,pin in ipairs(FCM._gatherWorldPins) do
    if pin:IsShown() and pin.nodeKind=='herbalism' then anyWorldHerb=true end
end
eq(anyWorldHerb,false,'Herbs Off removes visible world-map herbs without deleting nodes')
eq(FCM:GatherCounts().herbalism>0,true,'filter does not remove saved gathering records')
eq(FCM.db.settings.gatherPins,true,'world-map category filter leaves minimap enabled')
FCM._gatherWorldMapControls[2].scripts.OnClick()
eq(FCM.db.settings.gatherWorldMapKinds.herbalism,true,'Herbs filter can be re-enabled')
local foundRestored=false
for _,pin in ipairs(FCM._gatherWorldPins) do
    if pin:IsShown() and pin.nodeName=='Far Silverleaf' then foundRestored=true end
end
eq(foundRestored,true,'Herbs On restores historic map pins')
FCM._gatherWorldMapControls[1].scripts.OnClick()
eq(FCM.db.settings.gatherWorldMapPins,false,'map header master toggle persists disabled state')
eq(FCM._gatherWorldPins[1]:IsShown(),false,'master map toggle hides overlay immediately')
eq(FCM._gatherWorldMapControls[1].text,'FCM Pins: Off','map header label updates')
FCM._gatherWorldMapControls[1].scripts.OnClick()
eq(FCM.db.settings.gatherWorldMapPins,true,'map header toggle re-enables overlay')
eq(FCM._gatherWorldPins[1]:IsShown(),true,'master map toggle restores visible pins')
FCM:UpdateGatherWorldMap()
eq(worldFar:IsShown(),true,'unchanged map redraw is safely cached')
worldFar.scripts.OnEnter(worldFar)
local foundWorldGatherCount=false
for _,line in ipairs(GameTooltip.lines) do
    if line=='1 personal gather' then foundWorldGatherCount=true end
end
eq(foundWorldGatherCount,true,'world map hover displays personal gather counts')
eq(FCM:AddGatherNode('herbalism',1438,1234,5678,'New Map Herb','personal'),true,
    'gathering can save a fresh location while world map is open')
FCM._gatherWorldController.scripts.OnUpdate(FCM._gatherWorldController,.01)
local newMapHerb=false
for _,pin in ipairs(FCM._gatherWorldPins) do
    if pin:IsShown() and pin.nodeName=='New Map Herb' then newMapHerb=true end
end
eq(newMapHerb,true,'new node refreshes full map immediately without relog')
FCM.db.settings.gatherPins=false
FCM:UpdateGatherWorldMap()
eq(worldFar:IsShown(),true,'world map toggle is independent of minimap pins')
selectedMapID=37
FCM:UpdateGatherWorldMap()
local worldCopper=false
for _,pin in ipairs(FCM._gatherWorldPins) do
    if pin:IsShown() and pin.nodeName=='Copper Vein' then worldCopper=true end
    eq(pin.nodeName~='Far Silverleaf' or not pin:IsShown(),true,
        'old zone herbs are not retained after switching map zones')
end
eq(worldCopper,true,'switching map shows only its saved gathering records')
selectedMapID=41
FCM:UpdateGatherWorldMap()
local personalModernTeldrassil=false
for _,pin in ipairs(FCM._gatherWorldPins) do
    if pin:IsShown() and pin.nodeName=='Far Silverleaf' then
        personalModernTeldrassil=true
    end
end
eq(personalModernTeldrassil,true,
    'modern Teldrassil discoveries appear when client world map selects map 41')
selectedMapID=1438
WorldMapFrame.ScrollContainer=nil
WorldMapButton=frame()
FCM:UpdateGatherWorldMap()
eq(FCM._gatherWorldPins[1].parent,WorldMapFrame,
    'older clients still host visible icons on main map frame')
eq(FCM._gatherWorldPins[1].anchor,WorldMapButton,
    'older clients anchor map points to legacy WorldMapButton canvas')
WorldMapFrame:Hide()
FCM:UpdateGatherWorldMap()
eq(FCM._gatherWorldPins[1]:IsShown(),false,'closing the world map hides FCM overlay')
eq(FCM._gatherWorldDiagnostic:find('map now closed',1,true)~=nil,true,
    'closed map retains last open map diagnostics for screenshot review')
WorldMapFrame:Show()
FCM.db.settings.gatherWorldMapPins=false
FCM:UpdateGatherWorldMap()
eq(FCM._gatherWorldPins[1]:IsShown(),false,'independent world-map setting hides only full-map pins')
print('PASS: FCM gathering counts, circular icons, adjustable sizes, treasure, rim and world-map overlay')
