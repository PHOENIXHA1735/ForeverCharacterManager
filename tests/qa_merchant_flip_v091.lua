-- Read-only merchant flip and bag-vs-vendor guidance: actual purchase cost,
-- faction AH cut, user-selected margin, source freshness and tradeability.
local now=os.time()
local price={median=1150,minBuyout=1000,quantity=90,soldPerDay=9,
    market="forever.normal.alliance.us",observedAt=tostring(now),observedUnix=now,
    source="AHledgerAPI",snapshot=false}
local ch={faction="Alliance",name="Frosty",bags={}}
local FCM={db={settings={flipMinProfitPct=30}},externalData={items={}}}
function FCM:PriceQuote(id,character)
    assert(id==1001 and character==ch,"market quote must match the current character")
    return price
end
function FCM:MoneyLabel(c) return string.format("%dc",math.floor((c or 0)+0.5)) end
function FCM:Current() return ch end
function FCM:RecipeForOutput() return nil end
function FCM:KnownNamesForRecipe() return {} end
assert(loadfile("ForeverCharacterManager/ItemDecisions.lua"))("ForeverCharacterManager",FCM)

local d=FCM:AHFlipDecision(1001,ch,500,"merchant",false)
assert(d.status=="candidate" and d.net==950 and d.profit==450 and d.roi==90,
    "merchant ROI subtracts 5% AH fee before comparing with purchase price")
assert(FCM:AHFlipDecision(1001,ch,800,"merchant",false).status=="below_threshold",
    "expensive vendor stock is not a flip at 30% threshold")
FCM.db.settings.flipMinProfitPct=15
assert(FCM:AHFlipDecision(1001,ch,800,"merchant",false).status=="candidate",
    "adjustable margin changes recommendations")
FCM.db.settings.flipMinProfitPct=30
assert(FCM:AHFlipDecision(1001,ch,500,"merchant",true).status=="bound",
    "bound stock is never a flip")
assert(FCM:AHFlipDecision(1001,ch,100,"bag",nil).status=="binding_unknown",
    "unverified binding must not be called auctionable")
assert(FCM:AHFlipDecision(1001,ch,100,"bag",true).status=="bound",
    "bound items in bags are excluded")
assert(FCM:AHFlipDecision(1001,ch,nil,"merchant",false).status=="no_cost",
    "no invented merchant cost")
price.soldPerDay=0
assert(FCM:AHFlipDecision(1001,ch,500,"merchant",false).status=="low_demand",
    "no reported buyers: do not assert a profitable flip")
price.soldPerDay=9;price.minBuyout=nil
assert(FCM:AHFlipDecision(1001,ch,500,"merchant",false).status=="no_listing",
    "median alone cannot justify a flip")
price.minBuyout=1000;price.snapshot=true
assert(FCM:AHFlipDecision(1001,ch,500,"merchant",false).status=="stale",
    "bundled snapshots cannot trigger a purchase")
price.snapshot=false;price.observedUnix=now-4*3600
assert(FCM:AHFlipDecision(1001,ch,500,"merchant",false).status=="stale",
    "outdated local or public observations are suppressed")
price.observedUnix=now

local owner={GetName=function() return "MerchantItem3ItemButton" end}
local tooltip={GetOwner=function() return owner end,GetItem=function() return nil end,lines={}}
function tooltip:AddLine(line) self.lines[#self.lines+1]=line end
MerchantFrame={page=2,selectedTab=1,IsShown=function() return true end}
MERCHANT_ITEMS_PER_PAGE=10
GetMerchantItemLink=function(index)
    return index==13 and "|cff00ff00|Hitem:1001:0|h[Market Meat]|h|r" or nil
end
C_MerchantFrame={GetItemInfo=function(index)
    return {price=200,stackCount=5,numAvailable=10,isPurchasable=true,hasExtendedCost=false}
end}
local offer=FCM:MerchantOfferAtTooltip(1001,tooltip)
assert(offer and offer.index==13 and offer.pricePerUnit==40,
    "read real page-indexed merchant price and divide by purchase bundle")
assert(FCM:MerchantOfferAtTooltip(9999,tooltip)==nil,
    "merchant button does not price an unrelated item")
C_MerchantFrame.GetItemInfo=function() return {price=200,stackCount=5,hasExtendedCost=true} end
assert(FCM:MerchantOfferAtTooltip(1001,tooltip)==nil,
    "mixed-currency purchases never get a gold-only profit calculation")
C_MerchantFrame.GetItemInfo=function() return {price=200,stackCount=5,numAvailable=10} end

-- Verify rendered tooltip verdicts, including the bag-versus-vendor distinction.
C_Item={GetItemInfo=function()
    return "Market Meat","|Hitem:1001|h",1,1,1,"Food","Food",20,"",0,100,7,0,0
end}
TooltipDataProcessor={AddTooltipPostCall=function(_,fn) FCM.tooltipPost=fn end}
Enum={TooltipDataType={Item=1}}
assert(loadfile("ForeverCharacterManager/Tooltips.lua"))("ForeverCharacterManager",FCM)
FCM.tooltipPost(tooltip,{id=1001})
assert(table.concat(tooltip.lines,"\n"):find("POTENTIAL FLIP",1,true),
    "merchant hover shows actual purchase-cost flip advice")
MerchantFrame.IsShown=function() return false end
local bagOwner={GetBagID=function() return 0 end,GetID=function() return 2 end}
local bagTooltip={GetOwner=function() return bagOwner end,AddLine=tooltip.AddLine,lines={}}
C_Container={GetContainerItemInfo=function(bag,slot)
    return {itemID=1001,stackCount=4,isBound=false}
end}
FCM.tooltipPost(bagTooltip,{id=1001})
local lines=table.concat(bagTooltip.lines,"\n")
assert(lines:find("BAG: AH VS VENDOR",1,true) and
       lines:find("AH MAY BE BETTER THAN VENDOR",1,true),
    "bag hover shows projected AH-after-fee versus vendor sell price")
assert(not lines:find("MERCHANT FLIP",1,true),
    "bag hover never uses an unrelated merchant's purchase cost")
print("PASS: merchant/bag tooltip flip ROI, binding, price freshness, and source matching")
