local _, FCM = ...

local function clean(s)
    return string.lower((tostring(s or ""):gsub("[^%w]", "")))
end

local function countSelected(ch)
    local ranks,total={},0
    for _,node in pairs(ch.talents or {}) do
        local rank=tonumber(node.rank) or 0
        if node.name and rank>0 then
            local key=clean(node.name)
            ranks[key]=math.max(tonumber(ranks[key]) or 0,rank)
            total=total+rank
        end
    end
    return ranks,total
end

function FCM:TalentSpec(ch)
    local options=self.talentSpecChoices[ch and ch.class or ""] or {}
    local selected=ch and ch.talentSpec
    for _,name in ipairs(options) do if name==selected then return name end end
    return options[1]
end

function FCM:TalentGuide(ch)
    if not ch then return nil end
    local specs=self.talentGuides[ch.class] or {}
    return specs[self:TalentSpec(ch)]
end

-- Each specialization may have more than three documented build profiles.
-- Keep saved IDs stable for backward compatibility; accept only IDs available
-- to the selected character's current specialization.
function FCM:TalentProfileOrder(ch)
    local guide=self:TalentGuide(ch)
    if guide and guide.profileOrder then return guide.profileOrder end
    return self.talentProfileIDs or {"leveling","sustain","output"}
end

function FCM:TalentProfileID(ch)
    -- Old SavedVariables used "leveling" and "pve"; keep their migration.
    if not ch then return "leveling" end
    local guide=self:TalentGuide(ch)
    local profiles=guide and guide.profiles or {}
    local spec=self:TalentSpec(ch)
    local perSpec=ch.talentProfileBySpec and ch.talentProfileBySpec[spec]
    if perSpec and profiles[perSpec] then return perSpec end
    -- A saved selection is global only for the legacy character shape.
    -- Do not import a different specialization's extra profile into this one.
    if not ch.talentProfileBySpec then
        local selected=ch.talentProfile
        if selected and profiles[selected] then return selected end
    end
    if not ch.talentProfileBySpec and ch.talentBuild=="pve" and profiles.sustain then return "sustain" end
    return "leveling"
end

function FCM:SetTalentProfile(ch,id)
    if not ch then return false end
    if id=="pve" then id="sustain" end
    local guide=self:TalentGuide(ch)
    if not guide or not guide.profiles or not guide.profiles[id] then return false end
    -- Migrate old overrides into the old active profile before switching.
    if not ch.talentOverridesMigrated then self:TalentOverrides(ch) end
    ch.talentProfile=id
    ch.talentProfileBySpec=ch.talentProfileBySpec or {}
    ch.talentProfileBySpec[self:TalentSpec(ch) or "Unknown"]=id
    ch.talentBuild=(id=="leveling" and "leveling" or "pve")
    return true
end

function FCM:TalentProfile(ch)
    local guide=self:TalentGuide(ch)
    return guide and guide.profiles and guide.profiles[self:TalentProfileID(ch)] or nil
end

function FCM:TalentGuideURL(ch)
    local profile=self:TalentProfile(ch)
    return profile and profile.sourceURL or nil
end

function FCM:TalentOverrideKey(ch)
    return tostring(ch.class or "UNKNOWN") .. ":" .. tostring(self:TalentSpec(ch) or "UNKNOWN") .. ":" .. self:TalentProfileID(ch)
end

function FCM:TalentOverrides(ch)
    if not ch then return {} end
    ch.customTalents=ch.customTalents or {} -- preserve v0.7.0 data unchanged
    ch.customTalentProfiles=ch.customTalentProfiles or {}
    -- Migrate pre-v0.7.1 custom points once, to the ORIGINAL selected build.
    if not ch.talentOverridesMigrated then
        local legacy=ch.customTalents
        if next(legacy) then
            local key=self:TalentOverrideKey(ch)
            ch.customTalentProfiles[key]=ch.customTalentProfiles[key] or {}
            for level,name in pairs(legacy) do
                if ch.customTalentProfiles[key][level]==nil then
                    ch.customTalentProfiles[key][level]=name
                end
            end
        end
        ch.talentOverridesMigrated=true
    end
    local key=self:TalentOverrideKey(ch)
    ch.customTalentProfiles[key]=ch.customTalentProfiles[key] or {}
    return ch.customTalentProfiles[key]
end

function FCM:SetTalentOverride(ch,level,name)
    level=tonumber(level)
    if not ch or not level or level<10 or level>60 then return false end
    local custom=self:TalentOverrides(ch)
    if name==nil or tostring(name)=="" then
        custom[level]=nil
    else
        custom[level]=tostring(name)
    end
    return true
end

-- Optional rank-aware custom plan. Legacy /fcm talentadd entries remain
-- valid strings and are not converted into guessed talent ranks.
function FCM:SetTalentOverrideRank(ch,level,rank,name)
    level,rank=tonumber(level),tonumber(rank)
    if not ch or not level or not rank or level<10 or level>60 or
       rank<1 or rank>10 or rank~=math.floor(rank) or
       type(name)~="string" or name:match("^%s*$") then return false end
    local custom=self:TalentOverrides(ch)
    custom[level]={name=name,rank=rank,manual=true}
    return true
end

function FCM:TalentReport(ch)
    if not ch then return {status="Select a character",rows={}} end
    local guide=self:TalentGuide(ch)
    local profile=self:TalentProfile(ch)
    local profileID=self:TalentProfileID(ch)
    local source=ch.talentSource=="custom" and "custom" or "icy"
    local ranks,spent=countSelected(ch)
    local level=tonumber(ch.level) or 1
    local report={
        spec=self:TalentSpec(ch),build=(profileID=="leveling" and "leveling" or "pve"),
        profileID=profileID,profile=profile,profileTitle=profile and profile.title or "Unknown profile",
        source=source,guide=guide,spent=spent,checked=self.talentGuideEdition,level=level,
        url=profile and profile.sourceURL or nil,
        gaps={},matches={},goals=profile and profile.goals or {},rows={},steps={},
        exactCount=0,reviewedCount=0,coverage="unverified",pveDifferences={},
    }
    if ch.talentStamp then report.scanAge=self:Age(ch.talentStamp) end
    if not profile then
        report.status="Guide unavailable"
        report.summary="No Icy Veins reference profile found for this specialization."
        return report
    end
    report.summary=profile.summary
    report.coverage=profile.evidence or "reference"
    report.allocation=profile.allocation
    local custom=self:TalentOverrides(ch)
    local sequence=(source=="icy" and profile.sequence) or {}
    local earliestUnknown
    local firstPending
    local customCount=0
    for pointLevel=10,60 do
        local base=sequence[pointLevel]
        local override=custom[pointLevel]
        local step=nil
        if override then
            -- Manual entries may be a legacy talent-name string or the new
            -- {name,rank} form. Neither is represented as verified Icy Veins.
            local entry=type(override)=="table" and override or {name=override}
            if type(entry.name)=="string" and entry.name~="" then
                local rank=tonumber(entry.rank)
                if rank and (rank<1 or rank>10 or rank~=math.floor(rank)) then rank=nil end
                step={name=entry.name,rank=rank,level=pointLevel,custom=true}
                customCount=customCount+1
            end
        elseif source=="icy" and base and base.name and base.rank then
            step={name=base.name,rank=base.rank,level=pointLevel,
                verified=true,reason=base.reason}
            report.reviewedCount=report.reviewedCount+1
        end
        if step then
            report.exactCount=report.exactCount+1
            report.steps[#report.steps+1]=step
            if ch.talentStamp and step.rank and pointLevel<=level then
                step.actual=ranks[clean(step.name)] or 0
                if step.actual>=step.rank then
                    report.matches[#report.matches+1]=step
                else
                    report.gaps[#report.gaps+1]=step
                end
            end
            if pointLevel<=level and not firstPending and
                (not ch.talentStamp or not step.rank or (step.actual or 0)<step.rank) then
                firstPending=step
            end
        elseif pointLevel<=level and not earliestUnknown then
            earliestUnknown=pointLevel
        end
    end
    report.customCount=customCount
    report.firstUnknown=earliestUnknown
    report.fullExact=source=="icy" and report.reviewedCount==51 and not earliestUnknown
    if source=="custom" then
        report.nextStep=firstPending
    elseif ch.talentStamp and firstPending and
           (not earliestUnknown or firstPending.level<earliestUnknown) then
        -- Only recommend reviewed ranks BEFORE the first unknown level.
        -- A mismatch is not an instruction to pay for a respec.
        report.nextStep=firstPending
    else
        report.nextStep=nil
    end
    -- Endgame comparison requires a separately verified exact target for the
    -- selected profile, not an unrelated generic target from an older version.
    if source=="icy" and profile.target then
        report.pveComparable=level>=60 and ch.talentStamp~=nil
        for name,needed in pairs(profile.target) do
            local actual=ranks[clean(name)] or 0
            if report.pveComparable and actual~=needed then
                report.pveDifferences[#report.pveDifferences+1]={name=name,needed=needed,actual=actual}
            end
        end
        table.sort(report.pveDifferences,function(a,b)return a.name<b.name end)
    end
    if source=="custom" then
        report.status=customCount>0 and "Custom profile saved" or "Custom profile empty"
    elseif not ch.talentStamp then
        report.status="Waiting for live talent scan"
    elseif profileID~="leveling" and not profile.target then
        report.status="PvE variant reference; exact ranks not verified"
    elseif report.nextStep and report.nextStep.custom then
        report.status="Manual override; verify before spending"
    elseif #report.gaps>0 and not report.nextStep then
        report.status="Saved talents differ from reviewed steps"
    elseif report.nextStep and #report.gaps>0 then
        report.status="Reviewed talent point available; check allocation"
    elseif report.nextStep then
        report.status="Verified next point available"
    elseif profileID=="leveling" then
        report.status="Incomplete leveling sequence; verify the guide"
    else
        report.status="Verified target available"
    end
    return report
end

function FCM:TalentAdvice(ch)
    local report=self:TalentReport(ch)
    local nextText
    if report.nextStep then
        local step=report.nextStep
        nextText="Level "..step.level..": "..step.name..(step.rank and " (rank "..step.rank..")" or " (custom plan)")
        if step.custom then
            nextText=nextText.." - manually entered; FCM has not verified the rank or prerequisites."
        elseif report.source=="icy" and #report.gaps>0 then
            nextText=nextText.." - confirm a legal next point in your current tree before spending."
        end
    elseif report.source=="custom" then
        nextText="No actionable custom step. Add /fcm talentadd <level> <talent name>."
    elseif report.profileID=="leveling" then
        nextText="No safe verified next point for the current level; review the linked Icy Veins calculator."
    else
        nextText="Open the Icy Veins PvE build; exact individual ranks have not been verified in FCM."
    end
    if report.gaps and #report.gaps>0 then
        nextText=nextText.." Review differing verified steps before considering a respec."
    end
    return {status=report.status,next=nextText,
        guide=report.guide and report.guide.name or "No reviewed guide",
        source=report.url or "No source",summary=report.summary,checked=report.checked,
        report=report}
end
