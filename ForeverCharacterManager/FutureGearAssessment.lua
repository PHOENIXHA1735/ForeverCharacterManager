-- Read-only Future Gear Planner assessment adapter, phase 2 prototype.
-- Depends on FutureGearPlanner.lua and existing Gear:CompareItem.
-- Not in production TOC. Never invents coefficients or DPS/percent improvements.
local _,FCM=...
FCM.FutureGearPlanner=FCM.FutureGearPlanner or {}
local P=FCM.FutureGearPlanner
local function finite(n)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end
local function copy(t)
    local result={}
    for key,value in pairs(t) do result[key]=value end
    return result
end

function P:Assess(ch,candidates,options)
    options=options or {}
    if type(ch)~="table" or type(candidates)~="table" then
        return {},"Missing character or candidate list"
    end
    local gear=FCM.Gear
    local results={}
    local activity=options.activity or (type(FCM.GearActivity)=="function" and FCM:GearActivity(ch))
    local now=type(FCM.Now)=="function" and FCM:Now() or nil
    local threshold=FCM.db and FCM.db.settings and tonumber(FCM.db.settings.minimumUpgrade) or 0
    if not finite(threshold) or threshold<0 then threshold=0 end
    for _,record in ipairs(candidates) do
        if type(record)=="table" then
            local row=copy(record)
            row.assessment="insufficient-information"
            row.assessmentReason="Item evidence has not been evaluated."
            row.weightedDelta=nil
            row.modelProvenance=nil
            row.comparedTo="currently scanned equipment, not projected future equipment"
            if type(row.itemID)~="number" or not row.characterKey or row.characterKey~=ch.key or
                    row.levelNow~=ch.level or row.class~=ch.class or
                    not ch.talentSpec or row.specialization~=ch.talentSpec then
                row.assessmentReason="Candidate is not scoped to this character, spec and level; recollect references."
            elseif row.eligibility~="compatible" then
                row.assessmentReason="Equipment eligibility needs verification: "..tostring(row.eligibilityReason or "unknown")
            elseif row.availabilityStatus=="historical-beta-event" or row.availabilityStatus=="speculative" then
                row.assessmentReason="Source flags an unconfirmed or historical item; live availability must be verified."
            elseif not activity then
                row.assessmentReason="The character's intended activity is unknown."
            elseif not gear or type(gear.CompareItem)~="function" then
                row.assessmentReason="Shared gear comparison engine unavailable."
            elseif not tonumber(ch.gearStamp) or tonumber(ch.gearStamp)<=0 then
                row.assessmentReason="No verified equipped-gear scan."
            elseif finite(now) and now>0 and now-tonumber(ch.gearStamp)>604800 then
                row.assessmentReason="Equipped-gear scan is older than seven days; rescan before recommendations."
            else
                local ok,comparison=pcall(gear.CompareItem,gear,row.itemID,ch,nil,
                    {allowFutureLevel=true,activity=activity})
                if not ok or type(comparison)~="table" then
                    row.assessmentReason="Gear comparison failed or returned no evidence."
                else
                    row.comparisonStatus=comparison.status
                    row.modelProvenance=comparison.weightSource
                    row.comparisonReason=comparison.reason
                    row.compareSlot=comparison.slot
                    if comparison.status=="ok" and finite(comparison.delta) then
                        if comparison.confidence=="VERIFIED NUMERIC MODEL" and
                                comparison.modelResult and comparison.modelResult.complete==true then
                            row.weightedDelta=comparison.delta
                            if comparison.delta>threshold then
                                row.assessment="verified-weighted-upgrade"
                                row.assessmentReason="Valid build-matched weighted comparison against currently scanned equipment."
                            else
                                row.assessment="not-a-verified-upgrade"
                                row.assessmentReason="No weighted gain above the configured threshold."
                            end
                        elseif comparison.confidence=="PROVISIONAL USER-IMPORTED SCALE" or
                                comparison.confidence=="PROVISIONAL CUSTOM ESTIMATE" then
                            row.assessment="provisional-estimate"
                            row.weightedDelta=comparison.delta
                            row.assessmentReason="User-supplied model only; not an independently verified upgrade or DPS gain."
                        else
                            row.assessmentReason="Numerical result lacks a validated model/provenance and is withheld."
                        end
                    elseif comparison.guideVerdict=="supported" then
                        row.assessment="qualitative-candidate"
                        row.assessmentReason="Reviewed spec priorities support an improvement without measured numerical gain."
                    else
                        row.assessmentReason=comparison.reason or "Required item stats/model not available."
                    end
                end
            end
            results[#results+1]=row
        end
    end
    return results,nil
end
