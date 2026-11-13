local _, FCM = ...
-- Item market guidance is advisory: reported listings are not actual sales.
-- Only already-imported, unexpired, faction-specific AH data is considered.
local function number(v)
    local n=tonumber(v)
    if not n or n~=n or n==math.huge or n==-math.huge then return nil end
    return n
end
local function money(self, copper)
    if type(self.MoneyLabel)=="function" then return self:MoneyLabel(copper) end
    copper=math.floor((number(copper) or 0)+0.5)
    return string.format("%dg %ds %dc",math.floor(copper/10000),math.floor(copper%10000/100),copper%100)
end
-- Pure decision about ONE item, independent of the bag UI. Quality=1 means
-- Common/white in the WoW item API. Unknown quality is never assumed white.
function FCM:MarketItemAdvice(itemID,ch,quantity,quality,vendorCopper)
    local id=number(itemID)
    if not id or id<=0 or type(self.PriceQuote)~="function" then return nil end
    local q=self:PriceQuote(id,ch)
    if type(q)~="table" then return nil end
    -- Do not turn older no-expiry reference imports into a current-price alert.
    local expires=number(q.expiresAt)
    local current=(type(time)=="function" and number(time())) or
        (os and os.time and number(os.time())) or 0
    local providerManaged=(q.source=="AHledgerAPI")
    local bundledSnapshot=providerManaged and q.snapshot==true
    if not providerManaged and (not expires or expires<=current) then return nil end
    local median=number(q.median)
    local floor=number(q.minBuyout)
    if median and median<=0 then median=nil end
    if floor and floor<=0 then floor=nil end
    if not median and not floor then return nil end
    local count=math.floor(number(quantity) or 1)
    count=math.max(1,math.min(count,1000000))
    local vendor=number(vendorCopper)
    if vendor and vendor<0 then vendor=nil end
    local baseline30=number(q.median30d)
    local baseline7=number(q.median7d)
    local change30=nil
    if baseline30 and baseline30>0 and median then change30=(median/baseline30-1)*100 end
    local change7=nil
    if baseline7 and baseline7>0 and median then change7=(median/baseline7-1)*100 end
    local observation=number(q.observedUnix)
    local now=current
    local age=nil
    if observation and now and now>=observation then age=now-observation end
    -- The minimum known listing is a more conservative warning threshold than
    -- a median distorted by expensive listings. Without it, warn to REVIEW.
    local candidatePrice=floor or median
    local multiple=vendor and vendor>0 and (candidatePrice/vendor) or nil
    local common=(number(quality)==1)
    local promising=(not bundledSnapshot) and common and candidatePrice and candidatePrice>=10000 and
        ((vendor and vendor>0 and candidatePrice>=vendor*10) or
         (vendor==0) or (vendor==nil))
    local verdict=promising and "CHECK AH BEFORE VENDORING" or "AH price available"
    if bundledSnapshot then verdict="AHledger bundled snapshot; verify live prices" end
    if common and not promising then verdict="Compare AH listing with vendor value" end
    return {itemID=id,market=q.market,source="AHledger",snapshot=bundledSnapshot,
        providerManaged=providerManaged,median=median,minBuyout=floor,
        vendor=vendor,stackCount=count,stackMedian=median and median*count or nil,
        stackMinBuyout=floor and floor*count or nil,
        change30=change30,change7=change7,observedAt=q.observedAt,
        ageSeconds=age,expiresAt=expires,soldPerDay=number(q.soldPerDay),
        promising=not not promising,verdict=verdict,common=common,ratio=multiple}
end
function FCM:MarketItemAdviceLines(advice)
    if not advice then return {} end
    local lines={"AH market ("..tostring(advice.market or "market unknown")..")"}
    if advice.median then lines[#lines+1]="  Median listing: "..money(self,advice.median).." each" end
    if advice.minBuyout then lines[#lines+1]="  Lowest listed: "..money(self,advice.minBuyout).." each" end
    if advice.stackCount>1 and advice.stackMedian then
        lines[#lines+1]="  Stack of "..advice.stackCount..": approx. "..money(self,advice.stackMedian)
    end
    if advice.vendor then lines[#lines+1]="  Vendor: "..money(self,advice.vendor).." each" end
    if advice.change30 then
        lines[#lines+1]=string.format("  vs. source 30-day median: %+.0f%%",advice.change30)
    end
    if advice.change7 then
        lines[#lines+1]=string.format("  vs. source 7-day median: %+.0f%%",advice.change7)
    end
    if advice.observedAt then lines[#lines+1]="  Market observation: "..tostring(advice.observedAt) end
    if advice.promising then lines[#lines+1]="  "..advice.verdict.." (asking prices are not guaranteed sales)" end
    if advice.snapshot then lines[#lines+1]="  AHledger bundled snapshot: verify price before acting" end
    lines[#lines+1]="  Source: AHledger; market estimates, not confirmed sales."
    return lines
end
