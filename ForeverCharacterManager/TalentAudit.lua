local _, FCM = ...

-- Offline-compatible talent advice; ALL data comes from bundled guide
-- references or last scanned WoW character talent nodes. No point spending.
local function normalized(name)
    return string.lower((tostring(name or ""):gsub("[^%w]", "")))
end
local function talentRanks(ch)
    local ranks,names={},{}
    for _,node in pairs(ch.talents or {}) do
        local name=node and node.name
        local rank=node and tonumber(node.rank) or 0
        if type(name)=="string" and rank>0 then
            local key=normalized(name)
            if key~="" and not name:match("^Talent node %d+$") then
                -- A scan may contain duplicate presentation entries for the
                -- same talent; rank is NOT the sum of duplicate node ranks.
                ranks[key]=math.max(ranks[key] or 0,rank)
                names[key]=name
            end
        end
    end
    return ranks,names
end

function FCM:TalentAudit(ch)
    if not ch then return {status="No character selected",lines={}} end
    local report=self:TalentReport(ch)
    local ranks,names=talentRanks(ch)
    local audit={report=report,verified={},manual={},uncovered={},
        reviewed=0,matched=0,needsReview=0,manualRanked=0,
        status="Reference only",snapshot="No talent scan",lines={}}
    local scanned=ch.talentStamp~=nil and type(ch.talents)=="table"
    if scanned then
        audit.snapshot=self.Age and self:Age(ch.talentStamp) or "last recorded"
    end
    local seen={}
    local limits={}
    for _,step in ipairs(report.steps or {}) do
        -- Never compare a future planned rank against a lower-level toon.
        if step.name and step.level <= (tonumber(ch.level) or 1) and step.rank then
            local key=normalized(step.name)
            local current=ranks[key] or 0
            limits[key]=math.max(limits[key] or 0,step.rank)
            seen[key]=true
            local record={level=step.level,name=step.name,expected=step.rank,
                actual=scanned and current or nil,manual=step.custom}
            if step.custom then
                audit.manual[#audit.manual+1]=record
                audit.manualRanked=audit.manualRanked+1
            else
                audit.verified[#audit.verified+1]=record
                audit.reviewed=audit.reviewed+1
                if scanned then
                    if current>=step.rank then audit.matched=audit.matched+1
                    else audit.needsReview=audit.needsReview+1 end
                end
            end
        end
    end
    if scanned then
        local unknown={}
        for key,name in pairs(names) do
            if not seen[key] then unknown[#unknown+1]=name end
        end
        table.sort(unknown)
        audit.uncovered=unknown
    end
    if not scanned then
        audit.status="Awaiting successful talent scan"
    elseif report.source=="custom" then
        audit.status="Custom plan audit (user-entered ranks)"
    elseif audit.reviewed==0 then
        audit.status="Reference guide; no comparable ranked points"
    elseif audit.needsReview>0 then
        audit.status="Review "..audit.needsReview.." known point(s)"
    else
        audit.status="Known guide steps match (partial coverage)"
    end
    local lines={
        "Talent allocation audit - "..audit.status,
        "Character: "..tostring(ch.name or "Unknown").." | Spec: "..tostring(report.spec or "Unknown"),
        "Profile: "..tostring(report.profileTitle or "Unknown"),
        "Snapshot: "..audit.snapshot..(scanned and " (stored; not necessarily live)" or ""),
        "Reviewed guide steps applicable to level: "..audit.reviewed,
        "Reviewed steps matched: "..(scanned and tostring(audit.matched).." / "..audit.reviewed or "unknown - scan required"),
        "Custom ranked steps in this profile: "..audit.manualRanked,
    }
    if report.firstUnknown then
        lines[#lines+1]="Unverified point order begins at level "..report.firstUnknown..". Do not infer missing steps."
    end
    if scanned then
        for _,record in ipairs(audit.verified) do
            if record.actual<record.expected then
                lines[#lines+1]="Review level "..record.level..": "..record.name..
                    " recorded rank "..record.actual.." / guide "..record.expected
            end
        end
        for _,record in ipairs(audit.manual) do
            lines[#lines+1]="Manual level "..record.level..": "..record.name..
                " recorded rank "..record.actual.." / planned "..record.expected
        end
        if #audit.uncovered>0 then
            lines[#lines+1]="Scanned talents not covered by these limited guide steps: "..table.concat(audit.uncovered, ", ")
            lines[#lines+1]="Not listed is NOT evidence that a talent was spent incorrectly."
        end
    end
    lines[#lines+1]="The advisor does not verify talent prerequisites, points earned, or full build legality. No respec is recommended automatically."
    audit.lines=lines
    return audit
end

local labels={spell="Spell Power",int="Intellect",spi="Spirit",stam="Stamina",
    crit="Critical Rating",hit="Hit Rating",haste="Haste Rating",mp5="Mana Regeneration",
    str="Strength",agi="Agility",ap="Attack Power",dps="Weapon DPS",
    armor="Armor",def="Defense",resist="Resistance"}

function FCM:TalentGearHints(ch,count)
    if not ch or not self.Gear or not self.Gear.Weight then
        return {lines={"Gear weight reference unavailable."},priorities={}} end
    local activity=self:GearActivity(ch)
    local mode=self:Mode(ch,activity)
    local ranks={}
    for key,label in pairs(labels) do
        local value=self.Gear:Weight(key,ch,mode,activity)
        if type(value)=="number" and value>0 then
            ranks[#ranks+1]={key=key,name=label,weight=value}
        end
    end
    table.sort(ranks,function(a,b)
        if a.weight==b.weight then return a.name<b.name end
        return a.weight>b.weight
    end)
    local result={priorities=ranks,activity=activity,mode=mode,lines={}}
    result.lines[#result.lines+1]="Gear priorities for "..(self.TalentSpec and self:TalentSpec(ch) or "selected spec")
    result.lines[#result.lines+1]="Activity: "..(self.gearActivityLabels and self.gearActivityLabels[activity] or activity)..
        " | Style: "..(self.modeLabels and self.modeLabels[mode] or mode)
    local n=math.min(math.max(1,tonumber(count) or 6),#ranks)
    for i=1,n do
        local item=ranks[i]
        result.lines[#result.lines+1]=i..". "..item.name.." (relative weight "..string.format("%.2f",item.weight)..")"
    end
    result.lines[#result.lines+1]="These are existing FCM heuristic stat weights, NOT verified guide weights or predicted DPS."
    result.lines[#result.lines+1]="Talent profile alternatives do not automatically change these weights; class/spec/activity/style do."
    result.lines[#result.lines+1]="Caps, procs, set bonuses and individual talent synergies are not modeled."
    return result
end
