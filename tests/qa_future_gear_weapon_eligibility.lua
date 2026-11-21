-- Synthetic in-game API contract fixture, no real character records.
local F={currentKey="mage",Gear={}}
local build="synthetic-build"
local className="Mage"
local playerClass="MAGE"
local playerLevel=25
local currentSkills={"Defense","Staves"}
local tooltipLines={
    {leftText="Synthetic Future Staff"},
    {leftText="Requires Level 30"},
    {leftText="Classes: Mage, Priest"},
}
GetBuildInfo=function()return "Forever synthetic",build end
GetLocale=function()return "enUS" end
UnitClass=function()return className,playerClass end
UnitLevel=function()return playerLevel end
GetNumSkillLines=function()return #currentSkills end
GetSkillLineInfo=function(index)
    return currentSkills[index],false,false,(index==2 and 135 or 1)
end
C_TooltipInfo={GetHyperlink=function(link)
    assert(link=="item:900","Exact item ID requested for tooltip")
    return {lines=tooltipLines}
end}
F.Gear.Info=function(_,id)
    if id==900 then
        return {classID=2,subclassID=10,equip="INVTYPE_2HWEAPON",
            level=30,name="Synthetic Staff"}
    end
end
assert(loadfile("ForeverCharacterManager/FutureGearWeaponEligibility.lua"))("FCM",F)
local P=F.FutureGearPlanner
local ch={key="mage",class="MAGE",level=25}
local row={
    itemID=900,classID=2,equip="INVTYPE_2HWEAPON",
    requiredLevel=30,targetLevel=35,eligibility="verify",
    eligibilityReason="Prior reference restrictions not verified",
    sources={{kind="crafted-reference",name="Synthetic"}},
}
local evidence,err=P:WeaponProof(ch,row)
assert(evidence and not err and evidence.status=="verified" and
    evidence.source=="in-game" and evidence.proficiency=="Staves" and
    evidence.gameBuild==build,"Exact current player, skill and item tooltip verified")
assert(evidence.equippableAtLevel==30 and evidence.caution:find("not tested",1,true),
    "Future-level equip must remain explicitly untested")
local stamped,count=P:WithWeaponEvidence(ch,{row})
assert(count==0 and stamped[1].eligibility=="compatible" and
    stamped[1].weaponEligibility.status=="verified",
    "Trusted fresh client evidence promotes candidate")
assert(row.eligibility=="verify" and row.weaponEligibility==nil,
    "Original source item remains unchanged")
tooltipLines={{leftText="Synthetic Future Staff"},{leftText="Classes: Warrior"}}
local blocked,why=P:WeaponProof(ch,row)
assert(not blocked and why:find("class restriction",1,true),
    "Class-restricted weapon withheld")
tooltipLines={{leftText="Synthetic Future Staff"},{leftText="Requires Exalted reputation"}}
blocked,why=P:WeaponProof(ch,row)
assert(not blocked and why:find("requirement",1,true),
    "Unknown tooltip restrictions withheld")
tooltipLines={{leftText="Synthetic Future Staff"},{leftText="Requires Level 40"}}
blocked,why=P:WeaponProof(ch,row)
assert(not blocked and why:find("higher level",1,true),
    "Contradictory required level withheld")
tooltipLines={{leftText="Synthetic Future Staff"},{leftText="Requires Level 30"}}
currentSkills={"Defense","Axes"}
blocked,why=P:WeaponProof(ch,row)
assert(not blocked and why:find("proficiency",1,true),
    "Mage with no demonstrated staves skill withheld")
currentSkills={"Defense","Staves"}
ch.key="other"
blocked,why=P:WeaponProof(ch,row)
assert(not blocked and why:find("logged-in",1,true),
    "Offline character never inherits live skill")
ch.key="mage"
playerClass="WARLOCK"
blocked,why=P:WeaponProof(ch,row)
assert(not blocked and why:find("match",1,true),
    "Current character class mismatch withheld")
playerClass="MAGE"
local originalGetLocale=GetLocale
GetLocale=function()return "deDE" end
blocked,why=P:WeaponProof(ch,row)
assert(not blocked and why:find("enUS",1,true),
    "Unsupported locale cannot bypass restriction parser")
GetLocale=originalGetLocale
local originalTooltip=C_TooltipInfo.GetHyperlink
C_TooltipInfo.GetHyperlink=function()return nil end
blocked,why=P:WeaponProof(ch,row)
assert(not blocked and why:find("not loaded",1,true),
    "Missing item tooltip never grants proof")
C_TooltipInfo.GetHyperlink=originalTooltip
local noProof,withheld=P:WithWeaponEvidence(ch,{row})
assert(withheld==0 and noProof[1].weaponEligibility and
    noProof[1].weaponEligibility.status=="verified",
    "Successful current-player verification resumes after dependencies return")
print("PASS: future weapon proof requires live class, skill, build, level and tooltip")
