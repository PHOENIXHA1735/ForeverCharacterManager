-- FCM stat-weight foundation, schema 1.
-- This is a pure calculation layer. It does NOT invent class coefficients,
-- interpret an unknown client rating as a percentage, or claim to simulate DPS.
local _, FCM = ...
FCM.StatWeightEngine = FCM.StatWeightEngine or {}
local E = FCM.StatWeightEngine
E.schema = 1

local function finite(value)
    return type(value)=="number" and value==value and
        value~=math.huge and value~=-math.huge
end

-- Output samples come from an external, identifiable simulator or controlled
-- measurement. Example: baselineDPS=1000, samples.spell={delta=10,output=1020}.
-- The engine deliberately refuses to derive numerical weights from a mere
-- ranked list of stats. A reference stat normalizes the marginal gains.
function E:WeightsFromSamples(baselineOutput,samples,referenceStat)
    if not finite(baselineOutput) or type(samples)~="table" or
        type(referenceStat)~="string" then
        return nil,"Missing or invalid simulation baseline."
    end
    local marginal={}
    for key,sample in pairs(samples) do
        if type(key)~="string" or type(sample)~="table" or
            not finite(sample.delta) or sample.delta<=0 or
            not finite(sample.output) then
            return nil,"Invalid simulation sample: "..tostring(key)
        end
        marginal[key]=(sample.output-baselineOutput)/sample.delta
    end
    local reference=marginal[referenceStat]
    if not finite(reference) or reference<=0 then
        return nil,"Reference stat has no positive measured marginal value."
    end
    local weights={}
    for key,value in pairs(marginal) do weights[key]=value/reference end
    return {schema=self.schema,reference=referenceStat,weights=weights,
        marginals=marginal,baselineOutput=baselineOutput}
end

-- Return the useful increase/decrease in a capped stat. All three values MUST
-- use the same unit (e.g. percentage points). Using rating with percent caps
-- is forbidden by ScoreChanges, rather than silently producing a wrong score.
function E:CappedChange(current,cap,delta)
    if not finite(current) or not finite(cap) or not finite(delta) or
        current<0 or cap<0 then return nil,"Unverified cap context." end
    local before=math.min(cap,math.max(0,current))
    local after=math.min(cap,math.max(0,current+delta))
    return after-before
end

-- Only curated, versioned, build-matched profiles may replace the heuristic
-- scorer. A source without numerical measurements, an unverified profile or
-- a duplicate exact match is not sufficient evidence to rank equipment.
function E:VerifiedProfile(catalog,ch,mode,activity,clientBuild)
    if type(catalog)~="table" or catalog.schema~=self.schema or
        type(catalog.version)~="string" or type(catalog.profiles)~="table" or
        type(ch)~="table" or type(ch.level)~="number" then
        return nil,"No compatible weight catalog."
    end
    if type(catalog.gameBuild)~="string" or not clientBuild or
        catalog.gameBuild~=tostring(clientBuild) then
        return nil,"Unverified game-build match."
    end
    local matched=nil
    for _,profile in ipairs(catalog.profiles) do
        if type(profile)=="table" and profile.class==ch.class and
            profile.spec==ch.talentSpec and profile.activity==activity and
            profile.style==mode and ch.level>=(profile.levelMin or 61) and
            ch.level<=(profile.levelMax or 0) then
            if matched then return nil,"Ambiguous matching weight profiles." end
            matched=profile
        end
    end
    if not matched or matched.verified~=true or
        type(matched.source)~="string" or matched.source=="" or
        matched.schema~=self.schema or type(matched.weights)~="table" or
        not next(matched.weights) then
        return nil,"No verified numerical weights for this build."
    end
    if matched.talentProfile and matched.talentProfile~=ch.talentProfile then
        return nil,"Talent build does not match the verified profile."
    end
    for key,entry in pairs(matched.weights) do
        if type(key)~="string" or type(entry)~="table" or
            not finite(entry.value) or
            (entry.unit~="point" and entry.unit~="percentage_point") then
            return nil,"Invalid weight entry in verified catalog."
        end
    end
    for key,cap in pairs(matched.caps or {}) do
        local weight=matched.weights[key]
        if not weight or type(cap)~="table" or not finite(cap.value) or
            cap.value<0 or cap.unit~=weight.unit then
            return nil,"Invalid cap units in verified catalog."
        end
    end
    return matched
end

-- Compare two complete item-stat maps against an explicit profile and an
-- EQUIPPED CHARACTER snapshot. A profile weight has {value=N,unit="point"}
-- or {value=N,unit="percentage_point"}; caps/current carry matching units.
-- Unmodelled item stats are returned as unknown, never silently treated as
-- proven worthless. The score is an estimate, not predicted DPS/HPS.
function E:ScoreChanges(oldStats,newStats,profile,context)
    if type(oldStats)~="table" or type(newStats)~="table" or
        type(profile)~="table" or profile.schema~=self.schema or
        type(profile.weights)~="table" then
        return nil,"Invalid stat snapshot or profile."
    end
    context=context or {}
    local result={score=0,changes={},unknown={},complete=true}
    local keys={}
    for key in pairs(oldStats) do keys[key]=true end
    for key in pairs(newStats) do keys[key]=true end
    for key in pairs(keys) do
        local old=oldStats[key] or 0
        local new=newStats[key] or 0
        if not finite(old) or not finite(new) then
            return nil,"Invalid item stat: "..tostring(key)
        end
        local change=new-old
        if change~=0 then
            local entry=profile.weights[key]
            if type(entry)~="table" or not finite(entry.value) or
                (entry.unit~="point" and entry.unit~="percentage_point") then
                result.complete=false
                result.unknown[#result.unknown+1]=key
            else
                local effective=change
                local cap=context.caps and context.caps[key]
                if cap then
                    local current=context.current and context.current[key]
                    if type(cap)~="table" or type(current)~="table" or
                        cap.unit~=entry.unit or current.unit~=entry.unit then
                        return nil,"Cap unit or current value unavailable for "..key
                    end
                    local err
                    effective,err=self:CappedChange(current.value,cap.value,change)
                    if effective==nil then return nil,err end
                end
                local impact=effective*entry.value
                result.score=result.score+impact
                result.changes[#result.changes+1]={key=key,raw=change,
                    effective=effective,impact=impact,unit=entry.unit}
            end
        end
    end
    table.sort(result.unknown)
    table.sort(result.changes,function(a,b)
        if math.abs(a.impact)==math.abs(b.impact) then return a.key<b.key end
        return math.abs(a.impact)>math.abs(b.impact)
    end)
    return result
end
