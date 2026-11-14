-- FCM v0.9.1 QA4: inline Crafting quantity is a read-only, per-recipe draft.
local function eq(actual,expected,label)
    assert(actual==expected,(label or "mismatch")..": expected "..tostring(expected)..
        ", got "..tostring(actual))
end
local bag={id=6686,name="Red Linen Bag",outputID=5766,quantity=1,
    profession="Tailoring",learned=true,reagents={{itemID=2996,count=4}}}
local mage={key="mage",name="Frosty Bit",faction="Alliance",recipes={},
    bags={},bank={finished={itemID=5766,count=2,bound=false}}}
local warlock={key="tailor",name="Tator",faction="Alliance",recipes={[6686]=bag},bags={},bank={}}
local fcm={db={characters={mage=mage,tailor=warlock},craftingQueue={},settings={}},
    _characters={mage,warlock},currentKey="mage"}
function fcm:Characters() return self._characters end
function fcm:CanCollaborate(a,b) return a and b and a.faction==b.faction end
function fcm:DisplayCharacter(ch) return ch and ch.name or "unknown" end
function fcm:Try(fn,...) if fn then return fn(...) end end
function fcm:Now() return 12345 end
function fcm:Refresh() end
function fcm.ItemName(id) return "Reagent #"..tostring(id) end
assert(loadfile("ForeverCharacterManager/Crafting.lua"))("ForeverCharacterManager",fcm)
assert(loadfile("ForeverCharacterManager/SmartCrafting.lua"))("ForeverCharacterManager",fcm)
assert(loadfile("ForeverCharacterManager/UI.lua"))("ForeverCharacterManager",fcm)
local ui=fcm.UI

eq(ui:CraftDraftText(bag,mage),"3","Reach Total defaults to owned plus one")
local preview=fcm:CraftQuantityPreview(bag,mage,ui:CraftDraftText(bag,mage),"total")
eq(preview.quantity,3);eq(preview.owned,2);eq(preview.needed,1);eq(preview.casts,1)
eq(preview.produced,1);eq(preview.ownedKnown,true)

local additional=fcm:CraftQuantityPreview(bag,mage,"3","additional")
eq(additional.quantity,3);eq(additional.needed,3);eq(additional.casts,3)
local met=fcm:CraftQuantityPreview(bag,mage,"2","total")
eq(met.needed,0);eq(met.casts,0)
eq(fcm:CraftQuantityPreview(bag,mage,"0","total"),nil)
eq(fcm:CraftQuantityPreview(bag,mage,"invalid","total"),nil)
eq(fcm:CraftQuantityPreview(bag,mage,"1000","total"),nil)
eq(fcm:CraftQuantityPreview(bag,mage,"","total"),nil)

-- Multiple toons/recipes must not silently inherit one another's drafts.
ui.craftQuantityDrafts[ui:CraftDraftKey(bag,mage)]="5"
eq(ui:CraftDraftText(bag,mage),"5")
eq(ui:CraftDraftText(bag,warlock),"1")
eq(ui:CraftDraftText(bag,mage),"5")

-- The input event changes only a draft, not SavedVariables/queue records.
local field={value="4"}
function field:GetText() return self.value end
function field:SetText(value) self.value=value end
ui.tab="Crafting"
ui.frame={IsShown=function() return true end}
ui.craftQuantityEdit=field
ui.craftDraftKey=ui:CraftDraftKey(bag,mage)
ui.Refresh=function(self)self.refreshes=(self.refreshes or 0)+1 end
ui:QueueCraftQuantityPreview()
eq(ui:CraftDraftText(bag,mage),"4")
eq(ui.refreshes,1)
eq(#fcm.db.craftingQueue,0,"typing must not submit a request")
local nextPreview=fcm:CraftQuantityPreview(bag,mage,ui:CraftDraftText(bag,mage),"total")
eq(nextPreview.needed,2)

ui:SyncCraftQuantityBox(bag,warlock)
eq(field.value,"1")
eq(ui.craftDraftKey,"tailor:6686")
eq(ui:CraftDraftText(bag,mage),"4")

-- The transfer summary shown on the right is based on actual eligible stock.
mage.bags.cloth={itemID=2996,count=4,bound=false}
local learned=fcm:AllRecipes()[1]
local plan=fcm:SmartCraftingPlan(learned,mage,warlock,1)
eq(#plan.transfers,1,"one potential cross-character send")
eq(plan.transfers[1].count,4)
eq(plan.transfers[1].from,"Frosty Bit")
eq(plan.transfers[1].to,"Tator")
eq(plan.transfers[1].where,"bags")
mage.bags.cloth.bound=true
local bound=fcm:SmartCraftingPlan(learned,mage,warlock,1)
eq(#bound.transfers,0,"bound materials must not be suggested for sending")
eq(bound.missing[2996],4,"bound stock on recipient cannot satisfy crafter's need")

print("PASS: inline quantity, modes, per-recipe drafts, no auto-queue, validation and safe transfers")
