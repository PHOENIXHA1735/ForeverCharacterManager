local _, FCM = ...
-- Source-based advisory. Never invent drop rates, NPC locations or farming speed.
-- Farm records are reference claims; the game client does not validate them.
local MAX_SOURCE_ROWS=30
local function str(s)
    if type(s)~="string" and type(s)~="number" then return "" end
    local v=tostring(s):gsub("[\r\n]"," ")
    return v:sub(1,220)
end
local function num(x,min,max)
    local n=tonumber(x)
    if not n or n~=n or n<min or n>max then return nil end
    return n
end
local function kindOf(s)
    local k=str(s):lower()
    if k=="npc" or k=="enemy" or k=="creature" or k=="drop" then return "mob" end
    if k=="herb" then return "herbalism" end
    if k=="ore" then return "mining" end
    if k=="fish" then return "fishing" end
    if k=="mob" or k=="fishing" or k=="mining" or k=="herbalism" or
        k=="skinning" or k=="dungeon" or k=="vendor" then return k end
    return "reference"
end
local function addRow(out,seen,row)
    if type(row)~="table" or #out>=MAX_SOURCE_ROWS then return end
    local name=str(row.name or row.mob or row.boss or row.node)
    local zone=str(row.zone or row.area or row.location)
    if name=="" and zone=="" then return end
    local kind=kindOf(row.kind or row.type)
    local key=(kind.."|"..name.."|"..zone):lower()
    local rate=num(row.dropRatePct or row.ratePct,0.000001,100)
    local sample=num(row.sampleSize,1,1000000000)
    local killsPerHour=num(row.killsPerHour,0.0001,1000000)
    if seen[key] then
        local old=seen[key]
        -- A newer sparse reference must not erase richer rate data.
        if not old.dropRatePct and rate then old.dropRatePct=rate end
        if not old.sampleSize and sample then old.sampleSize=sample end
        if not old.killsPerHour and killsPerHour then old.killsPerHour=killsPerHour end
        return
    end
    local outRow={name=name,zone=zone,kind=kind,dropRatePct=rate,
        sampleSize=sample,killsPerHour=killsPerHour,source=str(row.source or row.provider),
        evidence=str(row.evidence),levelMin=num(row.levelMin,1,1000),
        levelMax=num(row.levelMax,1,1000)}
    seen[key]=outRow
    out[#out+1]=outRow
end
local function dungeonSources(out,seen,db,id)
    for _,d in pairs(db or {}) do
        if type(d)=="table" then
            local zone=str(d.name)
            for _,boss in ipairs(d.bosses or {}) do
                if type(boss)=="table" then
                    for _,drop in ipairs(boss.loot or {}) do
                        if tonumber(drop.id)==id then
                            addRow(out,seen,{name=boss.name,zone=zone,kind="dungeon",
                                source=d.sourceProvider or "Imported dungeon reference",
                                evidence="Boss-linked imported reference; not a confirmed live drop"})
                        end
                    end
                end
            end
            -- Dungeon-wide associations have no trustworthy boss attribution.
            for _,drop in ipairs(d.dungeonLoot or {}) do
                if tonumber(type(drop)=="table" and drop.id or drop)==id then
                    addRow(out,seen,{name="Boss unknown",zone=zone,kind="dungeon",
                        source=d.sourceProvider or "Imported dungeon reference",
                        evidence="Dungeon association only; no confirmed boss"})
                end
            end
            for _,linked in ipairs(d.lootIDs or {}) do
                if tonumber(linked)==id then
                    addRow(out,seen,{name="Boss unknown",zone=zone,kind="dungeon",
                        source=d.sourceProvider or "Imported dungeon reference",
                        evidence="Dungeon-level item association; verify live source"})
                end
            end
        end
    end
end
function FCM:FarmSources(itemID)
    local id=tonumber(itemID)
    if not id then return {} end
    local ext=self.externalData or {}
    local item=(ext.items or {})[id] or {}
    local rows,seen={},{}
    for _,raw in ipairs(item.farmSources or {}) do addRow(rows,seen,raw) end
    dungeonSources(rows,seen,ext.dungeons,id)
    -- An unstructured source description is useful but NOT eligible for
    -- drop-rate ranking. Treat it as one unverified reference hint.
    if #rows==0 and type(item.where)=="string" and item.where~="" then
        addRow(rows,seen,{name="Reported source (details unverified)",zone=item.where:sub(1,180),
            kind="reference",source=item.sourceProvider or item.source,
            evidence="Unstructured reference text; no measured drop rate"})
    end
    return rows
end
local function sortRows(a,b)
    -- Only measured parameters justify a rate/efficiency ranking.
    -- A zone-only reference never outranks a populated chance record.
    local ae=a.dropRatePct and a.killsPerHour and a.dropRatePct*a.killsPerHour/100
    local be=b.dropRatePct and b.killsPerHour and b.dropRatePct*b.killsPerHour/100
    if ae and be and ae~=be then return ae>be end
    if ae and not be then return true end
    if be and not ae then return false end
    local ar,br=a.dropRatePct,b.dropRatePct
    if ar and br and ar~=br then return ar>br end
    if ar and not br then return true end
    if br and not ar then return false end
    local an,bn=(a.zone.."|"..a.name):lower(),(b.zone.."|"..b.name):lower()
    return an<bn
end
function FCM:FarmAdvice(itemID,quantity,character)
    local id=tonumber(itemID)
    if not id or id<=0 then return nil end
    local count=num(quantity or 1,1,1000000) or 1
    local sources=self:FarmSources(id)
    table.sort(sources,sortRows)
    local priced=nil
    if type(self.PriceQuote)=="function" then
        local ok,value=pcall(self.PriceQuote,self,id,character)
        if ok and type(value)=="table" then priced=value end
    end
    local best=sources[1]
    local verdict="Sources recorded; drop rates unavailable"
    if best and best.dropRatePct then
        verdict=best.killsPerHour and "Highest estimated drops/hour among sources with both rate and pace data" or
            "Highest reported drop rate (not farming speed)"
    elseif not best then verdict="No sourced farm location recorded" end
    return {itemID=id,quantity=count,sources=sources,best=best,ranking=verdict,price=priced}
end
function FCM:FarmAdviceLines(itemID,quantity,character,maxRows)
    local plan=self:FarmAdvice(itemID,quantity,character)
    if not plan then return {"Invalid item ID."} end
    local rows={"|cffffd983ITEM FARMING ADVISOR - REFERENCE DATA|r",
        "Item #"..plan.itemID.." | Quantity wanted: "..string.format("%g",plan.quantity),
        plan.ranking,""}
    if #plan.sources==0 then rows[#rows+1]="No verified or imported farming sources are currently known." end
    for i=1,math.min(#plan.sources,math.max(1,math.min(tonumber(maxRows) or 8,20))) do
        local s=plan.sources[i]
        rows[#rows+1]=string.format("%d. %s - %s",i,s.name~="" and s.name or s.kind,
            s.zone~="" and s.zone or "Zone unspecified")
        rows[#rows+1]="  Type: "..s.kind.." | "..
            (s.dropRatePct and string.format("Reported drop rate %.2f%%",s.dropRatePct) or "Drop rate unknown")..
            (s.sampleSize and (" | sample "..string.format("%g",s.sampleSize)) or "")
        if s.dropRatePct then
            rows[#rows+1]="  Average kills/catches per desired quantity: about "..
                string.format("%.0f",math.ceil(plan.quantity*100/s.dropRatePct)).." (statistical estimate)"
            if s.killsPerHour then
                rows[#rows+1]=string.format("  Estimated drops/hr: %.2f (requires a reliable kills/hr rate)",
                    s.killsPerHour*s.dropRatePct/100)
            end
        end
        if s.source~="" then rows[#rows+1]="  Reference: "..s.source end
        if s.evidence~="" then rows[#rows+1]="  Caveat: "..s.evidence end
    end
    if plan.price then
        local median=tonumber(plan.price.median)
        if median and median>0 then
            local each=self.MoneyLabel and self:MoneyLabel(median) or tostring(median).." copper"
            local total=self.MoneyLabel and self:MoneyLabel(median*plan.quantity) or tostring(median*plan.quantity).." copper"
            rows[#rows+1]=""
            rows[#rows+1]="AH median (cached): "..each.." each | approx "..total.." total"
            rows[#rows+1]="Market data: "..str(plan.price.observedAt or plan.price.updated or "timestamp unknown")..
                " | Listings are not guaranteed sales or purchases."
            if type(self.MarketItemAdvice)=="function" then
                local meta=((self.externalData or {}).items or {})[plan.itemID] or {}
                local advice=self:MarketItemAdvice(plan.itemID,character,plan.quantity,meta.quality,meta.vendorPrice)
                if advice and advice.promising then
                    rows[#rows+1]="Market note: potential AH value; compare the cost of buying to your farming time."
                end
            end
        end
    end
    rows[#rows+1]=""
    rows[#rows+1]="Reported source ranks are advisory, not confirmed best routes or live drop odds."
    rows[#rows+1]="No spawn-density, respawn or travel estimate without measured data."
    return rows
end
function FCM:FarmQuickLine(itemID,character,quantity)
    local plan=self:FarmAdvice(itemID,quantity or 1,character)
    if not plan or not plan.best then return "Farm source: unknown (no reference)" end
    local s=plan.best
    local rate=s.dropRatePct and string.format("reported %.2f%%",s.dropRatePct) or "drop rate unknown"
    local estimate=s.dropRatePct and (" | approximately "..
        tostring(math.ceil(plan.quantity*100/s.dropRatePct)).." attempts for "..
        string.format("%g",plan.quantity).." items") or ""
    return "Reported farm: "..(s.name~="" and s.name or s.kind).." / "..
        (s.zone~="" and s.zone or "unknown zone").." | "..rate..estimate
end
