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
    field("Reported dungeon drops",item.dungeon)
    field("Source confidence",item.confidence)
    local price=self:PriceQuote(itemID)
    if price then
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
    local realm=ch and type(ch.realm)=="string" and string.lower(ch.realm) or ""
    local rule=nil
    if realm:find("rppvp",1,true) then rule="rppvp"
    elseif realm:find("normal",1,true) then rule="normal"
    elseif realm:find("pvp",1,true) then rule="pvp"
    elseif realm:find("roleplay",1,true) or realm=="rp" then rule="rp" end
    local options={}
    for market,items in pairs(data.pricesByMarket or {}) do
        if type(market)=="string" and type(items)=="table" and
           market:find(wanted,1,true) and (not rule or market:find("forever."..rule..".",1,true)==1) then
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
       (not rule or market:find("forever."..rule..".",1,true)==1) then
        return legacy
    end
    return {}
end
function FCM:PriceQuote(itemID,ch)
    return self:MarketPricesFor(ch)[tonumber(itemID)]
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
