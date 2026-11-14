-- Level 25 first Legacy point and catalog QA, based on user video + guide.
local fcm={legacyGuideUrl=nil}
function fcm:Now() return 1780000000 end
function fcm:Characters() return self.chars or {} end
assert(loadfile("ForeverCharacterManager/Progression.lua"))("ForeverCharacterManager",fcm)
local function eq(got,want,why)
    if got~=want then error((why or "Mismatch")..": "..tostring(got).." ~= "..tostring(want),2) end
end
local perks=fcm.legacyPerks
eq(#perks,21,"Seven perks in each of three trees")
local counts={Adventure=0,Professions=0,Resourcefulness=0}
local keys={}
for _,p in ipairs(perks) do
    assert(p.id and p.name and p.max and p.max>0 and p.effect and p.bonus)
    assert(not keys[p.id],"duplicate perk ID: "..p.id)
    keys[p.id]=true
    counts[p.tree]=counts[p.tree]+1
end
for tree,count in pairs(counts) do eq(count,7,tree) end
eq(fcm:LegacyPerk("High Alert").tree,"Adventure")
eq(fcm:LegacyPerk("Master Chef").tree,"Professions","in-game tree, not misplaced guide section")
eq(fcm:LegacyPerk("Bartering").tree,"Professions")
eq(fcm:LegacyPerk("Reagent Economy").tree,"Resourcefulness")
eq(fcm:LegacyPerk("High Alert").max,2)

fcm.chars={
    {class="MAGE",name="Frosty Bit",level=25},
    {class="MAGE",name="Other Mage",level=24},
    {class="PRIEST",name="Spotty Dotty",level=1},
}
local total,proof=fcm:LegacyClassMilestoneEstimate()
eq(total,1,"first Mage level 25 milestone")
eq(proof[1],"MAGE 25")
fcm.chars[1].level=45
total=fcm:LegacyClassMilestoneEstimate()
eq(total,2,"Mage 25+45 only once")
fcm.chars[3].level=25
total=fcm:LegacyClassMilestoneEstimate()
eq(total,3,"Priest 25 adds a new class milestone")

local frost={name="Frosty Bit"}
local alt={name="Spotty Dotty"}
eq(fcm:LegacySpent(frost),0)
eq(frost.legacyAvailable,nil,"no fabricated in-game point count")
assert(fcm:SetLegacyAvailable(frost,1))
eq(frost.legacyAvailable,1)
eq(alt.legacyAvailable,nil,"account unlock does not imply alt unspent balance")
assert(not fcm:SetLegacyAvailable(frost,17))
assert(not fcm:SetLegacyAvailable(frost,-1))
local ok,reason=fcm:SetLegacyRank(frost,"High Alert",1)
assert(ok,reason)
eq(frost.legacyRanks["high-alert"],1)
eq(fcm:LegacySpent(frost),1)
assert(not fcm:SetLegacyRank(frost,"High Alert",3))
assert(not fcm:SetLegacyRank(frost,"Invented Perk",1))
ok=fcm:SetLegacyRank(frost,"high alert",0)
eq(ok,true)
eq(frost.legacyRanks["high-alert"],0)
eq(fcm:LegacySpent(frost),0)
for _,perk in ipairs(perks) do
    local _,why=fcm:SetLegacyRank(frost,perk.name,perk.max)
    if fcm:LegacySpent(frost)==16 then break end
end
assert(fcm:LegacySpent(frost)<=16)
eq(fcm:LegacySpent(alt),0,"no cross-character rank copying")
print("PASS: first-point milestones, three in-game trees and manual Legacy ranks")
