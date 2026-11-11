local _, FCM = ...

-- Only confirmed talent point order is used for next-point prompts. Milestones
-- remain qualitative hints, never fabricated exact instructions.
function FCM:TalentReminder(ch)
    if not ch or not ch.level or not self.TalentReport then return nil end
    local r = self:TalentReport(ch)
    if r and #r.gaps>0 then
        return "Your allocated talents differ from reviewed guide steps; check the Talent Advisor before spending gold"
    end
    if r and r.nextStep and r.nextStep.name and r.nextStep.level <= (ch.level or 0) then
        return "Reviewed talent step: " .. r.nextStep.name .. (r.nextStep.rank and (" rank " .. r.nextStep.rank) or "") ..
            " (guide step at level " .. tostring(r.nextStep.level) .. ")"
    end
    return nil
end

function FCM:TrackSession()
    local ch=self:Current()
    if not ch then return end
    local now=self:Now()
    if not ch.sessionAnchor then
        ch.sessionAnchor=now; ch.sessionXP=ch.xp or 0; ch.sessionLevel=ch.level or 1
        ch.sessionXPMax=ch.xpMax or 0
    end
    -- Track XP gained only where change is computable; no assumptions about prior level caps.
    if (ch.level or 0)==(ch.sessionLevel or 0) then
        ch.sessionGain=math.max(0,(ch.xp or 0)-(ch.sessionXP or 0))
    else
        ch.sessionGain=math.max(0,(ch.sessionXPMax or 0)-(ch.sessionXP or 0))+(ch.xp or 0)
        ch.sessionLevel=ch.level
        ch.sessionXP=0
        ch.sessionXPMax=ch.xpMax
    end
end

function FCM:LevelingSummary(ch)
    if not ch then return "No character selected." end
    local parts={"Character: "..self:DisplayCharacter(ch), "Level: "..tostring(ch.level or "?"),
        "XP: "..tostring(ch.xp or 0).." / "..tostring(ch.xpMax or "?"),
        "Rested XP: "..tostring(ch.restedXP or 0)}
    if ch.sessionAnchor and ch.sessionGain then
        local hours=math.max(1/60,(self:Now()-ch.sessionAnchor)/3600)
        local rate=math.floor(ch.sessionGain/hours)
        parts[#parts+1]="Session XP recorded: "..ch.sessionGain
        parts[#parts+1]="Approx. XP / hour: "..rate
        if rate>0 and (ch.xpMax or 0)>(ch.xp or 0) then
            parts[#parts+1]="Approx. time to next level: "..string.format("%.1f",(ch.xpMax-ch.xp)/rate).." hours"
        end
    else parts[#parts+1]="XP/session tracking begins on your next login." end
    parts[#parts+1]="Offline estimates use the last recorded snapshot."
    return table.concat(parts,"\n")
end

-- Future Legacy trait capture requires the live Forever Legacy config identifier.
-- Keep user-set goals without presenting guessed amounts as live points.
function FCM:LegacyGoal(ch)
    return ch and ch.legacyGoal or "No Legacy goal set. Use /fcm legacygoal <goal>."
end
