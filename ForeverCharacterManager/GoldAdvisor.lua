-- Read-only advice from local companion summaries. No auction actions.
local _, FCM = ...
local G={cache={}}
FCM.GoldAdvisor=G
function G:ConfigureFees(input)
    local pct,deposit=tostring(input or ''):match('^%s*(%d+%.?%d*)%s+(%d+)%s*$')
    pct=tonumber(pct);deposit=tonumber(deposit)
    if not pct or pct>=100 or not deposit then return false end
    FCM.db.settings.goldAdvisorFees={cut=pct/100,deposit=deposit}
    return true
end
function G:ConfigureFarm(input)
    local id,profession,rate,alternative,deposit=tostring(input or ''):match('^%s*(%d+)|([^|]+)|(%d+%.?%d*)|(%d+)|(%d+)%s*$')
    id=tonumber(id);rate=tonumber(rate);alternative=tonumber(alternative);deposit=tonumber(deposit)
    if not id or id<=0 or not rate or rate<=0 or not alternative or not deposit then return false end
    FCM.db.settings.goldAdvisorFarmEffort=FCM.db.settings.goldAdvisorFarmEffort or {}
    FCM.db.settings.goldAdvisorFarmEffort[id]={profession=profession,unitsPerHour=rate,alternativeGoldPerHour=alternative,depositPerHour=deposit}
    return true
end
local function now() return (time and time()) or os.time() end
local LIVE_CACHE_SECONDS=30
local PRICE_MAX_AGE=24*60*60
local DEMAND_MAX_AGE=7*24*60*60
local function recent(stamp,maxAge)
    stamp=tonumber(stamp)
    return stamp and stamp>0 and now()-stamp>=0 and now()-stamp<=maxAge
end
local function liveAPI()
    local api=AHledgerAPI
    return type(api)=='table' and type(api.GetPrice)=='function' and api or nil
end
local function liveQuote(base,id,market,api,info)
    -- Never mutate the private historical record: live values are an ephemeral overlay.
    local q={}
    for key,value in pairs(base) do q[key]=value end
    q.priceStatus='Archived FCM observation; live AHledger price unavailable.'
    q.demandSource=q.demand and 'archived provider estimate' or 'unavailable'
    if not api then return q end
    local ok,p=pcall(api.GetPrice,tonumber(id),market)
    if not ok or type(p)~='table' then return q end
    -- AHledgerAPI expects slash-separated market identifiers. Never use the
    -- logged-in character's Alliance price for an offline Horde character.
    if p.market~=market then
        q.priceStatus='AHledger market mismatch; archived FCM observation retained.'
        return q
    end
    local stamp=tonumber(p.updated)
    if not stamp or stamp<=0 or stamp>now() then
        q.priceStatus='AHledger timestamp missing or invalid; archived FCM observation retained.'
        return q
    end
    if p.snapshot then
        q.priceStatus='AHledger bundled snapshot is not live; archived FCM observation retained.'
        return q
    end
    -- A personal scan can update p.updated without refreshing the provider's
    -- sales pace. Validate the underlying table timestamp separately.
    local demand=tonumber(p.soldPerDay)
    if info and info.market==market and not info.snapshot and recent(info.updated,DEMAND_MAX_AGE) and demand and demand>0 then
        q.demand=demand
        q.demandSource='AHledger recent provider-table estimate'
    end
    local median=tonumber(p.median)
    local low=tonumber(p.minBuyout)
    local supply=tonumber(p.quantity)
    if not recent(stamp,PRICE_MAX_AGE) then
        q.priceStatus='AHledger quote is stale; archived FCM observation retained.'
    elseif stamp<(tonumber(q.stamp) or 0) then
        q.priceStatus='FCM archive contains a newer personal observation; latest price retained.'
    elseif not median or median<=0 or not low or low<=0 or not supply or supply<=0 then
        q.priceStatus='AHledger quote is incomplete; archived FCM observation retained.'
    else
        q.current=median
        q.low=low
        q.supply=supply
        q.stamp=stamp
        q.currentSource='AHledger live'
        q.priceStatus='LIVE AHledger quote; historical averages remain from FCM archives.'
        local baseline=q.averages and q.averages[365]
        if baseline and baseline>0 then q.comparison=(median/baseline-1)*100 end
    end
    return q
end
local function countStock(ch,id)
    local n=0
    for _,where in ipairs({'bags','bank'}) do
        for _,s in pairs(ch and ch[where] or {}) do
            if tonumber(s.itemID)==id and s.bound==false then n=n+(tonumber(s.count) or 0) end
        end
    end
    return n
end
local function fresh(q) return q and now()-q.stamp>=0 and now()-q.stamp<=86400 end
local function usable(q)
    return fresh(q) and q.days>=14 and q.demand and q.demand>0 and q.supply and q.supply>0 and q.volatility and q.volatility<0.5
end
function G:Market(ch)
    local canonical={Normal='normal',PvP='pvp',RP='rp',['RP-PvP']='rppvp',Hardcore='hardcore'}
    local rule=ch and canonical[FCM:NormalizeRuleset(ch.ruleset)]
    local faction=ch and FCM:NormalizeFaction(ch.faction)
    if not rule or not faction or type(ch.region)~='string' then return nil end
    return 'forever/'..rule..'/'..string.lower(faction)..'/'..string.lower(ch.region)
end
function G:Prices(ch)
    local data=FCM_AHHistory
    local market=self:Market(ch)
    if not market or not data or data.schema~=1 then return {},market end
    if self.generation~=data.generatedUtc then self.cache={};self.liveCache={};self.generation=data.generatedUtc end
    if not self.cache[market] then
        local decoded={}
        for line in tostring(data.packed and data.packed[market] or ''):gmatch('[^\n]+') do
            local f={};local i=0
            for v in (line..','):gmatch('(.-),') do i=i+1;f[i]=tonumber(v) end
            if f[1] and f[2] and f[3] then
                local q={current=f[2],stamp=f[3],low=f[4],supply=f[5],demand=f[6],averages={},coverage={},minimum=f[17],maximum=f[18],comparison=f[19],days=f[20] or 0,observations=f[21] or 0,volatility=f[22],trend=f[23],confidence=({'low','moderate','high'})[f[24]] or 'low'}
                for j,n in ipairs({7,30,90,180,365}) do q.averages[n]=f[6+j];q.coverage[n]=f[11+j] or 0 end
                q.currentSource=f[25]==2 and 'personal scan' or 'provider table'
                decoded[f[1]]=q
            end
        end
        self.cache[market]=decoded
    end
    local api=liveAPI()
    self.liveCache=self.liveCache or {}
    local entry=self.liveCache[market]
    if entry and entry.api==api and recent(entry.checked,LIVE_CACHE_SECONDS) then return entry.prices,market end
    local tableInfo
    if api and type(api.GetTableInfo)=='function' then
        local ok,result=pcall(api.GetTableInfo,market)
        if ok and type(result)=='table' then tableInfo=result end
    end
    local out={}
    for id,base in pairs(self.cache[market]) do out[id]=liveQuote(base,id,market,api,tableInfo) end
    self.liveCache[market]={api=api,checked=now(),prices=out}
    return out,market
end
function G:Item(id,q,ch)
    local r={id=id,action='NO CLEAR RECOMMENDATION',profit=nil,score=0,quote=q,confidence=q and q.confidence or 'low'}
    if not usable(q) then r.reason='Need fresh prices, at least 14 observed days, supply, estimated demand and stable history.';return r end
    local baseline=q.averages[365]
    local price=q.low
    if not baseline or not price or price<=0 then r.reason='Current lowest buyout or historical baseline unavailable.';return r end
    local owned=countStock(ch,id)
    if owned>0 and price*0.95>=baseline*1.15 then
        r.action='SELL NOW';r.profit=(price-baseline)*0.95;r.reason='Owned transferable stock; net listing estimate exceeds observed daily baseline by 15%. Amount shown is premium over baseline, not acquisition profit. 5% AH cut assumed; deposits excluded.'
    elseif owned>0 and price<=baseline*0.85 and q.trend and q.trend>=0 then
        r.action='HOLD';r.profit=baseline*0.95-price*0.95;r.reason='Owned stock is below baseline while recent observed prices are stable or rising. Recovery is uncertain.'
    elseif price<=baseline*0.8 and q.trend and q.trend>=-20 then
        r.action='BUY NOW';r.profit=baseline*0.95-price;r.reason='Lowest observed buyout is at least 20% below daily baseline; estimated demand exists. Potential spread assumes 5% AH cut and excludes deposits.'
    else r.reason='Current spread and observed trend do not provide a clear edge.' end
    if r.action~='NO CLEAR RECOMMENDATION' then
        r.score=math.max(0,r.profit or 0)*math.min(q.demand,10)/(1+q.supply/100)/(1+(q.volatility or 0)*5)
    end
    return r
end
function G:Craft(recipe,ch,prices,fees)
    local q=prices[tonumber(recipe.outputID)]
    local r={id=tonumber(recipe.outputID),recipe=recipe,action='NO CLEAR RECOMMENDATION',quote=q,score=0,confidence='low'}
    if not q or not usable(q) or not q.low then r.reason='Output history, current buyout, supply or estimated demand is insufficient.';return r end
    local learned=ch and ch.recipes and (ch.recipes[recipe.id] or ch.recipes[tostring(recipe.id)])
    if not learned or learned.learned==false or not ch.professions or not ch.professions[recipe.profession] then r.reason='Selected character has no recorded learned recipe and matching profession.';return r end
    local info=FCM.Gear and FCM.Gear.Info and FCM.Gear:Info(recipe.outputID)
    if not info or not tonumber(info.bindType) or tonumber(info.bindType)==1 then r.reason='Sale eligibility requires verified transferable output binding.';return r end
    if recipe.complex or not recipe.reagents or #recipe.reagents==0 then r.reason='Incomplete or alternative reagent requirements.';return r end
    fees=fees or {}
    if type(fees.deposit)~='number' or fees.deposit<0 or type(fees.cut)~='number' or fees.cut<0 or fees.cut>=1 then r.reason='Auction cut and expected unrecovered deposit must be configured before net-profit advice.';return r end
    local cost,missing,discount=0,0,0
    for _,reagent in ipairs(recipe.reagents) do
        local id=tonumber(reagent.itemID);local count=tonumber(reagent.count)
        local p=prices[id]
        if not count or count<=0 or not fresh(p) or not p.low or p.low<=0 or not p.supply or p.supply<count then r.reason='Reagent price, available supply or quantity is missing/stale.';return r end
        -- Owned reagents have the same opportunity cost as purchased materials.
        cost=cost+p.low*count
        missing=missing+math.max(0,count-countStock(ch,id))
        if p.averages[30] and (p.coverage[30] or 0)>=7 and p.low<p.averages[30]*0.85 then discount=discount+1 end
    end
    r.profit=q.low*math.max(1,tonumber(recipe.quantity) or 1)*(1-fees.cut)-cost-fees.deposit
    r.materialCost=cost
    if r.profit<=0 then r.reason='Material opportunity cost and AH fees consume the estimated sale proceeds.';return r end
    r.action=(missing>0 and discount>0) and 'BUY MATERIALS' or 'CRAFT'
    r.reason='Learned eligible craft; subtracts material opportunity cost, configured AH cut and unrecovered deposit. Demand is estimated; a completed sale is not guaranteed.'
    r.confidence=q.confidence
    r.score=r.profit*math.min(q.demand or 0,10)/(1+(q.supply or 0)/100)/(1+(q.volatility or 0)*5)
    return r
end
function G:Farm(id,q,ch,effort)
    local r={id=id,quote=q,action='NO CLEAR RECOMMENDATION',score=0,confidence='low'}
    local profession=effort and effort.profession
    if not usable(q) or not q.low or not profession or not (ch.professions or {})[profession] or not effort.unitsPerHour or effort.unitsPerHour<=0 then r.reason='Verified gathering eligibility and measured acquisition rate are required.';return r end
    if type(effort.alternativeGoldPerHour)~='number' or type(effort.depositPerHour)~='number' then r.reason='Farming opportunity cost or deposit estimate is unknown.';return r end
    r.profit=q.low*effort.unitsPerHour*0.95-effort.depositPerHour-effort.alternativeGoldPerHour
    if r.profit>0 then r.action='FARM';r.confidence=q.confidence;r.score=r.profit;r.reason='Measured acquisition rate exceeds configured alternative earnings after estimated 5% AH cut and deposits. Listing values are not confirmed sales.'
    else r.reason='Estimated acquisition value does not beat the alternative use of time.' end
    return r
end
function G:Opportunities(ch,prices)
    prices=prices or self:Prices(ch)
    local out={}
    for id,q in pairs(prices) do out[#out+1]=self:Item(id,q,ch) end
    local settings=FCM.db and FCM.db.settings or {}
    for _,r in ipairs(FCM.AllRecipes and FCM:AllRecipes() or {}) do
        out[#out+1]=self:Craft(r,ch,prices,settings.goldAdvisorFees)
    end
    for id,effort in pairs(settings.goldAdvisorFarmEffort or {}) do
        id=tonumber(id)
        if prices[id] then out[#out+1]=self:Farm(id,prices[id],ch,effort) end
    end
    table.sort(out,function(a,b) if a.score==b.score then return tostring(a.id)<tostring(b.id) end return a.score>b.score end)
    return out
end
function G:Timing(id,ch)
    local market=self:Market(ch)
    local data=FCM_AHHistory or {}
    return data.timing and data.timing[market] and data.timing[market][tostring(id)],data.timezone or 'unknown timezone'
end
local function money(n)
    return type(n)=='number' and string.format('%.2fg',n/10000) or 'unknown'
end
local function updatedAt(stamp)
    local formatter=date or (os and os.date)
    if type(formatter)~='function' or type(stamp)~='number' then return 'unknown' end
    local ok,result=pcall(formatter,'%Y-%m-%d %H:%M',stamp)
    return ok and result or 'unknown'
end
function G:Details(r,ch)
    local q=r.quote
    local lines={r.reason or 'Insufficient evidence.', 'Advisory only. Listing observations are not completed sales.'}
    if not q then return table.concat(lines,'\n') end
    lines[#lines+1]='Current median ('..tostring(q.currentSource or 'snapshot')..'): '..money(q.current)..' | Lowest listing: '..money(q.low)
    lines[#lines+1]='Quote status: '..tostring(q.priceStatus or 'Historical quote; live status unknown.')
    lines[#lines+1]='Price updated (local): '..updatedAt(q.stamp)
    lines[#lines+1]='Observed days: '..q.days..' | Observations: '..q.observations..' | Confidence: '..q.confidence
    lines[#lines+1]='Age: '..math.floor(math.max(0,now()-q.stamp)/3600)..' hours | Supply: '..tostring(q.supply or 'unknown')
    lines[#lines+1]='Estimated units/day: '..tostring(q.demand or 'unknown')..' ('..tostring(q.demandSource or 'provider estimate')..'; not confirmed personal sales)'
    for _,n in ipairs({7,30,90,180,365}) do
        lines[#lines+1]='FCM '..n..'-day daily average: '..money(q.averages[n])..' | '..tostring(q.coverage[n] or 0)..' observed days'
    end
    lines[#lines+1]='365-day observed min/max: '..money(q.minimum)..' / '..money(q.maximum)
    lines[#lines+1]='Versus historical baseline: '..(q.comparison and string.format('%+.1f%%',q.comparison) or 'unknown')
    lines[#lines+1]='7-day vs previous 7-day trend: '..(q.trend and string.format('%+.1f%%',q.trend) or 'insufficient data')
    lines[#lines+1]='Daily volatility: '..(q.volatility and string.format('%.1f%%',q.volatility*100) or 'unknown')
    local timing,zone=self:Timing(r.id,ch)
    lines[#lines+1]='Days and hours in '..zone..'; UTC timestamps retained.'
    local weekdays={'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'}
    local supported=false
    for _,mode in ipairs({'weekday','hour'}) do
        local low,high
        for key,b in pairs(timing and timing[mode] or {}) do
            if b.adequate then
                local entry={key=key,b=b}
                if not low or b.relative<low.b.relative then low=entry end
                if not high or b.relative>high.b.relative then high=entry end
            end
        end
        -- Require at least two supported buckets to compare days/hours.
        if low and high and low.key~=high.key and fresh(q) then
            supported=true
            local function label(e) return mode=='weekday' and weekdays[tonumber(e.key)+1] or (string.format('%02d:00',tonumber(e.key))) end
            lines[#lines+1]='Lower observed prices: '..label(low)..' ('..low.b.observations..' observations, '..low.b.days..' dates)'
            lines[#lines+1]='Higher observed prices: '..label(high)..' ('..high.b.observations..' observations, '..high.b.days..' dates)'
        end
    end
    if not supported then lines[#lines+1]='No supported best buying/selling day or hour yet; more observations needed.' end
    return table.concat(lines,'\n')
end
function G:Rows(ch)
    local rows={}
    local function add(id,title,summary,detail) rows[#rows+1]={id=id,title=title,summary=summary,detail=detail} end
    local prices,market=self:Prices(ch)
    add('gold-status','Gold Advisor | '..tostring(market or 'market unknown'),'Current AHledger prices when fresh | Private FCM historical snapshots',
        'Fresh prices, supply and estimated demand come from the optional in-game AHledgerAPI, never from an extra network request or a new stored provider-table archive. When live data is unavailable, FCM labels the historical fallback.\nFCM calculates daily historical values from timestamped personal archives, not overlapping provider rolling averages. Missing days remain missing. Offline bags/bank are recorded snapshots.\n\nManual Sync / Enable / Disable controls are installed in FCM-Companion. In-game Lua cannot run Windows tasks.\nCrafting net-profit advice requires configured AH fees and transferable output. Farming advice requires measured acquisition effort; unknown inputs stay unknown.')
    local opportunities=self:Opportunities(ch,prices)
    local function recommendation(r,prefix)
        local id=r.id
        local label=(FCM.ItemName and FCM.ItemName(id)) or ('Item #'..tostring(id))
        local q=r.quote
        add(prefix..':'..tostring(id),label..' | '..r.action,
            (r.action=='FARM' and 'Net estimate/hour: ' or (r.recipe and 'Net estimate/batch: ' or 'Potential spread/unit: '))..money(r.profit)..' | Demand/day: '..tostring(q and q.demand or 'unknown')..' | '..r.confidence,
            self:Details(r,ch))
    end
    add('gold-top','Top Gold-Making Opportunities','Ranked eligible actions by estimated value, demand, supply and volatility.','Unknown eligibility and insufficient evidence do not enter this ranking.')
    local ranked=0
    for _,r in ipairs(opportunities) do
        if r.action~='NO CLEAR RECOMMENDATION' and ranked<20 then ranked=ranked+1;recommendation(r,'top'..ranked) end
    end
    if ranked==0 then add('gold-no-top','No supported opportunity yet','No clear recommendation with the available evidence.','Build history; record professions and inventory; do not interpret missing estimates as zero value.') end
    for _,section in ipairs({{'Buy / Hold / Sell Recommendations',{'BUY NOW','HOLD','SELL NOW'}},{'Profitable Crafting Opportunities',{'CRAFT'}},{'Materials Worth Purchasing',{'BUY MATERIALS'}},{'Farming Opportunities',{'FARM'}}}) do
        add('section:'..section[1],section[1],'Evidence and eligibility required.','Each estimate explains its assumptions. No auction action is automated.')
        local count=0
        for _,r in ipairs(opportunities) do
            local matches=false
            for _,action in ipairs(section[2]) do if r.action==action then matches=true end end
            if matches and count<25 then count=count+1;recommendation(r,section[1]..count) end
        end
        if count==0 then add('empty:'..section[1],'No clear recommendation','Insufficient evidence or no eligible profitable action.','Crafts need verified learned recipes, transferable outputs and fee settings. Farming needs measured effort; it is never invented.') end
    end
    add('gold-history','Current Market Prices / Historical Price Comparison','Select an item for all five windows, coverage, volatility and freshness.','Daily values use UTC dates. Long-term values weight observed days equally.')
    local ids={};for id in pairs(prices) do ids[#ids+1]=id end;table.sort(ids)
    for i=1,math.min(100,#ids) do
        local id=ids[i];local q=prices[id]
        recommendation(self:Item(id,q,ch),'market')
    end
    add('gold-times','Best Days and Times','Available inside each item detail | '..tostring(FCM_AHHistory and FCM_AHHistory.timezone or 'timezone unavailable'),
        'Weekday comparisons require at least 10 observations across 4 dates per bucket. Hour comparisons require at least 10 observations across 5 dates. At least two supported buckets are compared. Prices are normalized against each UTC day to reduce long-term trend bias. Sparse or stale evidence yields no timing recommendation. Personal confirmed sales are not inferred from listings.')
    add('gold-personal-sales','Confirmed Personal Sales | market unassigned','Separate account ledger | excluded from market averages and rankings',
        'These are recorded sale-mail events, separate from listing prices and estimated demand. The ledger does not record region/ruleset/faction, so FCM cannot safely assign these events to a market. Recorded timestamps may reflect mail collection and are not used as sale-hour evidence. Net proceeds subtract the recorded AH cut; refunded deposits are listed separately. Acquisition costs are unknown, so proceeds are not profit.')
    local saleIds={}
    for id in pairs(FCM_AHHistory and FCM_AHHistory.personalSales or {}) do saleIds[#saleIds+1]=id end
    table.sort(saleIds,function(a,b)return tonumber(a)<tonumber(b) end)
    for i=1,math.min(50,#saleIds) do
        local id=saleIds[i];local s=FCM_AHHistory.personalSales[id]
        add('personal-sale:'..id,tonumber(id)==0 and 'Unresolved item sales (may contain multiple items)' or (FCM.ItemName and FCM.ItemName(tonumber(id))) or ('Item #'..id),
            tostring(s.events)..' confirmed records | '..tostring(s.units)..' units | net proceeds '..money(s.netProceeds),
            'Market unassigned; excluded from faction/region comparisons.\nGross: '..money(s.gross)..' | AH cut: '..money(s.cut)..' | Refunded deposits: '..money(s.refundedDeposits)..'\nLatest recorded event: '..tostring(s.latestRecordedLocal)..' '..tostring(FCM_AHHistory.timezone)..'\nAcquisition cost and exact sale time are unknown. These are proceeds, not profit.')
    end
    return rows
end
