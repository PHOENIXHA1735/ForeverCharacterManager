-- Run production sidebar construction, layout and click dispatch using mock frames.
local FCM={}
local function frame()
    local f={points={},scripts={},width=145,height=500,offset=0}
    function f:SetPoint(...) self.points[#self.points+1]={...} end
    function f:ClearAllPoints() self.points={} end
    function f:SetWidth(w) self.width=w end
    function f:SetHeight(h) self.height=h end
    function f:SetSize(w,h) self.width,self.height=w,h end
    function f:GetHeight() return self.height end
    function f:SetScript(key,fn) self.scripts[key]=fn end
    function f:SetEnabled(value) self.enabled=value end
    function f:SetVerticalScroll(value) self.offset=value end
    function f:GetVerticalScroll() return self.offset end
    function f:Show() self.shown=true end
    function f:Hide() self.shown=false end
    function f:SetText(value) self.value=value end
    f.CreateTexture=frame
    f.CreateFontString=frame
    return setmetatable(f,{__index=function() return function() end end})
end
CreateFrame=frame
assert(loadfile('ForeverCharacterManager/UI.lua'))('FCM',FCM)
local ui=FCM.UI
local destinations={"Overview","Upgrade Plan","Future Gear","Upgrades","Characters","Gear","Crafting","Planner","Requests","Shopping",
    "Professions","Gathering","Catalog","Item Explorer","Dungeons","Auction","Gold","Reputation","Talents","Leveling",
    "Inventory","Legacy","QA Tests","Settings","Diagnostics","Help"}
ui.Navigate=function(self,name) self.tab=name end
ui.CharacterRecipeProfessions=function(_,ch) return ch or {} end
ui:BuildNavigation(frame())
assert(#ui.sidebarHeadings==5 and ui.sidebar.width==145)
local count=0
for _ in pairs(ui.tabButtons) do count=count+1 end
assert(count==#destinations)
for _,name in ipairs(destinations) do
    assert(ui.tabButtons[name].label.value==name)
    ui.tabButtons[name].scripts.OnClick()
    assert(ui.tab==name)
end
for _,height in ipairs({505,520,870}) do
    ui.sidebarScroll.height=height
    for _,selected in ipairs({'Overview','Help','Profession:mining'}) do
        ui.tab=selected
        ui:RefreshProfessionTabs({'Herbalism','Mining'})
        local occupied={}
        local function inside(w,h)
            local point=w.points[1]
            assert(point[4]+w.width<=145)
            local y=-point[5]
            assert(y>=0 and y+h<=ui.sidebarContent.height)
            for _,range in ipairs(occupied) do assert(y+h<=range[1] or y>=range[2]) end
            occupied[#occupied+1]={y,y+h}
            if w.enabled==false then
                assert(w.accent.shown and ui.sidebarScroll.offset<=y)
                assert(y+h<=ui.sidebarScroll.offset+height)
            end
        end
        for _,b in pairs(ui.tabButtons) do inside(b,24) end
        for _,heading in ipairs(ui.sidebarHeadings) do inside(heading,19) end
        for _,b in ipairs(ui.professionButtons) do inside(b,24) end
        ui.sidebarScroll.scripts.OnMouseWheel(nil,-500)
        assert(ui.sidebarScroll.offset==math.max(0,ui.sidebarContent.height-height))
    end
end
ui.professionButtons[2].scripts.OnClick()
assert(ui.tab=='Profession:mining')
ui:RefreshProfessionTabs({})
assert(ui.tab=='Professions' and ui.professionButtons[2].shown==false and ui.tabButtons.Professions.accent.shown)
print('PASS: grouped navigation retained all 26 tabs, dynamic professions, selection, scroll and bounds')
