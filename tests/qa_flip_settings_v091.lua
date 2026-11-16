-- Slider, exact number box, preset selection, and explicit Apply semantics.
local FCM={db={settings={flipMinProfitPct=30}}}
local messages={}
function FCM:Say(message) messages[#messages+1]=message end
assert(loadfile("ForeverCharacterManager/UI.lua"))("ForeverCharacterManager",FCM)
local ui=FCM.UI
ui.flipMarginSlider={SetValue=function(self,value) self.value=value end}
ui.flipMarginEdit={
    SetText=function(self,value) self.value=value end,
    GetText=function(self) return self.value end,
}
ui.flipMarginState={SetText=function(self,value) self.value=value end}
ui.Refresh=function(self) self.refreshes=(self.refreshes or 0)+1 end
ui:SyncFlipMarginControls(30,"Saved")
assert(ui.flipMarginSlider.value==30 and ui.flipMarginEdit.value=="30" and
    ui.flipMarginState.value=="Saved","saved threshold populates slider and field")
ui.flipMarginEdit.value="37.5"
assert(ui:StageFlipMarginInput()==37.5 and ui.flipMarginSlider.value==37.5,
    "exact decimal entry synchronizes the slider without forcing a whole number")
assert(FCM.db.settings.flipMinProfitPct==30 and ui.flipMarginState.value=="Not saved",
    "staging never saves account preferences")
assert(ui:ApplyFlipMargin() and FCM.db.settings.flipMinProfitPct==37.5 and
    ui.flipMarginState.value=="Saved" and ui.refreshes==1,
    "Apply saves the exact percentage account-wide")
ui.flipMarginEdit.value="501"
assert(ui:ApplyFlipMargin()==false and FCM.db.settings.flipMinProfitPct==37.5,
    "out-of-range values cannot be applied")
ui.flipMarginEdit.value="garbage"
assert(ui:ApplyFlipMargin()==false and FCM.db.settings.flipMinProfitPct==37.5,
    "non-numeric values cannot be applied")
ui.flipMarginEdit.value="0"
assert(ui:ApplyFlipMargin() and FCM.db.settings.flipMinProfitPct==0,
    "minimum zero is valid and not treated as missing")
local selected
ui.MakeMenu=function(self,anchor,options) selected=options end
ui.flipMarginButton={}
ui:ShowFlipMarginMenu()
selected[4].run() -- 50% preset
assert(ui.flipMarginDraft==50 and ui.flipMarginSlider.value==50 and
    FCM.db.settings.flipMinProfitPct==0,
    "presets also stage until Apply")
assert(ui:ApplyFlipMargin() and FCM.db.settings.flipMinProfitPct==50,
    "preset becomes active when Apply is clicked")
local source=assert(io.open("ForeverCharacterManager/UI.lua","rb")):read("*a")
for _,marker in ipairs({"FCMFlipMarginSlider","SetMinMaxValues(0,500)",
    "SetValueStep(0.5)","self.flipMarginEdit:SetScript(\"OnEnterPressed\"",
    "self.flipMarginApply=button(panel,\"Apply\""}) do
    assert(source:find(marker,1,true),"Settings control not wired: "..marker)
end
print("PASS: staged slider, exact numeric box, presets, validation and Apply")
