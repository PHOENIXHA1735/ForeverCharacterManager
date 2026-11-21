-- Synthetic tests against the production paths for the PR #9 release blockers.
local f={db={settings={minimumUpgrade=0}},gearActivityLabels={},modeLabels={}}
CreateFrame=function() return setmetatable({}, {__index=function() return function() end end}) end
SlashCmdList={}
for _,file in ipairs({"Core","Scan","Crafting","Advisor","SmartCrafting","Gear","UpgradeIntelligence"}) do
    assert(loadfile("ForeverCharacterManager/"..file..".lua"))("FCM",f)
end
local now=1800000000
function f:Now() return now end
local crafter={key="crafter",class="MAGE",level=30,faction="Alliance",ruleset="normal",region="us",
    professions={Tailoring={skill=100}},bags={},bank={},bagsStamp=now,bankStamp=now}
local alt={key="alt",faction="Alliance",ruleset="normal",region="us",bagsStamp=now,bankStamp=now,
    bags={{itemID=33,count=12,bound=false}},bank={}}
local opposite={key="opposite",faction="Horde",ruleset="normal",region="us",
    bags={{itemID=33,count=12,bound=false}},bagsStamp=now}
local recipe={id=7,name="Synthetic tailoring",profession="Tailoring",requiredSkill=50,outputID=99,
    crafters={crafter},reagents={{itemID=33,count=12}}}
function f:Characters() return {crafter,alt,opposite} end
function f:AllRecipes() return {recipe} end
function f:ReservedMaterials() return {} end
function f:Current() return crafter end
function f.ItemName(id) return "Fixture "..id end
function f:VisibleCharacters() return {crafter} end
local failed=0
local function check(name,fn)
    local ok,message=pcall(fn)
    if ok then print("PASS "..name)
    else failed=failed+1; print("FAIL "..name..": "..tostring(message)) end
end
check("skill thresholds and incompatible markets",function()
    assert(f:RecipeSkillStatus(recipe,crafter)=="ready")
    recipe.requiredSkill=101
    assert(f:RecipeSkillStatus(recipe,crafter)=="blocked")
    recipe.requiredSkill=50
    assert(f:CanCollaborate(crafter,alt))
    assert(not f:CanCollaborate(crafter,opposite))
    alt.ruleset="pvp"; assert(not f:CanCollaborate(crafter,alt)); alt.ruleset="normal"
end)
check("missing versus stale finished-item inventory",function()
    local c={bagsStamp=now,bags={},bank={}}
    assert(not f:FinishedItemStock(c,99).known)
    c.bankStamp=now-700000
    assert(f:FinishedItemStock(c,99).stale)
end)
check("smart plan requires retrieval of alt materials",function()
    local plan=f:SmartCraftingPlan(recipe,crafter)
    assert(plan.totalMissing==0 and #plan.transfers==1)
    assert(not plan.ready,"compatible alt stock is flagged ready before transfer")
end)
check("smart plan excludes opposite-faction and bound materials",function()
    alt.bags[1].bound=true
    local plan=f:SmartCraftingPlan(recipe,crafter)
    alt.bags[1].bound=false
    assert(plan.totalMissing==12 and not plan.ready and #plan.transfers==0)
end)
check("equipment snapshot survives failed link reads",function()
    local previous={[16]={itemID=501,link="item:501"}}
    crafter.gear,crafter.gearStamp=previous,now-10
    GetInventoryItemLink=function() error("synthetic client read failure") end
    f:ScanGear()
    GetInventoryItemLink=nil
    assert(crafter.gear==previous and crafter.gearStamp==now-10,"failed reads replaced/stamped prior gear")
    GetInventoryItemLink=function(_,slot) if slot==16 then return "item:501" end end
    GetInventoryItemID=function(_,slot) if slot==16 then return 501 elseif slot==17 then return 502 end end
    f:ScanGear()
    assert(crafter.gear==previous and crafter.gearStamp==now-10)
    GetInventoryItemID=function(_,slot) if slot==16 then return 501 end end
    f:ScanGear()
    assert(crafter.gear~=previous and crafter.gear[16].itemID==501 and crafter.gear[17]==nil and crafter.gearStamp==now)
    GetInventoryItemLink,GetInventoryItemID=nil,nil
end)
check("class cannot be offered an unusable weapon",function()
    assert(not f.Gear:IsPotentiallyWearable({equip="INVTYPE_2HWEAPON",classID=2,subclassID=1,level=10},crafter),
        "mage accepted for two-handed axe")
end)
check("nine classes fail closed without weapon evidence and accept demonstrated proficiency",function()
    local gear=f.Gear
    local old=gear.Info
    local axe={equip="INVTYPE_2HWEAPON",classID=2,subclassID=1,level=10}
    local weapon={equip="INVTYPE_WEAPONMAINHAND",classID=2,subclassID=15,level=15}
    gear.Info=function(_,id) if id==601 then return weapon end end
    for _,class in ipairs({"WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","SHAMAN","MAGE","WARLOCK","DRUID"}) do
        local ch={class=class,level=60,gear={[16]={itemID=601}}}
        assert(gear:IsPotentiallyWearable(weapon,ch)==true,class)
        assert(gear:IsPotentiallyWearable(axe,ch)==nil,class)
        assert(gear:IsPotentiallyWearable({equip="INVTYPE_CHEST",classID=4,subclassID=1,level=5},ch)==true,class)
        ch.level=10
        assert(gear:IsPotentiallyWearable(weapon,ch)==false,class)
    end
    gear.Info=old
end)
check("two-hander comparison includes offhand and respects future levels",function()
    local gear=f.Gear
    local oldInfo,oldStat=gear.Info,gear.StatValues
    local items={
        [701]={name="Equipped staff",equip="INVTYPE_2HWEAPON",classID=2,subclassID=10,level=15},
        [702]={name="Offhand",equip="INVTYPE_HOLDABLE",classID=4,subclassID=0,level=15},
        [703]={name="Higher-level staff",equip="INVTYPE_2HWEAPON",classID=2,subclassID=10,level=40},
    }
    local stats={[701]=10,[702]=5,[703]=20}
    gear.Info=function(_,id) return items[id] end
    gear.StatValues=function(_,id) return {int=stats[id]} end
    GetBuildInfo=function() return "synthetic","fixture" end
    local ch={key="weapon-fixture",class="MAGE",level=30,talentSpec="Frost",gearStamp=now,
        gear={[16]={itemID=701},[17]={itemID=702}}}
    assert(gear:SetCustomWeight(ch,"int",1))
    assert(gear:CompareItem(703,ch).status=="ineligible")
    local future=gear:CompareItem(703,ch,16,{allowFutureLevel=true})
    assert(future.status=="ok" and future.oldScore==15 and future.delta==5 and future.scorePct==nil)
    assert(gear:CompareItem(702,ch,17).status=="unknown")
    gear.Info,gear.StatValues=oldInfo,oldStat
    GetBuildInfo=nil
end)
check("bag, bank, transfer, reservation and stale statuses",function()
    local stack={itemID=33,count=12,bound=false}
    crafter.bags={stack}
    assert(f:SmartCraftingPlan(recipe,crafter).ready)
    crafter.bags={};crafter.bank={stack}
    assert(f:SmartCraftingPlan(recipe,crafter).status=="Bank withdrawal required")
    crafter.bank={}
    assert(f:SmartCraftingPlan(recipe,crafter).status=="Materials available after transfer")
    alt.bagsStamp=now-180000
    assert(f:SmartCraftingPlan(recipe,crafter).status=="Verification required")
    alt.bagsStamp=now
    local original=f.ReservedMaterials
    f.ReservedMaterials=function() return {[33]=12} end
    assert(f:SmartCraftingPlan(recipe,crafter).totalMissing==12)
    f.ReservedMaterials=original
end)
check("upgrade-plan adapter preserves estimates and missing-only fallback",function()
    local gear=f.Gear
    local originalCandidates,originalDungeon,originalUnlearned=gear.Candidates,gear.DungeonCandidates,gear.UnlearnedCandidates
    gear.Candidates=function() return {{recipe=recipe,slot=5,delta=3,crafters={crafter}}} end
    gear.DungeonCandidates=function() return {{itemID=100,slot=16,delta=2,sources={"Fixture (boss unknown)"}},{itemID=101}} end
    gear.UnlearnedCandidates=function() return {} end
    local plans=f:AccountUpgradePlans()
    gear.Candidates,gear.DungeonCandidates,gear.UnlearnedCandidates=originalCandidates,originalDungeon,originalUnlearned
    assert(#plans==2)
    local seen={}
    for _,row in ipairs(plans) do seen[row.kind]=row end
    assert(seen.crafted.delta==3 and seen.crafted.plan.crafter==crafter)
    assert(seen.dungeon.delta==2 and seen.dungeon.itemID==100 and #seen.dungeon.sources==1)
end)
check("legacy database keeps character, profession, gear, and request data",function()
    local saved={realm="SyntheticSurname",professions={Tailoring={skill=100}},
        bags={{itemID=33,count=12}},bank={{itemID=34,count=1}},
        gear={[5]={itemID=501}},recipes={[7]={name="Synthetic tailoring"}}}
    local request={crafterKey="old-crafter",quantity=2,recipeID=7}
    FCM_DB={schema=5,characters={legacy=saved},craftingQueue={request}}
    f:InitDB()
    assert(FCM_DB.schema>=6 and FCM_DB.characters.legacy==saved)
    assert(saved.surname=="SyntheticSurname" and saved.realm=="SyntheticSurname")
    assert(saved.professions.Tailoring.skill==100 and saved.recipes[7].name=="Synthetic tailoring")
    assert(saved.bags[1].count==12 and saved.bank[1].count==1 and saved.gear[5].itemID==501)
    assert(FCM_DB.craftingQueue[1]==request and request.quantity==2 and request.recipeID==7)
    assert(request.crafterKey==nil and request.previousCrafterKey=="old-crafter" and request.boardVersion==2)
end)
assert(failed==0,tostring(failed).." targeted assertions failed")
