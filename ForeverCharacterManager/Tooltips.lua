local _, FCM = ...
-- Modern tooltip API. Read-only; never overrides native stats or item links.
local function extraLines(tooltip,data)
    if not FCM.db or FCM.db.settings.tooltip==false then return end
    local itemID=data and tonumber(data.id)
    if not itemID then return end
    local inspectedItem=(data and type(data.hyperlink)=="string" and data.hyperlink) or itemID
    if tooltip and type(tooltip.GetItem)=="function" then
        local ok,_,link=pcall(tooltip.GetItem,tooltip)
        if ok and type(link)=="string" and link:find("item:",1,true) then
            inspectedItem=link
        end
    end
    local recipe=FCM:RecipeForOutput(itemID)
    local spellID
    if C_Item and C_Item.GetItemSpell then
        local _,id=FCM:Try(C_Item.GetItemSpell,itemID)
        spellID=id
    end
    local known=spellID and FCM:KnownNamesForRecipe(spellID) or {}
    local active=FCM:Current()
    local upgradeText
    -- Use the same validated slot comparison as the main Gear pane. Never
    -- assume a missing/unknown equipped item has a score of zero.
    if active and FCM.Gear and FCM.Gear.CompareItem then
        local comparison=FCM.Gear:CompareItem(inspectedItem,active)
        if comparison and comparison.status=="ok" and comparison.delta>=
                (FCM.db.settings.minimumUpgrade or 1) then
            local scoredSpec=type(active.talentSpec)=="string" and active.talentSpec or "spec unconfirmed"
            upgradeText="Possible upgrade for "..tostring(active.name or "this character")..
                " ("..scoredSpec.."): +"..FCM.Gear:ScoreLabel(comparison.delta).." weighted points"
        end
    end
    local boe
    if active and type(FCM.BoEProtectionCheck)=="function" then
        local ok,result=pcall(FCM.BoEProtectionCheck,FCM,inspectedItem,active)
        if ok and result and result.info and result.info.bindType==2 then boe=result end
    end
    local market=nil
    local quality, vendor
    if C_Item and type(C_Item.GetItemInfo)=="function" then
        local ok,_,_,q,_,_,_,_,_,_,_,v=pcall(C_Item.GetItemInfo,itemID)
        if ok then quality=q;vendor=tonumber(v) end
    end
    -- Prefer a precise bag-stack count when the tooltip owner exposes the bag
    -- and slot. Never infer stack size from an account-wide inventory total.
    local qty=data and tonumber(data.quantity)
    if (not qty or qty<1) and tooltip and type(tooltip.GetOwner)=="function" then
        local ok,owner=pcall(tooltip.GetOwner,tooltip)
        if ok and owner and type(owner.GetBagID)=="function" and type(owner.GetID)=="function" and
            C_Container and type(C_Container.GetContainerItemInfo)=="function" then
            local good,bag=pcall(owner.GetBagID,owner)
            local slotGood,slot=pcall(owner.GetID,owner)
            if good and slotGood and type(bag)=="number" and type(slot)=="number" then
                local infoOK,bagInfo=pcall(C_Container.GetContainerItemInfo,bag,slot)
                if infoOK and type(bagInfo)=="table" and tonumber(bagInfo.itemID)==itemID then
                    qty=tonumber(bagInfo.stackCount)
                end
            end
        end
    end
    if active and type(FCM.MarketItemAdvice)=="function" then
        market=FCM:MarketItemAdvice(itemID,active,qty,quality,vendor)
    end
    local showFarm=false
    if type(FCM.FarmSources)=="function" and
        (market and market.promising or recipe) then
        local ok,sources=pcall(FCM.FarmSources,FCM,itemID)
        showFarm=ok and type(sources)=="table" and #sources>0
    end
    if not recipe and #known==0 and not upgradeText and not boe and not market and not showFarm then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("Forever Character Manager v"..tostring(FCM.version),0.43,0.82,1)
    if market then
        local function coin(copper)
            if type(FCM.MoneyLabel)=="function" then return FCM:MoneyLabel(copper) end
            local n=math.floor(tonumber(copper) or 0)
            return string.format("%dg %ds %dc",math.floor(n/10000),math.floor(n%10000/100),n%100)
        end
        if market.median then tooltip:AddLine("AH median listing: "..coin(market.median).." each",1,0.84,0.4) end
        if market.minBuyout then tooltip:AddLine("Lowest buyout: "..coin(market.minBuyout).." each",0.85,0.85,0.85) end
        if qty and qty>1 and market.stackMedian then
            tooltip:AddLine("Stack of "..market.stackCount..": about "..coin(market.stackMedian),0.85,0.85,0.85)
        end
        if market.vendor then tooltip:AddLine("Vendor: "..coin(market.vendor).." each",0.8,0.8,0.8) end
        if market.change7 then
            tooltip:AddLine(string.format("vs. source 7-day median: %+.0f%%",market.change7),0.72,0.84,0.95)
        end
        if market.change30 then
            tooltip:AddLine(string.format("vs. source 30-day median: %+.0f%%",market.change30),0.72,0.84,0.95)
        end
        if market.soldPerDay then
            tooltip:AddLine(string.format("Reported units/day: %.1f (source estimate)",market.soldPerDay),0.72,0.84,0.95)
        end
        if market.observedAt then tooltip:AddLine("AH observed: "..tostring(market.observedAt),0.69,0.75,0.82) end
        if market.snapshot then tooltip:AddLine("AHledger bundled snapshot - verify prices before acting",1,0.70,0.40,true) end
        if market.promising then tooltip:AddLine("FCM: CHECK AH BEFORE VENDORING",0.5,1,0.62,true) end
        tooltip:AddLine("AHledger (ahledger.com): asking prices are not confirmed sales.",0.60,0.69,0.82,true)
    end
    if showFarm then
        local summary=FCM:FarmQuickLine(itemID,active,1)
        if summary then tooltip:AddLine(summary,0.75,0.88,0.95,true) end
    end
    if upgradeText then tooltip:AddLine(upgradeText,0.55,1,0.63,true) end
    if boe then
        local keep=boe.status=="keep"
        local r,g,b=keep and 0.45 or 1, keep and 0.92 or 0.80, keep and 0.58 or 0.40
        tooltip:AddLine("BOE / DE CHECK: "..tostring(boe.message),r,g,b,true)
        local shown=0
        for _,entry in ipairs(boe.candidates or {}) do
            if shown>=3 then break end
            local faction=FCM:NormalizeFaction(entry.character and entry.character.faction) or "Unknown"
            tooltip:AddLine(string.format("  %s (%s): +%.1f pts%s%s",entry.name,faction,entry.delta,
                entry.future and (" | equip level "..entry.requiredLevel).." (now "..entry.currentLevel..")" or " | usable now",
                not entry.transferable and " | mail/trade unverified" or ""),
                entry.transferable and 0.55 or 1,entry.transferable and 0.9 or 0.78,0.65,true)
            shown=shown+1
        end
        local excluded=0
        for _,entry in ipairs(boe.excluded or {}) do
            if excluded>=2 then break end
            tooltip:AddLine("  Excluded "..tostring(entry.name).." ("..
                tostring(entry.faction or "Unknown").."): "..tostring(entry.reason),
                0.7,0.72,0.77,true)
            excluded=excluded+1
        end
        if boe.transferState~="unbound" then
            tooltip:AddLine("Verify this copy is still unbound before mailing or DE.",1,0.72,0.38,true)
        end
    end
    if recipe then
        local names={}
        for _,ch in ipairs(recipe.crafters) do names[#names+1]=ch.name or "Unknown" end
        tooltip:AddLine("Known crafter: "..table.concat(names,", "),0.75,0.95,0.76,true)
    end
    if #known>0 then
        tooltip:AddLine("Pattern learned by: "..table.concat(known,", "),0.75,0.95,0.76,true)
    end
    tooltip:AddLine("Scores are estimates; offline snapshots may be outdated.",0.65,0.65,0.65,true)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,extraLines)
end
