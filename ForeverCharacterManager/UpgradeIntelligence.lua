-- FCM Unified v0.9.0 release candidate: account-wide upgrade intelligence.
-- Read-only interpretation of saved character scans and external reference data.
-- An estimated stat score is NOT a DPS prediction; reference loot is NOT a confirmed drop.
local _, FCM = ...
local MAX_PER_KIND = {crafted=4,dungeon=3,pattern=2}

local function list(value)
    return type(value)=="table" and value or {}
end
local function safeRows(fn,subject,character)
    if type(fn)~="function" then return {} end
    local ok,rows=pcall(fn,subject,character)
    return (ok and type(rows)=="table") and rows or {}
end
local function scoreLabel(value)
    if FCM.Gear and FCM.Gear.ScoreLabel then return FCM.Gear:ScoreLabel(value) end
    return string.format("%.1f", tonumber(value) or 0)
end
local function label(character)
    return (FCM.DisplayCharacter and FCM:DisplayCharacter(character)) or
        tostring(character.name or character.key or "Unknown")
end
local function stockStatus(plan)
    if not plan or not plan.crafter then return "No eligible learned crafter" end
    if #list(plan.blockers)>0 then return "Blocked / verify restrictions" end
    if (tonumber(plan.totalMissing) or 0)>0 then
        return tostring(plan.totalMissing).." materials missing (after nested crafts)"
    end
    if plan.ready then return "Recorded materials available; verify scans" end
    return "Materials/restrictions need verification"
end
local function comparisonScore(entry)
    -- Readiness improves actionability, but never turns score into a DPS estimate.
    local base=tonumber(entry.delta) or 0
    if entry.kind=="crafted" then
        return (entry.plan and entry.plan.ready and 10000 or
            (entry.plan and entry.plan.complete and 5000 or 1000))+base
    elseif entry.kind=="dungeon" then return 2000+base
    else return base end
end
local function order(a,b)
    local aRank,bRank=comparisonScore(a),comparisonScore(b)
    if aRank~=bRank then return aRank>bRank end
    if a.kind~=b.kind then return a.kind<b.kind end
    if a.character.key~=b.character.key then return tostring(a.character.key)<tostring(b.character.key) end
    if a.itemID~=b.itemID then return (tonumber(a.itemID) or 0)<(tonumber(b.itemID) or 0) end
    return tostring(a.slot)<tostring(b.slot)
end

-- Each proposed upgrade is assessed separately. This does NOT reserve all
-- recommended items together or promise that shared bank stock covers every row.
function FCM:AccountUpgradePlans(perCharacter)
    local all,seen={},{}
    local take=math.max(1,math.min(20,math.floor(tonumber(perCharacter) or 8)))
    for _,character in ipairs(safeRows(self.VisibleCharacters,self)) do
        if character and character.key then
            local kinds={crafted={},dungeon={},pattern={}}
            local crafted=safeRows(self.Gear and self.Gear.Candidates,self.Gear,character)
            for i=1,math.min(#crafted,15) do
                local c=crafted[i]
                local itemID=tonumber(c.recipe and c.recipe.outputID)
                if itemID and (tonumber(c.delta) or 0)>0 then
                    local key=tostring(character.key)..":"..itemID..":"..tostring(c.slot)..":crafted"
                    if not seen[key] then
                        seen[key]=true
                        local plan=nil
                        if type(self.SmartCraftingPlan)=="function" then
                            local ok,value=pcall(self.SmartCraftingPlan,self,c.recipe,character,nil,1)
                            if ok and type(value)=="table" then plan=value end
                        end
                        local itemName=(c.info and c.info.name) or c.recipe.name or ("Item #"..itemID)
                        kinds.crafted[#kinds.crafted+1]={kind="crafted",character=character,
                            itemID=itemID,itemName=itemName,slot=c.slot,delta=c.delta,
                            recipe=c.recipe,crafters=c.crafters,plan=plan,
                            status=stockStatus(plan)}
                    end
                end
            end
            local dungeon=safeRows(self.Gear and self.Gear.DungeonCandidates,self.Gear,character)
            for i=1,math.min(#dungeon,35) do
                local d=dungeon[i]
                local itemID=tonumber(d.itemID)
                if itemID and (tonumber(d.delta) or 0)>0 then
                    local key=tostring(character.key)..":"..itemID..":"..tostring(d.slot)..":dungeon"
                    if not seen[key] then
                        seen[key]=true
                        kinds.dungeon[#kinds.dungeon+1]={kind="dungeon",character=character,
                            itemID=itemID,itemName=(d.info and d.info.name) or ("Item #"..itemID),
                            slot=d.slot,delta=d.delta,sources=list(d.sources),
                            status="Reference drop location; not confirmed in-game"}
                    end
                end
            end
            local unlearned=safeRows(self.Gear and self.Gear.UnlearnedCandidates,self.Gear,character)
            for i=1,math.min(#unlearned,15) do
                local c=unlearned[i]
                local itemID=tonumber(c.entry and c.entry.outputID)
                if itemID and (tonumber(c.delta) or 0)>0 then
                    local key=tostring(character.key)..":"..itemID..":"..tostring(c.slot)..":pattern"
                    if not seen[key] then
                        seen[key]=true
                        kinds.pattern[#kinds.pattern+1]={kind="pattern",character=character,
                            itemID=itemID,itemName=(c.info and c.info.name) or ("Item #"..itemID),
                            slot=c.slot,delta=c.delta,pattern=c.entry,
                            status="Unlearned recipe; acquisition unverified"}
                    end
                end
            end
            local selected={}
            for _,kind in ipairs({"crafted","dungeon","pattern"}) do
                local group=kinds[kind]
                table.sort(group,order)
                for i=1,math.min(#group,MAX_PER_KIND[kind]) do
                    selected[#selected+1]=group[i]
                end
            end
            table.sort(selected,order)
            for i=1,math.min(#selected,take) do all[#all+1]=selected[i] end
        end
    end
    table.sort(all,order)
    return all
end

local function sortedNumericKeys(t)
    local ids={}
    for id,n in pairs(list(t)) do if tonumber(n) and tonumber(n)>0 then ids[#ids+1]=id end end
    table.sort(ids,function(a,b)
        if tonumber(a) and tonumber(b) then return tonumber(a)<tonumber(b) end
        return tostring(a)<tostring(b)
    end)
    return ids
end
function FCM:AccountUpgradePlanLines(entry)
    if not entry then return {"No recommendation selected."} end
    local ch=entry.character
    local activity=self.GearActivity and self:GearActivity(ch) or "leveling"
    local mode=self.Mode and self:Mode(ch,activity) or "dps"
    local lines={"|cffffd983ACCOUNT-WIDE UPGRADE PLAN (UNIFIED TEST)|r",
        entry.itemName or ("Item #"..tostring(entry.itemID)),
        "Recipient: "..label(ch),
        "Profile: "..tostring((self.gearActivityLabels or {})[activity] or activity).." / "..
            tostring((self.modeLabels or {})[mode] or mode),
        "Estimated weighted score improvement: +"..scoreLabel(entry.delta),
        "Source route: "..(entry.kind=="crafted" and "Known learned recipe" or
            (entry.kind=="dungeon" and "Imported dungeon reference" or "Unlearned recipe opportunity")),
        "Assessment: "..tostring(entry.status),""}
    if entry.kind=="crafted" then
        local p=entry.plan
        lines[#lines+1]="Recipe: "..tostring(entry.recipe and entry.recipe.name or "Unknown")
        lines[#lines+1]="Assigned planner crafter: "..(p and p.crafter and label(p.crafter) or "None recorded")
        if not p then
            lines[#lines+1]="No reliable crafting plan could be generated. Check recipe data."
        else
            lines[#lines+1]="Missing after saved stock, reservations and intermediate crafts: "..
                tostring(p.totalMissing or "unknown")
            lines[#lines+1]="This is ONE potential craft; other recommendations may need the same stock."
            if #list(p.steps)>0 then
                lines[#lines+1]="Craft sequence (not automatically executed):"
                for i,step in ipairs(p.steps) do
                    if i>12 then lines[#lines+1]="  Additional steps omitted";break end
                    lines[#lines+1]="  "..tostring(step.crafts or 1).."x "..tostring(step.recipe or "Unknown")..
                        " by "..(step.crafter and label(step.crafter) or "unknown")
                end
            end
            if #sortedNumericKeys(p.missing)>0 then
                lines[#lines+1]="Outstanding materials:"
                for _,id in ipairs(sortedNumericKeys(p.missing)) do
                    lines[#lines+1]="  "..tostring(p.missing[id]).." x "..
                        tostring(self.ItemName and self.ItemName(id) or ("Item #"..tostring(id)))
                end
            end
            if #list(p.transfers)>0 then
                lines[#lines+1]="Potential transfers (manual only):"
                for i,t in ipairs(p.transfers) do
                    if i>12 then lines[#lines+1]="  Additional transfers omitted";break end
                    lines[#lines+1]="  "..tostring(t.count or 0).."x "..tostring(t.name or "item")..
                        " from "..tostring(t.from or "unknown").." to "..tostring(t.to or "unknown")
                end
            end
            for _,warning in ipairs(list(p.warnings)) do lines[#lines+1]="Check: "..tostring(warning) end
            for _,blocker in ipairs(list(p.blockers)) do lines[#lines+1]="Blocked: "..tostring(blocker) end
            if p.reputation then
                local gate=p.reputation
                lines[#lines+1]="Recorded reputation gate: "..tostring(gate.faction or gate.factionID or "Unknown")..
                    " | "..tostring(gate.current or "?").." / "..tostring(gate.required or "?")..
                    " (verify vendor access)"
            end
        end
    elseif entry.kind=="dungeon" then
        lines[#lines+1]="Reported dungeon associations (NOT verified live drops):"
        for i,source in ipairs(list(entry.sources)) do
            if i>12 then lines[#lines+1]="  Additional references omitted";break end
            lines[#lines+1]="  "..tostring(source)
        end
        if #list(entry.sources)==0 then lines[#lines+1]="  Boss or dungeon source missing" end
        lines[#lines+1]="The character's current scanned gear and client stats determine this score."
    elseif entry.kind=="pattern" then
        local p=entry.pattern or {}
        lines[#lines+1]="Profession: "..tostring(p.profession or "Unknown")
        lines[#lines+1]="Unlearned recipe name: "..tostring(p.name or "Unknown")
        lines[#lines+1]="Reference acquisition: "..tostring(p.source or "Not recorded")
        lines[#lines+1]="Not craftable until the recipe, faction and reputation gates are confirmed."
    end
    lines[#lines+1]=""
    lines[#lines+1]="Priorities use heuristic weighted stat scores, not real DPS or verified loot/drop odds."
    lines[#lines+1]="Refresh character inventories, gear and reputations before acting on offline advice."
    return lines
end
