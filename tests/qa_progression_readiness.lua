local f={db={settings={}}}
local legacy={skill="110",maxSkill="225"}
local current={name=" Blacksmithing ",skill=140,maxSkill=225}
local synthetic={skill=150,maxSkill=225}
local c={name="Fixture",professions={Tailoring=synthetic,Alchemy=legacy,
    [164]=current,[999]={skill=1,maxSkill=225},Broken="not a table",
    Partial={name="Partial",skill=100},BadRank={skill={},maxSkill=225},
    Infinite={skill=100,maxSkill=math.huge}}}
function f:VisibleCharacters() return {c,{name="Invalid",professions="legacy invalid container"}} end
function f:TalentAdvice() end
assert(loadfile("ForeverCharacterManager/Planner.lua"))("FCM",f)
local milestones={}
for _,r in ipairs(f:UpgradeDashboard())do milestones[r.title]=true end
assert(milestones["Fixture: Tailoring milestone 225"])
assert(milestones["Fixture: Alchemy milestone 150"])
assert(milestones["Fixture: Blacksmithing milestone 150"])
local count=0
for _ in pairs(milestones) do count=count+1 end
assert(count==3 and not synthetic.name and legacy.skill=="110" and current.name==" Blacksmithing ")
f.externalData={items={[3199]={classID=2,subclassID=1,requiredLevel=17,equipLoc="INVTYPE_2HWEAPON"}}}
assert(loadfile("ForeverCharacterManager/Gear.lua"))("FCM",f)
assert(loadfile("ForeverCharacterManager/DungeonCatalog.lua"))("FCM",f)
function f.Gear:Info() return nil end
local mage={class="MAGE",level=14}
local warrior={class="WARRIOR",level=30}
assert(f:DungeonItemEligibility(3199,mage)=="other")
assert(f:DungeonItemEligibility(3199,warrior)=="unknown")
assert(f:DungeonItemEligibility(999999,mage)=="unknown")
function f.Gear:Info(id)
    if id==3199 then return {itemID=3199,equip="INVTYPE_2HWEAPON",classID=2,subclassID=1,level=17} end
end
assert(f.Gear:CompareItem(3199,mage,nil,{allowFutureLevel=true}).status=="ineligible")
f.externalData.dungeons={[36]={name="Deadmines",bosses={{name="Rhahk'Zor",loot={{id=3199}}}}}}
assert(#f.Gear:DungeonCandidates(mage)==0)

-- Exercise the real row and detail builders for every Progression navigation tab.
local host={}
CreateFrame=function() return setmetatable({}, {__index=function() return function() end end}) end
SlashCmdList={}
GetBuildInfo=function() return "synthetic","fixture" end
local absent={["ExternalData.generated.lua"]=true,["AHPrices.generated.lua"]=true,["AHHistory.generated.lua"]=true}
for line in io.lines("ForeverCharacterManager/ForeverCharacterManager.toc") do
    local file=line:match("^([^#].*%.lua)%s*$")
    if file and not absent[file] then assert(loadfile("ForeverCharacterManager/"..file))("FCM",host) end
end
host:InitDB()
local saved={key="Fixture-Mage",name="Synthetic Mage",class="MAGE",talentSpec="Frost",level=30,
    faction="Alliance",ruleset="Normal",region="us",professions={Tailoring={skill=150,maxSkill=225}},
    bags={},bank={},recipes={},gear={},reputations={}}
host.db.characters[saved.key]=saved
function host.UI:GetCharacter() return saved end
local build
for index=1,60 do
    local name,value=debug.getupvalue(host.UI.Refresh,index)
    if name=="buildRows" then build=value;break end
end
assert(build,"Unable to locate the production row builder")
for _,tab in ipairs({"Upgrade Plan","Upgrades","Talents","Legacy","Leveling","Reputation"}) do
    host.UI.tab=tab
    local rows=build(host.UI)
    assert(#rows>0,tab)
    for _,row in ipairs(rows) do
        if type(row.detail)=="function" then assert(type(row.detail())=="string",tab) end
    end
end
print("PASS: keyed and malformed professions, Battle Slayer restrictions, future and unknown handling")
