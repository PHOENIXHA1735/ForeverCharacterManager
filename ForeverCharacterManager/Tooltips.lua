local _, FCM = ...
-- Modern tooltip API. Read-only; never overrides native stats or item links.
local function extraLines(tooltip,data)
    if not FCM.db or FCM.db.settings.tooltip==false then return end
    local itemID=data and tonumber(data.id)
    if not itemID then return end
    local recipe=FCM:RecipeForOutput(itemID)
    local spellID
    if C_Item and C_Item.GetItemSpell then
        local _,id=FCM:Try(C_Item.GetItemSpell,itemID)
        spellID=id
    end
    local known=spellID and FCM:KnownNamesForRecipe(spellID) or {}
    local active=FCM:Current()
    local upgradeText
    if active and FCM.Gear and FCM.Gear.Info and C_Item and C_Item.GetItemStats then
        local info=FCM.Gear:Info(itemID)
        if FCM.Gear:IsPotentiallyWearable(info,active) then
            local score=FCM.Gear:Score(info.link or itemID,active,FCM:Mode(active))
            local bestDelta
            for _,slot in ipairs(FCM.Gear.slots[info.equip] or {}) do
                local old=active.gear and active.gear[slot]
                local baseline=(old and old.link and FCM.Gear:Score(old.link,active,FCM:Mode(active))) or 0
                if score and (not bestDelta or (score-baseline)>bestDelta) then bestDelta=score-baseline end
            end
            if bestDelta and bestDelta>=(FCM.db.settings.minimumUpgrade or 1) then
                upgradeText="Possible "..(FCM.modeLabels[FCM:Mode(active)] or "gear").." upgrade: +"..
                    FCM.Gear:ScoreLabel(bestDelta).." weighted points"
            end
        end
    end
    if not recipe and #known==0 and not upgradeText then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("Forever Character Manager",0.43,0.82,1)
    if upgradeText then tooltip:AddLine(upgradeText,0.55,1,0.63,true) end
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
