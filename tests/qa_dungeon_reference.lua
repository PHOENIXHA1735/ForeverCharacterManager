local FCM={externalData={dungeons={}}}
assert(loadfile("ForeverCharacterManager/DungeonCatalog.lua"))("FCM",FCM)
local function find(rows,name)
    for _,row in ipairs(rows) do if row.name==name then return row end end
    error("Missing directory row "..name)
end
local empty=FCM:BrowseDungeons("dungeons","all",1)
assert(#empty==35)
local missing=find(empty,"Sunken Temple")
assert(missing.referenceOnly and not missing.imported)
local named,linked,associated=FCM:DungeonReferenceCounts(missing)
assert(named==0 and linked==0 and associated==0)
FCM.externalData.dungeons[12]={
    name="The Temple of Atal'Hakkar",sourceProvider="ForeverDB",bossCount=2,
    bosses={
        {name="First",loot={{id=22},{id=22}}},
        {name="Second",loot={{id=23}}},
    },
    dungeonLoot={{id=24}},
}
local populated=FCM:BrowseDungeons("dungeons","all",1)
assert(#populated==35)
local row=find(populated,"Sunken Temple")
assert(row.imported and row.sourceProvider=="ForeverDB")
assert(row.bosses[1].name=="First" and row.bosses[2].name=="Second")
named,linked,associated=FCM:DungeonReferenceCounts(row)
assert(named==2 and linked==2 and associated==1)
assert(FCM:DungeonAssociatedDrops(row)[1].id==24)
assert(#FCM:BrowseDungeons("dungeons","current",1)==0)
FCM.externalData.items={
    [22]={classID=4,subclass="plate",requiredLevel=20},
    [23]={classID=4,subclass="cloth",requiredLevel=20},
}
assert(FCM:DungeonItemEligibility(22,{class="MAGE",level=1})=="other")
assert(FCM:DungeonItemEligibility(23,{class="MAGE",level=1})=="future")
assert(loadfile("ForeverCharacterManager/UI.lua"))("FCM",FCM)
FCM.db={settings={dungeonLootScope="class"}}
local noop=function() end
local function widget()
    return setmetatable({
        SetText=function(self,value) self.value=value end,
        SetWidth=function(self,value) self.width=value end,
        SetHeight=function(self,value) self.height=value end,
        SetSize=function(self,width,height) self.width,self.height=width,height end,
        SetPoint=function(self,_,_,_,_,offset) self.offset=offset end,
        SetScript=function(self,name,fn) self[name]=fn end,
        GetStringHeight=function(self) return #self.value>self.width/5 and 28 or 14 end,
        GetWidth=function(self) return self.width end,
        SetVerticalScroll=function(self,offset) self.scroll=offset end,
    },{__index=function() return noop end})
end
local ui=FCM.UI
ui.detailChild,ui.detailScroll,ui.detailText=widget(),widget(),widget()
function ui:AcquireDungeonWidget(kind)
    local pool=self.dungeonWidgetPool or {label={},row={},texture={}}
    self.dungeonWidgetPool=pool
    local w=widget()
    w.bg,w.icon,w.name,w.sub=widget(),widget(),widget(),widget()
    pool[kind][#pool[kind]+1]=w
    return w
end
local mage={class="MAGE",level=1}
local function render(width)
    ui.dungeonWidgetPool=nil
    ui.detailChild:SetWidth(width)
    ui:RenderDungeonDetail(row,mage)
    return ui.dungeonWidgetPool.row
end
local small=render(210)
assert(#small==2 and small[1].sub.value:find("Requires a higher level",1,true))
local wide=render(420)
assert(wide[1].width>small[1].width and ui.detailChild.height>=340)
ui.dungeonBossFocus={dungeon=row.id,index=2}
local focused=render(260)
assert(#focused==1)
focused[1]:OnClick("LeftButton")
assert(ui.dungeonItemSelection==row.id..":boss:2:23" and ui.detailScroll.scroll==0)
ui.dungeonItemSelection=nil
FCM.db.settings.dungeonLootScope="all"
ui.dungeonBossFocus=nil
assert(#render(420)==3)
print("PASS: dungeon aliases, missing references, level-independent browse, boss order and separate loot")
