-- Synthetic-only shortlist policy tests. No WoW client or source item records.
local F={}
local build="synthetic-build"
GetBuildInfo=function()return "Forever test",build end
local ch={key="mage",class="MAGE",talentSpec="Frost",level=25}
assert(loadfile("ForeverCharacterManager/FutureGearShortlist.lua"))("FCM",F)
local P=F.FutureGearPlanner
local function r(id,slot,weapon,assessment,delta)
    local row={
        itemID=id,characterKey="mage",class="MAGE",specialization="Frost",
        levelNow=25,targetLevel=35,requiredLevel=30,
        classID=weapon and 2 or 4,
        slot=slot,equip=weapon and "INVTYPE_2HWEAPON" or
            (slot==11 and "INVTYPE_FINGER" or "INVTYPE_CHEST"),
        eligibility="compatible",sources={{kind="crafted-reference",name="Synthetic"}},
        assessment=assessment or "insufficient-information",
        weightedDelta=delta,
    }
    if weapon then
        row.weaponEligibility={
            status="verified",source="in-game",itemID=id,class="MAGE",
            equip=row.equip,equippableAtLevel=30,gameBuild=build,
        }
    end
    return row
end
local assessed={}
for i=1,12 do
    assessed[#assessed+1]=r(100+i,5,false,
        i==12 and "verified-weighted-upgrade" or "insufficient-information",
        i==12 and 100 or nil)
end
for i=1,7 do
    assessed[#assessed+1]=r(200+i,16,true,"qualitative-candidate")
end
local noProof=r(300,16,true)
noProof.weaponEligibility=nil
assessed[#assessed+1]=noProof
local wrongBuild=r(301,16,true)
wrongBuild.weaponEligibility.gameBuild="old-build"
assessed[#assessed+1]=wrongBuild
local wrongClass=r(302,16,true)
wrongClass.weaponEligibility.class="WARLOCK"
assessed[#assessed+1]=wrongClass
local unverified=r(303,16,true)
unverified.eligibility="verify"
assessed[#assessed+1]=unverified
local mislinked=r(304,16,true)
mislinked.weaponEligibility.itemID=111
assessed[#assessed+1]=mislinked
local normalOffhand=r(350,17,false)
normalOffhand.equip="INVTYPE_HOLDABLE"
assessed[#assessed+1]=normalOffhand
local ring1=r(360,11,false);ring1.equip="INVTYPE_FINGER"
local ring2=r(361,12,false);ring2.equip="INVTYPE_FINGER"
assessed[#assessed+1]=ring1
assessed[#assessed+1]=ring2
local foreign=r(400,5,false);foreign.specialization="Fire"
assessed[#assessed+1]=foreign
local blocked=r(401,5,false);blocked.eligibility="blocked"
assessed[#assessed+1]=blocked
local short,err=P:Shortlist(ch,assessed)
assert(not err and short.itemsPerSlot==5 and short.weaponsPerSlot==3,
    "Default caps are 5 normal, 3 weapons per slot")
assert(short.withheldWeapons==5,"Five unverified weapons withheld")
local groups={}
for _,g in ipairs(short.groups) do groups[g.key]=g end
assert(#groups["equipment:5"].rows==5 and groups["equipment:5"].total==12,
    "Chest capped after evaluating all 12 records")
assert(groups["equipment:5"].rows[1].itemID==112,
    "Highest verified improvement must survive limit despite arriving last")
assert(groups["equipment:5"].hidden==7,"Hidden count should support Show More")
assert(#groups["weapon:16"].rows==3 and groups["weapon:16"].total==7,
    "Only verified weapons, 3 initially")
assert(groups["equipment:17"].rows[1].itemID==350,
    "Non-weapon offhand stays under normal-item cap")
assert(#groups["equipment:11"].rows==2 and not groups["equipment:12"],
    "Two ring slots share one logical list")
local expanded=P:Shortlist(ch,assessed,{itemsPerSlot=10,weaponsPerSlot=5})
local wide={}
for _,g in ipairs(expanded.groups) do wide[g.key]=g end
assert(#wide["equipment:5"].rows==10 and #wide["weapon:16"].rows==5,
    "Expanded limits are 10 and 5")
assert(expanded.hiddenByLimit==4,"Only four source rows remain hidden")
local bounded=P:Shortlist(ch,assessed,{itemsPerSlot=300,weaponsPerSlot=300})
assert(bounded.itemsPerSlot==10 and bounded.weaponsPerSlot==5,"Limits clamped")
assert(noProof.weaponEligibility==nil and assessed[1].assessment=="insufficient-information",
    "Shortlist does not mutate candidate input or invent upgrade scores")
assert(groups["weapon:16"].rows[1].sources[1].name=="Synthetic",
    "Original acquisition evidence stays attached")
build="changed-build"
local changed=P:Shortlist(ch,{r(777,16,true)})
assert(changed.withheldWeapons==1 and #changed.groups==0,
    "Client build changes invalidate earlier proficiency proof")
print("PASS: 5-10 normal and 3-5 verified weapons per slot, after assessment")
