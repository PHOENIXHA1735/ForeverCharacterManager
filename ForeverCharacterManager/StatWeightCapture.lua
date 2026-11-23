-- Explicit, local-only diagnostic capture for future stat-weight simulations.
-- Captures item IDs, raw numeric API fields and talent ranks, but NO character
-- name, GUID, surname, realm, account identity, currency or chat history.
-- Raw item stats and client-reported percentages are NOT yet unit-verified.
local _, FCM = ...
FCM.WeightCapture = FCM.WeightCapture or {}
local W = FCM.WeightCapture

local function try(fn,...)
    if type(fn)~="function" then return nil end
    local ok,a,b,c,d,e=pcall(fn,...)
    if ok then return a,b,c,d,e end
    return nil
end
local function finite(value)
    return type(value)=="number" and value==value and value~=math.huge and
        value~=-math.huge and math.abs(value)<=1000000
end
local function cleanText(value)
    if type(value)~="string" then return "unknown" end
    local normalized=value:gsub("[^%w_%- ]", "")
    return normalized~="" and normalized:sub(1,64) or "unknown"
end
local function rawItemStats(link)
    local raw=nil
    if C_Item then raw=try(C_Item.GetItemStats,link) end
    if type(raw)~="table" then raw=try(GetItemStats,link) end
    local values={}
    if type(raw)=="table" then
        for key,value in pairs(raw) do
            if type(key)=="string" and #key<=70 and
                key:match("^[A-Z0-9_]+$") and finite(value) then
                values[key]=value
            end
        end
    end
    return values
end

-- The capture is a *probe*, never the trusted ch.gearStatContext required
-- for capped recommendations. No code copies it into the verified catalog.
function W:Capture()
    if not (FCM.Current and FCM.ScanBasic and FCM.ScanGear) then
        return nil,"Character scanner is unavailable."
    end
    FCM:ScanBasic()
    FCM:ScanGear()
    if FCM.ScanTalents then FCM:ScanTalents() end
    local ch=FCM:Current()
    if type(ch)~="table" or type(ch.class)~="string" or
        type(ch.level)~="number" then return nil,"Character class or level unavailable." end
    local _,build=try(GetBuildInfo)
    -- Some Forever clients return a nonnumeric value from the generic time()
    -- wrapper. Prefer the client's epoch seconds, then a numeric FCM clock;
    -- preserve "unknown" if none exists instead of fabricating a timestamp.
    local serverTime=tonumber(try(GetServerTime))
    local localTime=tonumber(FCM:Now())
    local gameTime=tonumber(try(time))
    local capturedAt=(serverTime and serverTime>0 and serverTime) or
        (localTime and localTime>0 and localTime) or
        (gameTime and gameTime>0 and gameTime) or nil
    local capture={schema=1,kind="client_raw_probe",capturedAt=capturedAt,
        gameBuild=build and tostring(build) or "unknown",
        class=cleanText(ch.class),spec=cleanText(ch.talentSpec),
        race=cleanText(ch.race),
        specSource="fcm_user_selection_unverified",
        level=ch.level,activity=FCM.GearActivity and FCM:GearActivity(ch) or "leveling",
        style=FCM.Mode and FCM:Mode(ch) or "dps",gear={},talents={},probes={},
        unitsVerified=false}
    if type(GetInventoryItemLink)=="function" then
        for slot=1,19 do
            local link=try(GetInventoryItemLink,"player",slot)
            if type(link)=="string" then
                local id=tonumber(link:match("item:(%d+)"))
                if id and id>0 then
                    capture.gear[#capture.gear+1]={slot=slot,itemID=id,
                        rawStats=rawItemStats(link)}
                end
            end
        end
    end
    if type(ch.talents)=="table" then
        for nodeID,entry in pairs(ch.talents) do
            local id=tonumber(nodeID)
            local rank=type(entry)=="table" and tonumber(entry.rank) or nil
            if id and id>0 and rank and rank>0 and rank<=100 then
                capture.talents[#capture.talents+1]={nodeID=id,rank=rank}
            end
        end
    end
    table.sort(capture.talents,function(a,b) return a.nodeID<b.nodeID end)
    -- Before any talent points exist the client cannot reveal a specialization.
    -- Do not guess "Affliction" merely because this character is a Warlock.
    if capture.spec=="unknown" then
        if ch.level<10 and #capture.talents==0 then
            capture.spec="unselected"
            capture.specSource="no_talents_yet"
        else
            capture.specSource="selection_missing"
        end
    end
    -- API provenance is retained: a rating-point result cannot be silently
    -- treated as a 1%-point Hit/Crit/Haste stat. All are provisional probes.
    local ratingAPIs={
        hit={"CR_HIT_SPELL","CR_HIT_MELEE"},
        crit={"CR_CRIT_SPELL"},haste={"CR_HASTE_SPELL"}}
    for category,constantNames in pairs(ratingAPIs) do
        for _,constantName in ipairs(constantNames) do
            local ratingID=_G[constantName]
            if type(ratingID)=="number" then
                local value=try(GetCombatRating,ratingID)
                if finite(value) then
                    capture.probes[category.."_rating_"..constantName]={value=value,
                        source="GetCombatRating",unit="rating_points_unverified"}
                end
                local bonus=try(GetCombatRatingBonus,ratingID)
                if finite(bonus) then
                    capture.probes[category.."_bonus_"..constantName]={value=bonus,
                        source="GetCombatRatingBonus",unit="reported_percent_unverified"}
                end
            end
        end
    end
    for school=2,7 do
        local crit=try(GetSpellCritChance,school)
        if finite(crit) then
            capture.probes["spell_crit_school_"..school]={value=crit,
                source="GetSpellCritChance",unit="reported_percent_unverified"}
        end
    end
    return capture
end

-- Simple line protocol, deliberately parseable without executing Lua.
-- All fields are generated from strict numeric/whitelisted values. No names.
function W:Serialize(snapshot)
    if type(snapshot)~="table" or snapshot.schema~=1 or
        snapshot.kind~="client_raw_probe" then return nil,"Invalid capture." end
    local lines={"FCM-WEIGHT-SNAPSHOT/1"}
    local function add(key,value) lines[#lines+1]=key.."="..tostring(value) end
    local function number(value)
        -- Epoch seconds are about 1.8 billion in 2026, whereas item stats
        -- are capped at one million by rawItemStats. Do not apply the item
        -- limit to timestamps, or every valid capture serializes "unknown".
        if type(value)~="number" or value~=value or value==math.huge or
            value==-math.huge or math.abs(value)>1000000000000 then return nil end
        return string.format("%.6f",value)
    end
    for _,key in ipairs({"gameBuild","class","spec","race","specSource","activity","style"}) do
        add(key,cleanText(snapshot[key]))
    end
    add("level",number(snapshot.level) or "unknown")
    add("capturedAt",number(snapshot.capturedAt) or "unknown")
    add("unitsVerified","false")
    for _,item in ipairs(snapshot.gear or {}) do
        local slot,id=tonumber(item.slot),tonumber(item.itemID)
        if slot and slot>=1 and slot<=19 and id and id>0 then
            add("gear."..slot..".itemID",id)
            local keys={}
            for stat in pairs(item.rawStats or {}) do keys[#keys+1]=stat end
            table.sort(keys)
            for _,stat in ipairs(keys) do
                if type(stat)=="string" and stat:match("^[A-Z0-9_]+$") and
                    #stat<=70 and number(item.rawStats[stat]) then
                    add("gear."..slot..".raw."..stat,number(item.rawStats[stat]))
                end
            end
        end
    end
    for _,talent in ipairs(snapshot.talents or {}) do
        if number(talent.nodeID) and number(talent.rank) then
            add("talent."..talent.nodeID,number(talent.rank))
        end
    end
    local keys={}
    for key in pairs(snapshot.probes or {}) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local probe=snapshot.probes[key]
        if type(key)=="string" and key:match("^[%w_]+$") and
            type(probe)=="table" and number(probe.value) then
            add("probe."..key..".value",number(probe.value))
            add("probe."..key..".unit",cleanText(probe.unit))
            add("probe."..key..".source",cleanText(probe.source))
        end
    end
    return table.concat(lines,"\n")
end

-- Explicit copy dialog. The user decides whether to paste this diagnostic
-- anywhere. The addon does not contact external websites or create requests.
function W:ShowExport(textValue)
    if type(CreateFrame)~="function" or not UIParent then
        return nil,"A game UI is required to display the copyable capture."
    end
    if not self.frame then
        local frame=CreateFrame("Frame","FCMWeightCaptureExport",UIParent,"BasicFrameTemplateWithInset")
        frame:SetSize(750,480)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart",function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
        frame:SetFrameStrata("DIALOG")
        if frame.TitleText then frame.TitleText:SetText("FCM Stat-Weight Snapshot (local, unverified)") end
        local label=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
        label:SetPoint("TOPLEFT",frame,"TOPLEFT",18,-34)
        label:SetText("Ctrl+C to copy the selected text. This captures no name, GUID or account data.")
        local scroll=CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",frame,"TOPLEFT",18,-60)
        scroll:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-36,18)
        local edit=CreateFrame("EditBox",nil,scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(680)
        edit:SetHeight(400)
        edit:SetMaxLetters(0)
        edit:SetScript("OnEscapePressed",function() frame:Hide() end)
        edit:SetScript("OnTextChanged",function(self)
            -- Read-only export: manual edits have no side effects.
            if self:GetText()~=W.exportText then
                self:SetText(W.exportText or "")
                self:HighlightText()
            end
        end)
        scroll:SetScrollChild(edit)
        frame.edit=edit
        self.frame=frame
    end
    self.exportText=textValue
    self.frame.edit:SetText(textValue)
    self.frame:Show()
    self.frame.edit:SetFocus()
    self.frame.edit:HighlightText()
    return true
end

function W:CaptureAndShow()
    local snapshot,why=self:Capture()
    if not snapshot then return nil,why end
    local serialized,err=self:Serialize(snapshot)
    if not serialized then return nil,err end
    local shown,displayError=self:ShowExport(serialized)
    if shown then return snapshot end
    return nil,displayError
end
