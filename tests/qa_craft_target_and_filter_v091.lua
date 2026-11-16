-- FCM v0.9.1: recipe-only filtering and bank-aware Reach Total requests.
-- Run from repository root: texlua tests/qa_craft_target_and_filter_v091.lua
local function eq(actual,expected,label)
    if actual~=expected then
        error((label or "mismatch")..": expected "..tostring(expected)..", got "..tostring(actual),2)
    end
end
local function setup()
    local bag={id=501,name="Red Linen Bag",outputID=901,quantity=1,profession="Tailoring",
        reagents={{itemID=101,count=2}},learned=true,complex=false}
    local meal={id=502,name="Clam Chowder",outputID=902,quantity=2,profession="Cooking",
        reagents={{itemID=102,count=3}},learned=true,complex=false}
    local tailor={key="tailor",name="Tator",faction="Alliance",recipes={[501]=bag,[502]=meal},
        bags={linen={itemID=101,count=6,bound=false},fish={itemID=102,count=9,bound=false}},bank={}}
    local recipient={key="mage",name="Frosty Bit",faction="Alliance",recipes={},
        bags={linen={itemID=101,count=2,bound=false}},
        bank={finished={itemID=901,count=2,bound=false},food={itemID=902,count=1,bound=false}},bagsStamp=12345,bankStamp=12345}
    local other={key="other",name="Another Mage",faction="Alliance",recipes={},bags={},
        bank={finished={itemID=901,count=100,bound=false}}}
    local fcm={db={characters={tailor=tailor,mage=recipient,other=other},craftingQueue={},
        settings={},requestHistory={}},_characters={tailor,recipient,other},currentKey="mage",
        externalData={items={[902]={name="Cooked Clam Soup"}}}}
    function fcm:Characters() return self._characters end
    function fcm:Try(fn,...) if fn then return fn(...) end end
    function fcm:Now() return 12345 end
    function fcm:DisplayCharacter(ch) return ch and ch.name or "Unknown" end
    function fcm:CanCollaborate(a,b) return a and b and a.faction==b.faction end
    function fcm:InFactionView(ch) return ch~=nil end
    function fcm:VisibleCharacters() return self:Characters() end
    function fcm:NormalizeFaction(v) return v end
    function fcm:Refresh() end
    assert(loadfile("ForeverCharacterManager/Crafting.lua"))("ForeverCharacterManager",fcm)
    assert(loadfile("ForeverCharacterManager/Planner.lua"))("ForeverCharacterManager",fcm)
    return fcm,bag,meal,tailor,recipient,other
end

local passed=0
local function test(name,fn)
    fn();passed=passed+1;print("PASS: "..name)
end

test("Reach Total is default; Frosty has two banked bags and requests three total",function()
    local fcm,bag,_,tailor,frosty=setup()
    eq(fcm:DefaultCraftRequestMode(),"total")
    eq(fcm:QueueCraft(bag.id,frosty.key,tailor.key,3),true)
    local request=fcm.db.craftingQueue[1]
    eq(request.quantityMode,"total")
    local runs,produced,_,needed,owned,known,mode=fcm:CraftRequestRuns(bag,request,frosty)
    eq(runs,1);eq(produced,1);eq(needed,1);eq(owned,2);eq(known,true);eq(mode,"total")
    eq(fcm:ReservedMaterials(nil,tailor)[101],2,"one bag reserves two linen")
    local shopping=fcm:ShoppingList("Alliance")
    eq(#shopping,1)
    eq(shopping[1].required,2,"shopping requires only one bag's reagents")
    eq(shopping[1].missing,0)
end)

test("Craft Additional preserves three new bags despite existing stock",function()
    local fcm,bag,_,tailor,frosty=setup()
    eq(fcm:QueueCraft(bag.id,frosty.key,tailor.key,3,"additional"),true)
    local request=fcm.db.craftingQueue[1]
    local runs,_,_,needed,owned,_,mode=fcm:CraftRequestRuns(bag,request,frosty)
    eq(runs,3);eq(needed,3);eq(owned,2);eq(mode,"additional")
    eq(fcm:ReservedMaterials(nil,tailor)[101],6)
    eq(fcm:ShoppingList("Alliance")[1].required,6)
end)

test("Other character's finished items do not satisfy recipient's target",function()
    local fcm,bag,_,tailor,frosty,other=setup()
    eq(fcm:OwnedFinishedItems(other,bag.outputID),100)
    eq(fcm:QueueCraft(bag.id,frosty.key,tailor.key,3,"total"),true)
    eq(fcm:CraftRequestNeeded(bag,fcm.db.craftingQueue[1],frosty),1)
end)

test("Meeting a target later releases reservations and shopping needs",function()
    local fcm,bag,_,tailor,frosty=setup()
    eq(fcm:QueueCraft(bag.id,frosty.key,tailor.key,3),true)
    frosty.bank.finished.count=3
    local runs,_,_,needed=fcm:CraftRequestRuns(bag,fcm.db.craftingQueue[1],frosty)
    eq(runs,0);eq(needed,0)
    eq(fcm:ReservedMaterials(nil,tailor)[101],0)
    eq(#fcm:ShoppingList("Alliance"),0)
    bag.complex=true -- met goals require nothing even when the recipe is uncertain
    local shopping,unresolved=fcm:ShoppingList("Alliance")
    eq(#shopping,0);eq(#unresolved,0)
    frosty.bank.finished.count=2
    eq(fcm:CraftRequestNeeded(bag,fcm.db.craftingQueue[1],frosty),1)
end)

test("Legacy untagged requests remain Craft Additional and can be changed explicitly",function()
    local fcm,bag,_,tailor,frosty=setup()
    local old={key="501:mage",recipeID=501,recipientKey="mage",crafterKey="tailor",
        quantity=3,status="requested",created=123}
    table.insert(fcm.db.craftingQueue,old)
    eq(fcm:CraftRequestMode(old),"additional")
    eq(fcm:CraftRequestNeeded(bag,old,frosty),3)
    eq(fcm:UpdateQueuedCraftQuantity(old,3),true)
    eq(fcm:CraftRequestMode(old),"additional")
    eq(fcm:UpdateQueuedCraftQuantity(old,3,"total"),true)
    eq(fcm:CraftRequestNeeded(bag,old,frosty),1)
end)

test("Multi-output recipes round up only remaining target items",function()
    local fcm,_,meal,tailor,frosty=setup()
    eq(fcm:QueueCraft(meal.id,frosty.key,tailor.key,6,"total"),true)
    local runs,produced,yield,needed,owned=fcm:CraftRequestRuns(meal,fcm.db.craftingQueue[1],frosty)
    eq(owned,1);eq(needed,5);eq(runs,3);eq(produced,6);eq(yield,2)
    eq(fcm:ReservedMaterials(nil,tailor)[102],9)
    eq(fcm:ShoppingList("Alliance")[1].required,9)
end)

test("Unknown finished item ID is not silently treated as verified inventory",function()
    local fcm,bag,_,tailor,frosty=setup()
    bag.outputID=nil
    eq(fcm:QueueCraft(bag.id,frosty.key,tailor.key,3,"total"),true)
    local needed,owned,known=fcm:CraftRequestNeeded(bag,fcm.db.craftingQueue[1],frosty)
    eq(needed,3);eq(owned,0);eq(known,false)
end)

test("Crafting dropdown and search include learned recipes only",function()
    local fcm,bag,meal=setup()
    local profs=fcm:CraftRecipeProfessions()
    eq(#profs,2);eq(profs[1].name,"Cooking");eq(profs[2].name,"Tailoring")
    eq(#fcm:BrowseCraftRecipes("tailoring","Red Linen"),1)
    eq(fcm:BrowseCraftRecipes("tailoring","Red Linen")[1].id,bag.id)
    eq(#fcm:BrowseCraftRecipes("cooking","Red Linen"),0)
    eq(fcm:BrowseCraftRecipes("cooking","502")[1].id,meal.id)
    eq(fcm:BrowseCraftRecipes("cooking","Cooked Clam Soup")[1].id,meal.id)
    eq(#fcm:BrowseCraftRecipes("all","Linen Cloth"),0,"reagent names never match")
    eq(#fcm:BrowseCraftRecipes("all",""),2)
end)

test("Crafting UI dropdown and mode choices update independent saved settings",function()
    local fcm=setup()
    assert(loadfile("ForeverCharacterManager/UI.lua"))("ForeverCharacterManager",fcm)
    local ui=fcm.UI
    ui.craftProfessionButton={};ui.craftModeButton={}
    function ui:MakeMenu(_,options) self.choices=options end
    ui:ShowCraftProfessionMenu()
    eq(#ui.choices,3,"All plus two learned professions")
    ui.choices[3].run()
    eq(fcm.db.settings.craftProfession,"tailoring")
    ui.choices[1].run()
    eq(fcm.db.settings.craftProfession,"all")
    ui:ShowCraftRequestModeMenu()
    ui.choices[2].run()
    eq(fcm:DefaultCraftRequestMode(),"additional")
    ui.choices[1].run()
    eq(fcm:DefaultCraftRequestMode(),"total")
end)

print("All "..passed.." Reach Total and Crafting filter regressions passed.")
