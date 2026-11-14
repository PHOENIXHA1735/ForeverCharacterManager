-- QA4j: container capacity comes from verified item metadata or client tooltip,
-- never from assuming a custom Forever bag's size from its name.
local function eq(actual,expected,context)
    assert(actual==expected,(context or "mismatch")..": "..tostring(actual).." ~= "..tostring(expected))
end

local linen={name="Linen Bag",classID=1,bagSlots=6,quality=1}
local wool={name="Woolen Bag",classID=1,quality=1}
local custom={name="Custom Forever Bag",classID=1,quality=2}
local sword={name="Linen Bag of Tricks",classID=2,bagSlots=99}
local FCM={externalData={items={[4238]=linen,[4240]=wool,[9999]=custom,[9800]=sword}}}
function FCM:Try(fn,...) local ok,a=pcall(fn,...);if ok then return a end end
function FCM:ExpandedItemDetails() return "Additional item information" end
assert(loadfile("ForeverCharacterManager/ItemCatalog.lua"))("ForeverCharacterManager",FCM)
assert(loadfile("ForeverCharacterManager/UI.lua"))("ForeverCharacterManager",FCM)

local count,bag=FCM:ContainerCapacity(4238,linen)
eq(count,6,"imported bagSlots field")
eq(bag,true,"recognized container")
eq(FCM:ItemCategory({name="Travel Pack",category="Bags & containers"}),"container",
    "reference category identifies bags")

C_TooltipInfo={GetItemByID=function(itemID)
    if itemID==4240 then return {lines={{leftText="Woolen Bag"},{leftText="8 Slot Bag"}}} end
    if itemID==9999 then return {lines={{leftText="Binds when equipped"}}} end
end}
count,bag=FCM:ContainerCapacity(4240,wool)
eq(count,8,"read actual client bag tooltip")
eq(bag,true,"client bag recognized")
eq(FCM._containerCapacityCache[4240],8,"successful lookup cached")

count,bag=FCM:ContainerCapacity(9999,custom)
eq(count,nil,"unknown custom bag is not guessed")
eq(bag,true,"unknown size still recognized as bag")
eq(FCM._containerCapacityCache[9999],nil,"missing cache can retry after item loads")
C_TooltipInfo.GetItemByID=function() return {lines={{leftText="24 Slots"}}} end
eq(FCM:ContainerCapacity(9999,custom),24,"a later tooltip load fills bag capacity")

count,bag=FCM:ContainerCapacity(9800,sword)
eq(count,nil,"weapon cannot inherit a bagSlots field")
eq(bag,false,"weapon is not a container")
local malformed={name="Unknown Bag",classID=1,capacity=900}
C_TooltipInfo.GetItemByID=function() return {lines={{leftText="Increases slots by 5"}}} end
count,bag=FCM:ContainerCapacity(9090,malformed)
eq(count,nil,"invalid capacity and text descriptions are ignored")

-- Older Forever clients may not expose C_TooltipInfo; use an invisible
-- standard tooltip and only read the line that actually states bag slots.
C_TooltipInfo=nil
UIParent={}
GetItemInfoInstant=function(itemID)
    if itemID==9998 then return itemID,"Container","Bag","INVTYPE_BAG",0,1,0 end
end
local nativeTip={}
function nativeTip:SetOwner() end
function nativeTip:ClearLines() end
function nativeTip:SetHyperlink(link) self.link=link end
function nativeTip:GetNumLines() return 2 end
function nativeTip:Hide() self.hidden=true end
CreateFrame=function() return nativeTip end
_G.FCMContainerCapacityScannerTextLeft1={GetText=function()return "Custom Pack" end}
_G.FCMContainerCapacityScannerTextLeft2={GetText=function()return "12 Slot Bag" end}
count,bag=FCM:ContainerCapacity(9998,{name="Custom Pack"})
eq(count,12,"invisible standard tooltip works on older client")
eq(bag,true,"GetItemInfoInstant identifies a bag without companion category")
eq(nativeTip.link,"item:9998","scanner requested correct item hyperlink")
eq(nativeTip.hidden,true,"scanner tooltip is hidden afterward")
CreateFrame=nil;UIParent=nil;GetItemInfoInstant=nil
_G.FCMContainerCapacityScannerTextLeft1=nil
_G.FCMContainerCapacityScannerTextLeft2=nil

local details=FCM:CatalogItemDetails(4238,nil)
assert(details:find("Bag capacity: 6 slots",1,true),"capacity appears in item detail text")
local missing=FCM:CatalogItemDetails(9090,nil)
assert(not missing:find("Bag capacity: 900 slots",1,true),"bogus capacity never displayed")

local function label()
    return {SetText=function(self,value) self.value=value end}
end
local preview={icon={SetTexture=function()end},title=label(),kind=label(),stats=label()}
function preview:Show() self.shown=true end
local detailText={ClearAllPoints=function()end,SetPoint=function()end}
local ui=FCM.UI
ui.itemPreview=preview
ui.detailText=detailText
ui.detailChild={}
eq(ui:RenderItemPreview({id="item:4238",title="Linen Bag"}),112,"bag preview active")
eq(preview.stats.value,"Bag capacity: 6 slots","bag size displayed where stats usually appear")
assert(preview.kind.value:find("6 slots",1,true),"bag size also in preview summary")

GameTooltip={SetOwner=function(self,_,side) self.side=side end,
    SetHyperlink=function()end,Show=function()end}
ui:DungeonTooltip({},4238,"left")
eq(GameTooltip.side,"ANCHOR_LEFT","hover tooltip opens outside the detail pane")

print("PASS: FCM bag slot capacity from reference/client, safe unknowns, item preview and hover")
