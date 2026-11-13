-- Unified FCM v0.9.0: read-only BoE upgrade and disenchant safety advisor.
-- Does not hook/replace/prohibit the game's protected Disenchant action.
local _, FCM = ...
local DEFAULT_LOOKAHEAD=10
local MAX_TOOLTIP_RECIPIENTS=3

local function display(ch)
    return (FCM.DisplayCharacter and FCM:DisplayCharacter(ch)) or tostring(ch and ch.name or "Unknown")
end
local function ageUncertain(self,ch)
    if type(self.ScanFreshness)=="function" then
        local freshness=self:ScanFreshness(ch,"gear")
        return freshness.status=="outdated" or freshness.status=="unknown"
    end
    if not ch or type(ch.gearStamp)~="number" or ch.gearStamp<=0 then return true end
    local now=self.Now and self:Now() or 0
    return now>0 and now-ch.gearStamp>7*86400
end
local function instances(owner,itemID)
    local result={count=0,unbound=0,bound=0,unknown=0}
    if not owner then return result end
    for _,location in ipairs({"bags","bank"}) do
        for _,entry in pairs(owner[location] or {}) do
            if tonumber(entry.itemID)==itemID then
                local count=math.max(1,tonumber(entry.count) or 1)
                result.count=result.count+count
                if entry.bound==true then result.bound=result.bound+count
                elseif entry.bound==false then result.unbound=result.unbound+count
                else result.unknown=result.unknown+count end
            end
        end
    end
    return result
end
-- A BoE item cannot be mailed to an alt on the opposing faction or a
-- different realm/ruleset. Such alts may be interesting comparisons, but
-- they must NOT cause KEEP or REVIEW advice for the actual item owner.
local function knownTransferBarrier(self,owner,recipient)
    local af=self:NormalizeFaction(owner and owner.faction)
    local rf=self:NormalizeFaction(recipient and recipient.faction)
    if af and rf and af~=rf then
        return "Opposing faction ("..af.." to "..rf..")"
    end
    local ar=self:NormalizeRuleset(owner and owner.ruleset)
    local rr=self:NormalizeRuleset(recipient and recipient.ruleset)
    if ar and rr and ar~=rr then return "Different rulesets ("..ar.." / "..rr..")" end
    local regionA=owner and owner.region
    local regionB=recipient and recipient.region
    if type(regionA)=="string" and type(regionB)=="string" and
       regionA~="" and regionB~="" and regionA~=regionB then return "Different regions" end
    return nil
end
local function rowOrder(a,b)
    -- Immediately equipable upgrades first, then upcoming upgrades; within
    -- each group prioritize the estimated improvement.
    if a.future~=b.future then return not a.future end
    if a.delta~=b.delta then return a.delta>b.delta end
    return a.name<b.name
end

-- Item ID or item link accepted. "Required level" is GetItemInfo's fifth
-- return, NOT the separate item level (ilvl). Future-only checks deliberately
-- compare against LAST SCANNED equipped gear, not a predicted future loadout.
function FCM:BoEProtectionCheck(item,owner)
    local report={status="review",candidates={},excluded={},uncertain={},restrictions={},
        item=item,owner=owner or (self.Current and self:Current())}
    local gear=self.Gear
    if not gear or not gear.Info or not gear.CompareItem then
        report.message="Gear comparison is unavailable";return report
    end
    local info=gear:Info(item)
    if not info then report.message="Item details are not cached; check again later";return report end
    report.info=info
    report.requiredLevel=tonumber(info.level) or 0
    if info.bindType~=2 then
        report.status=(info.bindType==1 and "bop" or "review")
        report.message=(info.bindType==1 and "Bind on Pickup; not transferable to another character" or
            "BoE binding type not confirmed")
        return report
    end
    local ownerChar=report.owner
    local itemID=type(item)=="number" and item or tonumber(tostring(item):match("item:(%d+)"))
    report.itemID=itemID
    local owned=itemID and instances(ownerChar,itemID) or {count=0,unbound=0,bound=0,unknown=0}
    report.ownership=owned
    report.transferState=owned.unbound>0 and "unbound" or
        (owned.bound>0 and owned.unknown==0 and "bound" or "uncertain")
    if not ownerChar then
        report.message="Item owner not established";return report
    end
    local roster=(self.Characters and self:Characters()) or {}
    if #roster==0 then report.message="No scanned characters";return report end
    local minimum=(self.db and self.db.settings and tonumber(self.db.settings.minimumUpgrade)) or 1
    local lookahead=(self.db and self.db.settings and tonumber(self.db.settings.boeFutureLevels)) or DEFAULT_LOOKAHEAD
    lookahead=math.max(0,math.min(30,lookahead))
    report.lookahead=lookahead
    for _,ch in ipairs(roster) do
        if ch and ch.key then
            local same=ownerChar.key and ch.key==ownerChar.key
            -- BoP and already-bound BoE cannot transfer. Unknown binding is
            -- evaluated for warning only; never claims mailing is possible.
            local transferOK=true
            local transferReason=nil
            if not same then
                if report.transferState=="bound" then
                    transferOK=false;transferReason="Item copy already soulbound"
                elseif type(self.CanCollaborate)=="function" then
                    local allowed,reason=self:CanCollaborate(ownerChar,ch)
                    if not allowed then transferOK=false;transferReason=reason or "Transfer not confirmed" end
                else
                    transferOK=false;transferReason="Transfer rules not available"
                end
            end
            local barrier=not same and knownTransferBarrier(self,ownerChar,ch) or nil
            local currentLevel=tonumber(ch.level)
            if not currentLevel then
                -- Inaccessible opposing-faction alts are not evidence that
                -- the owner should hold this piece of gear.
                if not barrier then
                    report.uncertain[#report.uncertain+1]=display(ch)..": character level unknown"
                end
            else
                local future=report.requiredLevel>currentLevel
                local levelsToGo=math.max(0,report.requiredLevel-currentLevel)
                -- Pass the future-level opt-in; all normal gear checks retain
                -- their present-level restrictions.
                local comparison=gear:CompareItem(item,ch,nil,{allowFutureLevel=true})
                if comparison.status=="ok" and tonumber(comparison.delta) and comparison.delta>=minimum then
                    local entry={character=ch,name=display(ch),delta=comparison.delta,
                        currentLevel=currentLevel,requiredLevel=report.requiredLevel,
                        future=future,levelsToGo=levelsToGo,slot=comparison.slot,
                        transferable=same or (transferOK and report.transferState=="unbound"),
                        transferReason=transferReason,stale=ageUncertain(self,ch),
                        distant=future and levelsToGo>lookahead,
                        comparison=comparison}
                    if barrier then
                        -- Useful in an account-wide comparison, but cannot be
                        -- delivered to this character. Do not count toward
                        -- either KEEP or a conservative REVIEW warning.
                        report.excluded[#report.excluded+1]={name=entry.name,
                            faction=self:NormalizeFaction(ch.faction),delta=entry.delta,
                            reason=barrier}
                    else
                        report.candidates[#report.candidates+1]=entry
                        if not entry.transferable and not same then
                            report.restrictions[#report.restrictions+1]=entry.name..": "..
                                (transferReason or "Unbound status not verified")
                        end
                        if entry.distant then
                            report.uncertain[#report.uncertain+1]=entry.name..
                                ": equip in "..levelsToGo.." levels; future gear may change"
                        end
                    end
                elseif comparison.status=="unknown" then
                    if not barrier then
                        report.uncertain[#report.uncertain+1]=display(ch)..": "..
                            tostring(comparison.reason or "gear stats not available")
                    end
                elseif comparison.status=="ok" and ageUncertain(self,ch) and not barrier then
                    report.uncertain[#report.uncertain+1]=display(ch)..": equipment snapshot older than seven days"
                end
            end
        end
    end
    table.sort(report.candidates,rowOrder)
    local best=nil
    for _,candidate in ipairs(report.candidates) do
        if candidate.transferable and not candidate.distant and not candidate.stale then
            best=candidate;break
        end
    end
    report.best=best
    if best then
        report.status="keep"
        report.message="KEEP - upgrade for "..best.name..
            (best.future and (" at level "..best.requiredLevel) or " now")
    elseif report.transferState=="bound" then
        report.status="bound"
        report.message="Already soulbound; not transferable. No confirmed usable upgrade"
    elseif #report.candidates>0 or #report.uncertain>0 or report.transferState~="unbound" then
        report.status="review"
        report.message="REVIEW before disenchanting: possible upgrade or outdated/uncertain character data"
    else
        report.status="no-known-upgrade"
        report.message="No transferable upgrades among eligible characters; consider DE, sale or vendor after checking"
    end
    return report
end

function FCM:BoEProtectionLines(report,limit)
    if not report then return {} end
    local lines={"|cffffd983ACCOUNT-WIDE BOE / DISENCHANT CHECK|r"}
    local colors={keep="|cff76e59a",review="|cffffcf80",bound="|cffc8d1df",
        bop="|cffc8d1df",["no-known-upgrade"]="|cffc8d1df"}
    local color=colors[report.status] or "|cffffcf80"
    lines[#lines+1]=color..tostring(report.message or "Item data uncertain").."|r"
    if report.info then
        lines[#lines+1]="Required equip level: "..tostring(report.requiredLevel or "Unknown")
    end
    local max=math.max(1,tonumber(limit) or 6)
    for i,c in ipairs(report.candidates or {}) do
        if i>max then lines[#lines+1]="More possible recipients omitted";break end
        local when=c.future and ("at level "..c.requiredLevel.." (currently "..c.currentLevel..")") or "now"
        local transfer=c.transferable and "Transfer eligible" or "Transfer requires verification"
        lines[#lines+1]=string.format("  %s: +%.1f weighted points, %s; %s%s",c.name,c.delta,when,
            transfer,c.distant and " - far-future estimate only" or "")
        local freshness=type(self.ScanFreshness)=="function" and self:ScanFreshness(c.character,"gear")
        if freshness then
            lines[#lines+1]="    Recipient gear: "..freshness.label
        elseif c.stale then
            lines[#lines+1]="    Gear scan older than 7 days; recheck before using"
        end
    end
    for i,c in ipairs(report.excluded or {}) do
        if i>2 then lines[#lines+1]="More inaccessible recipients omitted";break end
        lines[#lines+1]="  Excluded "..c.name.." ("..tostring(c.faction or "?")..") - "..c.reason
    end
    if report.transferState=="uncertain" and report.info and report.info.bindType==2 then
        lines[#lines+1]="This item's actual unbound state was not verified in saved bags."
    elseif report.transferState=="bound" then
        lines[#lines+1]="This recorded item is soulbound; do not plan to mail it."
    end
    if #(report.uncertain or {})>0 then
        lines[#lines+1]="Some characters need updated gear data; absence of an upgrade is not proof."
    end
    lines[#lines+1]="Estimates use last scanned gear and stat weights, not simulated DPS."
    lines[#lines+1]="Advisory only: FCM does not block the Disenchant spell."
    return lines
end

-- Notify only after a real subsequent bag update in the current session.
-- A first-login scan is intentionally a baseline, not fresh loot.
function FCM:AnnounceNewBoE(owner,before,after)
    if not self.db or not self.db.settings or self.db.settings.boeAlerts==false then return end
    local function counts(rows)
        local byID={}
        for _,entry in pairs(rows or {}) do
            local id=tonumber(entry.itemID)
            if id then byID[id]=(byID[id] or 0)+(tonumber(entry.count) or 1) end
        end
        return byID
    end
    local old=counts(before)
    local now=counts(after)
    self._boeWarnedAt=self._boeWarnedAt or {}
    local shown=0
    for id,quantity in pairs(now) do
        if quantity>(old[id] or 0) and shown<3 then
            local recent=self._boeWarnedAt[id] or -100000
            local stamp=self:Now()
            if stamp-recent>=30 then
                local result=self:BoEProtectionCheck(id,owner)
                if result.status=="keep" or result.status=="review" and result.info and result.info.bindType==2 then
                    self:Say("BoE check: "..tostring(result.info.name).." - "..result.message..
                        ". Hover the item for details; do not DE until reviewed.")
                    self._boeWarnedAt[id]=stamp
                    shown=shown+1
                end
            end
        end
    end
end
