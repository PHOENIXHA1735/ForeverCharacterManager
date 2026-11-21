-- Future Gear Planner: normal FCM list/detail view adapter.
-- UI.lua owns the actual Blizzard widgets; this file supplies readonly rows.
local _,FCM=...
FCM.FutureGearPlanner=FCM.FutureGearPlanner or {}
local P=FCM.FutureGearPlanner

local assessmentLabels={
    ["verified-weighted-upgrade"]="Verified weighted improvement",
    ["not-a-verified-upgrade"]="Not an improvement under verified model",
    ["qualitative-candidate"]="Qualitative improvement candidate",
    ["provisional-estimate"]="Provisional user-weight estimate",
    ["insufficient-information"]="Unverified future option",
}
local function sourceLabel(src)
    local label=src.kind or "Reference"
    label=label..": "..tostring(src.name or "Unknown")
    if src.boss then label=label.." / "..tostring(src.boss) end
    if src.profession then label=label.." / "..tostring(src.profession) end
    if src.acquisition and src.acquisition~="" then
        label=label.." | Recorded acquisition: "..tostring(src.acquisition)
    end
    if src.provider then label=label.." | Source: "..tostring(src.provider) end
    if src.classification=="unverified" then label=label.." | Instance type unclassified" end
    return label
end
local function itemDetail(row)
    local lines={
        tostring(row.itemName or ("Item #"..tostring(row.itemID))),
        "Item ID: "..tostring(row.itemID),
        "Required level: "..tostring(row.requiredLevel),
        "Gear slot: "..tostring(row.equip or "Unknown"),
        "Spec: "..tostring(row.specialization or "Unknown"),
        "Assessment: "..tostring(assessmentLabels[row.assessment] or "Unknown"),
        "Assessment evidence: "..tostring(row.assessmentReason or "Unverified"),
        "Equipment restrictions: "..tostring(row.eligibilityReason or "Unverified"),
        "Future-level item is NOT an equip test and cannot project level-35 DPS.",
    }
    if type(row.weaponEligibility)=="table" then
        lines[#lines+1]="Recorded current proficiency: "..tostring(row.weaponEligibility.proficiency)
        lines[#lines+1]=tostring(row.weaponEligibility.caution or "")
    end
    if row.weightedDelta then
        lines[#lines+1]="Model points, not DPS: "..string.format("%+.2f",row.weightedDelta)
    end
    if row.itemEvidence then lines[#lines+1]="Item reference note: "..tostring(row.itemEvidence) end
    if row.itemCheckedAt then lines[#lines+1]="Reference checked: "..tostring(row.itemCheckedAt) end
    lines[#lines+1]=""
    lines[#lines+1]="ACQUISITION REFERENCES (not confirmed live drops or craft readiness):"
    for _,src in ipairs(row.sources or {}) do
        lines[#lines+1]="- "..sourceLabel(src)
        for _,crafter in ipairs(src.knownCrafters or {}) do
            lines[#lines+1]="  Crafter "..tostring(crafter.key or "?")..": "..
                tostring(crafter.recipientStatus or "verification required")..
                " (last-recorded skill: "..tostring(crafter.skillStatus or "unknown")..")"
        end
    end
    return table.concat(lines,"\n")
end

function P:ViewRows(ch,lookahead,expanded)
    if type(ch)~="table" then
        return {{id="future-empty",title="Select a saved character",
            summary="No selected character",detail="Log in and scan a character first."}},nil
    end
    if type(self.Candidates)~="function" or type(self.Assess)~="function" or
            type(self.Shortlist)~="function" or type(self.WithWeaponEvidence)~="function" then
        return nil,"Future Gear Planner modules are not fully loaded"
    end
    local candidates,err=self:Candidates(ch,lookahead)
    if err then return nil,err end
    local withProof,withheld=self:WithWeaponEvidence(ch,candidates)
    local assessed,assessmentError=self:Assess(ch,withProof)
    if assessmentError then return nil,assessmentError end
    local shortlist,shortError=self:Shortlist(ch,assessed,{
        itemsPerSlot=expanded and 10 or 5,
        weaponsPerSlot=expanded and 5 or 3,
    })
    if shortError then return nil,shortError end
    local results={}
    results[#results+1]={
        id="future-status",title="Future gear reference status",
        summary=tostring(#candidates).." source-linked items | "..tostring(shortlist.totalShown)..
            " shown | "..tostring(shortlist.withheldWeapons).." weapons withheld",
        detail="This is an offline/reference-backed planning view, not confirmed drops or DPS. "..
            "It looks "..tostring(lookahead).." levels ahead. "..
            "The source cache lacks numerical stats for many items; actual comparison requires loaded client stats and a valid model. "..
            "Weapon checks require the logged-in character's actual weapon skills and exact client tooltip. "..
            "If those APIs or restrictions are unavailable, weapons are withheld. "..
            "Currently trained weapon skills are evidence for future-level planning, but successful future equip is not guaranteed.",
    }
    for _,group in ipairs(shortlist.groups) do
        results[#results+1]={
            id="future-section:"..group.key,
            title=group.label.." ("..tostring(#group.rows).." shown of "..tostring(group.total)..")",
            summary=(group.hidden>0 and tostring(group.hidden).." more available in expanded view" or
                "No additional candidates in this source scope"),
            detail="Sorted by evidence category and then comparable model points or level. "..
                "Missing numerical weights do not imply an item is worse.",
        }
        for _,item in ipairs(group.rows) do
            local label=assessmentLabels[item.assessment] or "Unknown confidence"
            local description="Requires level "..tostring(item.requiredLevel).." | "..label
            if item.weightedDelta then
                description=description.." | "..string.format("%+.2f",item.weightedDelta).." model points"
            end
            results[#results+1]={
                id="future-item:"..tostring(group.key)..":"..tostring(item.itemID),
                title=item.itemName or ("Item #"..item.itemID),
                summary=description,detail=itemDetail(item),
                itemID=item.itemID,compareSlot=item.compareSlot or item.slot,
                futurePlan=true,
            }
        end
    end
    if #shortlist.groups==0 then
        results[#results+1]={
            id="future-no-gear",title="No verified or source-linked options in this range",
            summary="No equipment candidates currently displayable",
            detail="The imported data is incomplete and some weapons may be withheld. "..
                "Select a different level window, scan the logged-in character, or verify in-game item details. "..
                "This does not mean the game contains no upgrades.",
        }
    end
    return results,{totalCandidates=#candidates,withheldWeapons=shortlist.withheldWeapons,
        hiddenByLimit=shortlist.hiddenByLimit,totalShown=shortlist.totalShown}
end
