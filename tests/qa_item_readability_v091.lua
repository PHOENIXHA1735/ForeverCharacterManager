-- QA5: Item Explorer/Global Search readable details and provenance.
local function contains(value,needle,context)
    assert(value:find(needle,1,true),(context or 'missing')..': '..needle)
end
local FCM={
    externalData={items={
        [5503]={name='Clam Meat',classID=7,subclass='Cooking',quality=1,itemLevel=14,
            equipLoc='INVTYPE_NON_EQUIP_IGNORE',sourceProvider='ForeverDB',
            sourceStatus='ForeverDB client item record; availability not guaranteed',
            referenceCheckedAt='2026-11-14T21:29:00Z'},
        [9999]={name='Mystery Material',classID=7,quality=1},
    },dungeons={}},
}
function FCM:ItemRelations(id)
    if id==5503 then return {usedIn={{name='Boiled Clams',profession='Cooking',count=1}},
        producedBy={},owned={},total=0} end
    return {usedIn={},producedBy={},owned={},total=0}
end
function FCM:PriceQuote(id)
    if id==5503 then return {median=36,minBuyout=30,market='forever.normal.alliance.us',
        observedAt='1794685800'} end
end
function FCM:MoneyLabel(amount)
    return tostring(amount)..' copper'
end
function FCM:Try(fn,...)
    local ok,value=pcall(fn,...)
    if ok then return value end
end
local originalDate=date
date=function(_,timestamp)
    assert(timestamp==1794685800,'formatted timestamp must use real epoch')
    return 'Nov 14, 2026 01:10 PM'
end

assert(loadfile('ForeverCharacterManager/ItemCatalog.lua'))('ForeverCharacterManager',FCM)
assert(loadfile('ForeverCharacterManager/FarmingAdvisor.lua'))('ForeverCharacterManager',FCM)
assert(loadfile('ForeverCharacterManager/UI.lua'))('ForeverCharacterManager',FCM)

local details=FCM:ReadableItemDetails(5503,nil)
for _,section in ipairs({'HOW TO GET IT','CRAFTING & USES','YOUR CHARACTERS',
    'AUCTION HOUSE','ITEM FACTS','ABOUT THIS DATA'}) do
    contains(details,section,'readable sections')
end
contains(details,'Giant Clam','documented Forever source')
contains(details,'Seen in Forever','attribution')
contains(details,'foreverdb.net/item/5503','source page')
contains(details,'Boiled Clams','known cooking use')
contains(details,'36 copper','friendly market money')
contains(details,'Nov 14, 2026 01:10 PM','friendly date')
assert(not details:find('1794685800',1,true),'raw Unix market timestamp must not be visible')
assert(not details:find('INVTYPE_NON_EQUIP_IGNORE',1,true),'raw inventory enum must not be visible')
assert(not details:find('Class ID',1,true),'internal class ID should not clutter overview')

local unknown=FCM:ReadableItemDetails(9999,nil)
contains(unknown,'No acquisition location in the imported data yet.','honest unknown sources')
assert(not unknown:find('Giant Clam',1,true),'curated source must be item-specific')

local function label()return {SetText=function(self,v)self.value=v end} end
local preview={icon={SetTexture=function()end},title=label(),kind=label(),stats=label()}
function preview:Show()end
local ui=FCM.UI
ui.itemPreview=preview
ui.detailText={ClearAllPoints=function()end,SetPoint=function()end}
ui.detailChild={}
assert(ui:RenderItemPreview({id='item:5503',title='Clam Meat'})==112,'preview height unchanged')
contains(preview.stats.value,'no combat stats','material-specific quick summary')
assert(not preview.kind.value:find('INVTYPE_',1,true),'technical slot enum removed from header')

local farmLines=table.concat(FCM:FarmAdviceLines(5503,1,nil,3),'\n')
assert(not farmLines:find('1794685800',1,true),'legacy advisor timestamp formatted')
date=originalDate
print('PASS: readable item sections, confirmed source hint, no fabricated rates, friendly dates and preview')
