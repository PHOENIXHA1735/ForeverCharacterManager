local _, FCM = ...
-- Gold Finder reads prices on demand from AHledgerAPI (or FCM's unexpired
-- fallback); it never scans the AH, calls the network, or stores provider
-- prices in SavedVariables. Unknown source skills and farming speeds stay unknown.

local VENDOR_COST = { [2678]=2, [2692]=40, [3713]=160 } -- regular vendor copper, before discounts
local FISHING_REFERENCE = {
    -- Explicitly sourced fallback locations when the optional companion has
    -- no structured fish source. These are zone thresholds, not catch rates.
    [6522]={zone="The Barrens (oases)",name="Deviate Fish schools",skill=1,reliable=75,levelMin=10,levelMax=35},
    [6291]={zone="Starting-zone freshwater",name="Open water",skill=1,reliable=25,levelMin=1,levelMax=30},
    [13889]={zone="Feralas (Jademir Lake)",name="Inland water",skill=205,reliable=300,levelMin=40,levelMax=60},
}
local FISHING_ZONE_SKILL = {
    ["the barrens"]={1,75}, ["wailing caverns"]={1,75},
    ["elwynn forest"]={1,25}, ["durotar"]={1,25}, ["dun morogh"]={1,25},
    ["feralas"]={205,300}, ["tanaris"]={205,300},
    ["azshara"]={205,300}, ["the hinterlands"]={205,300},
    ["winterspring"]={330,425}, ["eastern plaguelands"]={330,425},
    ["silithus"]={330,425},
}
local nameOf
local function skillOf(ch,name)
    for key,p in pairs(ch.professions or {}) do
        if type(p)=="table" and tostring(p.name or key):lower()==name:lower() then
            return tonumber(p.skill)
        end
    end
    return nil
end
local function eligibleLevel(source,level)
    local lo,hi=tonumber(source.levelMin),tonumber(source.levelMax)
    if lo and lo>level+3 then return false end
    if hi and hi<level-12 then return false end
    return true
end
local function zoneFishingSkill(zone)
    local lower=tostring(zone or ""):lower()
    for name,range in pairs(FISHING_ZONE_SKILL) do
        if lower:find(name,1,true) then return range[1],range[2] end
    end
end
local function checkedQuote(self,itemID,ch)
    local price=self:PriceQuote(itemID,ch)
    if type(price)~="table" or price.snapshot==true then return nil end
    -- Reject known outdated provider scans; an old price must never appear
    -- as a fresh sale estimate just because the table is still installed.
    local observed=tonumber(price.observedUnix or price.observedAt)
    local now=(type(time)=="function" and time()) or (os and os.time and os.time())
    if observed and observed>1000000000 and now and now-observed>3*3600 then return nil end
    local median=tonumber(price.median)
    if not median or median<=0 then return nil end
    local qty=tonumber(price.quantity)
    if qty and qty<=0 then return nil end
    return price
end

function FCM:BagSaleEstimate(ch)
    local result={rows={},confirmedNet=0,confirmedLowNet=0,uncertainNet=0,
        unpriced=0,bound=0,unknownBinding=0,pricedUnits=0}
    if not ch then return result end
    local grouped={}
    for _,stack in pairs(ch.bags or {}) do
        local id=type(stack)=="table" and tonumber(stack.itemID)
        local qty=type(stack)=="table" and tonumber(stack.count) or nil
        if id and id>0 and qty and qty>0 then
            local record=grouped[id] or {itemID=id,count=0,unbound=0,unknown=0,bound=0,
                name=stack.name}
            grouped[id]=record
            record.name=record.name or stack.name
            record.count=record.count+qty
            if stack.bound==false then record.unbound=record.unbound+qty
            elseif stack.bound==true then record.bound=record.bound+qty
            else record.unknown=record.unknown+qty end
        end
    end
    for id,record in pairs(grouped) do
        local quote=checkedQuote(self,id,ch)
        if quote then
            record.quote=quote
            record.name=nameOf(self,id,{name=record.name})
            record.confirmedNet=math.floor(quote.median*record.unbound*0.95+0.5)
            record.uncertainNet=math.floor(quote.median*record.unknown*0.95+0.5)
            record.lowNet=math.floor((tonumber(quote.minBuyout) or quote.median)*record.unbound*0.95+0.5)
            result.confirmedNet=result.confirmedNet+record.confirmedNet
            result.confirmedLowNet=result.confirmedLowNet+record.lowNet
            result.uncertainNet=result.uncertainNet+record.uncertainNet
            result.pricedUnits=result.pricedUnits+record.unbound+record.unknown
            -- Bound-only items never qualify for sale; summarize them above
            -- without adding misleading zero-value auction candidates.
            if record.unbound>0 or record.unknown>0 then result.rows[#result.rows+1]=record end
        else result.unpriced=result.unpriced+record.count end
        result.bound=result.bound+record.bound
        result.unknownBinding=result.unknownBinding+record.unknown
    end
    table.sort(result.rows,function(a,b)
        if a.confirmedNet~=b.confirmedNet then return a.confirmedNet>b.confirmedNet end
        if a.uncertainNet~=b.uncertainNet then return a.uncertainNet>b.uncertainNet end
        return a.name<b.name
    end)
    return result
end

function FCM:BagSaleEstimateLines(record,ch)
    if not record or not record.quote then return "No current quote for this bag item." end
    local q=record.quote
    local money=function(n) return self:MoneyLabel(n) end
    return table.concat({"|cffffd983"..tostring(record.name).."|r", "",
        "BAG SALE ESTIMATE — "..tostring(ch and ch.name or "selected character"),
        "In bags: "..tostring(record.count).." | Confirmed unbound: "..record.unbound..
            " | Binding unknown: "..record.unknown.." | Bound: "..record.bound,
        "AH median per item: "..money(q.median),
        "Lowest observed buyout per item: "..money(q.minBuyout),
        "Potential net sale at median for confirmed unbound stack(s): "..money(record.confirmedNet),
        "Potential net sale at lowest buyout for confirmed unbound stack(s): "..money(record.lowNet),
        "Additional UNVERIFIED value where item binding is unknown: "..money(record.uncertainNet),
        "Market: "..tostring(q.market or "unknown"),
        "Last market scan: "..(self.TimestampLabel and self:TimestampLabel(q.observedAt) or tostring(q.observedAt or "unknown")),
        "", "Estimates subtract 5% auction cut, but not listing deposits. Price and availability can change.",
        "Before posting: open the Auction House and run /ahl scan. Check the current lowest listing; ",
        "AHledger Sync may need to download the newer table and WoW may require /reload before FCM sees it.",
        "FCM never posts, buys, or scans the AH automatically from outside the Auction House.",
        "Prices from AHledger (ahledger.com)."},"\n")
end
local function kindOf(source)
    local k=tostring(source.kind or source.type or ""):lower()
    if k=="fish" or k=="fishing" then return "fish" end
    if k=="herbalism" or k=="mining" or k=="skinning" or k=="herb" or k=="ore" or
        k=="mob" or k=="creature" or k=="npc" or k=="drop" or k=="enemy" then return "farm" end
    return nil
end
local function permittedSource(ch,kind,source,level,fishSkill)
    if not eligibleLevel(source,level) then return false end
    local required=tonumber(source.skillRequired or source.requiredSkill or source.gatherSkill)
    local profession
    if kind=="fish" then
        profession="Fishing"
        local zoneMinimum=zoneFishingSkill(source.zone or source.area or source.location)
        required=required or zoneMinimum
    else
        local k=tostring(source.kind or source.type or ""):lower()
        if k=="mining" or k=="ore" then profession="Mining"
        elseif k=="herbalism" or k=="herb" then profession="Herbalism"
        elseif k=="skinning" then profession="Skinning" end
    end
    local have=profession=="Fishing" and fishSkill or (profession and skillOf(ch,profession))
    if profession and (not have or have<=0) then return false end
    if required and required>0 and profession and have<required then return false end
    return true,required,profession
end
local function kindOrder(kind)
    if kind=="cook" then return 1 end
    if kind=="fish" then return 2 end
    return 3
end
nameOf=function(self,id,record)
    return tostring((record and record.name) or
        (self.externalData and self.externalData.items and
            self.externalData.items[id] and self.externalData.items[id].name) or
        (self.ItemName and self.ItemName(id)) or ("Item #"..id))
end
local function push(out,row)
    row.unitValue=row.kind=="cook" and row.profitEach or
        math.floor((tonumber(row.quote.median) or 0)*0.95+0.5)
    local daily=tonumber(row.quote.soldPerDay)
    row.salesPerDay=daily and daily>=0 and daily or nil
    row.marketCeiling=row.salesPerDay and row.salesPerDay*row.unitValue or nil
    out[#out+1]=row
end
function FCM:GoldOpportunities(ch,view)
    local out={}
    local level=ch and tonumber(ch.level)
    if not level or level<1 then return out end
    view=view or "all"
    local fishSkill=skillOf(ch,"Fishing")
    local items=(self.externalData or {}).items or {}
    if view=="all" or view=="farm" or view=="fish" then
        for key,item in pairs(items) do
            local id=tonumber(key)
            if id and id>0 and type(item)=="table" then
                local candidates={}
                for _,source in ipairs(item.farmSources or {}) do
                    local kind=kindOf(source)
                    if kind and (view=="all" or kind==view) then
                        local ok,required,profession=permittedSource(ch,kind,source,level,fishSkill)
                        if ok then
                            candidates[#candidates+1]={kind=kind,source=source,
                                required=required,profession=profession,
                                verifiedLevel=tonumber(source.levelMin)~=nil or
                                    tonumber(source.levelMax)~=nil}
                        end
                    end
                end
                -- Indexed, known fishing opportunities remain discoverable if
                -- ForeverDB has not imported the item's farmSources yet.
                local known=FISHING_REFERENCE[id]
                if known and (view=="all" or view=="fish") and fishSkill and
                    fishSkill>=known.skill and eligibleLevel(known,level) then
                    candidates[#candidates+1]={kind="fish",source={name=known.name,zone=known.zone,
                        levelMin=known.levelMin,levelMax=known.levelMax,
                        evidence="Published fishing-zone threshold, not a verified catch rate"},
                        required=known.skill,profession="Fishing",reliable=known.reliable,
                        verifiedLevel=true}
                end
                if #candidates>0 then
                    table.sort(candidates,function(a,b)
                        if a.verifiedLevel~=b.verifiedLevel then return a.verifiedLevel end
                        if (a.required~=nil)~=(b.required~=nil) then return a.required~=nil end
                        return a.kind=="fish" and b.kind~="fish"
                    end)
                    -- An item is shown once, using its best documented source.
                    local picked=candidates[1]
                    local quote=checkedQuote(self,id,ch)
                    if quote then
                        push(out,{kind=picked.kind,itemID=id,name=nameOf(self,id,item),
                            quote=quote,source=picked.source,skillRequired=picked.required,
                            sourceProfession=picked.profession,sourceVerifiedLevel=picked.verifiedLevel,
                            reliableSkill=picked.reliable,level=level})
                    end
                end
            end
        end
        -- Published fishing references may be usable before the optional
        -- item catalog has been populated. Quote these exact IDs directly;
        -- never infer prices or catch rates for unidentified items.
        if (view=="all" or view=="fish") and fishSkill then
            for id,known in pairs(FISHING_REFERENCE) do
                if not items[id] and not items[tostring(id)] and
                    fishSkill>=known.skill and eligibleLevel(known,level) then
                    local quote=checkedQuote(self,id,ch)
                    if quote then
                        push(out,{kind="fish",itemID=id,name=nameOf(self,id),quote=quote,
                            source={name=known.name,zone=known.zone,
                                evidence="Published fishing-zone threshold, not a verified catch rate"},
                            skillRequired=known.skill,sourceProfession="Fishing",
                            sourceVerifiedLevel=true,reliableSkill=known.reliable,level=level})
                    end
                end
            end
        end
    end
    if view=="all" or view=="cook" then
        local cookingSkill=skillOf(ch,"Cooking")
        if cookingSkill and cookingSkill>0 then
            for key,learned in pairs(ch.recipes or {}) do
                if type(learned)=="table" and learned.learned then
                    local ref=((self.externalData or {}).recipes or {})[tonumber(learned.id or key)] or {}
                    local profession=tostring(learned.profession or ref.profession or ""):lower()
                    -- Learned, scanned recipes are required; a public catalog
                    -- record is not proof the character owns the recipe.
                    if profession=="cooking" and not learned.complex then
                        local required=tonumber(learned.requiredSkill)
                        if not required or required<=cookingSkill then
                            local outputID=tonumber(learned.outputID or ref.resultID)
                            local qty=tonumber(learned.quantity or ref.quantity) or 1
                            local reagents=learned.reagents
                            if type(reagents)~="table" or #reagents==0 then reagents=ref.reagents end
                            if outputID and qty>=1 and qty<=100 and type(reagents)=="table" and #reagents>0 then
                                local quote=checkedQuote(self,outputID,ch)
                                if quote then
                                    local cost,parts,missing=0,{},false
                                    for _,mat in ipairs(reagents) do
                                        local mid=tonumber(mat.itemID or mat.id)
                                        local count=tonumber(mat.count or mat.qty)
                                        if not mid or not count or count<=0 then missing=true;break end
                                        local mp=checkedQuote(self,mid,ch)
                                        if mp and quote.market and mp.market and mp.market~=quote.market then missing=true;break end
                                        local vendor=VENDOR_COST[mid]
                                        local unit=mp and tonumber(mp.median) or nil
                                        if vendor and (not unit or vendor<unit) then unit=vendor end
                                        if not unit then missing=true;break end
                                        cost=cost+unit*count
                                        parts[#parts+1]={itemID=mid,name=nameOf(self,mid,items[mid]),
                                            count=count,unit=unit,vendor=vendor and unit==vendor}
                                    end
                                    if not missing then
                                        local gain=quote.median*qty*0.95-cost
                                        if gain>0 then
                                            push(out,{kind="cook",itemID=outputID,name=nameOf(self,outputID,items[outputID]),
                                                quote=quote,profitEach=gain/qty,profitCraft=gain,
                                                materialCost=cost,outputQty=qty,reagents=parts,
                                                recipeName=learned.name or ref.name or "Cooking recipe",
                                                skillRequired=required,level=level,
                                                cookingSkill=cookingSkill})
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(out,function(a,b)
        if view=="all" and a.kind~=b.kind then return kindOrder(a.kind)<kindOrder(b.kind) end
        if (a.sourceVerifiedLevel==true)~=(b.sourceVerifiedLevel==true) and a.kind~="cook" and b.kind~="cook" then
            return a.sourceVerifiedLevel==true
        end
        if (a.marketCeiling~=nil)~=(b.marketCeiling~=nil) then return a.marketCeiling~=nil end
        if a.marketCeiling and b.marketCeiling and a.marketCeiling~=b.marketCeiling then return a.marketCeiling>b.marketCeiling end
        if a.unitValue~=b.unitValue then return a.unitValue>b.unitValue end
        return a.name<b.name
    end)
    return out
end

function FCM:GoldOpportunityLines(entry,ch)
    if not entry then return "No opportunity selected." end
    local quote=entry.quote or {}
    local money=function(value) return self:MoneyLabel(value) end
    local lines={"|cffffd983"..entry.name.."|r", "",
        "Category: "..(entry.kind=="cook" and "Cooking" or (entry.kind=="fish" and "Fishing" or "Farming / gathering")),
        "Character: "..tostring(ch and ch.name or "Unknown").." | Level "..tostring(entry.level or "?"),
        "Market: "..tostring(quote.market or "not identified"),
        "AH median: "..money(quote.median).." | Lowest observed buyout: "..money(quote.minBuyout),
        "Listed units: "..tostring(quote.quantity or "unknown"),
        "Estimated market sales/day: "..(entry.salesPerDay and string.format("%.1f",entry.salesPerDay) or "unknown"),
        "Last source update: "..(self.TimestampLabel and self:TimestampLabel(quote.observedAt) or
            tostring(quote.observedAt or "unknown")),""}
    if entry.kind=="cook" then
        lines[#lines+1]="COOKING MARGIN"
        lines[#lines+1]="Recipe: "..entry.recipeName
        lines[#lines+1]="Recorded Cooking skill: "..tostring(entry.cookingSkill)
        lines[#lines+1]="Craft yields: "..tostring(entry.outputQty).." item(s)"
        lines[#lines+1]="Ingredients per craft (median AH or regular vendor price):"
        for _,mat in ipairs(entry.reagents or {}) do
            lines[#lines+1]="  "..tostring(mat.count).." x "..mat.name.." @ "..money(mat.unit)..
                (mat.vendor and " (vendor baseline)" or "")
        end
        lines[#lines+1]="Material cost per craft: "..money(entry.materialCost)
        lines[#lines+1]="Estimated profit per craft after 5% AH cut: "..money(entry.profitCraft)
        lines[#lines+1]="Estimated profit per output item: "..money(entry.profitEach)
    else
        local source=entry.source or {}
        lines[#lines+1]="WHERE TO "..(entry.kind=="fish" and "FISH" or "FARM")
        lines[#lines+1]="Reported source: "..tostring(source.name or source.mob or source.node or source.kind or "Source not named")
        lines[#lines+1]="Zone: "..tostring(source.zone or source.area or "not recorded")
        lines[#lines+1]="Character-level match: "..(entry.sourceVerifiedLevel and "Recorded range checked" or "Source level not verified")
        if entry.sourceProfession then
            lines[#lines+1]="Required "..entry.sourceProfession.." skill: "..tostring(entry.skillRequired or "not recorded")
        end
        if entry.reliableSkill then lines[#lines+1]="Fishing skill for fewer missed casts: "..tostring(entry.reliableSkill) end
        if source.evidence and source.evidence~="" then lines[#lines+1]="Source caveat: "..tostring(source.evidence) end
        lines[#lines+1]="Potential net sale value per item (after AH cut): "..money(entry.unitValue)
        lines[#lines+1]="Potential value if 20 items sell: "..money(entry.unitValue*20)
        lines[#lines+1]="Farming cost, catch rate and travel time are NOT included. This is NOT profit/hour."
    end
    lines[#lines+1]=""
    if entry.marketCeiling then
        lines[#lines+1]="Whole-market theoretical daily "..(entry.kind=="cook" and "crafting profit" or "sale value")..
            " at current estimated demand: "..money(entry.marketCeiling)
        lines[#lines+1]="This is market-wide demand, NOT what one character will earn."
    else lines[#lines+1]="Daily sale volume unknown; do not assume stock will sell." end
    lines[#lines+1]=""
    lines[#lines+1]="Prices from AHledger (ahledger.com). These are scan snapshots, not live guaranteed sales."
    lines[#lines+1]="Check current lowest buyout and deposit before spending gold or posting."
    return table.concat(lines,"\n")
end
