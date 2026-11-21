-- Framed Gathering details for materials, nodes, fishing and treasure.
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
    if not self.detailChild or not FCM.GatherDetailModel then return false end
    local model=FCM:GatherDetailModel(resource,ch,expanded)
    if not model then return false end
    self.gatherMaterialFrames=self.gatherMaterialFrames or {}
    for _,frame in ipairs(self.gatherMaterialFrames) do frame:Hide() end
    local index=0
    local host=self.detailChild
    local width=math.max(1,host:GetWidth()-8)
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
    local titleHeight=math.max(20,math.ceil(header.title:GetStringHeight()))
    header.subtitle:SetPoint("TOPLEFT",header,"TOPLEFT",59,-(14+titleHeight))
    header.subtitle:SetWidth(width-72)
    header.subtitle:SetText(tostring(model.itemType)..
        (model.itemID and ("  |  Item "..model.itemID) or "").."  |  "..tostring(model.profession))
    header.subtitle:Show()
    local headerHeight=math.max(70,26+titleHeight+math.ceil(header.subtitle:GetStringHeight()))
    header:SetHeight(headerHeight)
    y=y+headerHeight+10

    local metrics=model.metrics or {}
    local spacing=7
    local metricColors={"ddb27a","b7e4c4","ffc77b"}
    local inline=width>=330 and #metrics>1
    local tileW=inline and math.floor((width-spacing*(#metrics-1))/#metrics) or width
    local tileHeight=0
    local tiles={}
    for n,entry in ipairs(metrics) do
        local x=inline and 3+(n-1)*(tileW+spacing) or 3
        local box=card(tileW,56,x,y)
        box.bg:SetColorTexture(.08,.105,.105,.98)
        box.subtitle:ClearAllPoints()
        box.subtitle:SetPoint("TOPLEFT",box,"TOPLEFT",9,-8)
        box.subtitle:SetWidth(tileW-18)
        box.subtitle:SetText(entry[1])
        box.subtitle:Show()
        local labelHeight=math.ceil(box.subtitle:GetStringHeight())
        box.title:ClearAllPoints()
        box.title:SetPoint("TOPLEFT",box,"TOPLEFT",9,-(13+labelHeight))
        box.title:SetWidth(tileW-18)
        box.title:SetText("|cff"..metricColors[n]..tostring(entry[2]).."|r")
        box.title:Show()
        local height=math.max(54,23+labelHeight+math.ceil(box.title:GetStringHeight()))
        if inline then
            tileHeight=math.max(tileHeight,height)
            tiles[#tiles+1]=box
        else
            box:SetHeight(height)
            y=y+height+spacing
        end
    end
    if inline then
        for _,box in ipairs(tiles) do box:SetHeight(tileHeight) end
        y=y+tileHeight+spacing
    end

    local function section(title,lines)
        local box=card(width,50,3,y)
        box.bg:SetColorTexture(.065,.105,.095,.97)
        box.title:ClearAllPoints()
        box.title:SetPoint("TOPLEFT",box,"TOPLEFT",10,-8)
        box.title:SetWidth(width-20)
        box.title:SetText("|cffffcf75"..title.."|r")
        box.title:Show()
        box.body:ClearAllPoints()
        local bodyTop=21+math.ceil(box.title:GetStringHeight())
        box.body:SetPoint("TOPLEFT",box,"TOPLEFT",11,-bodyTop)
        box.body:SetWidth(width-22)
        box.body:SetText(table.concat(lines,"\n"))
        box.body:Show()
        local contentHeight=math.ceil(tonumber(box.body:GetStringHeight()) or 0)
        local height=math.max(56,contentHeight+bodyTop+13)
        box:SetHeight(height)
        y=y+height+8
    end

    if model.sources then
        local sources={}
        for _,src in ipairs(model.sources) do
            sources[#sources+1]="|cffffe4b5"..src.name.."|r  (Req: "..tostring(src.required)..
                ")\nMeets reference node skill: "..tostring(src.eligibility)
        end
        sources[#sources+1]="|cffffc77bWoW Forever material drops are not confirmed.|r"
        section(model.sourceHeading,sources)

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

        section("YOUR GATHERING HISTORY",model.history)
        -- Keep acquisition notes and provenance in expanded detail, rather
        -- than presenting redundant cards in the default material overview.
        if expanded then
            section("HOW IT IS OBTAINED",{model.explanation})
            section("REFERENCE STATUS",{model.verificationNote})
            if model.referenceSection then section(model.referenceSection.title,model.referenceSection.lines) end
        end
    else
        for _,entry in ipairs(model.sections or {}) do section(entry.title,entry.lines) end
    end
    host:SetHeight(math.max(345,y+9))
    self.detailText:Hide()
    self.gatherMaterialActive=true
    self.gatherMaterialRow=resource
    self.gatherMaterialCharacter=ch
    self.gatherMaterialExpanded=expanded
    return true
end
