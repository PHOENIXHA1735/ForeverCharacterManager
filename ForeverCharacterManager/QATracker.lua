-- QA9-13 candidate: a persistent, user-controlled test checklist.
-- No tests are marked passed automatically. SavedVariables keep all results
-- between characters, logouts, and backup-first addon updates.
local _,FCM=...
FCM.qaTestCases={
    {id="Q01",phase="QA8",title="Horde Feral source",
        steps="Log into Fawendyn Ragewanderer (Horde Druid); select Feral on Talents, set Gear activity Leveling; /fcm statguide.",
        expected="Feral Druid leveling source loads; Horde identity stays correct."},
    {id="Q02",phase="QA8",title="Horde Restoration Healing",
        steps="On Fawendyn: choose Restoration on Talents and Healing style in Gear; /fcm statguide; restore Feral/DPS afterwards.",
        expected="Restoration guide loads; healing comparisons are reference-only."},
    {id="Q03",phase="QA9",title="Gear confidence and safety",
        steps="On Frosty inspect a replacement item in Gear or Item Explorer; check stat gains/losses, confidence, and unknown-cap warnings. Do not equip or buy.",
        expected="No unsupported precise DPS claim; uncertain swaps stay Review Required."},
    {id="Q04",phase="QA10",title="Readable colors across tabs",
        steps="Open Overview, Gear, Crafting, Gathering, Inventory, Item Explorer, Dungeons, Talents, Legacy, Settings and Diagnostics.",
        expected="Every tab uses consistent high-contrast headings, labels and backgrounds; no white-on-white text."},
    {id="Q05",phase="QA11",title="Bank and bag crafting preview",
        steps="On Frosty inspect Red Linen Bag in Crafting; verify Bags and Bank counts (2 in bank if still recorded), then change Qty without submitting.",
        expected="Reach Total and Craft Additional update live; partial or stale scans clearly warn; no request is sent by typing."},
    {id="Q06",phase="QA11",title="Character crafting isolation",
        steps="Compare Tator and Frosty crafting recipients, request visibility, and learned recipes. Inspect alt stock; do not transfer materials.",
        expected="Correct recipient/crafter; no double-counted bank stock or cross-faction transfers."},
    {id="Q07",phase="QA12",title="Gathering node counts",
        steps="Hover a personally gathered herb/mining node on the minimap; inspect counts, range rim, and Hide within control.",
        expected="Count reflects recorded gathers and never presents a saved reference node as a guaranteed spawn."},
    {id="Q08",phase="QA12",title="Map category and chest/fish pins",
        steps="Toggle world-map herb, ore, fish and chest controls separately; inspect any known fishing/treasure nodes.",
        expected="Each kind toggles independently; unknown nodes are not fabricated."},
    {id="Q09",phase="QA13",title="Companion missing-name audit",
        steps="On Windows companion, run Audit Reference Data; inspect reference-audit.json named searches for Clam Meat and Brilliant Fish.",
        expected="Audit reports cache match counts and source caveats without claiming missing names do not exist."},
    {id="Q10",phase="QA13",title="Companion schedule and quota review",
        steps="Review overnight catalog schedule, quota ledger, build stamp, and cache age. Do not increase the 4,500/day limit.",
        expected="No false fresh-data claim; provider cache and request quota limits stay respected."},
    {id="Q11",phase="QA9",title="Per-character activity persistence",
        steps="Switch Tator to PvE, log to Spotty Shadow leveling, then return; confirm both profiles remain independent. Restore Tator leveling.",
        expected="No character/faction profile leak or unintended reset."},
    {id="Q12",phase="QA11 R2",title="Faction-aware Crafting list",
        steps="On an Alliance recipient, verify only compatible crafters' recipes and professions appear. Later log onto Horde Fawendyn with no Horde crafter scanned and open Crafting; then scan a Horde crafter and check the list again.",
        expected="Horde does not list Alliance-only recipes or lures. When no eligible crafter is known, a clear no-compatible-recipes message appears. Scanning a matching Horde crafter reveals only its recipes. No cross-faction requests are offered."},
    {id="Q13",phase="QA10 R3",title="Full talent build names",
        steps="On Frosty open Talents, inspect the build selector near the bottom-right. Switch between Efficient Frost and at least one long-named endgame profile, then hover the build button.",
        expected="The full Efficient Frost label fits the wide first-row button; other long names use a readable short title if necessary and reveal the complete title on hover. Spec/source selectors remain on the lower row and nothing overlaps."},
}

function FCM:QATestByID(id)
    for _,entry in ipairs(self.qaTestCases) do
        if entry.id==tostring(id or ""):upper() then return entry end
    end
end
function FCM:QATestRecord(id)
    local entry=self:QATestByID(id)
    local saved=self.db and self.db.qaChecks
    return entry,entry and type(saved)=="table" and saved[entry.id] or nil
end
function FCM:SetQATestStatus(id,status,note)
    local entry=self:QATestByID(id)
    if not entry or not self.db then return false,"Unknown test ID; use /fcm qa list." end
    status=tostring(status or ""):lower()
    if status~="pass" and status~="fail" and status~="reset" then
        return false,"Choose pass, fail or reset."
    end
    self.db.qaChecks=self.db.qaChecks or {}
    if status=="reset" then self.db.qaChecks[entry.id]=nil
    else
        self.db.qaChecks[entry.id]={status=status,at=self:Now(),
            note=tostring(note or ""):sub(1,160)}
    end
    if self.Refresh then self:Refresh() end
    return true,entry.id.." "..(status=="reset" and "OPEN" or status:upper()).." (saved)."
end
function FCM:QATestSummaryLines()
    local lines={}
    local passed,failed,open=0,0,0
    for _,entry in ipairs(self.qaTestCases) do
        local _,record=self:QATestRecord(entry.id)
        local status=record and record.status or "open"
        if status=="pass" then passed=passed+1
        elseif status=="fail" then failed=failed+1
        else open=open+1 end
        lines[#lines+1]=entry.id.." ["..string.upper(status).."] "..entry.title
    end
    table.insert(lines,1,"QA9-13 TRACKER: "..passed.." passed / "..failed.." failed / "..open.." open")
    return lines
end
