-- Opt-in visual-detail prototype for collected Gathering materials.
-- The rest of FCM continues to use UI:RenderDetailCards unchanged.
local _,FCM=...
local UI=FCM.UI

local function fill(frame,r,g,b,a)
    local tex=frame:CreateTexture(nil,"BACKGROUND")
    tex:SetAllPoints(frame)
    tex:SetColorTexture(r,g,b,a or 1)
    return tex
end

local function line(frame,edge)
    local tex=frame:CreateTexture(nil,"BORDER")
    tex:SetColorTexture(.49,.35,.15,.90)
    if edge=="TOP" then
        tex:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0)
        tex:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0)
        tex:SetHeight(1)
    elseif edge=="BOTTOM" then
        tex:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",0,0)
        tex:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0)
        tex:SetHeight(1)
    elseif edge=="LEFT" then
        tex:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0)
        tex:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",0,0)
        tex:SetWidth(1)
    else
        tex:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0)
        tex:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0)
        tex:SetWidth(1)
    end
end

local function label(frame,style)
    local text=frame:CreateFontString(nil,"OVERLAY",style or "GameFontHighlight")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    return text
end

function UI:HideGatherMaterialPanel()
    self.gatherMaterialActive=false
    for _,frame in ipairs(self.gatherMaterialFrames or {}) do frame:Hide() end
end

function UI:RenderGatherMaterialPanel(resource,ch,expanded)
    if not self.detailChild or not FCM.GatherMaterialDetailModel then return false end
    local model=FCM:GatherMaterialDetailModel(resource,ch,expanded)
    if not model then return false end
    self.gatherMaterialFrames=self.gatherMaterialFrames or {}
    for _,frame in ipairs(self.gatherMaterialFrames) do frame:Hide() end
    local index=0
    local host=self.detailChild
    local width=math.max(220,host:GetWidth()-8)
    local y=5
    local function card(w,h,x,top)
        index=index+1
        local frame=self.gatherMaterialFrames[index]
        if not frame then
            frame=CreateFrame("Frame",nil,host)
            frame.bg=fill(frame,.065,.09,.105,.96)
            for _,edge in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do line(frame,edge) end
            frame.title=label(frame,"GameFontNormalLarge")
            frame.subtitle=label(frame,"GameFontHighlightSmall")
            frame.icon=frame:CreateTexture(nil,"ARTWORK")
            frame.body=label(frame,"GameFontHighlight")
            self.gatherMaterialFrames[index]=frame
        end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT",host,"TOPLEFT",x or 3,-(top or y))
        frame:SetSize(w,h)
        frame.title:Hide()
        frame.subtitle:Hide()
        frame.icon:Hide()
        frame.body:Hide()
        frame:Show()
        return frame
    end
    local header=card(width,69,3,y)
    header.bg:SetColorTexture(.06,.11,.115,.97)
    header.icon:SetSize(42,42)
    header.icon:ClearAllPoints()
    header.icon:SetPoint("TOPLEFT",header,"TOPLEFT",9,-10)
    header.icon:SetTexture(model.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    header.icon:Show()
    header.title:ClearAllPoints()
    header.title:SetPoint("TOPLEFT",header,"TOPLEFT",59,-9)
    header.title:SetWidth(width-72)
    header.title:SetText("|cffffd17b"..tostring(model.name).."|r")
    header.title:Show()
    header.subtitle:ClearAllPoints()
    header.subtitle:SetPoint("TOPLEFT",header,"TOPLEFT",59,-35)
    header.subtitle:SetWidth(width-72)
    header.subtitle:SetText(tostring(model.itemType).."  |  Item "..tostring(model.itemID or "Unknown")..
        "  |  "..tostring(model.profession))
    header.subtitle:Show()
    y=y+77

    local spacing=5
    local tileW=math.floor((width-spacing*2)/3)
    local metricData={
        {"Required Skill",model.required,"ffddb27a"},
        {"Your Skill",model.current..(model.cap and ("/"..model.cap) or ""),"ffb7e4c4"},
        {"Can Gather",model.canGather,"ffffc77b"}
    }
    for n,entry in ipairs(metricData) do
        local x=3+(n-1)*(tileW+spacing)
        local w=n==3 and width-2*(tileW+spacing) or tileW
        local box=card(w,54,x,y)
        box.bg:SetColorTexture(.08,.105,.105,.98)
        box.subtitle:ClearAllPoints()
        box.subtitle:SetPoint("TOPLEFT",box,"TOPLEFT",7,-8)
        box.subtitle:SetWidth(w-12)
        box.subtitle:SetText(entry[1])
        box.subtitle:Show()
        box.title:ClearAllPoints()
        box.title:SetPoint("TOPLEFT",box,"TOPLEFT",7,-26)
        box.title:SetWidth(w-12)
        box.title:SetText("|cff"..entry[3]..tostring(entry[2]).."|r")
        box.title:Show()
    end
    y=y+62

    local function section(title,lines)
        local box=card(width,50,3,y)
        box.bg:SetColorTexture(.065,.105,.095,.97)
        box.title:ClearAllPoints()
        box.title:SetPoint("TOPLEFT",box,"TOPLEFT",10,-8)
        box.title:SetWidth(width-20)
        box.title:SetText("|cffffcf75"..title.."|r")
        box.title:Show()
        box.body:ClearAllPoints()
        box.body:SetPoint("TOPLEFT",box,"TOPLEFT",11,-32)
        box.body:SetWidth(width-22)
        box.body:SetText(table.concat(lines,"\n"))
        box.body:Show()
        local contentHeight=math.ceil(tonumber(box.body:GetStringHeight()) or 0)
        local height=math.max(56,contentHeight+43)
        box:SetHeight(height)
        y=y+height+8
    end

    local sources={}
    for _,src in ipairs(model.sources) do
        sources[#sources+1]="|cffffe4b5"..src.name.."|r  (Req: "..tostring(src.required)..
            ")  |cffd5d5d5"..tostring(src.eligibility).."|r"
    end
    sources[#sources+1]="|cffffc77bWoW Forever material drops are not confirmed.|r"
    section("POSSIBLE SOURCE DEPOSITS",sources)

    local places={}
    for _,group in ipairs(model.zoneGroups) do
        places[#places+1]="|cffffd27f"..group.name.."|r"
        for _,loc in ipairs(group.locations) do
            places[#places+1]="   "..loc.name..(loc.reported and " (reported)" or " (reference)")
        end
        if group.total==0 then places[#places+1]="   No verified zone locations" end
        if group.remaining>0 then
            places[#places+1]="   |cffb3d3fb+"..group.remaining..
                " more zones — Show All Details below|r"
        end
    end
    section("POTENTIAL SOURCE ZONES",places)

    section("HOW IT IS OBTAINED",{model.explanation})
    section("YOUR GATHERING HISTORY",model.history)
    if expanded then section("REFERENCE STATUS",{model.verificationNote}) end
    host:SetHeight(math.max(345,y+9))
    self.detailText:Hide()
    self.gatherMaterialActive=true
    self.gatherMaterialRow=resource
    self.gatherMaterialCharacter=ch
    self.gatherMaterialExpanded=expanded
    return true
end
