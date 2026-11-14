-- QA6d: requested finished-item quantities propagate through crafting plans.
-- Run from source root: texlua tests/qa_craft_quantity_v090.lua
local base='ForeverCharacterManager/'
local function eq(got,want,label)
    if got~=want then error((label or 'mismatch')..': expected '..tostring(want)..', got '..tostring(got),2) end
end
local function setup()
    local bag={id=501,name='Linen Bag',outputID=901,quantity=1,profession='Tailoring',
        reagents={{itemID=101,count=2}},learned=true,complex=false}
    local food={id=502,name='Stack of Meals',outputID=902,quantity=2,profession='Cooking',
        reagents={{itemID=102,count=3}},learned=true,complex=false}
    local tailor={key='tailor',name='Tator',faction='Alliance',recipes={[501]=bag,[502]=food},
        bags={cloth={itemID=101,count=6,bound=false},fish={itemID=102,count=5,bound=false}},bank={}}
    local mage={key='mage',name='Frosty Bit',faction='Alliance',recipes={},
        bags={cloth={itemID=101,count=4,bound=false},fish={itemID=102,count=17,bound=false}},bank={}}
    local fcm={db={characters={tailor=tailor,mage=mage},craftingQueue={},requestHistory={}},
        _characters={tailor,mage},currentKey='mage'}
    function fcm:Try(fn,...) if fn then return fn(...) end end
    function fcm:Characters() return self._characters end
    function fcm:Now() return 1720000000 end
    function fcm:DisplayCharacter(ch) return ch and ch.name or 'Unknown' end
    function fcm:CanCollaborate(a,b) return a and b and a.faction==b.faction end
    function fcm:NormalizeFaction(v) return v end
    function fcm:Refresh() end
    assert(loadfile(base..'Crafting.lua'))('ForeverCharacterManager',fcm)
    assert(loadfile(base..'Planner.lua'))('ForeverCharacterManager',fcm)
    assert(loadfile(base..'Advisor.lua'))('ForeverCharacterManager',fcm)
    return fcm,bag,food,tailor,mage
end
local passed=0
local function test(name,fn) fn();passed=passed+1;print('PASS: '..name) end

test('whole finished-item quantities and recipe yield calculate correct casts',function()
    local fcm,bag,food=setup()
    eq(fcm:ValidCraftQuantity('20'),20)
    eq(fcm:ValidCraftQuantity('1.5'),nil)
    eq(fcm:ValidCraftQuantity(0),nil)
    eq(fcm:ValidCraftQuantity(1000),nil)
    local runs,produced,yieldPerCast=fcm:CraftRuns(food,19)
    eq(runs,10);eq(produced,20);eq(yieldPerCast,2)
    eq(fcm:CraftRuns(food,20),10)
    eq(fcm:CraftRuns(bag,6),6)
end)

test('6 bags and 20 food create correctly sized requests',function()
    local fcm,bag,food,tailor,mage=setup()
    eq(fcm:QueueCraft(bag.id,mage.key,tailor.key,6),true)
    eq(fcm:QueueCraft(food.id,mage.key,tailor.key,20),true)
    eq(#fcm.db.craftingQueue,2)
    eq(fcm.db.craftingQueue[1].quantity,6)
    eq(fcm.db.craftingQueue[2].quantity,20)
    eq(fcm:QueueCraft(bag.id,mage.key,tailor.key,9),false,'duplicate request blocked')
    eq(fcm:QueueCraft(food.id,mage.key,tailor.key,0),false,'invalid request blocked')
end)

test('reagent calculations, availability and reservation scale by casts',function()
    local fcm,bag,food,tailor,mage=setup()
    fcm:QueueCraft(bag.id,mage.key,tailor.key,6)
    fcm:QueueCraft(food.id,mage.key,tailor.key,20)
    local reserved=fcm:ReservedMaterials(nil,tailor)
    eq(reserved[101],12,'six bags reserve twelve cloth')
    eq(reserved[102],30,'twenty food reserve thirty fish')
    local bags=fcm:MaterialsFor(bag,tailor,6)
    local meals=fcm:MaterialsFor(food,tailor,20)
    eq(bags[1].required,12);eq(bags[1].missing,2)
    eq(meals[1].required,30);eq(meals[1].missing,8)
    local bagStatus=fcm:CraftAvailability(bag,tailor,fcm.db.craftingQueue[1].key,6)
    local foodStatus=fcm:CraftAvailability(food,tailor,fcm.db.craftingQueue[2].key,20)
    eq(bagStatus.lines[1].required,12)
    eq(bagStatus.lines[1].missing,2)
    eq(foodStatus.lines[1].required,30)
    eq(foodStatus.lines[1].missing,8)
    local expanded=fcm:ExpandedCraftingPlan(food,tailor,20,fcm.db.craftingQueue[2].key)
    eq(expanded.missing[102],8,'expanded plan honors 20 finished food')
end)

test('shopping list allocates shared stock once for multiple quantities',function()
    local fcm,bag,food,tailor,mage=setup()
    fcm:QueueCraft(bag.id,mage.key,tailor.key,6)
    fcm:QueueCraft(food.id,mage.key,tailor.key,20)
    local list=fcm:ShoppingList('Alliance')
    local indexed={}
    for _,row in ipairs(list) do indexed[row.id]=row end
    eq(indexed[101].required,12)
    eq(indexed[101].available,10)
    eq(indexed[101].missing,2)
    eq(indexed[102].required,30)
    eq(indexed[102].available,22)
    eq(indexed[102].missing,8)
end)

test('quantity edit updates stock planning and reopens ready requests',function()
    local fcm,bag,food,tailor,mage=setup()
    fcm:QueueCraft(bag.id,mage.key,tailor.key,6)
    local req=fcm.db.craftingQueue[1]
    req.status='ready'
    eq(fcm:UpdateQueuedCraftQuantity(req,3),true)
    eq(req.quantity,3)
    eq(req.status,'gathering')
    eq(fcm:ReservedMaterials(nil,tailor)[101],6)
    eq(fcm:ShoppingList('Alliance')[1].required,6)
    eq(fcm:UpdateQueuedCraftQuantity(req,1000),false)
    eq(req.quantity,3)
    req.status='crafted'
    eq(fcm:UpdateQueuedCraftQuantity(req,2),false)
end)

test('archival preserves quantity and old saved requests remain single-item',function()
    local fcm,bag,food,tailor,mage=setup()
    fcm:QueueCraft(food.id,mage.key,tailor.key,20)
    local req=fcm.db.craftingQueue[1]
    eq(fcm:ChangeRequestStatus(req,'delivered'),true)
    eq(#fcm.db.craftingQueue,0)
    eq(fcm.db.requestHistory[1].quantity,20)
    local old={key='501:mage',recipeID=bag.id,recipientKey=mage.key,
        crafterKey=tailor.key,status='requested',created=1720000000}
    table.insert(fcm.db.craftingQueue,old)
    eq(fcm:CraftRequestQuantity(old),1)
    eq(fcm:ReservedMaterials(nil,tailor)[101],2)
    eq(fcm:UpdateQueuedCraftQuantity(old,4),true)
    eq(old.quantity,4)
end)

print('All '..passed..' craft quantity regression tests passed.')
