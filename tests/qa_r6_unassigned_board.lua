-- Offline R6 check: no SavedVariables deletion, unassigned requests,
-- binding-safe materials, partial manual fulfillment, and conservative scans.
local function eq(actual,expected,label)
    assert(actual==expected,(label or "mismatch")..": "..tostring(actual).." ~= "..tostring(expected))
end
local coreFile=assert(io.open("ForeverCharacterManager/Core.lua","r"))
local source=coreFile:read("*a");coreFile:close()
local partial=assert(source:match("^(.-)local f = CreateFrame%(") )
local FCM={}
assert((loadstring or load)(partial))("ForeverCharacterManager",FCM)

local recipe={id=4501,name="Training Vest",outputID=5501,quantity=1,
    profession="Tailoring",learned=true,complex=false,reagents={{itemID=6001,count=2}}}
local second={id=4502,name="Training Cloak",outputID=5502,quantity=1,
    profession="Tailoring",learned=true,complex=false,reagents={{itemID=6001,count=1}}}
local function character(key,faction,known)
    return {key=key,name=key,faction=faction,ruleset="Normal",region="US",level=25,
        recipes=known and {[4501]=recipe,[4502]=second} or {},bags={},bank={}}
end
local frost=character("Frosty","Alliance",true)
local tator=character("Tattor","Alliance",true)
local spotty=character("Spotty","Alliance",false)
local horde=character("Horde","Horde",true)
local request={key="4501:Spotty",recipeID=4501,recipientKey="Spotty",
    crafterKey="Frosty",quantity=2,quantityMode="additional",status="requested",created=10}
FCM_DB={characters={Frosty=frost,Tattor=tator,Spotty=spotty,Horde=horde},
    craftingQueue={request},settings={minimumUpgrade=1}}
FCM:InitDB()
FCM.currentKey="Frosty"
eq(#FCM.db.craftingQueue,1,"migration preserves queued request")
eq(request.crafterKey,nil,"migration removes automatic assignment")
eq(request.previousCrafterKey,"Frosty","historical assignment is recoverable")
eq(request.quantity,2,"quantity preserved")
eq(request.boardVersion,2,"board schema migrated")
eq(request.fulfilled,0,"partial completion starts at zero")
assert(loadfile("ForeverCharacterManager/Scan.lua"))("ForeverCharacterManager",FCM)
assert(loadfile("ForeverCharacterManager/Crafting.lua"))("ForeverCharacterManager",FCM)
assert(loadfile("ForeverCharacterManager/Planner.lua"))("ForeverCharacterManager",FCM)
local eligible=FCM:RequestEligibleCrafters(request)
eq(#eligible,2,"both learned Alliance toons can craft")
eq(FCM:CanCraftRequest(request,frost),true,"Frosty eligible")
eq(FCM:CanCraftRequest(request,tator),true,"Tattor eligible")
eq(FCM:CanCraftRequest(request,horde),false,"Horde ineligible")
eq(FCM:CanCraftRequest(request,spotty),false,"recipient never learns recipe implicitly")

-- A bag may contain a BoE that is already SOULBOUND. Only true unbound
-- item *instances* transfer; unknown bindings also stay inaccessible.
tator.bags={unbound={itemID=6001,count=3,bound=false},
    equippedBoe={itemID=6001,count=7,bound=true},
    unverified={itemID=6001,count=9}}
frost.bags={own={itemID=6001,count=2,bound=true}}
local total,usable,locations=FCM:MaterialLocations(6001,frost)
eq(total,21,"all copies remain accounted for")
eq(usable,5,"own soulbound plus another toon unbound only")
eq(#locations,4,"each stack is tracked separately")
assert(FCM:QueueCraft(4502,"Spotty",nil,2,"additional"))
local new=FCM.db.craftingQueue[2]
eq(new.crafterKey,nil,"new requests never choose a crafter")
eq(new.fulfilled,0)
eq(#FCM:RequestEligibleCrafters(new),2)
eq(FCM:RecordCraftProgress(new,"Horde",1),false,"cross-faction progress rejected")
eq(FCM:RecordCraftProgress(new,"Spotty",1),false,"unlearned progress rejected")
local ok,message=FCM:RecordCraftProgress(new,"Frosty",1)
assert(ok and message:find("1 still needed",1,true))
eq(new.fulfilled,1,"first partial craft recorded")
eq(new.status,"gathering","partial craft stays pending")
eq(FCM:CraftRequestNeeded(FCM:RecipeByID(4502),new,spotty),1)
FCM.currentKey="Tattor"
eq(FCM:RecordCraftProgress(new,"Tattor",1),true)
eq(new.fulfilled,2,"second maker can finish board request")
eq(new.status,"crafted","awaiting delivery")
eq(FCM:CanCraftRequest(new,frost),false,"completed craft cannot duplicate")
eq(FCM:CraftRequestNeeded(FCM:RecipeByID(4502),new,spotty),0)
eq(FCM:CountAssignedRequests("Frosty"),1,"badge counts only still-craftable requests")

-- An absent API must never erase the previously saved gold/XP of the active
-- toon. This is the specific Frosty snapshot regression seen in R5 QA.
frost.gold=39511;frost.xp=7432;frost.xpMax=34000
FCM.currentKey="Frosty"
GetMoney=nil;UnitXP=nil;UnitXPMax=nil
UnitFullName=function()return "Frosty","Bit" end
UnitLevel=function()return 25 end
FCM:ScanBasic()
eq(frost.gold,39511,"unavailable gold API does not zero saved gold")
eq(frost.xp,7432,"unavailable XP API does not zero saved XP")
eq(frost.xpMax,34000,"unavailable XP cap does not zero saved XP")
GetMoney=function()return 0 end
UnitXP=function()return 0 end
UnitXPMax=function()return 34500 end
FCM:ScanBasic()
eq(frost.gold,0,"real zero gold is still valid")
eq(frost.xp,0,"real zero XP with valid cap is still valid")
eq(frost.xpMax,34500,"new XP maximum saved")
-- Partial container API responses must not erase item records from an
-- otherwise visible bag, the suspected lost-Clam-Meat failure mode.
frost.bags={old={itemID=7001,count=7,bound=false}}
frost.bagsStamp=100
C_Container={
    GetContainerNumSlots=function(bag)return bag==0 and 1 or 0 end,
    GetContainerItemInfo=function()return nil end,
    GetContainerItemID=function()return 7001 end,
}
FCM:ScanBags()
eq(frost.bags.old.count,7,"incomplete scan preserves old bag item")
C_Container.GetContainerItemInfo=function()
    return {itemID=7002,stackCount=3,isBound=false,itemName="New Reagent"}
end
C_Container.GetContainerItemID=function()return 7002 end
FCM:ScanBags()
eq(frost.bags["0:1"].count,3,"verified scan replaces old snapshot")
eq(frost.lastBagChanges.removed[7001],7,"scan records removed item delta")
eq(frost.lastBagChanges.added[7002],3,"scan records new item delta")
print("PASS: R6 unassigned request migration, partial progress, safe binding, gold/XP scan")
