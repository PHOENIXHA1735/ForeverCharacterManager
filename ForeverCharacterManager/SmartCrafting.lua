-- FCM v0.10.0: offline, read-only, account-wide crafting plan.
-- Data comes from character snapshots and learned recipes. No protected actions.
local _, FCM = ...
local MAX_DEPTH = 6
local function amount(n)
    return math.max(0, math.floor((tonumber(n) or 0) + 0.00001))
end
local function sortedKeys(t)
    local ids={}
    for k in pairs(t or {}) do ids[#ids+1]=k end
    table.sort(ids,function(a,b)return tostring(a)<tostring(b) end)
    return ids
end
local function display(ch)
    return (ch and FCM.DisplayCharacter and FCM:DisplayCharacter(ch)) or
        (ch and (ch.name or ch.key)) or "Unknown"
end
local function addUnique(target,seen,message)
    if message and not seen[message] then target[#target+1]=message;seen[message]=true end
end
local function boundInfo(itemID)
    local info=FCM.Gear and FCM.Gear.Info and FCM.Gear:Info(itemID)
    if info and tonumber(info.bindType) then return tonumber(info.bindType) end
    -- Imported item records can have incomplete/unknown binding metadata.
    local ref=FCM.externalData and FCM.externalData.items and
        (FCM.externalData.items[tonumber(itemID)] or FCM.externalData.items[tostring(itemID)])
    if ref then
        local n=tonumber(ref.bindType)
        if n then return n end
    end
    return nil
end
local function eligibleCrafters(recipe,recipient,outputID)
    local list={}
    local bop=outputID and boundInfo(outputID)==1
    for _,ch in ipairs(recipe and recipe.crafters or {}) do
        if ch and ch.key and recipient and FCM:CanCollaborate(ch,recipient) and
            (not bop or ch.key==recipient.key) then list[#list+1]=ch end
    end
    table.sort(list,function(a,b)return tostring(a.key)<tostring(b.key) end)
    return list
end
local function makeSources(recipient)
    local sources={}
    for _,ch in ipairs(FCM:Characters()) do
        for _,where in ipairs({"bags","bank"}) do
            for _,stackKey in ipairs(sortedKeys(ch[where])) do
                local stack=ch[where][stackKey]
                local id=tonumber(stack and stack.itemID)
                local count=amount(stack and stack.count)
                if id and count>0 then
                    sources[id]=sources[id] or {}
                    sources[id][#sources[id]+1]={owner=ch,where=where,stackKey=stackKey,
                        bound=stack.bound==true,bindingKnown=type(stack.bound)=="boolean",
                        amount=count,initial=count,
                        stamp=ch[where=="bags" and "bagsStamp" or "bankStamp"]}
                end
            end
        end
    end
    return sources
end
local function makePlan(recipe,recipient,crafter,crafts,excludeKey)
    local plan={recipe=recipe,recipient=recipient,crafter=crafter,
        requestedCrafts=crafts,steps={},missing={},transfers={},warnings={},blockers={},
        used={},reserved={},uncertain=false,ready=false,stockReady=false,complete=false,
        totalMissing=0,generated={},snapshots={},source="Recorded character scans (not live inventory)"}
    local warnSeen,blockSeen={},{ }
    local function warn(msg) addUnique(plan.warnings,warnSeen,msg) end
    local function block(msg) addUnique(plan.blockers,blockSeen,msg) end
    if not recipient then block("No recipient selected.") end
    if not crafter then block("No eligible learned crafter is recorded for this recipient.") end
    if not recipe or recipe.complex or type(recipe.reagents)~="table" or #recipe.reagents==0 then
        block("Main recipe has unknown, alternative, or incomplete reagent requirements.")
    end
    if not crafter or #plan.blockers>0 then
        plan.uncertain=true
        return plan
    end
    local outputBinding=recipe.outputID and boundInfo(recipe.outputID)
    if outputBinding==1 and crafter.key~=recipient.key then
        block("Bind-on-pickup output must be crafted by its recipient.")
    elseif not outputBinding and crafter.key~=recipient.key then
        warn("Output binding not verified; confirm that the crafted item is transferable.")
    end
    local gate=FCM.ReputationGate and FCM:ReputationGate(recipe.id,crafter)
    if gate then
        plan.reputation=gate
        -- A gate governs acquisition of a recipe; this crafter already learned it.
        if not gate.unlocked then
            warn("Recorded reputation gate is not satisfied or is outdated; verify access to the recipe/vendor.")
        end
    end
    local pool=makeSources(recipient)
    local reservations=(FCM.ReservedMaterials and FCM:ReservedMaterials(excludeKey,crafter)) or {}
    for id,count in pairs(reservations) do
        id=tonumber(id)
        count=amount(count)
        if id then
            plan.reserved[id]=count
            local left=count
            -- Conservatively remove previously requested stock from the global pool.
            for _,src in ipairs(pool[id] or {}) do
                local take=math.min(left,src.amount)
                src.amount=src.amount-take
                left=left-take
                if left<=0 then break end
            end
        end
    end
    local index={}
    for _,r in ipairs(FCM:AllRecipes()) do
        local id=tonumber(r.outputID)
        if id and id~=tonumber(recipe.outputID) and not r.complex and
           type(r.reagents)=="table" and #r.reagents>0 then
            index[id]=index[id] or {}
            index[id][#index[id]+1]=r
        end
    end
    for _,arr in pairs(index) do
        table.sort(arr,function(a,b)return tostring(a.id)<tostring(b.id) end)
    end
    local virtual={}
    local function takeStock(id,count,who)
        local remaining=count
        local function usable(src)
            if src.owner.key==who.key then return true end
            if src.bound or not src.bindingKnown then return false end
            return FCM:CanCollaborate(src.owner,who)==true
        end
        local function withdraw(src,n)
            if n<=0 then return end
            src.amount=src.amount-n
            remaining=remaining-n
            plan.used[id]=(plan.used[id] or 0)+n
            local entry=src.owner.key.."/"..src.where.."/"..tostring(src.stackKey).."/"..id
            if src.virtual then return end
            if src.owner.key~=who.key then
                local row=plan.transfers[entry]
                if not row then
                    row={itemID=id,name=FCM.ItemName(id),count=0,from=display(src.owner),
                        to=display(who),fromKey=src.owner.key,toKey=who.key,
                        where=src.where,stamp=src.stamp}
                    plan.transfers[entry]=row
                end
                row.count=row.count+n
            end
            local stamp=tonumber(src.stamp)
            if not stamp then
                warn("An inventory snapshot used by the plan has no scan time; refresh before crafting.")
            elseif FCM.Now and FCM:Now()>0 and FCM:Now()-stamp>172800 then
                warn("Some inventory snapshots used by this plan are older than 48 hours.")
            end
        end
        -- Previously planned surplus is available before real inventory.
        for _,src in ipairs(virtual[id] or {}) do
            if remaining>0 and src.amount>0 and usable(src) then withdraw(src,math.min(remaining,src.amount)) end
        end
        -- The crafter's own stock first, then compatible character stock.
        for pass=1,2 do
            for _,src in ipairs(pool[id] or {}) do
                if remaining>0 and src.amount>0 and usable(src) and
                    ((pass==1 and src.owner.key==who.key) or (pass==2 and src.owner.key~=who.key)) then
                    withdraw(src,math.min(remaining,src.amount))
                end
            end
        end
        if remaining>0 then
            for _,src in ipairs(pool[id] or {}) do
                if src.amount>0 and not src.bindingKnown and src.owner.key~=who.key and
                    FCM:CanCollaborate(src.owner,who) then
                    warn("Some stock of item #"..id.." has unknown binding; cross-character transfers are not counted.")
                    break
                end
            end
        end
        return remaining
    end
    local function chooseCrafter(sub,target)
        local candidates=eligibleCrafters(sub,target,sub.outputID)
        for _,c in ipairs(candidates) do if c.key==target.key then return c end end
        return candidates[1]
    end
    local need
    need=function(id,qty,who,depth,path)
        id=tonumber(id);qty=amount(qty)
        if not id or qty<=0 then
            if qty>0 then block("A recipe has an invalid reagent ID.") end
            return
        end
        local remainder=takeStock(id,qty,who)
        if remainder<=0 then return end
        if depth>=MAX_DEPTH or path[id] then
            if path[id] then warn("Crafting recipe cycle detected for item #"..id.."; listed as missing.")
            else warn("Craft chain exceeds six levels; deeper ingredients are unresolved.") end
            plan.missing[id]=(plan.missing[id] or 0)+remainder
            return
        end
        local chosen,subCrafter
        for _,r in ipairs(index[id] or {}) do
            local c=chooseCrafter(r,who)
            if c then chosen=r;subCrafter=c;break end
        end
        if chosen then
            local binding=boundInfo(id)
            if not binding and subCrafter.key~=who.key then
                warn("Intermediate item #"..id.." has unverified binding; confirm it can be transferred.")
            end
            local madePerCraft=math.max(1,amount(chosen.quantity))
            local count=math.ceil(remainder/madePerCraft)
            path[id]=true
            for _,m in ipairs(chosen.reagents) do
                if not m.itemID or amount(m.count)<=0 then
                    block("Recipe "..tostring(chosen.name).." has an invalid ingredient record.")
                else
                    need(m.itemID,amount(m.count)*count,subCrafter,depth+1,path)
                end
            end
            path[id]=nil
            plan.steps[#plan.steps+1]={recipeID=chosen.id,recipe=chosen.name,
                outputID=id,crafts=count,produces=count*madePerCraft,
                crafter=subCrafter,profession=chosen.profession,intermediate=true}
            local surplus=count*madePerCraft-remainder
            if surplus>0 then
                virtual[id]=virtual[id] or {}
                virtual[id][#virtual[id]+1]={owner=subCrafter,where="planned surplus",
                    amount=surplus,virtual=true,bound=binding==1}
                plan.generated[id]=(plan.generated[id] or 0)+surplus
            end
        else
            plan.missing[id]=(plan.missing[id] or 0)+remainder
        end
    end
    for _,m in ipairs(recipe.reagents or {}) do
        if not m.itemID or amount(m.count)<=0 then
            block("Main recipe has an invalid reagent record.")
        else
            need(m.itemID,amount(m.count)*crafts,crafter,0,{})
        end
    end
    plan.steps[#plan.steps+1]={recipeID=recipe.id,recipe=recipe.name,
        outputID=recipe.outputID,crafts=crafts,
        produces=crafts*math.max(1,amount(recipe.quantity)),crafter=crafter,
        profession=recipe.profession,intermediate=false}
    local transferList={}
    for _,row in pairs(plan.transfers) do transferList[#transferList+1]=row end
    table.sort(transferList,function(a,b)
        if a.name~=b.name then return a.name<b.name end
        return a.from<b.from
    end)
    plan.transfers=transferList
    for _,quantity in pairs(plan.missing) do plan.totalMissing=plan.totalMissing+quantity end
    plan.stockReady=(plan.totalMissing==0 and #plan.blockers==0)
    plan.uncertain=#plan.warnings>0 or #plan.blockers>0
    plan.complete=#plan.blockers==0
    plan.ready=plan.stockReady and not plan.uncertain
    if not plan.ready then
        plan.status=(#plan.blockers>0 and "Blocked") or
            (plan.totalMissing>0 and "Missing ingredients") or "Verification needed"
    else
        plan.status="Recorded stock ready"
    end
    return plan
end

function FCM:SmartCraftingPlan(recipe,recipient,preferredCrafter,crafts,excludeKey)
    crafts=math.max(1,math.min(999,amount(crafts or 1)))
    local choices=eligibleCrafters(recipe,recipient,recipe and recipe.outputID)
    if preferredCrafter then
        local matched=false
        for _,ch in ipairs(choices) do if ch.key==preferredCrafter.key then matched=true end end
        if matched then choices={preferredCrafter}
        else choices={} end
    end
    if #choices==0 then
        local plan=makePlan(recipe,recipient,nil,crafts,excludeKey)
        return plan
    end
    local best
    for _,ch in ipairs(choices) do
        local plan=makePlan(recipe,recipient,ch,crafts,excludeKey)
        if not best or (plan.complete and not best.complete) or
           (plan.complete==best.complete and plan.totalMissing<best.totalMissing) or
           (plan.complete==best.complete and plan.totalMissing==best.totalMissing and
            (#plan.warnings<#best.warnings or (#plan.warnings==#best.warnings and
             #plan.transfers<#best.transfers))) then best=plan end
    end
    return best
end

function FCM:SmartCraftingPlanLines(plan)
    if not plan then return {"No plan available."} end
    local out={"|cffffd983SMART CRAFTING PLAN (UNIFIED v0.9.0)|r",
        "Recipient: "..display(plan.recipient),"Main crafter: "..display(plan.crafter),
        "Requested crafts: "..tostring(plan.requestedCrafts),
        "Status: "..tostring(plan.status or "Blocked"),""}
    if #plan.blockers>0 then
        out[#out+1]="Blocks:"
        for _,b in ipairs(plan.blockers) do out[#out+1]="  "..b end
    end
    if #plan.steps>0 then
        out[#out+1]="Crafting sequence (materials first):"
        for i,step in ipairs(plan.steps) do
            out[#out+1]=string.format("  %d. %dx %s | %s",i,step.crafts,
                step.recipe or "Unknown recipe",display(step.crafter))
        end
    end
    out[#out+1]=""
    out[#out+1]="Unfilled ingredients (after recorded stock, reservations and nested crafts):"
    local count=0
    for _,id in ipairs(sortedKeys(plan.missing)) do
        local n=plan.missing[id]
        out[#out+1]="  "..FCM.ItemName(id)..": "..tostring(n)
        local ref=FCM.externalData and FCM.externalData.items and
            (FCM.externalData.items[tonumber(id)] or FCM.externalData.items[tostring(id)])
        if FCM.FarmQuickLine then
            out[#out+1]="    "..FCM:FarmQuickLine(id,plan.recipient,n)
        elseif ref and type(ref.where)=="string" and ref.where~="" then
            out[#out+1]="    Reference source (unverified): "..ref.where:sub(1,180)
        end
        count=count+1
    end
    if count==0 then out[#out+1]="  No computed shortage" end
    if #plan.transfers>0 then
        out[#out+1]=""
        out[#out+1]="Potential transfers (not sent automatically):"
        for _,t in ipairs(plan.transfers) do
            out[#out+1]="  "..t.count.."x "..t.name.." from "..t.from.." ("..t.where..") to "..t.to
        end
    end
    if plan.reputation then
        local gate=plan.reputation
        out[#out+1]=""
        out[#out+1]="Recipe/vendor reputation: "..tostring(gate.faction or gate.factionID)..
            " | recorded standing "..tostring(gate.current or "unknown")..
            " / required "..tostring(gate.required or "unknown")
        if tonumber(gate.current) and tonumber(gate.required) and gate.current<gate.required then
            out[#out+1]="  Shortfall: "..tostring(gate.required-gate.current)..
                " standing level(s); exact reputation points are not available."
        end
    end
    if #plan.warnings>0 then
        out[#out+1]=""
        out[#out+1]="Verification required:"
        for _,w in ipairs(plan.warnings) do out[#out+1]="  "..w end
    end
    out[#out+1]=""
    out[#out+1]="Offline advisory only. Stock, binding, vendor availability, and craft eligibility may have changed."
    return out
end
