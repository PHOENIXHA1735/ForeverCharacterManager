local _, FCM = ...
-- Starter records are compact, sourced examples. ExternalData.generated.lua
-- is written by the optional Windows companion and loaded *after* this file.
-- Neither file reads or changes SavedVariables.
FCM.externalData = FCM.externalData or { edition="starter 2026-11-09", items={}, recipes={} }
FCM.externalData.items = FCM.externalData.items or {}
FCM.externalData.recipes = FCM.externalData.recipes or {}
FCM.externalData.prices = FCM.externalData.prices or {}
FCM.externalData.dungeons = FCM.externalData.dungeons or {}
FCM.externalData.items[6291] = {
    name="Raw Brilliant Smallfish", category="Fishing reagent",
    where="Low-level freshwater: Elwynn Forest, Stormwind City, Durotar, Mulgore, Tirisfal Glades, Teldrassil, Dun Morogh, Loch Modan and other starting areas. Specific catches vary.",
    uses="Brilliant Smallfish (Cooking 1); Fish Bowl (Fishing 20); Fish Chunks",
    recipes="Recipe: Brilliant Smallfish, item 6325. Vendors include Catherine Leland (Stormwind), Tharynn Bouden (Elwynn Forest), Sewa Mistrunner (Thunder Bluff), and other fishing/cooking suppliers.",
    link="https://db.icy-veins.com/wow-forever/items/6291",
    source="Icy Veins Forever database; Wowhead Forever; Questing.wiki Forever",
    sourceStatus="Reference; verify live availability"
}
FCM.externalData.items[6325] = {
    name="Recipe: Brilliant Smallfish", category="Cooking recipe",
    where="Vendor purchase: Catherine Leland (Stormwind City); Tharynn Bouden (Elwynn Forest); Sewa Mistrunner (Thunder Bluff); and other cooking/fishing vendors.",
    uses="Teaches Brilliant Smallfish (Cooking 1)",
    link="https://www.wowhead.com/forever/item=6325/recipe-brilliant-smallfish",
    source="Wowhead Forever; Questing.wiki Forever",
    sourceStatus="Vendor list from public references; verify in game"
}

-- Sourced starter item used to verify general item searches before a full catalog sync.
-- User's later ForeverDB imports may replace/add details for this item.
FCM.externalData.items[3173] = {
    name="Bear Meat", category="Cooking reagent", quality=1, itemLevel=11,
    where="Reported bear drops; ForeverDB distinguishes player-observed sources from older Classic reference data.",
    uses="Cooking reagent used in Blood Sausage and Smoked Bear Meat.",
    link="https://foreverdb.net/item/3173",
    source="ForeverDB.net / WoW Forever item #3173",
    sourceStatus="Seen in Forever reference; individual drop sources require verification"
}

function FCM:ExplorerRecords()
    local output, seen = {}, {}
    local items=(self.externalData and self.externalData.items) or {}
    for id,entry in pairs(items) do
        if type(id)=="number" and type(entry)=="table" then
            output[#output+1]={id=id, name=entry.name or ("Item #"..id), item=entry}
            seen[id]=true
        end
    end
    -- Locally observed items are included even when online metadata has never
    -- been imported. Their source information is then explicitly unknown.
    for _,char in pairs((self.db and self.db.characters) or {}) do
        for _,storage in ipairs({char.bags or {},char.bank or {},char.gear or {}}) do
            for _,record in pairs(storage) do
                local id=type(record)=="table" and tonumber(record.itemID)
                if id and not seen[id] then
                    local name=record.name
                    if not name and self.ItemName then name=self.ItemName(id) end
                    output[#output+1]={id=id,name=name or ("Item #"..id), item={name=name or ("Item #"..id),sourceStatus="Observed in character scan; reference details unavailable"}}
                    seen[id]=true
                end
            end
        end
    end
    table.sort(output,function(a,b) return (a.name or "") < (b.name or "") end)
    return output
end

function FCM:ExplorerDetails(itemID)
    local item=(self.externalData and self.externalData.items and self.externalData.items[itemID]) or {}
    local result={"Item #"..tostring(itemID).."  "..(item.name or ""),""}
    local function field(label,value)
        if value and tostring(value)~="" then result[#result+1]=label..": "..tostring(value) end
    end
    field("Category",item.category)
    field("Where to obtain",item.where)
    if self.FarmAdviceLines then
        result[#result+1]=""
        for _,line in ipairs(self:FarmAdviceLines(itemID,1,nil,5)) do result[#result+1]=line end
        result[#result+1]=""
    end
    field("Reported dungeon drops",item.dungeonSources or item.dungeon)
    field("Source confidence",item.confidence)
    field("Reference provider",item.sourceProvider)
    field("Reference last checked",item.referenceCheckedAt)
    field("Evidence level",item.sourceEvidence)
    field("Gathering evidence",item.gatheringEvidence)
    field("Vendor evidence",item.vendorEvidence)
    -- Reuse the same market and quality evaluation as the bag tooltip.
    local marketInfo
    if type(self.MarketItemAdvice)=="function" then
        marketInfo=self:MarketItemAdvice(itemID,nil,1,item.quality,item.vendorPrice)
        if marketInfo then
            for _,line in ipairs(self:MarketItemAdviceLines(marketInfo)) do result[#result+1]=line end
            result[#result+1]=""
        end
    end
    local price=self:PriceQuote(itemID)
    if price and not marketInfo then
        local function money(copper)
            local c=tonumber(copper)
            if not c then return "Unavailable" end
            return string.format("%dg %ds %dc",math.floor(c/10000),math.floor(c%10000/100),math.floor(c%100))
        end
        field("Auction price source", "AHledger (ahledger.com); market "..tostring(price.market or "unselected"))
        field("Median price (recorded)",money(price.median))
        field("Lowest buyout (recorded)",money(price.minBuyout))
        field("Last market scan", price.observedAt or price.updated)
        result[#result+1]="Prices are historical snapshots, not current live auctions."
    end
    field("Uses / crafted outputs",item.uses)
    field("Recipe sources",item.recipes)
    field("Item stats (database)",item.stats)
    field("Item effects (database)",item.effects)
    local recipes=(self.externalData and self.externalData.recipes) or {}
    local related={}
    for _,r in pairs(recipes) do
        if type(r)=="table" then
            local used=false
            for _,mat in ipairs(r.reagents or {}) do
                if tonumber(mat.id)==itemID then used=true; break end
            end
            if used then
                related[#related+1]=(r.name or "Unknown craft").." ["..(r.profession or "Profession unknown").."]"
            end
        end
    end
    table.sort(related)
    if #related>0 then
        result[#result+1]=""
        result[#result+1]="Used in imported recipes (up to 20):"
        for i=1,math.min(#related,20) do result[#result+1]=" - "..related[i] end
        if #related>20 then result[#result+1]=" ... and "..(#related-20).." more" end
        result[#result+1]="Crafting data: AHledger (ahledger.com) or ForeverDB.net; check individual recipe source"
    end
    for _,r in pairs(recipes) do
        if type(r)=="table" and tonumber(r.resultID)==itemID then
            result[#result+1]="Produced by: "..(r.name or "Unknown recipe").." ("..(r.profession or "Profession unknown")..")"
            field("Recipe acquisition",r.acquisition)
            field("Reference provider",r.sourceProvider)
            field("Reference last checked",r.referenceCheckedAt)
            field("Reference evidence",r.sourceEvidence)
            field("Required profession skill",r.skill)
            result[#result+1]=r.source or "Imported reference recipe; verify against current client"
        end
    end
    local owners={}
    for _,ch in ipairs(self:Characters()) do
        local total=0
        for _,storage in ipairs({ch.bags or {},ch.bank or {}}) do
            for _,rec in pairs(storage) do
                if tonumber(rec.itemID)==itemID then total=total+(tonumber(rec.count) or 1) end
            end
        end
        if total>0 then owners[#owners+1]=self:DisplayCharacter(ch)..": "..total end
    end
    result[#result+1]=""
    result[#result+1]="Account inventory (last scans): "..(#owners>0 and table.concat(owners,"; ") or "none recorded")
    field("Data status",item.sourceStatus or "Partial imported data: may lack sources")
    field("Reference",item.link)
    field("Attribution",item.source)
    field("Additional data",item.metadataSource)
    if ((item.metadataSource or ""):find("ForeverDB",1,true) or (item.source or ""):find("ForeverDB",1,true)) then
        result[#result+1]="ForeverDB attribution: https://foreverdb.net"
    end
    field("Last external update",self.externalData and self.externalData.edition)
    return table.concat(result,"\n")
end

function FCM:DungeonRecords()
    local result={}
    for id,r in pairs((self.externalData and self.externalData.dungeons) or {}) do
        if type(r)=="table" then result[#result+1]={id=id,record=r} end
    end
    table.sort(result,function(a,b)return (a.record.name or "") < (b.record.name or "") end)
    return result
end

-- Only compares sources with sufficient current imported snapshot data.
-- Results are cost *estimates*, not in-game auction actions or guaranteed sales.
-- AHledger prices are faction AND market-specific, never global gold values.
-- A Horde character must not receive an Alliance price merely because the
-- item ID matches. If multiple rule-set markets match and the rule set cannot
-- be established from the character record, the price is considered unknown.
function FCM:MarketPricesFor(ch)
    local data=self.externalData or {}
    ch=ch or (self.UI and self.UI.GetCharacter and self.UI:GetCharacter()) or
        (self.db and self.db.characters[self.currentKey or ""])
    local faction=ch and self:NormalizeFaction(ch.faction)
    if not faction then return {} end
    local wanted="."..string.lower(faction).."."
    -- Prefer the scheduled, ruleset-specific AH pair when its source cache is
    -- still valid. Do not mix Normal/PvP or Horde/Alliance prices.
    local canonical={Normal="normal",PvP="pvp",RP="rp",["RP-PvP"]="rppvp",Hardcore="hardcore"}
    local rule=canonical[self:NormalizeRuleset(ch and ch.ruleset)]
    local currentRegion=ch and type(ch.region)=="string" and string.lower(ch.region) or nil
    -- No guessing from surnames or a companion's last selected market.
    if not rule or not currentRegion or currentRegion=="" then return {} end
    local ruleset=data.dailyAHRuleSet
    local region=data.dailyAHRegion
    local now=(type(time)=="function" and time()) or (os and os.time and os.time()) or 0
    if ruleset and region and string.lower(tostring(ruleset))==rule and
       string.lower(tostring(region))==currentRegion and
       (tonumber(data.dailyAHExpiresAt) or 0)>now then
        local selected="forever."..rule.."."..string.lower(faction).."."..currentRegion
        local items=data.pricesByMarket and data.pricesByMarket[selected]
        if type(items)=="table" then return items end
    end
    local options={}
    for market,items in pairs(data.pricesByMarket or {}) do
        if type(market)=="string" and type(items)=="table" and
           market:find(wanted,1,true) and market:find("forever."..rule..".",1,true)==1 and
           market:sub(-#currentRegion)==currentRegion then
            options[#options+1]=items
        end
    end
    if #options==1 then return options[1] end
    if #options>1 then return {} end -- ambiguous ruleset/region
    local legacy=data.prices or {}
    local market=nil
    for _,price in pairs(legacy) do
        if type(price)=="table" and price.market then market=price.market;break end
    end
    if market and market:find(wanted,1,true) and
       market:find("forever."..rule..".",1,true)==1 and
       market:sub(-#currentRegion)==currentRegion then
        return legacy
    end
    return {}
end
-- AHledger's in-game API owns its market data and freshness. This module
-- NEVER copies AHledger price data into character SavedVariables or generated
-- Lua cache. FCM only reads it while the user is playing.
-- Market identifiers may use either dots or slashes, depending on the API
-- response; canonicalize them before comparing, without mixing factions.
local function canonicalAHMarket(value)
    if type(value)~="string" then return nil end
    local key=string.lower(value):gsub("/", ".")
    local game,rule,faction,region=key:match("^([%w]+)%.([%w]+)%.([%w]+)%.([%w]+)$")
    if game~="forever" or (faction~="alliance" and faction~="horde") or
       (region~="us" and region~="eu" and region~="cn") or
       (rule~="normal" and rule~="pvp" and rule~="rp" and rule~="rppvp") then
        return nil
    end
    return key
end

local function aHLQuote(p,selected)
    if type(p)~="table" then return nil end
    local actual=canonicalAHMarket(p.market)
    -- An explicit requested market must not yield a different market's quote.
    if selected and actual and actual~=selected then return nil end
    local median=tonumber(p.median)
    local low=tonumber(p.minBuyout)
    if not ((median and median>0) or (low and low>0)) then return nil end
    local observed=p.updated
    return {market=actual or selected,median=median,minBuyout=low,
        quantity=tonumber(p.quantity),
        median7d=tonumber(p.median7d),median30d=tonumber(p.median30d),
        soldPerDay=tonumber(p.soldPerDay),
        source="AHledgerAPI",snapshot=p.snapshot==true,
        observedAt=observed and tostring(observed) or nil,
        observedUnix=tonumber(observed)}
end

function FCM:PriceQuote(itemID,ch)
    itemID=tonumber(itemID)
    if not itemID or itemID<=0 then return nil end
    local api=AHledgerAPI
    if type(api)=="table" and type(api.GetPrice)=="function" then
        local current=self:Current()
        local target=ch or current
        local playerFaction=type(UnitFactionGroup)=="function" and
            self:NormalizeFaction(UnitFactionGroup("player")) or nil
        local faction=target and self:NormalizeFaction(target.faction)
        -- A current-player quote is safe to obtain using the documented
        -- default-market form; an offline character's price is NOT.
        local active=not ch or (current~=nil and ch==current)
        if not faction and active then faction=playerFaction end
        local ownMarket=nil
        if type(api.GetMarket)=="function" then
            local ok,value=pcall(api.GetMarket)
            if ok then ownMarket=canonicalAHMarket(value) end
        end
        local requested=nil
        if faction and ownMarket then
            local rule,_,region=ownMarket:match("^forever%.([%w]+)%.([%w]+)%.([%w]+)$")
            requested="forever."..rule.."."..string.lower(faction).."."..region
            -- Explicit market is essential for other characters, including
            -- offline Horde characters viewed from an Alliance login.
            local ok,p=pcall(api.GetPrice,itemID,requested)
            if ok then
                local quote=aHLQuote(p,requested)
                if quote then return quote end
            end
        end
        -- Some AHledger versions expose their price lookup before their
        -- market helper, or return nil on explicit-market lookup even though
        -- their default/current-market lookup is populated. Only use this
        -- fallback for the logged-in character, never for an offline toon.
        if active and faction and playerFaction==faction then
            local ok,p=pcall(api.GetPrice,itemID)
            if ok and type(p)=="table" then
                local actual=canonicalAHMarket(p.market)
                -- If a market is supplied, its faction MUST match the player.
                if actual then
                    local pFaction=actual:match("^forever%.[%w]+%.([%w]+)%.")
                    if pFaction==string.lower(faction) and
                       (not ownMarket or actual==ownMarket) then
                        local quote=aHLQuote(p,actual)
                        if quote then return quote end
                    end
                elseif ownMarket and ownMarket:find("."..string.lower(faction)..".",1,true) then
                    local quote=aHLQuote(p,ownMarket)
                    if quote then return quote end
                end
            end
        end
    end
    -- Previous provider cache is accepted only while its expiry is valid.
    local quote=self:MarketPricesFor(ch)[itemID]
    if quote and quote.expiresAt then
        local now=(type(time)=="function" and time()) or (os and os.time and os.time()) or 0
        if tonumber(quote.expiresAt)<=now then return nil end
    end
    return quote
end

-- In-game diagnostics, intentionally no API tokens/account information.
function FCM:AHPriceDiagnostic(itemID)
    local api=AHledgerAPI
    local available=type(api)=="table" and type(api.GetPrice)=="function"
    local market=nil
    if available and type(api.GetMarket)=="function" then
        local ok,value=pcall(api.GetMarket)
        if ok then market=tostring(value) end
    end
    local direct=nil
    if available then
        local ok,p=pcall(api.GetPrice,tonumber(itemID) or 4537)
        if ok and type(p)=="table" then direct=p end
    end
    local ch=self:Current()
    local quote=self:PriceQuote(itemID,ch)
    self:Say("AH check: AHledger API "..(available and "present" or "missing")..
        " | player market "..tostring(market or "unavailable")..
        " | faction "..tostring(ch and ch.faction or "unknown"))
    self:Say("AH check: provider median "..tostring(direct and direct.median or "nil")..
        " | provider market "..tostring(direct and direct.market or "nil")..
        " | FCM median "..tostring(quote and quote.median or "nil"))
end
function FCM:CraftPriceEstimate(recipe,ch)
    if not recipe then return nil end
    local result=self:PriceQuote(recipe.outputID or recipe.resultID,ch)
    local total=0
    local missing=0
    local market=nil
    for _,reagent in ipairs(recipe.reagents or {}) do
        local id=reagent.itemID or reagent.id
        local qty=tonumber(reagent.count or reagent.qty) or 0
        if not id or qty<=0 then
            missing=missing+1
        else
            local quote=self:PriceQuote(id,ch)
            if quote and tonumber(quote.median) and tonumber(quote.median)>0 then
                if market and quote.market~=market then missing=missing+1 end
                market=market or quote.market
                total=total+tonumber(quote.median)*qty
            else missing=missing+1 end
        end
    end
    if not recipe.reagents or #recipe.reagents==0 then missing=missing+1 end
    if not result or result.market~=market then result=nil end
    return {materialCost=total,unknown=missing,market=market,resultMedian=result and tonumber(result.median) or nil}
end
function FCM:MoneyLabel(copper)
    copper=tonumber(copper)
    if not copper then return "not priced" end
    copper=math.floor(copper+0.5)
    return string.format("%dg %ds %dc",math.floor(copper/10000),math.floor((copper%10000)/100),copper%100)
end
