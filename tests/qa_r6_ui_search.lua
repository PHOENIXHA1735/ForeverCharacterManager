-- R6 behavior: searching Inventory/Requests stays in that view and reference
-- filters default to All/Any each time the reference window is entered.
local FCM={db={settings={itemCategory="weapons",itemType="swords",itemSlot="mainhand",
    itemScope="known",itemQuality="uncommon",itemSort="quality"}}}
function FCM:Say()end
function FCM:QueueCraft() self.queued=(self.queued or 0)+1;return true end
assert(loadfile("ForeverCharacterManager/UI.lua"))("ForeverCharacterManager",FCM)
local UI=FCM.UI
local typed=""
UI.search={GetText=function()return typed end,SetText=function(_,value)typed=value end}
UI.scroll={SetVerticalScroll=function()end}
UI.detailScroll={SetVerticalScroll=function()end}
UI.Refresh=function(self)self.calls=(self.calls or 0)+1 end
UI.tab="Inventory"
typed="Clam Meat"
UI:QueueLiveSearch()
assert(UI.tab=="Inventory","typing must not switch Inventory to Global Search")
assert(UI.appliedSearch=="Clam Meat","local Inventory search is applied")
UI:Navigate("Requests")
assert(UI.tab=="Requests" and UI.appliedSearch=="" and typed=="",
    "changing tabs clears the old local search")
typed="Fine Thread"
UI:QueueLiveSearch()
assert(UI.tab=="Requests" and UI.appliedSearch=="Fine Thread")
UI:Navigate("Item Explorer")
local s=FCM.db.settings
assert(s.itemCategory=="all" and s.itemType=="all" and s.itemSlot=="all")
assert(s.itemScope=="all" and s.itemQuality=="all" and s.itemSort=="name")
typed="Clam Meat"
UI:ExecuteSearch()
assert(UI.tab=="Global Search" and UI.appliedSearch=="Clam Meat")
UI:BackFromSearch()
assert(UI.tab=="Item Explorer","Back restores the originating window")

UI:ShowCrafterMenu({id=100,name="Example"},"recipient",nil,{{key="maker"}},2,"additional")
assert(FCM.queued==1,"request saved without a crafter-selection menu")
-- The Forever client may clear the edit field before dispatching OnAccept.
-- Pressing Enter must still record the player's typed number of items.
FCM.currentKey="maker"
function FCM:Current()return {key="maker"}end
function FCM:RecipeByID()return {id=100}end
function FCM:CanCraftRequest()return true end
function FCM:RecordCraftProgress(_,_,count)self.recorded=count;return true,"recorded" end
StaticPopupDialogs={}
local popupName
StaticPopup_Show=function(which)popupName=which end
local req={recipeID=100}
UI:ShowCraftProgressQuantity(req)
assert(popupName=="FCM_RECORD_CRAFT_PROGRESS")
local specification=StaticPopupDialogs.FCM_RECORD_CRAFT_PROGRESS
local dialog={}
local box={value="1"}
function box:SetText(v)self.value=v end
function box:GetText()return self.value end
function box:HighlightText()end
function box:SetFocus()end
function box:GetParent()return dialog end
dialog.editBox=box
dialog.button1={Click=function()
    box.value="" -- client clears the box before the callback
    specification.OnAccept(dialog)
end}
specification.OnShow(dialog)
box:SetText("3");specification.EditBoxOnTextChanged(box)
specification.EditBoxOnEnterPressed(box)
assert(FCM.recorded=="3","Enter must preserve typed progress when client clears field")
print("PASS: R6 tab-local search, broad reference defaults, direct unassigned requests")
