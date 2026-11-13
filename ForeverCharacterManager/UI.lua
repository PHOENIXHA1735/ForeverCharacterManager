local _, FCM = ...
local UI = {}
FCM.UI = UI

local function text(parent, content, size, x, y, width, height)
    local label = parent:CreateFontString(nil, "OVERLAY", size or "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    if width then label:SetWidth(width) end
    if height then label:SetHeight(height) end
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetText(content or "")
    return label
end
local function button(parent, label, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, height or 26)
    b:SetText(label or "")
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end
local function background(parent, r, g, b, a)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(r or 0.06, g or 0.08, b or 0.11, a or 0.97)
    return bg
end
local function color(s, hex) return "|cff" .. (hex or "ffffff") .. tostring(s) .. "|r" end
local function short(s, limit)
    s = tostring(s or "")
    if #s > (limit or 100) then return s:sub(1, limit or 100) .. "..." end
    return s
end
local function sortByName(a,b) return (a.title or "") < (b.title or "") end
local function niceGold(copper)
    copper = math.max(0, tonumber(copper) or 0)
    return string.format("%dg %ds %dc", math.floor(copper/10000), math.floor(copper%10000/100), copper%100)
end
local standingNames = {"Hated","Hostile","Unfriendly","Neutral","Friendly","Honored","Revered","Exalted"}

-- The minimap icon is separate from the main window, so it appears at login.
-- Position is saved as x/y offsets from Minimap's center in account-wide settings.
function UI:PlaceMinimap(x, y)
    if not self.minimap or not Minimap then return end
    local width = Minimap:GetWidth() or 140
    local height = Minimap:GetHeight() or 140
    local radius = math.max(width, height) / 2 + 12
    local px = tonumber(x) or -58
    local py = tonumber(y) or 58
    local len = math.sqrt(px * px + py * py)
    if len > 0.01 then
        px, py = px * radius / len, py * radius / len
    else
        px, py = -radius * 0.7071, radius * 0.7071
    end
    self.minimap:ClearAllPoints()
    self.minimap:SetPoint("CENTER", Minimap, "CENTER", px, py)
    self.iconX, self.iconY = px, py
end

function UI:MoveMinimapFromCursor(save)
    if not self.minimap or not Minimap or not GetCursorPosition then return end
    local cursorX, cursorY = GetCursorPosition()
    local centerX, centerY = Minimap:GetCenter()
    if not cursorX or not cursorY or not centerX or not centerY then return end
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not scale or scale <= 0 then scale = 1 end
    self:PlaceMinimap(cursorX / scale - centerX, cursorY / scale - centerY)
    if save and FCM.db and FCM.db.settings then
        FCM.db.settings.minimap = {x = self.iconX, y = self.iconY}
    end
end

function UI:ResetMinimap()
    if FCM.db and FCM.db.settings then
        FCM.db.settings.minimap = {x = -58, y = 58}
    end
    self:PlaceMinimap(-58, 58)
end

function UI:CreateMinimap()
    if self.minimap or not Minimap then return end
    local minimap = CreateFrame("Button", "FCMMinimapButton", Minimap)
    minimap:SetSize(32, 32)
    minimap:SetFrameStrata("MEDIUM")
    -- Self-contained RGBA TGA with circular alpha and integrated gold ring.
    -- No portrait conversion, tracking border or mask textures: these clipped
    -- the icon on some Forever clients.
    local icon = minimap:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\ForeverCharacterManager\\Media\\FCM_Emblem")
    icon:SetAllPoints(minimap)
    icon:SetTexCoord(0, 1, 0, 1)
    minimap.bookIcon = icon
    minimap.border = nil
    -- A highlight with no extraneous square/atlas borders.
    local hover = minimap:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture("Interface\\AddOns\\ForeverCharacterManager\\Media\\FCM_Emblem")
    hover:SetAllPoints(minimap)
    hover:SetAlpha(0.22)
    hover:SetBlendMode("ADD")
    minimap:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimap:RegisterForDrag("LeftButton")
    minimap:SetScript("OnDragStart", function(btn)
        btn.dragging = true
    end)
    minimap:SetScript("OnUpdate", function(btn)
        if btn.dragging then UI:MoveMinimapFromCursor(false) end
    end)
    minimap:SetScript("OnDragStop", function(btn)
        if not btn.dragging then return end
        UI:MoveMinimapFromCursor(true)
        btn.dragging = false
        btn.dragStoppedAt = type(GetTime) == "function" and GetTime() or nil
    end)
    minimap:SetScript("OnClick", function(btn, mouseButton)
        -- Some clients also send a click after a completed drag.
        if btn.dragging then return end
        if btn.dragStoppedAt and type(GetTime) == "function" and GetTime() - btn.dragStoppedAt < 0.2 then return end
        if mouseButton == "RightButton" then
            UI:ResetMinimap()
            FCM:Say("Minimap icon reset to its default position.")
        else
            FCM:Toggle()
        end
    end)
    minimap:SetScript("OnEnter", function(btn)
        if GameTooltip then
            GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
            GameTooltip:AddLine("Forever Character Manager")
            local pending = FCM:CountAssignedRequests(FCM.currentKey)
            if pending > 0 then GameTooltip:AddLine("Pending crafts for you: "..pending, 0.55, 1, 0.65) end
            GameTooltip:AddLine("Left-click: open/close", 1, 1, 1)
            GameTooltip:AddLine("Left-drag: move around minimap", 1, 1, 1)
            GameTooltip:AddLine("Right-click: reset icon position", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    minimap:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.minimap = minimap
    local position = FCM.db and FCM.db.settings and FCM.db.settings.minimap or {}
    self:PlaceMinimap(position.x, position.y)
end

function UI:ConfirmDeleteSelected()
    if self.tab ~= "Characters" or not FCM.db then return end
    local ch = self.selectedRow and FCM.db.characters[self.selectedRow]
    if not ch then FCM:Say("Select a character in the Characters list first."); return end
    if ch.key == FCM.currentKey or ch.key == FCM:CharacterKey() then
        FCM:Say("You cannot remove your currently logged-in character. Switch to another character first.")
        return
    end
    if not StaticPopupDialogs or not StaticPopup_Show then
        FCM:Say("WoW's confirmation dialog is unavailable; no data was removed.")
        return
    end
    StaticPopupDialogs.FCM_CONFIRM_REMOVE_SAVED = StaticPopupDialogs.FCM_CONFIRM_REMOVE_SAVED or {
        text = "Remove ALL saved addon data for %s?\n\nAny queued crafts for this character will also be removed. This will NOT delete the WoW character.",
        button1 = YES or "Remove",
        button2 = CANCEL or "Cancel",
        OnAccept = function(_, data)
            if data and data.key then FCM:DeleteCharacter(data.key) end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("FCM_CONFIRM_REMOVE_SAVED", FCM:DisplayCharacter(ch), nil, {key=ch.key})
end

-- Dedicated Dungeon Explorer widgets: keep the list and item details separate.
-- These live inside the normal scrolling detail child, but are reusable so
-- changing a loot filter or selected item does not leak frames.
local qualityColors={
    [0]="9d9d9d",[1]="ffffff",[2]="1eff00",[3]="0070dd",[4]="a335ee",[5]="ff8000",[6]="e6cc80",
}
local itemSlotLabels={
    INVTYPE_HEAD="Head",INVTYPE_NECK="Neck",INVTYPE_SHOULDER="Shoulder",INVTYPE_CLOAK="Back",
    INVTYPE_CHEST="Chest",INVTYPE_ROBE="Chest",INVTYPE_WRIST="Wrist",INVTYPE_HAND="Hands",
    INVTYPE_WAIST="Waist",INVTYPE_LEGS="Legs",INVTYPE_FEET="Feet",INVTYPE_FINGER="Finger",
    INVTYPE_TRINKET="Trinket",INVTYPE_WEAPON="Weapon",INVTYPE_WEAPONMAINHAND="Main-hand",
    INVTYPE_WEAPONOFFHAND="Off-hand",INVTYPE_2HWEAPON="Two-hand",INVTYPE_RANGED="Ranged",
    INVTYPE_RANGEDRIGHT="Ranged",INVTYPE_SHIELD="Shield",INVTYPE_HOLDABLE="Off-hand",
    INVTYPE_RELIC="Relic",INVTYPE_BODY="Shirt",INVTYPE_TABARD="Tabard",
}
local statNames={
    ITEM_MOD_STRENGTH_SHORT="Strength",ITEM_MOD_AGILITY_SHORT="Agility",
    ITEM_MOD_STAMINA_SHORT="Stamina",ITEM_MOD_INTELLECT_SHORT="Intellect",
    ITEM_MOD_SPIRIT_SHORT="Spirit",ITEM_MOD_SPELL_POWER_SHORT="Spell power",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT="Spell damage",ITEM_MOD_ATTACK_POWER_SHORT="Attack power",
    ITEM_MOD_CRIT_RATING_SHORT="Crit rating",ITEM_MOD_HIT_RATING_SHORT="Hit rating",
    ITEM_MOD_HASTE_RATING_SHORT="Haste rating",ITEM_MOD_MANA_REGENERATION_SHORT="Mana regen",
    ITEM_MOD_ARMOR_SHORT="Armor",ITEM_MOD_DEFENSE_SKILL_RATING_SHORT="Defense rating",
}
local function itemMetadata(id,drop)
    local stored=FCM.externalData and FCM.externalData.items and FCM.externalData.items[id] or {}
    local game=FCM.Gear and FCM.Gear.Info and FCM.Gear:Info(id) or nil
    local itemName=(drop and drop.name) or stored.name or (game and game.name) or ("Item #"..tostring(id))
    if itemName=="" then itemName=stored.name or (game and game.name) or ("Item #"..tostring(id)) end
    local equip=(game and game.equip) or stored.equipLoc or stored.inventoryType
    local quality=tonumber((game and game.quality) or stored.quality)
    if not quality and stored.quality then
        local name=string.lower(tostring(stored.quality))
        local byName={poor=0,common=1,uncommon=2,rare=3,epic=4,legendary=5,artifact=6}
        quality=byName[name]
    end
    local icon=(game and game.icon) or stored.icon or stored.iconID or nil
    if not icon and C_Item and type(C_Item.GetItemIconByID)=="function" then
        icon=FCM:Try(C_Item.GetItemIconByID,id)
    end
    if not icon and type(GetItemIcon)=="function" then icon=FCM:Try(GetItemIcon,id) end
    return {id=id,name=itemName,store=stored,game=game,icon=icon,
        slot=itemSlotLabels[equip] or equip,
        typeName=(game and game.subType) or stored.subclass or stored.category,quality=quality,
        color=qualityColors[quality] or "f0d27b"}
end
-- Prefer cached client stats over imported reference text.  Global GetItemStats
-- exists on some Forever/Classic clients even when C_Item.GetItemStats does not.
local function itemStats(id,stored,game)
    local lines={}
    local stats
    local lookup=(game and game.link) or ("item:"..tostring(id))
    if C_Item and type(C_Item.GetItemStats)=="function" then
        stats=FCM:Try(C_Item.GetItemStats,lookup)
        if type(stats)~="table" then stats=FCM:Try(C_Item.GetItemStats,id) end
    end
    if type(stats)~="table" and type(GetItemStats)=="function" then
        stats=FCM:Try(GetItemStats,lookup)
    end
    -- Present the same de-duplicated client stats that Gear Advisor scores.
    -- Previously this preview used raw aliases while the comparison summed
    -- them, making displayed Spell Damage and calculated Spell Power disagree.
    if FCM.Gear and FCM.Gear.StatValues then
        local normalized=FCM.Gear:StatValues(lookup)
        if normalized then
            local keys={}
            for key,value in pairs(normalized) do
                if type(value)=="number" and value~=0 then keys[#keys+1]=key end
            end
            table.sort(keys,function(a,b)return (FCM.Gear.statLabels[a] or a)<(FCM.Gear.statLabels[b] or b) end)
            for _,key in ipairs(keys) do
                local value=normalized[key]
                lines[#lines+1]=((value>0) and "+" or "")..tostring(value).." "..(FCM.Gear.statLabels[key] or key)
            end
            return lines
        end
    end
    if type(stats)=="table" then
        local keys={}
        for key,value in pairs(stats) do
            if type(value)=="number" and value~=0 then keys[#keys+1]=key end
        end
        table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
        for _,key in ipairs(keys) do
            local label=statNames[key] or tostring(key):gsub("ITEM_MOD_",""):gsub("_SHORT",""):gsub("_"," ")
            local n=stats[key]
            lines[#lines+1]=((n>0) and "+" or "")..tostring(n).." "..label
            if #lines>=8 then break end
        end
    end
    if #lines==0 and stored then
        if type(stored.stats)=="string" and stored.stats~="" then
            lines[#lines+1]="Reference stats: "..stored.stats
        elseif type(stored.stats)=="table" then
            local keys={}
            for key,value in pairs(stored.stats) do
                if type(value)=="number" and value~=0 then keys[#keys+1]=key end
            end
            table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
            for _,key in ipairs(keys) do
                local label=statNames[key] or tostring(key):gsub("ITEM_MOD_",""):gsub("_SHORT",""):gsub("_"," ")
                local n=stored.stats[key]
                lines[#lines+1]=((n>0) and "+" or "")..tostring(n).." "..label
                if #lines>=8 then break end
            end
        end
    end
    if #lines==0 then lines[1]="Stats unavailable in current records" end
    return lines
end
function UI:DungeonTooltip(anchor,id)
    if not GameTooltip or not id or id<=0 then return end
    GameTooltip:SetOwner(anchor,"ANCHOR_RIGHT")
    local ok=false
    if GameTooltip.SetItemByID then ok=pcall(GameTooltip.SetItemByID,GameTooltip,id) end
    if not ok and GameTooltip.SetHyperlink then ok=pcall(GameTooltip.SetHyperlink,GameTooltip,"item:"..tostring(id)) end
    if not ok then
        local item=itemMetadata(id)
        GameTooltip:AddLine(item.name,1,0.84,0.4)
        GameTooltip:AddLine("Game item tooltip not cached yet.",0.8,0.8,0.8)
    end
    GameTooltip:Show()
end
-- Reusable item preview for EVERY item-backed details panel, not only Dungeons.
-- Non-item rows (characters, talent plans, faction standings, settings, etc.)
-- intentionally retain the normal text-only presentation.
local function previewItemID(row)
    if not row then return nil end
    local explicit=tonumber(row.itemID)
    if explicit and explicit>0 then return explicit end
    local rowID=tostring(row.id or "")
    local numeric=rowID:match("^searchitem:(%d+)$") or
        rowID:match("^item:(%d+)$") or
        rowID:match("^overview%-item:(%d+)$") or
        rowID:match("^auction:(%d+)$") or
        rowID:match("^shop:(%d+)$") or
        rowID:match("^dungeon%-upgrade:(%d+)$")
    if numeric then return tonumber(numeric) end
    local recipe=row.recipe
    if not recipe then
        local recipeID=rowID:match("^recipe:(%d+)$") or
            rowID:match("^myrecipe:(%d+)$") or
            rowID:match("^searchrecipe:(%d+)$") or
            rowID:match("^enchant:(%d+)$") or
            rowID:match("^train:(%d+)$")
        if recipeID and FCM.RecipeByID then recipe=FCM:RecipeByID(tonumber(recipeID)) end
        if recipeID and not recipe and FCM.externalData and FCM.externalData.recipes then
            recipe=FCM.externalData.recipes[tonumber(recipeID)]
        end
    end
    local itemID=recipe and tonumber(recipe.outputID or recipe.resultID or recipe.outputItemID)
    if itemID and itemID>0 then return itemID end
    return nil
end
function UI:ResetItemPreview()
    if self.itemPreview then self.itemPreview:Hide();self.itemPreview.itemID=nil end
    if self.detailText then
        self.detailText:ClearAllPoints()
        self.detailText:SetPoint("TOPLEFT",self.detailChild,"TOPLEFT",3,-3)
    end
end
function UI:RenderItemPreview(row)
    local id=previewItemID(row)
    if not id or not self.itemPreview then self:ResetItemPreview(); return 0 end
    local meta=itemMetadata(id,{name=row.title})
    local preview=self.itemPreview
    preview.itemID=id
    preview.icon:SetTexture(meta.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    preview.title:SetText(color(short(meta.name,54),meta.color))
    local store=meta.store or {}
    local qualityNames={[0]="Poor",[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",[5]="Legendary",[6]="Artifact"}
    local descriptors={}
    if meta.slot then descriptors[#descriptors+1]=tostring(meta.slot)
    elseif meta.typeName then descriptors[#descriptors+1]=tostring(meta.typeName) end
    if meta.quality then descriptors[#descriptors+1]=qualityNames[meta.quality] or "Item" end
    local ilvl=tonumber((meta.game and meta.game.ilvl) or store.itemLevel or store.ilvl)
    if ilvl and ilvl>0 then descriptors[#descriptors+1]="iLvl "..ilvl end
    preview.kind:SetText(short(table.concat(descriptors,"  |  "),43))
    local stats=itemStats(id,store,meta.game)
    if #stats>0 and stats[1]~="Stats unavailable in current records" then
        local subtitle=stats[1]
        if #stats>1 and #subtitle+#stats[2]<51 then subtitle=subtitle.."  |  "..stats[2] end
        preview.stats:SetText(short(subtitle,58))
    else
        preview.stats:SetText("Stats unavailable: see details")
    end
    preview:Show()
    self.detailText:ClearAllPoints()
    self.detailText:SetPoint("TOPLEFT",self.detailChild,"TOPLEFT",3,-112)
    return 112
end
function UI:ResetDungeonWidgets()
    self.dungeonWidgetCounts={label=0,row=0,texture=0}
    for _,pool in pairs(self.dungeonWidgetPool or {}) do
        for _,widget in ipairs(pool) do widget:Hide() end
    end
end
function UI:AcquireDungeonWidget(kind)
    self.dungeonWidgetPool=self.dungeonWidgetPool or {label={},row={},texture={}}
    self.dungeonWidgetCounts=self.dungeonWidgetCounts or {label=0,row=0,texture=0}
    local index=self.dungeonWidgetCounts[kind]+1
    self.dungeonWidgetCounts[kind]=index
    local pool=self.dungeonWidgetPool[kind]
    if pool[index] then return pool[index] end
    local widget
    if kind=="label" then
        widget=self.detailChild:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        widget:SetJustifyH("LEFT")
        widget:SetJustifyV("TOP")
        widget:SetWordWrap(true)
    elseif kind=="texture" then
        widget=self.detailChild:CreateTexture(nil,"ARTWORK")
    else
        widget=CreateFrame("Button",nil,self.detailChild)
        widget.bg=background(widget,0.10,0.15,0.20,0.92)
        widget.icon=widget:CreateTexture(nil,"ARTWORK")
        widget.icon:SetSize(32,32)
        widget.icon:SetPoint("LEFT",widget,"LEFT",7,0)
        widget.name=widget:CreateFontString(nil,"OVERLAY","GameFontNormal")
        widget.name:SetPoint("TOPLEFT",widget,"TOPLEFT",46,-6)
        widget.name:SetJustifyH("LEFT")
        widget.sub=widget:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        widget.sub:SetPoint("TOPLEFT",widget,"TOPLEFT",46,-26)
        widget.sub:SetJustifyH("LEFT")
        widget:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    end
    pool[index]=widget
    return widget
end
function UI:RenderDungeonDetail(r,ch)
    if not r then return end
    self.detailText:Hide()
    self:ResetDungeonWidgets()
    local width=math.max(245,self.detailChild:GetWidth()-12)
    local y=5
    local function line(content,height,hex,indent)
        local label=self:AcquireDungeonWidget("label")
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT",self.detailChild,"TOPLEFT",indent or 6,-y)
        label:SetWidth(width-(indent or 6)-6)
        label:SetHeight(height or 19)
        label:SetText(hex and color(content,hex) or content)
        label:Show()
        y=y+(height or 19)
    end
    local function gap(n)y=y+(n or 7) end
    local kind=(r.kind=="raid" and "Raid" or (r.kind=="unclassified" and "Unclassified instance" or "Dungeon"))
    line(r.name,24,"ffd76d")
    line(kind.."  |  Guide levels "..tostring(r.levels or "unknown"),20,"c2cad7")
    if r.newToForever then line("New to WoW Forever",17,"93ddb9") end
    gap(9)
    local scope=FCM.db.settings.dungeonLootScope or "class"
    if scope=="spec" then
        line("Spec-fit uses stat patterns, not BIS or proven specialization value.",39,"aeb9ca")
    elseif scope=="upgrades" then
        line("Upgrades are weighted estimates from cached client item stats.",39,"aeb9ca")
    end
    local filtered=0
    local seen={}
    local shown=0
    local eligibilityCache={}
    local focus=self.dungeonBossFocus
    local focusedIndex=(focus and focus.dungeon==tostring(r.id)) and focus.index or nil
    local function allowed(itemID)
        local cache=eligibilityCache[itemID]
        if not cache then
            local eligibility,reason=FCM:DungeonItemEligibility(itemID,ch)
            local upgrade=ch and FCM.Gear and FCM.Gear:DungeonUpgradeAssessment(itemID,ch) or nil
            local fit,fitReason=FCM:DungeonSpecFit(itemID,ch)
            cache={eligibility=eligibility,reason=reason,upgrade=upgrade,fit=fit,fitReason=fitReason}
            eligibilityCache[itemID]=cache
        end
        local eligible=cache.eligibility~="other" and cache.eligibility~="future"
        local ok=scope=="all" or (scope=="class" and cache.eligibility~="other") or
            (scope=="spec" and eligible and cache.fit=="match") or
            (scope=="upgrades" and eligible and cache.upgrade and cache.upgrade.state=="upgrade")
        return ok,cache.eligibility,cache.reason,cache.upgrade,cache.fit,cache.fitReason
    end
    local function lootKey(bossIndex,itemID)
        return tostring(r.id)..":"..(bossIndex and ("boss:"..bossIndex) or "associated")..":"..tostring(itemID)
    end
    local function unassignedDrops()
        return FCM:DungeonAssociatedDrops(r)
    end
    -- Sort a copy, never the saved/imported data. Confirmed positive weighted
    -- comparisons appear before unknowns; deterministic name ordering follows.
    local function orderedDrops(drops)
        local sorted={}
        for _,drop in ipairs(drops or {}) do sorted[#sorted+1]=drop end
        table.sort(sorted,function(a,b)
            local aid,bid=tonumber(a.id),tonumber(b.id)
            local _,_,_,aa=allowed(aid)
            local _,_,_,bb=allowed(bid)
            local av=(aa and aa.state=="upgrade") and aa.delta or nil
            local bv=(bb and bb.state=="upgrade") and bb.delta or nil
            if av and bv and av~=bv then return av>bv end
            if (av~=nil)~=(bv~=nil) then return av~=nil end
            local an,bn=tostring(a.name or ""),tostring(b.name or "")
            if an~=bn then return an<bn end
            return (aid or 0)<(bid or 0)
        end)
        return sorted
    end
    -- Selected loot details stay near the top, rather than expanding at the
    -- bottom of a long, scrolling boss/loot list.
    local selectedDrop,selectedBoss,selectedBossLinked
    local function checkSelected(drop,bossName,bossIndex)
        local id=tonumber(drop and drop.id)
        if id and self.dungeonItemSelection==lootKey(bossIndex,id) then
            local visible=allowed(id)
            if visible then
                selectedDrop,selectedBoss,selectedBossLinked=drop,bossName,bossIndex~=nil
            end
        end
    end
    for index,boss in ipairs(r.bosses or {}) do
        if not focusedIndex or focusedIndex==index then
            for _,drop in ipairs(boss.loot or {}) do
                checkSelected(drop,tostring(boss.name or "Boss name unavailable"),index)
            end
        end
    end
    if not focusedIndex then
        for _,drop in ipairs(unassignedDrops()) do
            if not selectedDrop then checkSelected(drop,nil,nil) end
        end
    end
    if selectedDrop then
        local id=tonumber(selectedDrop.id)
        local meta=itemMetadata(id,selectedDrop)
        local _,eligibility,why,upgrade=allowed(id)
        local store=meta.store or {}
        line("SELECTED ITEM",20,"ffd76d")
        local icon=self:AcquireDungeonWidget("texture")
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT",self.detailChild,"TOPLEFT",9,-y)
        icon:SetSize(28,28)
        icon:SetTexture(meta.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:Show()
        line(short(meta.name,42),32,meta.color,45)
        local location=meta.slot or meta.typeName or "Equipment type not available"
        line(short(location,36).."  |  Item #"..id,20,"d6e3ef",8)
        local required=tonumber((meta.game and meta.game.level) or store.requiredLevel or store.minLevel)
        local level=tonumber((meta.game and meta.game.ilvl) or store.itemLevel or store.ilvl)
        if required and required>0 then line("Required level: "..required,19,"d1dde9",8) end
        if level and level>0 then line("Item level: "..level,19,"d1dde9",8) end
        local binding=store.binding or (meta.game and meta.game.bindType)
        local bindNames={[1]="Binds when picked up",[2]="Binds when equipped",[3]="Binds when used"}
        if binding then
            line("Binding: "..(bindNames[tonumber(binding)] or tostring(binding)),19,"d1dde9",8)
        end
        for _,stat in ipairs(itemStats(id,store,meta.game)) do
            line(short(stat,75),stat:len()>44 and 34 or 19,"a8edbd",8)
        end
        if store.effects and tostring(store.effects)~="" then
            line("Effect: "..short(store.effects,100),36,"d1dde9",8)
        end
        -- Show the saved equipped comparison target when available. A recorded
        -- slot is a reference, not proof an upgrade score is accurate.
        local compareSlot=upgrade and upgrade.slot
        if not compareSlot and FCM.Gear and FCM.Gear.slots and meta.game then
            local slots=FCM.Gear.slots[meta.game.equip]
            compareSlot=slots and slots[1]
        end
        local worn=ch and ch.gear and compareSlot and ch.gear[compareSlot]
        if worn and (worn.itemID or worn.link) then
            local oldInfo=FCM.Gear and FCM.Gear:Info(worn.link or worn.itemID)
            local oldStored=FCM.externalData and FCM.externalData.items and worn.itemID and FCM.externalData.items[worn.itemID]
            local oldName=(oldInfo and oldInfo.name) or (oldStored and oldStored.name) or "item information unavailable"
            line("Compared with equipped: "..short(oldName,47),34,"c7d6e9",8)
        end
        if eligibility=="other" then
            line("Cannot use: "..short(why or "incompatible item",58),35,"ffaaaa",8)
        elseif upgrade and upgrade.state=="upgrade" then
            line(string.format("Estimated upgrade: +%.1f weighted points",upgrade.delta or 0),23,"a8efb5",8)
        elseif upgrade and upgrade.state=="not-upgrade" then
            line("No estimated gain over recorded equipment",24,"f0d27b",8)
        else
            line("Upgrade not confirmed: "..short((upgrade and upgrade.reason) or why or "missing data",58),38,"f0d27b",8)
        end
        -- Per-stat change indicators use ACTUAL client stats and the
        -- selected replacement slot. Missing stats never imply zero.
        if ch and FCM.Gear and FCM.Gear.CompareItem then
            local comparison=FCM.Gear:CompareItem(id,ch,compareSlot)
            local comparisonLines=FCM.Gear:ComparisonLines(comparison)
            if #comparisonLines>0 then
                gap(6)
                for index,entry in ipairs(comparisonLines) do
                    local h=entry:find("Why:",1,true) and 74 or
                        (entry:find("Equipped:",1,true) and 38 or
                        (entry:find("Not modeled:",1,true) and 54 or
                        (entry:find("KNOWN STATS",1,true) and 28 or 44)))
                    line(entry,h,nil,8)
                end
                gap(5)
            end
        end
        -- Show all activity scores for the SELECTED character, without
        -- presenting a weighted estimate as a real DPS/arena prediction.
        if eligibility~="other" and compareSlot and ch and FCM.Gear and FCM.Gear.CompareActivities then
            line("ACTIVITY SCORE COMPARISON (not DPS)",23,"ffd76d",8)
            local comparisons=FCM.Gear:CompareActivities(id,ch,
                worn and (worn.link or worn.itemID),compareSlot,meta.game and meta.game.equip)
            for _,comparison in ipairs(comparisons) do
                local label=comparison.label.." ["..(FCM.modeLabels[comparison.style] or "DPS").."]"
                if comparison.delta then
                    line(label..": "..string.format("%+.1f points",comparison.delta),22,"c7d6e9",8)
                else
                    line(label..": data unavailable",23,"aeb9ca",8)
                end
            end
            line("Unmodeled: procs, caps, set bonuses, PvP effects.",33,"99aaba",8)
        end
        if selectedBossLinked then
            local provenance=tostring(selectedDrop.sourceType or "legacy")
            line("Reference-linked boss: "..short(selectedBoss or "Unknown",39),22,"c7d6e9",8)
            line(provenance=="boss-direct" and "Link: boss loot payload (ForeverDB)" or
                (provenance=="boss-explicit" and "Link: explicit boss field (ForeverDB)" or
                "Link: legacy import; provenance not recorded"),32,"aeb9ca",8)
            line("Boss/drop not confirmed by live game observation.",32,"e4b27e",8)
        else
            line("Dungeon-associated; boss not verified.",32,"e4b27e",8)
        end
        line("Right-click an item row for the full game tooltip.",31,"99aaba",8)
        gap(7)
    else
        line("ITEM DETAILS — select an item below",23,"ffd76d")
        line("Left-click for stats and comparison; right-click for tooltip.",34,"aab8c9",8)
        gap(7)
    end
    local bossNames={}
    local bossRows={}
    for _,boss in ipairs(r.bosses or {}) do
        local name=tostring(boss.name or "")
        if name~="" and not name:find("name not supplied",1,true) and
            not name:find("name unavailable",1,true) then bossNames[#bossNames+1]=name end
        bossRows[#bossRows+1]=boss
    end
    line("BOSSES  ("..#bossNames.." named in reference)",26,"ffd76d")
    if #bossNames==0 then
        line("Boss names not available in imported data.",35,"aeb9ca")
    else
        for i=1,#bossNames,2 do
            local a=short(bossNames[i],21)
            local b=bossNames[i+1] and short(bossNames[i+1],19) or ""
            line("  "..a..(b~="" and "     |     "..b or ""),19,"d8e4f1")
        end
    end
    gap(11)
    local function itemRow(drop, bossName, bossIndex)
        local id=tonumber(drop.id)
        if not id or id<=0 then return end
        local show,eligibility,why,upgrade,fit,fitReason=allowed(id)
        if not show then filtered=filtered+1;return end
        local key=lootKey(bossIndex,id)
        if seen[key] then return end
        seen[key]=true
        shown=shown+1
        local meta=itemMetadata(id,drop)
        local selected=self.dungeonItemSelection==key
        local row=self:AcquireDungeonWidget("row")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",self.detailChild,"TOPLEFT",8,-y)
        row:SetSize(width-15,49)
        row.bg:SetColorTexture(selected and 0.15 or 0.09,selected and 0.28 or 0.16,selected and 0.38 or 0.23,0.94)
        row.icon:SetTexture(meta.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.name:SetText(color(short(meta.name,40),meta.color))
        row.name:SetWidth(width-70)
        local label=meta.slot or meta.typeName or "Item type unknown"
        local verdict="Stats unknown"
        if eligibility=="other" then verdict="Not for this class"
        elseif upgrade and upgrade.state=="upgrade" then verdict="Potential upgrade"
        elseif upgrade and upgrade.state=="not-upgrade" then verdict="Not an upgrade"
        elseif eligibility=="future" then verdict="Requires a higher level"
        elseif eligibility=="candidate" then verdict="Potential class item" end
        local fitLabel=fit=="match" and "spec fit?" or (fit=="offspec" and "off-spec?" or "")
        row.sub:SetText(short(label.."  |  "..verdict..(fitLabel~="" and (" | "..fitLabel) or ""),51))
        row.sub:SetWidth(width-70)
        -- Left click opens a readable in-panel detail area at the top.
        -- Only right click opens the game's large (and addon-extended) tooltip.
        -- No automatic hover tooltip: that previously obscured the FCM window.
        row:RegisterForClicks("LeftButtonUp","RightButtonUp")
        row:SetScript("OnClick",function(btn,mouseButton)
            if mouseButton=="RightButton" then
                self:DungeonTooltip(btn,id)
                return
            end
            if GameTooltip then GameTooltip:Hide() end
            self.dungeonItemSelection=key
            if self.detailScroll and self.detailScroll.SetVerticalScroll then
                self.detailScroll:SetVerticalScroll(0)
            end
            self:RenderDungeonDetail(r,ch)
        end)
        row:SetScript("OnEnter",nil)
        row:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        row:Show()
        y=y+54
    end
    line("FOREVERDB BOSS-LINKED LOOT (reference, not confirmed)",38,"ffd76d")
    local bossDropCount=0
    for index,boss in ipairs(bossRows) do
        if not focusedIndex or focusedIndex==index then
            local drops=boss.loot or {}
            if #drops>0 then
                bossDropCount=bossDropCount+#drops
                local bossName=tostring(boss.name or "Boss name unavailable")
                line(short(bossName,38),20,"c7d6e9")
                for _,drop in ipairs(orderedDrops(drops)) do itemRow(drop,bossName,index) end
            end
        end
    end
    if bossDropCount==0 then
        line("No boss-linked loot records for this selection.",35,"aeb9ca")
    else
        line("Source-linked, not confirmed in the live game.",31,"aeb9ca")
    end
    gap(9)
    if not focusedIndex then
        line("DUNGEON-ASSOCIATED (BOSS UNKNOWN)",23,"ffd76d")
        line("No boss inferred; these are not confirmed drops.",33,"aeb9ca")
        local unassigned=unassignedDrops()
        local before=shown
        for _,drop in ipairs(orderedDrops(unassigned)) do itemRow(drop,nil,nil) end
        if #unassigned==0 then
            line("No dungeon-only item associations imported.",29,"aeb9ca")
        elseif shown==before then
            line("No associated items match the filter.",29,"aeb9ca")
        end
    else
        line("Boss filter active; dungeon-only associations hidden.",34,"aeb9ca")
    end
    if filtered>0 then
        gap(6)
        line(tostring(filtered).." items hidden by current loot filter.",19,"abb9c9")
    end
    gap(11)
    line("Reference: "..tostring(r.sourceProvider or "ForeverDB").."  |  Imported "..tostring(r.referenceCheckedAt or "date unknown"),34,"96a3b3")
    line("Reported sources are not confirmed live drops.",25,"96a3b3")
    self.detailChild:SetHeight(math.max(340,y+12))
end

-- Each selected character gets contextual recipe tabs for primary crafting
-- professions. Gathering and the three secondary skills live elsewhere.
local nonRecipeTabs={
    ["herbalism"]=true,["mining"]=true,["skinning"]=true,
    ["fishing"]=true,["cooking"]=true,["first aid"]=true,
    ["firstaid"]=true,["archaeology"]=true,
}
function UI:CharacterRecipeProfessions(ch)
    local names={}
    if not ch then return names end
    local seen={}
    local function include(name)
        name=tostring(name or "")
        local key=string.lower(name)
        if name~="" and key~="unknown profession" and not nonRecipeTabs[key] and not seen[key] then
            seen[key]=true; names[#names+1]=name
        end
    end
    for key,profession in pairs(ch.professions or {}) do
        include((type(profession)=="table" and profession.name) or key)
    end
    for _,recipe in pairs(ch.recipes or {}) do
        if recipe.learned then include(recipe.profession) end
    end
    table.sort(names)
    return names
end
function UI:Navigate(tab)
    self.tab=tab
    self.selectedRow=nil
    self.dungeonItemSelection=nil
    self.appliedSearch=""
    self.searchReturnTab=nil
    self.searchSelectedItem=false
    self.suppressSearch=true
    if self.search then self.search:SetText("") end
    self.suppressSearch=false
    if self.scroll and self.scroll.SetVerticalScroll then self.scroll:SetVerticalScroll(0) end
    if self.detailScroll and self.detailScroll.SetVerticalScroll then self.detailScroll:SetVerticalScroll(0) end
    self:Refresh()
end
function UI:RefreshProfessionTabs(ch)
    if not self.sidebar or not self.sidebarTabs then return end
    local names=self:CharacterRecipeProfessions(ch)
    local supported={}
    for _,name in ipairs(names) do supported["Profession:"..string.lower(name)]=true end
    if self.tab and self.tab:sub(1,11)=="Profession:" and not supported[self.tab] then
        self.tab="Professions"; self.selectedRow=nil
    end
    for _,b in ipairs(self.professionButtons or {}) do b:Hide() end
    local position=0
    local inserted=false
    for _,tab in ipairs(self.sidebarTabs) do
        position=position+1
        local widget=self.tabButtons[tab]
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT",self.sidebarContent,"TOPLEFT",7,-7-(position-1)*24)
        if tab=="Professions" and not inserted then
            inserted=true
            for i,name in ipairs(names) do
                local b=self.professionButtons[i]
                local destination="Profession:"..string.lower(name)
                if not b then
                    b=button(self.sidebarContent,name,131,23,function() self:Navigate(b.destination) end)
                    self.professionButtons[i]=b
                end
                b.destination=destination
                b:SetText(name)
                b:SetEnabled(self.tab~=destination)
                b:ClearAllPoints()
                position=position+1
                b:SetPoint("TOPLEFT",self.sidebarContent,"TOPLEFT",7,-7-(position-1)*24)
                b:Show()
            end
        end
    end
    if self.sidebarContent then self.sidebarContent:SetHeight(math.max(400,position*24+14)) end
    if self.sidebarScroll then
        local maxScroll=math.max(0,(self.sidebarContent:GetHeight() or 0)-(self.sidebarScroll:GetHeight() or 1))
        if (self.sidebarScroll:GetVerticalScroll() or 0)>maxScroll then
            self.sidebarScroll:SetVerticalScroll(maxScroll)
        end
    end
end
-- Global search opens regardless of the current tab. A search result can be
-- inspected in the detail pane; Back restores the results, then the old tab.
function UI:BackFromSearch()
    if self.tab~="Global Search" then return end
    if self.searchSelectedItem then
        self.searchSelectedItem=false
        self.selectedRow="search-summary"
    else
        local returnTab=self.searchReturnTab or "Overview"
        self.searchReturnTab=nil
        self.tab=returnTab
        self.selectedRow=nil
        self.appliedSearch=""
        self.suppressSearch=true
        if self.search then self.search:SetText("") end
        self.suppressSearch=false
    end
    self:Refresh()
end
function UI:ExecuteSearch()
    local q=self.search and self.search:GetText() or ""
    q=tostring(q):gsub("^%s+",""):gsub("%s+$","")
    if q=="" and self.tab~="Global Search" then return end
    if self.tab~="Global Search" then
        self.searchReturnTab=self.tab or "Overview"
        self.tab="Global Search"
    end
    self.appliedSearch=q
    self.selectedRow="search-summary"
    self.searchSelectedItem=false
    if self.scroll and self.scroll.SetVerticalScroll then self.scroll:SetVerticalScroll(0) end
    if self.detailScroll and self.detailScroll.SetVerticalScroll then self.detailScroll:SetVerticalScroll(0) end
    self:Refresh()
end
function UI:QueueLiveSearch()
    if self.suppressSearch then return end
    self.searchRevision=(self.searchRevision or 0)+1
    local revision=self.searchRevision
    if C_Timer and type(C_Timer.After)=="function" then
        C_Timer.After(0.25,function()
            if revision==self.searchRevision and self.frame and self.frame:IsShown() then
                self:ExecuteSearch()
            end
        end)
    else
        -- Some Forever client builds do not expose C_Timer.After.
        self:ExecuteSearch()
    end
end

function UI:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "ForeverCharacterManagerWindow", UIParent, "BackdropTemplate")
    local prefs=(FCM.db and FCM.db.settings and FCM.db.settings.window) or {}
    f:SetSize(math.max(1000,tonumber(prefs.width) or 1010),math.max(635,tonumber(prefs.height) or 650))
    f:SetPoint("CENTER",UIParent,"CENTER",tonumber(prefs.x) or 0,tonumber(prefs.y) or 0)
    if f.SetResizable then f:SetResizable(true) end
    if f.SetResizeBounds then f:SetResizeBounds(1000,635,1500,1000)
    elseif f.SetMinResize then f:SetMinResize(1000,635) end
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        UI:SaveWindow()
    end)
    f:SetScript("OnSizeChanged",function() if UI.panel then UI:Reflow() end end)
    background(f)
    if f.SetBackdrop then f:SetBackdrop({edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize=24, insets={left=5,right=5,top=5,bottom=5}}) end
    text(f,"Forever Character Manager", "GameFontNormalLarge", 20, -16, 700)
    text(f,"WoW Forever  |  v"..FCM.version.."  |  Character data is recorded when each toon logs in", "GameFontHighlightSmall", 22, -42, 920)
    local sources=f:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
    sources:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",22,8)
    sources:SetText("Data from ForeverDB.net (https://foreverdb.net)  |  Prices from AHledger (https://ahledger.com)")
    -- ESC is handled by the Blizzard UI panel close stack, not by an OnKeyDown
    -- handler that could swallow normal gameplay input.
    if type(UISpecialFrames)=="table" then
        local found=false
        for _,name in ipairs(UISpecialFrames) do
            if name=="ForeverCharacterManagerWindow" then found=true;break end
        end
        if not found then table.insert(UISpecialFrames,"ForeverCharacterManagerWindow") end
    end
    local close = button(f, "X", 30, 25, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -13)

    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT",f,"TOPLEFT",16,-70)
    sidebar:SetWidth(145)
    sidebar:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",16,24)
    background(sidebar, 0.085, 0.11, 0.14, 0.8)
    local tabs = {"Overview", "Upgrade Plan", "Upgrades", "Characters", "Gear", "Crafting", "Planner", "Requests", "Shopping", "Professions", "Catalog", "Item Explorer", "Dungeons", "Auction", "Reputation", "Talents", "Leveling", "Inventory", "Legacy", "Settings", "Diagnostics", "Help"}
    -- Sidebar can exceed the window height when a character has multiple
    -- profession tabs. Keep every destination reachable with wheel or arrows.
    local sidebarScroll=CreateFrame("ScrollFrame",nil,sidebar)
    sidebarScroll:SetPoint("TOPLEFT",sidebar,"TOPLEFT",0,-4)
    sidebarScroll:SetPoint("BOTTOMRIGHT",sidebar,"BOTTOMRIGHT",0,30)
    local sidebarContent=CreateFrame("Frame",nil,sidebarScroll)
    sidebarContent:SetSize(145,540)
    sidebarScroll:SetScrollChild(sidebarContent)
    local function sidebarStep(delta)
        local maxScroll=math.max(0,(sidebarContent:GetHeight() or 0)-(sidebarScroll:GetHeight() or 1))
        sidebarScroll:SetVerticalScroll(math.max(0,math.min(maxScroll,(sidebarScroll:GetVerticalScroll() or 0)+delta)))
    end
    sidebarScroll:EnableMouseWheel(true)
    sidebarScroll:SetScript("OnMouseWheel",function(_,delta) sidebarStep(-delta*72) end)
    local up=button(sidebar,"Up",61,22,function() sidebarStep(-72) end)
    up:SetPoint("BOTTOMLEFT",sidebar,"BOTTOMLEFT",7,5)
    local down=button(sidebar,"Down",61,22,function() sidebarStep(72) end)
    down:SetPoint("LEFT",up,"RIGHT",7,0)
    self.sidebar=sidebar
    self.sidebarScroll=sidebarScroll
    self.sidebarContent=sidebarContent
    self.sidebarTabs=tabs
    self.tabButtons={}
    self.professionButtons={}
    for _,tab in ipairs(tabs) do
        local selectedTab=tab
        self.tabButtons[tab]=button(sidebarContent,tab,131,23,function() self:Navigate(selectedTab) end)
    end

    local panel = CreateFrame("Frame",nil,f)
    panel:SetPoint("TOPLEFT", f,"TOPLEFT",171,-70)
    panel:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-22,24)
    background(panel,0.025,0.045,0.065,0.68)
    self.panel = panel
    self.heading = text(panel,"Overview","GameFontNormalLarge",14,-12,500)
    self.subtitle = text(panel,"Select a character and module", "GameFontHighlightSmall",14,-39,640)

    self.charButton = button(panel,"Character",125,27, function() self:ShowCharactersMenu() end)
    self.charButton:SetPoint("TOPLEFT",panel,"TOPLEFT",15,-64)
    self.activityButton = button(panel,"Leveling",125,27,function() self:ShowGearActivityMenu() end)
    self.activityButton:SetPoint("LEFT",self.charButton,"RIGHT",8,0)
    self.modeButton = button(panel,"Style: DPS",92,27, function() self:ShowModesMenu() end)
    self.modeButton:SetPoint("LEFT",self.activityButton,"RIGHT",8,0)
    self.scanButton = button(panel,"Scan",65,27,function()
        FCM:ScanBasic(); FCM:ScanBags(); FCM:ScanGear(); FCM:ScanProfessions();
        FCM:ScanTalents(); FCM:ScanReputations(); FCM:ScanRecipes()
        if FCM.bankOpen then FCM:ScanBank() end
        self:Refresh()
        FCM:Say("Scan complete. Open the profession and bank windows for their data.")
    end)
    self.scanButton:SetPoint("LEFT",self.modeButton,"RIGHT",8,0)
    self.factionButton = button(panel,"Faction: All",95,27,function() self:ShowFactionMenu() end)
    self.factionButton:SetPoint("LEFT",self.scanButton,"RIGHT",8,0)

    self.search=CreateFrame("EditBox",nil,panel,"InputBoxTemplate")
    self.search:SetSize(142,24)
    self.search:SetAutoFocus(false)
    self.search:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-102,-66)
    self.search:SetText("")
    -- Live global search replaces per-tab submitted search. A small debounce
    -- avoids rebuilding thousands of reference entries for every keystroke.
    self.search:SetScript("OnTextChanged",function() self:QueueLiveSearch() end)
    self.search:SetScript("OnEnterPressed",function(edit) edit:ClearFocus(); self:ExecuteSearch() end)
    self.search:SetScript("OnEscapePressed",function(edit)
        edit:ClearFocus()
        if self.tab=="Global Search" then self:BackFromSearch() else f:Hide() end
    end)
    self.clearSearchButton=button(panel,"X",25,25,function()
        self.search:SetText("")
        if self.tab=="Global Search" then self:ExecuteSearch() end
    end)
    self.clearSearchButton:SetPoint("LEFT",self.search,"RIGHT",4,0)
    self.backSearchButton=button(panel,"Back",54,25,function()
        self.search:ClearFocus(); self:BackFromSearch()
    end)
    self.backSearchButton:SetPoint("LEFT",self.clearSearchButton,"RIGHT",3,0)
    self.backSearchButton:Hide()
    local searchLabel=text(panel,"Search all items or recipes", "GameFontHighlightSmall",0,0,170)
    searchLabel:ClearAllPoints()
    searchLabel:SetPoint("BOTTOMLEFT",self.search,"TOPLEFT",0,5)
    if self.searchPending then self.search:SetText(self.searchPending); self.searchPending=nil end

    local listPanel = CreateFrame("Frame",nil,panel)
    listPanel:SetPoint("TOPLEFT",panel,"TOPLEFT",14,-107)
    listPanel:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",14,64)
    background(listPanel,0.045,0.065,0.08,0.6)
    self.listPanel=listPanel
    self.scroll = CreateFrame("ScrollFrame",nil,listPanel,"UIPanelScrollFrameTemplate")
    self.scroll:SetPoint("TOPLEFT",listPanel,"TOPLEFT",7,-7)
    self.scroll:SetPoint("BOTTOMRIGHT",listPanel,"BOTTOMRIGHT",-26,7)
    local scrollChild=CreateFrame("Frame",nil,self.scroll)
    scrollChild:SetSize(440,100)
    self.scroll:SetScrollChild(scrollChild)
    self.scrollChild=scrollChild
    self.rows={}

    local detailPanel = CreateFrame("Frame",nil,panel)
    detailPanel:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-15,-107)
    detailPanel:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-15,68)
    detailPanel:SetWidth(285)
    listPanel:SetPoint("RIGHT",detailPanel,"LEFT",-12,0)
    background(detailPanel,0.055,0.075,0.095,0.82)
    self.detailPanel=detailPanel
    self.detailScroll=CreateFrame("ScrollFrame",nil,detailPanel,"UIPanelScrollFrameTemplate")
    self.detailScroll:SetPoint("TOPLEFT",detailPanel,"TOPLEFT",9,-9)
    self.detailScroll:SetPoint("BOTTOMRIGHT",detailPanel,"BOTTOMRIGHT",-27,8)
    local dc=CreateFrame("Frame",nil,self.detailScroll)
    dc:SetSize(247,450)
    self.detailScroll:SetScrollChild(dc)
    self.detailChild=dc
    self.detailText=text(dc,"Select an entry.","GameFontHighlight",3,-3,241)
    self.detailText:SetWordWrap(true)
    -- Icon, name and useful metadata are displayed in-place for item-backed
    -- rows (Auction, Global Search, Item Explorer, inventory, crafting, etc.).
    local itemPreview=CreateFrame("Frame",nil,dc)
    itemPreview:SetPoint("TOPLEFT",dc,"TOPLEFT",3,-3)
    itemPreview:SetPoint("TOPRIGHT",dc,"TOPRIGHT",-4,-3)
    itemPreview:SetHeight(102)
    itemPreview.bg=background(itemPreview,0.10,0.16,0.22,0.93)
    local previewIcon=CreateFrame("Button",nil,itemPreview)
    previewIcon:SetSize(40,40)
    previewIcon:SetPoint("TOPLEFT",itemPreview,"TOPLEFT",7,-9)
    previewIcon.texture=previewIcon:CreateTexture(nil,"ARTWORK")
    previewIcon.texture:SetAllPoints(previewIcon)
    previewIcon:RegisterForClicks("RightButtonUp")
    previewIcon:SetScript("OnClick",function(btn,mouse)
        if mouse=="RightButton" and itemPreview.itemID then
            self:DungeonTooltip(btn,itemPreview.itemID)
        end
    end)
    itemPreview.icon=previewIcon.texture
    itemPreview.title=itemPreview:CreateFontString(nil,"OVERLAY","GameFontNormal")
    itemPreview.title:SetPoint("TOPLEFT",itemPreview,"TOPLEFT",55,-7)
    itemPreview.title:SetPoint("RIGHT",itemPreview,"RIGHT",-6,0)
    itemPreview.title:SetHeight(34)
    itemPreview.title:SetJustifyH("LEFT")
    itemPreview.title:SetJustifyV("TOP")
    itemPreview.title:SetWordWrap(true)
    itemPreview.kind=itemPreview:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    itemPreview.kind:SetPoint("TOPLEFT",itemPreview,"TOPLEFT",55,-43)
    itemPreview.kind:SetPoint("RIGHT",itemPreview,"RIGHT",-6,0)
    itemPreview.kind:SetJustifyH("LEFT")
    itemPreview.stats=itemPreview:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    itemPreview.stats:SetPoint("TOPLEFT",itemPreview,"TOPLEFT",8,-65)
    itemPreview.stats:SetPoint("RIGHT",itemPreview,"RIGHT",-6,0)
    itemPreview.stats:SetJustifyH("LEFT")
    local previewHint=itemPreview:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    previewHint:SetPoint("BOTTOMLEFT",itemPreview,"BOTTOMLEFT",8,5)
    previewHint:SetText("Right-click icon for full tooltip")
    self.itemPreview=itemPreview
    itemPreview:Hide()

    -- Footer is OUTSIDE the scrolling detail panel, so it never covers recipe text.
    self.action = button(panel,"Request craft",264,29,function()
        if self.tab == "Requests" and self.activeRequest then
            local req = self.activeRequest
            local recipe = FCM:RecipeByID(req.recipeID)
            if not recipe then FCM:Say("Recipe no longer exists in scanned records."); return end
            self:ShowCrafterMenu(recipe, req.recipientKey, req)
            return
        end
        if not self.activeRecipe then return end
        local recipient=(self.activeRecipientKey and FCM.db.characters[self.activeRecipientKey]) or self:GetCharacter()
        if not recipient then return end
        local current=FCM:FindQueuedCraft(self.activeRecipe.id, recipient.key)
        if current then
            FCM:RemoveQueuedCraft(self.activeRecipe.id, recipient.key)
            FCM:Say("Cancelled craft request for " .. recipient.name .. ".")
            self:Refresh()
            return
        end
        self:ShowCrafterMenu(self.activeRecipe, recipient.key, nil, self.activeCrafters)
    end)
    self.action:SetPoint("TOPLEFT",detailPanel,"BOTTOMLEFT",9,-8)
    self.action:Hide()
    self.cancelRequestButton = button(panel,"Set Status",129,29,function()
        self:ShowRequestStatusMenu()
    end)
    self.cancelRequestButton:SetPoint("LEFT",self.action,"RIGHT",7,0)
    self.cancelRequestButton:Hide()
    self.status = text(panel,"", "GameFontHighlightSmall",14,-501,285,20)
    self.status:ClearAllPoints()
    self.status:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",14,13)
    self.deleteButton = button(panel,"Remove Saved Character",174,29,function()
        self:ConfirmDeleteSelected()
    end)
    self.deleteButton:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",322,12)
    self.deleteButton:Hide()
    self.resetIconButton = button(panel,"Reset Minimap Icon",174,29,function()
        self:ResetMinimap()
        FCM:Say("Minimap button position reset.")
    end)
    self.resetIconButton:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",322,12)
    self.resetIconButton:Hide()
    self.filterButton=button(panel,"Ready: All",133,25,function() self:ShowAdvisorFilterMenu() end)
    self.filterButton:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-152,10)
    self.filterButton:Hide()
    self.sortButton=button(panel,"Sort: Best",137,25,function() self:ShowAdvisorSortMenu() end)
    self.sortButton:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-12,10)
    self.sortButton:Hide()
    -- Auction House-style item filters are shown when searching globally or
    -- browsing Item Explorer. Each level resets its dependent selections.
    self.itemCategoryButton=button(panel,"Category: All",132,25,function() self:ShowItemCategoryMenu() end)
    self.itemCategoryButton:SetPoint("TOPLEFT",panel,"TOPLEFT",14,-108)
    self.itemCategoryButton:Hide()
    self.itemTypeButton=button(panel,"Type: All",128,25,function() self:ShowItemTypeMenu() end)
    self.itemTypeButton:SetPoint("LEFT",self.itemCategoryButton,"RIGHT",3,0)
    self.itemTypeButton:Hide()
    self.itemSlotButton=button(panel,"Slot: All",120,25,function() self:ShowItemSlotMenu() end)
    self.itemSlotButton:SetPoint("LEFT",self.itemTypeButton,"RIGHT",3,0)
    self.itemSlotButton:Hide()
    self.itemScopeButton=button(panel,"Source: All",128,25,function() self:ShowItemScopeMenu() end)
    self.itemScopeButton:SetPoint("LEFT",self.itemSlotButton,"RIGHT",3,0)
    self.itemScopeButton:Hide()
    self.itemQualityButton=button(panel,"Quality: Any",128,25,function() self:ShowItemQualityMenu() end)
    self.itemQualityButton:SetPoint("LEFT",self.itemScopeButton,"RIGHT",3,0)
    self.itemQualityButton:Hide()
    self.itemResetButton=button(panel,"Reset",65,25,function()
        local st=FCM.db.settings
        st.itemCategory="all";st.itemType="all";st.itemSlot="all"
        st.itemScope="all";st.itemQuality="all";st.itemSort="name"
        self.selectedRow=nil;self:Refresh()
    end)
    self.itemResetButton:SetPoint("LEFT",self.itemQualityButton,"RIGHT",3,0)
    self.itemResetButton:Hide()
    -- Dungeon and raid references are separate; the level filter is optional.
    self.dungeonViewButton=button(panel,"Dungeons",146,25,function() self:ShowDungeonViewMenu() end)
    self.dungeonViewButton:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-12,10)
    self.dungeonViewButton:Hide()
    self.dungeonLevelButton=button(panel,"All levels",146,25,function() self:ShowDungeonLevelMenu() end)
    self.dungeonLevelButton:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-165,10)
    self.dungeonLevelButton:Hide()
    self.dungeonLootButton=button(panel,"Class loot",146,25,function()
        self:ShowDungeonLootMenu()
    end)
    self.dungeonLootButton:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-318,10)
    self.dungeonLootButton:Hide()
    self.dungeonBossButton=button(panel,"Boss: All",146,25,function() self:ShowDungeonBossMenu() end)
    self.dungeonBossButton:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-471,10)
    self.dungeonBossButton:Hide()

    -- Talent settings are per-character. These only appear on the Talents tab,
    -- outside the scrolling detail area so they never cover recommendations.
    self.talentSpecButton = button(panel,"Specialization",92,29,function() self:ShowTalentSpecsMenu() end)
    self.talentSpecButton:SetPoint("TOPLEFT",detailPanel,"BOTTOMLEFT",1,-8)
    self.talentSpecButton:Hide()
    self.talentBuildButton = button(panel,"Leveling",92,29,function() self:ShowTalentBuildMenu() end)
    self.talentBuildButton:SetPoint("LEFT",self.talentSpecButton,"RIGHT",1,0)
    self.talentBuildButton:Hide()
    self.talentSourceButton = button(panel,"Icy Veins",93,29,function() self:ShowTalentSourceMenu() end)
    self.talentSourceButton:SetPoint("LEFT",self.talentBuildButton,"RIGHT",1,0)
    self.talentSourceButton:Hide()

    self.openLegacyButton = button(panel,"Open Legacy Panel",174,29,function()
        if type(ToggleLegacySystemUI)=="function" then ToggleLegacySystemUI()
        else FCM:Say("Forever's Legacy window API is not available in this client build.") end
    end)
    self.openLegacyButton:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",322,12)
    self.openLegacyButton:Hide()
    self.clearDiagButton = button(panel,"Clear Error Log",174,29,function()
        if FCM.db and FCM.db.diagnostics then FCM.db.diagnostics.errors={} end
        FCM:Say("FCM error log cleared.")
        self:Refresh()
    end)
    self.clearDiagButton:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",322,12)
    self.clearDiagButton:Hide()
    local grip=CreateFrame("Button",nil,f)
    grip:SetSize(20,20)
    grip:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-6,5)
    local grtex=grip:CreateTexture(nil,"ARTWORK")
    grtex:SetAllPoints()
    grtex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart",function()
        if not InCombatLockdown or not InCombatLockdown() then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnDragStop",function()
        f:StopMovingOrSizing()
        UI:SaveWindow()
    end)
    self.sizeGrip=grip
    self:CreateMinimap()
    f:Hide()
    self.frame=f
    self:Reflow()
    FCM.window=f
end

function UI:SaveWindow()
    if not FCM.db or not self.frame then return end
    local f=self.frame
    local pref=FCM.db.settings.window or {}
    pref.width=math.floor(f:GetWidth()+0.5)
    pref.height=math.floor(f:GetHeight()+0.5)
    local cx,cy=f:GetCenter()
    local px,py=UIParent:GetCenter()
    if cx and cy and px and py then pref.x=cx-px;pref.y=cy-py end
    FCM.db.settings.window=pref
end
function UI:ResetWindow()
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    self.frame:SetSize(1010,650)
    self:SaveWindow()
    self:Reflow()
end
function UI:Reflow()
    if not self.panel or not self.listPanel then return end
    local listWidth=math.max(250,self.listPanel:GetWidth()-40)
    self.scrollChild:SetWidth(listWidth)
    self.detailChild:SetWidth(math.max(190,self.detailPanel:GetWidth()-42))
    self.detailText:SetWidth(math.max(180,self.detailChild:GetWidth()-8))
    for _,w in ipairs(self.rows or {}) do
        w:SetWidth(listWidth-3)
        if w.label then w.label:SetWidth(listWidth-18) end
        if w.desc then w.desc:SetWidth(listWidth-20) end
    end
    self:SaveWindow()
end
function UI:ShowAdvisorFilterMenu()
    local options={
        {label="All entries", value="all"},
        {label="Recorded materials ready", value="ready"},
        {label="Missing materials / not ready", value="missing"},
    }
    local entries={}
    for _,opt in ipairs(options) do
        local key=opt.value
        entries[#entries+1]={label=opt.label,run=function()
            FCM.db.settings.advisorFilter=key
            self.selectedRow=nil
            self:Refresh()
        end}
    end
    self:MakeMenu(self.filterButton,entries,222,true)
end
function UI:ShowAdvisorSortMenu()
    local browsing=self.tab=="Item Explorer" or self.tab=="Global Search"
    local entries=browsing and {
        {label="Name (A-Z)",value="name"},
        {label="Quality (highest first)",value="quality"},
        {label="Item level (highest first)",value="itemlevel"},
        {label="Required level (highest first)",value="requiredlevel"},
    } or {
        {label="Recommended order",value="recommended"},
        {label="Item / character name",value="name"},
    }
    local options={}
    for _,opt in ipairs(entries) do
        local v=opt.value
        options[#options+1]={label=opt.label,run=function()
            FCM.db.settings[browsing and "itemSort" or "advisorSort"]=v
            self.selectedRow=nil
        end}
    end
    self:MakeMenu(self.sortButton,options,236,true)
end
function UI:ShowItemFilterMenu(anchor, optionSet, setting)
    if not (FCM.db and FCM.db.settings) then return end
    local choices={}
    for _,option in ipairs(optionSet or {}) do
        local id=option.id
        choices[#choices+1]={label=option.title,run=function()
            FCM.db.settings[setting]=id
            self.selectedRow=nil
        end}
    end
    self:MakeMenu(anchor,choices,225,true)
end
function UI:ShowItemCategoryMenu()
    local options={}
    for _,entry in ipairs(FCM.itemCategoryOptions or {}) do
        local id=entry.id
        options[#options+1]={label=entry.title,run=function()
            local s=FCM.db.settings
            s.itemCategory=id;s.itemType="all";s.itemSlot="all";self.selectedRow=nil
        end}
    end
    self:MakeMenu(self.itemCategoryButton,options,228,false)
end
function UI:ShowItemTypeMenu()
    local s=FCM.db.settings
    local options={}
    for _,entry in ipairs(FCM.itemTypeOptions[s.itemCategory] or {{id="all",title="All types"}}) do
        local id=entry.id
        options[#options+1]={label=entry.title,run=function()
            s.itemType=id;s.itemSlot="all";self.selectedRow=nil
        end}
    end
    self:MakeMenu(self.itemTypeButton,options,205,false)
end
function UI:ShowItemSlotMenu()
    local s=FCM.db.settings
    local options={}
    for _,entry in ipairs(FCM:ItemSlotOptions(s.itemCategory,s.itemType)) do
        local id=entry.id
        options[#options+1]={label=entry.title,run=function()
            s.itemSlot=id;self.selectedRow=nil
        end}
    end
    self:MakeMenu(self.itemSlotButton,options,190,false)
end
function UI:ShowItemScopeMenu()
    self:ShowItemFilterMenu(self.itemScopeButton,FCM.itemScopeOptions,"itemScope")
end
function UI:ShowItemQualityMenu()
    self:ShowItemFilterMenu(self.itemQualityButton,FCM.itemQualityOptions,"itemQuality")
end
function UI:ShowDungeonViewMenu()
    local choices={{"Dungeons (35 listed)","dungeons"},{"Raids (imported)","raids"},{"All references","all"}}
    local options={}
    for _,choice in ipairs(choices) do
        local label,value=choice[1],choice[2]
        options[#options+1]={label=label,run=function()
            FCM.db.settings.dungeonView=value
            self.selectedRow=nil
        end}
    end
    self:MakeMenu(self.dungeonViewButton,options,200,true)
end
function UI:ShowDungeonLevelMenu()
    local options={}
    for _,choice in ipairs({{"All levels","all"},{"At selected character's level","current"}}) do
        local label,value=choice[1],choice[2]
        options[#options+1]={label=label,run=function()
            FCM.db.settings.dungeonLevelFilter=value
            self.selectedRow=nil
        end}
    end
    self:MakeMenu(self.dungeonLevelButton,options,244,true)
end
function UI:ShowDungeonLootMenu()
    local options={}
    for _,choice in ipairs({
        {"Potential upgrades (known stats)","upgrades"},
        {"Likely spec-fit (stat heuristic)","spec"},
        {"Class loot (including uncertain)","class"},
        {"All associated items","all"},
    }) do
        local label,value=choice[1],choice[2]
        options[#options+1]={label=label,run=function()
            FCM.db.settings.dungeonLootScope=value
            self.dungeonItemSelection=nil
        end}
    end
    self:MakeMenu(self.dungeonLootButton,options,242,true)
end
function UI:ShowDungeonBossMenu()
    local r=self.currentDungeonRecord
    if not r then return end
    local options={{label="All bosses + dungeon items",run=function()
        self.dungeonBossFocus=nil
        self.dungeonItemSelection=nil
    end}}
    for index,boss in ipairs(r.bosses or {}) do
        local i=index
        local name=tostring(boss.name or ("Boss #"..index))
        options[#options+1]={label=short(name,39),run=function()
            self.dungeonBossFocus={dungeon=tostring(r.id),index=i}
            self.dungeonItemSelection=nil
        end}
    end
    self:MakeMenu(self.dungeonBossButton,options,255,true)
end
function UI:ShowRequestStatusMenu()
    local req=self.activeRequest
    if not req then return end
    local options={}
    for _,row in ipairs({{"Requested","requested"},{"Gathering Materials","gathering"},{"Ready to Craft","ready"},
        {"Crafted - Awaiting Delivery","crafted"},{"Delivered / Archive","delivered"},{"Cancel / Archive","cancelled"}}) do
        local label,code=row[1],row[2]
        options[#options+1]={label=label,run=function()
            local ok,why=FCM:ChangeRequestStatus(req,code)
            FCM:Say(ok and ("Request status: "..label) or (why or "Unable to update request"))
            self.selectedRow=nil
        end}
    end
    self:MakeMenu(self.cancelRequestButton,options,224,true)
end

function UI:GetCharacter()
    if not FCM.db then return nil end
    local selected=FCM.db.characters[self.selectedCharacter]
    if selected and FCM:InFactionView(selected) then return selected end
    local current=FCM.db.characters[FCM.currentKey or ""]
    if current and FCM:InFactionView(current) then return current end
    local visible=FCM:VisibleCharacters()
    return visible[1]
end

function UI:MakeMenu(anchor, options, width, above, page)
    if self.menu then self.menu:Hide(); self.menu=nil end
    options=options or {}
    width=math.min(tonumber(width) or 200,300)
    page=math.max(1,tonumber(page) or 1)
    -- Limit the menu to 9 rows per page: no popover taller than the FCM window.
    local perPage=8
    local pages=math.max(1,math.ceil(#options/perPage))
    page=math.min(page,pages)
    local visible={}
    local first=(page-1)*perPage+1
    for i=first,math.min(first+perPage-1,#options) do visible[#visible+1]=options[i] end
    if pages>1 then
        if page>1 then
            table.insert(visible,1,{label="< Previous options",run=function()
                self:MakeMenu(anchor,options,width,above,page-1)
            end,keepOpen=true})
        end
        if page<pages then
            visible[#visible+1]={label="Next options >",run=function()
                self:MakeMenu(anchor,options,width,above,page+1)
            end,keepOpen=true}
        end
    end
    local h=math.max(27,#visible*27+8)
    local menu=CreateFrame("Frame",nil,self.panel,"BackdropTemplate")
    menu:SetSize(width,h)
    if menu.SetClampedToScreen then menu:SetClampedToScreen(true) end
    local parentLeft=self.frame and self.frame.GetLeft and self.frame:GetLeft()
    local parentRight=self.frame and self.frame.GetRight and self.frame:GetRight()
    local anchorLeft=anchor and anchor.GetLeft and anchor:GetLeft()
    local anchorRight=anchor and anchor.GetRight and anchor:GetRight()
    local rightAlign=(parentRight and anchorRight and anchorRight+width>parentRight-15) or
        (anchor==self.sortButton or anchor==self.filterButton or
         anchor==self.itemQualityButton or anchor==self.itemScopeButton or
         anchor==self.itemSlotButton)
    -- If anchored near the right side, align right edges instead of letting a
    -- 200-300px popover escape the window. Works with the window moved/resized.
    local panelLeft=self.panel.GetLeft and self.panel:GetLeft()
    local panelTop=self.panel.GetTop and self.panel:GetTop()
    local panelBottom=self.panel.GetBottom and self.panel:GetBottom()
    local anchorTop=anchor.GetTop and anchor:GetTop()
    local anchorBottom=anchor.GetBottom and anchor:GetBottom()
    local panelWidth=self.panel:GetWidth()
    if panelLeft and panelTop and panelBottom and anchorLeft and anchorTop and anchorBottom and
        panelWidth and panelWidth>width+20 then
        local xpos=math.max(8,math.min(anchorLeft-panelLeft,panelWidth-width-8))
        local panelHeight=panelTop-panelBottom
        local topOffset
        if above then topOffset=anchorTop-panelTop+h+3
        else topOffset=anchorBottom-panelTop-3 end
        -- Keep both horizontal and vertical extents inside the frame.
        topOffset=math.min(-8,math.max(-panelHeight+h+8,topOffset))
        menu:SetPoint("TOPLEFT",self.panel,"TOPLEFT",xpos,topOffset)
    elseif rightAlign then
        if above then menu:SetPoint("BOTTOMRIGHT",anchor,"TOPRIGHT",0,3)
        else menu:SetPoint("TOPRIGHT",anchor,"BOTTOMRIGHT",0,-3) end
    else
        if above then menu:SetPoint("BOTTOMLEFT",anchor,"TOPLEFT",0,3)
        else menu:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",0,-3) end
    end
    menu:SetFrameStrata("TOOLTIP")
    background(menu,0.12,0.16,0.21,1)
    if menu.SetBackdrop then menu:SetBackdrop({edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=16}) end
    for i,opt in ipairs(visible) do
        local option=opt
        local b=button(menu,short(option.label,math.floor((width-18)/7)),width-10,24,function()
            if not option.keepOpen then menu:Hide();self.menu=nil end
            if option.run then option.run() end
            if not option.keepOpen then self:Refresh() end
        end)
        b:SetPoint("TOPLEFT",menu,"TOPLEFT",5,-4-(i-1)*27)
        if b.GetFontString then
            local t=b:GetFontString()
            if t and t.SetWordWrap then t:SetWordWrap(false) end
        end
    end
    self.menu=menu
end

function UI:ShowCharactersMenu()
    local options={}
    for _,ch in ipairs(FCM:VisibleCharacters()) do
        local selected=ch
        local tag=(FCM:NormalizeFaction(ch.faction)=="Horde" and "H" or
            (FCM:NormalizeFaction(ch.faction)=="Alliance" and "A" or "?"))
        options[#options+1]={label=short("["..tag.."] "..FCM:DisplayCharacter(ch),28),run=function()
            self.selectedCharacter=selected.key
            self.selectedRow=(self.tab == "Characters" or self.tab == "Overview") and selected.key or nil
        end}
    end
    if #options==0 then options={{label="No characters scanned",run=function() end}} end
    self:MakeMenu(self.charButton,options,225)
end

function UI:ShowFactionMenu()
    local options={}
    for _,choice in ipairs({{"All factions","all"},{"Alliance only","Alliance"},{"Horde only","Horde"}}) do
        local label,value=choice[1],choice[2]
        options[#options+1]={label=label,run=function()
            FCM.db.settings.factionView=value
            self.selectedRow=nil
            self.selectedCharacter=nil
        end}
    end
    self:MakeMenu(self.factionButton,options,188)
end

function UI:ShowGearActivityMenu()
    local options={}
    for _,activity in ipairs(FCM.gearActivityOrder) do
        local selected=activity
        options[#options+1]={label=FCM.gearActivityLabels[selected],run=function()
            FCM:SetGearActivity(self:GetCharacter(),selected)
            self.selectedRow=nil
        end}
    end
    self:MakeMenu(self.activityButton,options,160)
end
function UI:ShowModesMenu()
    local options={}
    for _,mode in ipairs({"dps","balanced","survival"}) do
        local selected=mode
        options[#options+1]={label=FCM.modeLabels[selected],run=function()
            FCM:SetGearStyle(self:GetCharacter(),selected)
            self.selectedRow=nil
        end}
    end
    self:MakeMenu(self.modeButton,options,160)
end

function UI:ShowTalentSpecsMenu()
    local ch=self:GetCharacter()
    if not ch then return end
    local choices=FCM.talentSpecChoices[ch.class] or {}
    local options={}
    for _,spec in ipairs(choices) do
        local chosen=spec
        options[#options+1]={label=chosen,run=function()
            if not ch.talentOverridesMigrated then FCM:TalentOverrides(ch) end
            ch.talentSpec=chosen
            self.selectedRow=nil
        end}
    end
    if #options==0 then options={{label="No spec choices",run=function() end}} end
    self:MakeMenu(self.talentSpecButton,options,183,true)
end
function UI:ShowTalentBuildMenu()
    local ch=self:GetCharacter()
    if not ch then return end
    local guide=FCM:TalentGuide(ch)
    local p=guide and guide.profiles or {}
    local options={}
    for _,id in ipairs(FCM:TalentProfileOrder(ch)) do
        local chosen=id
        local profile=p[id]
        if profile then
            options[#options+1]={label=short(profile.title or id,38),run=function()
                FCM:SetTalentProfile(ch,chosen)
                self.selectedRow=nil
            end}
        end
    end
    self:MakeMenu(self.talentBuildButton,options,310,true)
end
function UI:ShowTalentSourceMenu()
    local ch=self:GetCharacter()
    if not ch then return end
    self:MakeMenu(self.talentSourceButton,{
        {label="Icy Veins (bundled)",run=function()ch.talentSource="icy";self.selectedRow=nil end},
        {label="Custom points",run=function()ch.talentSource="custom";self.selectedRow=nil end},
    },185,true)
end

-- When there are several learned crafters, let the requester choose who sees
-- the request. An unassigned migrated request can also be claimed here.
function UI:ShowCrafterMenu(recipe, recipientKey, existing, eligibleCrafters)
    if not recipe then return end
    local candidates = eligibleCrafters or recipe.crafters or {}
    local options = {}
    local recipient = FCM.db.characters[recipientKey]
    for _, c in ipairs(candidates) do
        local crafter = c
        if recipient and FCM:CanCollaborate(crafter,recipient) then
        options[#options+1] = {
            label = short(FCM:DisplayCharacter(crafter), 31),
            run = function()
                local success, why
                if existing then
                    success, why = FCM:AssignQueuedCraft(existing, crafter.key)
                else
                    success, why = FCM:QueueCraft(recipe.id, recipientKey, crafter.key)
                end
                if success then
                    FCM:Say("Craft request assigned to " .. FCM:DisplayCharacter(crafter) ..
                        " for " .. (recipient and FCM:DisplayCharacter(recipient) or "the recipient") .. ".")
                else
                    FCM:Say(why or "Could not save craft request.")
                end
                self:Refresh()
            end
        }
        end
    end
    if #options == 0 then
        FCM:Say("No eligible same-faction, same-ruleset crafter with the learned recipe is recorded.")
        return
    end
    if #options == 1 then
        options[1].run()
    else
        self:MakeMenu(self.action, options, 235, true)
    end
end

local function buildRows(ui)
    local rows, tab, ch = {}, ui.tab or "Overview", ui:GetCharacter()
    local function add(id,title,summary,detail,recipe,request,crafters,recipientKey,ready)
        rows[#rows+1]={id=tostring(id),title=title,summary=summary or "",detail=detail,
            recipe=recipe,request=request,crafters=crafters,recipientKey=recipientKey,ready=ready}
    end
    local function charDetails(c)
        local p={"|cffffd983"..FCM:DisplayCharacter(c).."|r","",
            (c.class or "Class unknown").."  /  "..(c.race or "Race unknown").."  /  "..(c.faction or "Faction unknown"),
            "Ruleset: "..(FCM:NormalizeRuleset(c.ruleset) or "Not yet verified - log into this character"),
            "Region: "..(c.region or "Not yet verified"),
            "Level: "..tostring(c.level or "?"),"Gold: "..niceGold(c.gold),
            "XP: "..tostring(c.xp or 0).." / "..tostring(c.xpMax or 0),
            "Last login: "..FCM:Age(c.lastSeen),"",
            "Professions:"}
        local has=false
        for key,prof in pairs(c.professions or {}) do
            if type(prof)=="table" then
                local name=type(prof.name)=="string" and prof.name or key
                if type(name)=="string" and name:match("%S") and
                        tonumber(prof.skill) and tonumber(prof.skill)>0 then
                    p[#p+1]="  "..name..": "..tostring(prof.skill).."/"..tostring(prof.maxSkill or "?")
                    has=true
                end
            end
        end
        if not has then p[#p+1]="  Open your profession pane to scan" end
        p[#p+1]=""
        p[#p+1]=""
        p[#p+1]="Scan freshness (saved across logouts):"
        for _,entry in ipairs(FCM:DataQuality(c)) do
            p[#p+1]="  "..entry.name..": "..entry.label
        end
        p[#p+1]="Bank/recipes update when their game windows are opened."
        p[#p+1]="An old scan needs review; it does not mean the items were lost."
        return table.concat(p,"\n")
    end
    if tab=="Upgrade Plan" then
        local recommendations=FCM:AccountUpgradePlans(8)
        for i,entry in ipairs(recommendations) do
            local e=entry
            local prefix=e.kind=="crafted" and "Craft" or
                (e.kind=="dungeon" and "Dungeon" or "Unlearned")
            add("account-plan:"..i,FCM:DisplayCharacter(e.character)..": "..e.itemName,
                prefix.." | +"..FCM.Gear:ScoreLabel(e.delta).." weighted | "..e.status,
                function() return table.concat(FCM:AccountUpgradePlanLines(e),"\n") end,
                e.kind=="crafted" and e.recipe or nil,nil,
                e.kind=="crafted" and e.crafters or nil,
                e.character.key,e.kind=="crafted" and e.plan and e.plan.ready or false)
            rows[#rows].itemID=e.itemID
            rows[#rows].compareSlot=e.slot
        end
        if #recommendations==0 then
            add("account-plan-empty","No scored upgrade plans yet",
                "Log in to scan gear, recipes, and reference items after the servers return.",
                "Account-wide suggestions require scanned equipped items, known stats and reliable recipe or dungeon references.\n\n"
                .."No score is inferred for unknown gear. Cross-faction trades and unknown item binding are never assumed safe.")
        end
    elseif tab=="Upgrades" then
        for i,entry in ipairs(FCM:UpgradeDashboard()) do
            local e=entry
            add("upgrade:"..i,e.title,e.summary,function()
                if e.kind=="talent" then
                    local advice=FCM:TalentAdvice(e.ch)
                    return "|cffffd983Talent recommendation|r\n\n"..FCM:DisplayCharacter(e.ch).."\n"..advice.next..
                        "\n\n"..(advice.source or "Source unavailable").."\nOnly confirmed guide steps are shown."
                elseif e.kind=="opportunity" then
                    local o=e.opportunity
                    return "|cffffd983Potential recipe opportunity|r\n\n"..o.info.name..
                        "\nRecipient: "..FCM:DisplayCharacter(e.ch)..
                        "\nEstimated score gain: +"..FCM.Gear:ScoreLabel(o.delta)..
                        "\nRecipe: "..o.entry.name..
                        "\nProfession: "..(o.entry.profession or "Unknown")..
                        "\nKnown crafter: NONE recorded\nSource: "..(o.entry.source or "Not verified")..
                        "\n\nThis recipe was visible as UNLEARNED. The vendor, reputation and acquisition path require verification."
                elseif e.kind=="profession" then
                    return "|cffffd983Profession milestone|r\n\n"..e.summary.."\n\nThis is a progression goal, not an automatic skill gain."
                end
                local c=e.candidate;local crafter=e.crafter or (c.crafters and c.crafters[1])
                local plan=FCM:CraftAvailability(c.recipe,crafter)
                local mats,ready=plan.lines,plan.ready
                local lines={"|cffffd983"..c.info.name.."|r", "For: "..FCM:DisplayCharacter(e.ch),
                    "Activity: "..FCM.gearActivityLabels[FCM:GearActivity(e.ch)],
                    "Style: "..(FCM.modeLabels[c.mode] or "DPS"),"Weighted gain: +"..FCM.Gear:ScoreLabel(c.delta),
                    "Crafter: "..(crafter and FCM:DisplayCharacter(crafter) or "Unknown"),
                    "Materials: "..(ready and "Stock appears sufficient" or "Shortage / verification needed"),""}
                for _,m in ipairs(mats) do
                    lines[#lines+1]=m.name..": "..m.unreserved.."/"..m.required..
                        " (missing "..m.missing..", reserved "..m.reserved..")"
                end
                lines[#lines+1]=""
                lines[#lines+1]="Material transfers to assigned crafter:"
                for _,transfer in ipairs(plan.transfers or {}) do
                    lines[#lines+1]="  "..transfer.from.." / "..transfer.where..": "..transfer.count.." x "..transfer.name
                end
                if #(plan.transfers or {})==0 then lines[#lines+1]="  None identified in usable scanned storage." end
                lines[#lines+1]=""
                local estimate=FCM:CraftPriceEstimate(c.recipe,e.ch)
                if estimate then
                    if estimate.unknown==0 then
                        lines[#lines+1]="Estimated all-reagent AH cost: "..FCM:MoneyLabel(estimate.materialCost)
                        if estimate.resultMedian then
                            lines[#lines+1]="Result's reported AH median: "..FCM:MoneyLabel(estimate.resultMedian)
                        else
                            lines[#lines+1]="Result's AH price: not available for the same market."
                        end
                        lines[#lines+1]="Prices from AHledger (ahledger.com), historical snapshots; not a profit guarantee."
                    else
                        lines[#lines+1]="Craft cost incomplete: "..estimate.unknown.." ingredient price(s) missing or inconsistent."
                    end
                end
                lines[#lines+1]=""
                lines[#lines+1]=FCM.Gear:Explain(c,e.ch)
                return table.concat(lines,"\n")
            end,e.kind=="upgrade" and e.candidate.recipe or nil,nil,e.kind=="upgrade" and e.candidate.crafters or nil,e.ch.key,e.kind=="upgrade" and e.ready or nil)
            -- The dashboard contains non-item advice as well as gear; only
            -- concrete craft output IDs receive an item preview.
            if e.kind=="upgrade" and e.candidate and e.candidate.recipe then
                rows[#rows].itemID=tonumber(e.candidate.recipe.outputID)
            elseif e.kind=="opportunity" and e.opportunity and e.opportunity.entry then
                rows[#rows].itemID=tonumber(e.opportunity.entry.outputID)
            end
        end
        if ch and FCM.Gear.DungeonCandidates then
            for i,d in ipairs(FCM.Gear:DungeonCandidates(ch)) do
                if i>15 then break end
                local item=d
                add("dungeon-upgrade:"..item.itemID,
                    "Dungeon: "..(item.info.name or ("Item #"..item.itemID)),
                    "Estimated score gain +"..FCM.Gear:ScoreLabel(item.delta).." | "..item.source,
                    function()
                        return "Potential dungeon item for "..FCM:DisplayCharacter(ch).."\n\n"..
                            "Item: "..(item.info.name or ("Item #"..item.itemID)).."\n"..
                            "Source-reported associations (not confirmed live drops):\n"..
                            table.concat(item.sources or {item.source},"\n").."\n"..
                            "Estimated weighted gain: +"..FCM.Gear:ScoreLabel(item.delta).."\n\n"..
                            "NOT a simulated DPS gain. Dungeon loot and equip restrictions must be verified against the live Forever client."
                    end)
            end
        end
        if #rows==0 then add("no-upgrades","No actionable upgrades found","Scan gear and recipes on the appropriate characters.",
            "Upgrades are derived only from known recipes and loaded item stats. Unlearned, raid and dungeon items require a verified database; no guesses are made.") end
    elseif tab=="Shopping" then
        local list,unresolved=FCM:ShoppingList(FCM:FactionView())
        for _,m in ipairs(list) do
            local a=m
            add("shop:"..a.id,a.name,"Needed "..a.required.." | allocated "..a.available.." | missing "..a.missing,function()
                local d={"|cffffd983"..a.name.."|r","", "Total across pending requests: "..a.required,
                    "Allocated usable stock: "..a.available,"Still needed: "..a.missing,
                    "Requests using this material: "..a.requests,"", "Last recorded locations:"}
                local _,_,places=FCM:MaterialLocations(a.id,ch)
                for _,loc in ipairs(places) do
                    d[#d+1]="  "..loc.name.." "..loc.where..": "..loc.count..(loc.usable and "" or " (restricted)")
                end
                d[#d+1]=""
                local quote=FCM:PriceQuote(a.id,ch)
                if quote and tonumber(quote.median) then
                    d[#d+1]="Estimated AH cost of missing quantity: "..FCM:MoneyLabel(quote.median*a.missing)
                    d[#d+1]="AHledger snapshot / market: "..tostring(quote.market or "unknown")
                    d[#d+1]="Last scan: "..tostring(quote.observedAt or "not supplied")
                    d[#d+1]="Prices from AHledger (ahledger.com). Not guaranteed current."
                else
                    d[#d+1]="No verified imported price for this material on the selected market."
                end
                d[#d+1]=""
                d[#d+1]="Transfers must be completed manually. Values from offline characters may be stale."
                return table.concat(d,"\n")
            end)
        end
        for i,item in ipairs(unresolved) do add("unresolved:"..i,"Needs manual review",item,
            "This queued craft has incomplete recipe data or no selected crafter. Its ingredients cannot safely be counted in the combined shopping list.") end
        if #rows==0 then add("shopping-empty","No shopping needs recorded","Request crafts on Gear or Crafting to build an account list.",
            "The shared pool allocates items once across requests. The system does not buy, move, or farm materials automatically.") end
    elseif tab and tab:sub(1,11)=="Profession:" then
        local professionName=tab:sub(12)
        local profKey=string.lower(professionName)
        if ch then
            local recipes={}
            for _,r in pairs(ch.recipes or {}) do
                local ref=FCM.externalData and FCM.externalData.recipes and
                    FCM.externalData.recipes[tonumber(r.id)]
                local actual=string.lower(tostring((ref and ref.profession) or r.profession or ""))
                local normalizedName=string.lower(tostring(r.name or ""))
                -- The Forever-specific conversion spell is Enchanting; some
                -- early profession scans tagged it as Tailoring. Never mutate
                -- the saved spell, only classify it correctly for this view.
                if normalizedName:find("^enchant[%s:%-]") or
                   normalizedName=="dust to motes" or tonumber(r.id)==1245320 then
                    actual="enchanting"
                end
                if r.learned and actual==profKey then
                    recipes[#recipes+1]=r
                end
            end
            table.sort(recipes,function(a,b) return string.lower(a.name or "")<string.lower(b.name or "") end)
            for _,recipe in ipairs(recipes) do
                local r=recipe
                local plan=FCM:CraftAvailability(r,ch)
                add("myrecipe:"..tostring(r.id),r.name,
                    (plan.ready and "Materials ready" or "Materials missing or unverified")..
                    " | Known by "..FCM:DisplayCharacter(ch),function()
                    local d={"|cffffd983"..r.name.."|r","",
                        "Profession: "..tostring(r.profession),
                        "Known by: "..FCM:DisplayCharacter(ch),
                        "Recipe ID: "..tostring(r.id),
                        "Required skill: "..tostring(r.requiredSkill or "Not recorded"),
                        "", "Required materials:"}
                    local materials,ready=FCM:MaterialsFor(r,ch)
                    if #materials==0 then d[#d+1]="  No reagent details recorded" end
                    for _,m in ipairs(materials) do
                        d[#d+1]="  "..m.name..": "..tostring(m.usable).." / "..tostring(m.required)..
                            (m.missing>0 and (" (missing "..m.missing..")") or "")
                    end
                    d[#d+1]=""
                    d[#d+1]=ready and "Recorded materials available (subject to reservations)" or
                        "Materials incomplete, unknown or in another character's inventory"
                    d[#d+1]="Use Crafting for account-wide crafters and cross-toon requests."
                    return table.concat(d,"\n")
                end,r,nil,{ch},ch.key,plan.ready)
            end
        end
        if #rows==0 then
            add("no-known-prof-recipes","No learned "..professionName.." recipes scanned",
                "Open this character's "..professionName.." profession window, then Scan Now.",
                "This tab only lists the selected character's learned recipes. Account-wide recipes remain in Crafting.")
        end
    elseif tab=="Enchants" then
        for _,r in ipairs(FCM:AllRecipes()) do
            local eligible={}
            for _,crafter in ipairs(r.crafters or {}) do
                if ch and FCM:CanCollaborate(crafter,ch) then eligible[#eligible+1]=crafter end
            end
            if #eligible>0 and FCM:IsEquipmentEnchantRecipe(r) then
                local recipe=r
                add("enchant:"..r.id,r.name,"Known by "..#eligible.." character(s)",function()
                    local crafter=eligible[1]
                    local mats,ready=FCM:MaterialsFor(recipe,crafter)
                    local d={"|cffffd983"..recipe.name.."|r","", "Enchanters:"}
                    for _,p in ipairs(eligible) do d[#d+1]="  "..FCM:DisplayCharacter(p) end
                    d[#d+1]=""
                    d[#d+1]=ready and "Recorded materials sufficient" or "Material shortage or unknown reagents"
                    for _,m in ipairs(mats) do d[#d+1]="  "..m.name.." "..m.usable.."/"..m.required end
                    d[#d+1]=""
                    d[#d+1]="Only equipment enchant formulas appear here. Verify each effect in-game."
                    return table.concat(d,"\n")
                end,recipe)
            end
        end
        if #rows==0 then add("no-enchants","No enchanting recipes scanned","Log into your enchanter and open Enchanting.",
            "This view lists scanned equipment enchant formulas, excluding rods, wands, oils, and mislabeled crafting recipes.") end
    elseif tab=="Catalog" then
        local catalog=FCM:CatalogRecords()
        for i,r in ipairs(catalog) do
            local entry=r
            add("catalog:"..i,r.name,(r.profession or "Recipe").." | "..(r.status or "Reference"),function()
                local d={"|cffffd983"..entry.name.."|r","", "Profession: "..(entry.profession or "Unknown"),
                    "Source: "..(entry.source or "Not verified"),"Status: "..(entry.status or "Reference only")}
                if entry.recipeID then d[#d+1]="Game recipe ID: "..entry.recipeID end
                if entry.seenOn then
                    d[#d+1]="Seen as unlearned on:"
                    for _,c in ipairs(entry.seenOn) do d[#d+1]="  "..FCM:DisplayCharacter(c) end
                end
                if entry.skill then d[#d+1]="Required skill (source): "..entry.skill end
                if entry.standing then d[#d+1]="Reputation: "..(standingNames[entry.standing] or "Unknown") end
                if entry.favor then d[#d+1]="Merchant's Favor: "..entry.favor end
                if entry.standing and ch then
                    local rep=FCM:ReputationForCatalog(ch,entry)
                    if rep then
                        d[#d+1]=""
                        d[#d+1]="For "..FCM:DisplayCharacter(ch)..":"
                        d[#d+1]="  Faction: "..rep.faction
                        d[#d+1]="  Current: "..(standingNames[rep.current] or "Unscanned")
                        d[#d+1]="  Goal: "..(standingNames[rep.required] or "Unknown")
                        if rep.nextStandingMissing then d[#d+1]="  To next standing: "..rep.nextStandingMissing.." reputation" end
                        d[#d+1]="  "..(rep.unlocked and "Reputation requirement met" or "Locked or not verified")
                    end
                end
                d[#d+1]=""
                d[#d+1]="This catalogue is a limited, sourced reference. The client has not verified this vendor's current stock."
                d[#d+1]="Use /fcm catalogadd <profession> <recipe name> to save your own unverified note."
                return table.concat(d,"\n")
            end)
            rows[#rows].itemID=tonumber(entry.outputID or entry.resultID or entry.outputItemID)
        end
        if #rows==0 then add("no-catalog","No reference recipes","Use the in-game profession scanner to populate known recipes.") end
    elseif tab=="Global Search" then
        local opts=FCM.db.settings
        local query=ui.appliedSearch or ""
        local browse=(query~="" or opts.itemCategory~="all")
        local filtered,total={},0
        if browse then
            filtered,total=FCM:BrowseItems(query,opts.itemCategory,opts.itemScope,opts.itemQuality,150,
                opts.itemType,opts.itemSlot,opts.itemSort)
        end
        ui.globalSearchTotal=total
        add("search-summary","Global Search — "..tostring(total).." matching items",
            query~="" and ("Search: "..short(query,60)) or "Enter a name or choose a category",
            "Select an item to view its stats, which characters own it, recipes using it, and known sources. "..
            "Filters narrow the account-wide item reference database; unknown subtype metadata cannot be classified. "..
            "The companion may need another reference-data sync to fill missing item details.")
        for _,entry in ipairs(filtered) do
            local e=entry
            add("searchitem:"..e.id,e.name,"#"..e.id.." | "..e.group..
                (e.itemType~="all" and " / "..e.itemType or "")..
                (e.owned and " | Owned" or ""),
                function() return FCM:CatalogItemDetails(e.id,ch) end)
        end
        -- Learned recipe matches are account-wide. The Item Details pane also
        -- performs reverse-reagent lookups through ExpandedItemDetails.
        if query~="" and (opts.itemCategory=="all" or opts.itemCategory=="recipe") then
            local added=0
            for _,recipe in ipairs(FCM:AllRecipes()) do
                if FCM:SearchMatches(recipe.name,query) and added<35 then
                    local r=recipe
                    add("searchrecipe:"..tostring(r.id),r.name,
                        "Recipe | "..tostring(r.profession or "Unknown")..
                        " | "..tostring(#(r.crafters or {})).." crafter(s)",function()
                        local d={r.name,"Profession: "..tostring(r.profession or "Unknown"),"Known by:"}
                        for _,c in ipairs(r.crafters or {}) do d[#d+1]="  "..FCM:DisplayCharacter(c) end
                        d[#d+1]="Required materials:"
                        for _,mat in ipairs(r.reagents or {}) do
                            d[#d+1]="  "..FCM.ItemName(mat.itemID or mat.id).." x"..tostring(mat.count or 1)
                        end
                        return table.concat(d,"\n")
                    end)
                    added=added+1
                end
            end
        end
    elseif tab=="Item Explorer" then
        local opts=FCM.db.settings
        local query=ui.appliedSearch or ""
        local filtered,total=FCM:BrowseItems(query,opts.itemCategory,opts.itemScope,opts.itemQuality,190,
            opts.itemType,opts.itemSlot,opts.itemSort)
        ui.itemExplorerTotal=total
        add("explorer-info", "Item Database — "..tostring(total).." matches",
            "Use Category > Type > Slot, Source, Quality, and Sort",function()
                return "Reference records: "..tostring(total).." match the current filters. "..
                    "The Windows companion can import more records incrementally (up to 1,000 per run with an approved ForeverDB key). "..
                    "An item stored in client files may be speculative or unobtainable in the live game. "..
                    "FCM does not fabricate sources, stats, or missing item entries.\n\n"..
                    "Source credit: ForeverDB.net (https://foreverdb.net), TheWoWDB (https://thewowdb.com), "..
                    "AHledger (https://ahledger.com). Prices are historical snapshots."
            end)
        for _,entry in ipairs(filtered) do
            local selected=entry
            local info=entry.item or {}
            local quality=FCM:ItemQualityName(info)
            local summary="#"..entry.id.."  |  "..selected.group.."  |  "..quality..
                (selected.owned and "  |  Owned" or "")..
                (selected.uncertain and "  |  Review availability" or "")..
                (not selected.externallySourced and "  |  Reference missing" or "")
            add("item:"..tostring(entry.id),entry.name,summary,
                function() return FCM:CatalogItemDetails(selected.id,ch) end)
        end
        if total==0 then
            add("item-explorer-help", "No items match these filters", "Clear filters or run the companion's Reference Data sync.",
                "The companion builds an expandable item catalog from ForeverDB and supplemental public sources. "..
                "For an item not in the database, try an exact numeric item ID. No private character information is uploaded.")
        end
    elseif tab=="Dungeons" then
        local config=FCM.db.settings
        local view=config.dungeonView or "dungeons"
        local levelOnly=config.dungeonLevelFilter or "all"
        local records=FCM:BrowseDungeons(view,levelOnly,ch and ch.level)
        ui.dungeonTotal=#records
        local source=FCM.dungeonDirectorySource or "https://www.icy-veins.com/wow-forever/dungeons-overview"
        add("dungeon-source", "Dungeon directory — "..#records.." entries",
            "Reference levels | boss-linked data vs unconfirmed associations",function()
                return "The dungeon DIRECTORY uses the 35 entries published by Icy Veins (24 Oct 2026). "..
                    "Its levels are guide ranges, not confirmed entrance requirements. Boss and loot details are separate and "..
                    "appear only when supported by imported ForeverDB records. Use the Dungeons / Raids button below to change views.\n\n"..
                    "Directory: "..source.."\nImported data: https://foreverdb.net\n"..
                    "A boss-linked reference is NOT a verified live-game drop. Use the boss and class/spec filters; "..
                    "only cached live client stats can support a weighted upgrade comparison."
            end)
        for _,entry in ipairs(records) do
            local r=entry
            local typeLabel=(r.kind=="raid" and "Raid" or (r.kind=="unclassified" and "Unclassified instance" or "Dungeon"))
            local bossN, namedN, lootN=0,0,0
            for _,boss in ipairs(r.bosses or {}) do
                bossN=bossN+1
                local bossName=tostring(boss.name or "")
                if bossName~="" and not bossName:find("name not supplied",1,true) and
                    not bossName:find("name unavailable",1,true) then namedN=namedN+1 end
                lootN=lootN+#(boss.loot or {})
            end
            local unassignedN=#(r.dungeonLoot or {})
            local bossStatus
            if bossN>0 then
                bossStatus=tostring(bossN).." bosses ("..namedN.." named) | "..tostring(lootN+unassignedN).." associated items"
            elseif r.imported then
                bossStatus="Index imported; boss/loot coverage missing"
            else
                bossStatus="Guide directory only; details not imported"
            end
            local rowId="dungeon:"..r.id
            add(rowId,r.name,
                typeLabel.." | Levels "..tostring(r.levels or "unknown").." | "..bossStatus,
                "Select a dungeon to view source-linked bosses, class/spec filters and estimated upgrades.")
            rows[#rows].dungeonRecord=r
        end
        if #records==0 then
            add("dungeons-empty","No imported records in this view",
                "Switch to Dungeons, All references, or All levels.",
                "The 35-dungeon guide directory remains available under Dungeons / All levels. "..
                "The Raids view depends on ForeverDB imports. The selected level range may have no records.")
        end
    elseif tab=="Auction" then
        local prices=FCM:MarketPricesFor(ch)
        add("auction-credit","Auction data source","AHledger (ahledger.com) | historic snapshots only",
            "Prices from AHledger (ahledger.com). Values are recorded for the selected regional market when the companion last synchronized.\n\nThis does not scan your current in-game auction house. Exact live listings and buyouts can change.")
        local sorted={}
        for id,p in pairs(prices) do if type(id)=="number" and type(p)=="table" then sorted[#sorted+1]={id=id,p=p} end end
        table.sort(sorted,function(a,b)return (tonumber(a.p.median) or 0)>(tonumber(b.p.median) or 0) end)
        for i=1,math.min(#sorted,350) do
            local entry=sorted[i]
            local info=FCM.externalData.items and FCM.externalData.items[entry.id] or {}
            local label=info.name or (FCM.ItemName and FCM.ItemName(entry.id)) or ("Item #"..entry.id)
            local p=entry.p
            local gold=(tonumber(p.median) or 0)/10000
            add("auction:"..entry.id,label,string.format("%.2fg median | %s",gold,tostring(p.market or "unknown market")),
                function()
                    return FCM:ExplorerDetails(entry.id)
                end)
        end
        if #sorted==0 then add("auction-empty","No matching faction/market prices imported","Run the Windows companion with an AHledger market matching the selected character faction and ruleset.",
            "To preserve performance, the companion imports prices only for selected/scanned item IDs. Missing prices do not imply an item is worthless or unavailable.") end
    elseif tab=="Leveling" then
        for _,person in ipairs(FCM:VisibleCharacters()) do
            local c=person
            add("level:"..c.key,FCM:DisplayCharacter(c),"Level "..(c.level or "?").." | XP "..(c.xp or 0).."/"..(c.xpMax or 0),function()
                local d={"|cffffd983Leveling Progress|r","",FCM:LevelingSummary(c),"", "Upcoming crafted equipment (next 10 levels):"}
                local futures=FCM.Gear:FutureCandidates(c,10)
                for i=1,math.min(12,#futures) do
                    local f=futures[i]
                    d[#d+1]="  Level "..tostring(f.info.level)..": "..f.info.name
                end
                if #futures==0 then d[#d+1]="  No scanned future crafts at present." end
                d[#d+1]=""
                d[#d+1]="Future gear availability depends on learned recipes and loaded item data."
                return table.concat(d,"\n")
            end)
        end
    elseif tab=="Diagnostics" then
        add("report","FCM System Health","Live addon state, data ages, and recorded API errors",function()
            return FCM:DiagnosticsReport().."\n\n"..FCM:AdvisorDiagnostics()
        end)
        for _,person in ipairs(FCM:VisibleCharacters()) do
            local c=person
            add("fresh:"..c.key,FCM:DisplayCharacter(c),"Snapshot freshness",function()
                local d={"Data freshness for "..FCM:DisplayCharacter(c),""}
                for _,item in ipairs(FCM:DataQuality(c)) do
                    d[#d+1]=item.name..": "..item.label
                end
                d[#d+1]=""
                d[#d+1]="To refresh a character, log into it. Bank and profession data require opening those windows."
                return table.concat(d,"\n")
            end)
        end
    elseif tab=="Overview" or tab=="Characters" then
        if tab == "Overview" then
            local searchTerm=(ui.appliedSearch or ""):match("^%s*(.-)%s*$")
            if searchTerm~="" then
                local matches,total=FCM:BrowseItems(searchTerm,"all","all","all",45)
                for _,result in ipairs(matches) do
                    local item=result
                    add("overview-item:"..item.id,item.name,
                        "Item search: "..searchTerm.." | #"..item.id.." | "..item.group,
                        function() return FCM:CatalogItemDetails(item.id,ch) end)
                end
                if total==0 then
                    add("overview-item-help:"..searchTerm,
                        "No cached item matching "..searchTerm,
                        "Item search: "..searchTerm.." | Add the name to companion lookup terms and sync.",
                        "Overview now searches imported items as well as character summaries. "..
                        "No item with this name exists in the currently loaded FCM reference records. "..
                        "Try the Item Explorer tab or an exact item ID. To search online data, "..
                        "add this term to the Windows companion's item lookup field, run Scan and Update with WoW closed, then restart WoW. "..
                        "A missing record is not proof that the item doesn't exist in Forever.")
                end
            end
            add("gold","Visible gold: "..niceGold(FCM:ViewGold()),"Last-recorded gold for the selected faction view",function()
                local d={"|cffffd983Gold by Character|r",""}
                for _,person in ipairs(FCM:VisibleCharacters()) do
                    d[#d+1]=FCM:DisplayCharacter(person)..": "..niceGold(person.gold).." ("..FCM:Age(person.lastSeen)..")"
                end
                d[#d+1]=""
                d[#d+1]="Offline gold amounts are snapshots; account total may be out of date."
                return table.concat(d,"\n")
            end)
            for _, item in ipairs(FCM:VisibleRequests()) do
                if item.crafter and item.crafter.key == FCM.currentKey then
                    local request = item.request
                    local recipient = item.recipient
                    local recipe = item.recipe
                    local name = recipe and recipe.name or ("Recipe #" .. request.recipeID)
                    add("overview-request:"..request.key,
                        "CRAFT REQUEST FOR YOU: "..name,
                        "For "..(recipient and FCM:DisplayCharacter(recipient) or "unknown recipient") .. " | Open Requests to manage",
                        "|cffffd983Craft assigned to you|r\n\n" .. name ..
                        "\nRecipient: " .. (recipient and FCM:DisplayCharacter(recipient) or "Unknown") ..
                        "\n\nOpen Requests to view ingredients, reassign, complete, or cancel this craft.")
                end
            end
        end
        for _,person in ipairs(FCM:VisibleCharacters()) do
            local c=person
            local recipes=0
            for _,r in pairs(c.recipes or {}) do if r.learned then recipes=recipes+1 end end
            add(c.key,FCM:DisplayCharacter(c),"["..(FCM:NormalizeFaction(c.faction) or "Unknown").." / "..(FCM:NormalizeRuleset(c.ruleset) or "Ruleset unverified").."] Lv "..tostring(c.level or "?").." "..(c.class or "").." | "..recipes.." learned recipes",function() return charDetails(c) end)
        end
        if #rows==0 then add("empty","No characters scanned","Log into a character to initialize your roster.",function()
            return "The addon automatically scans the currently played character. It cannot inspect a toon that has never logged in with FCM installed."
        end) end
    elseif tab=="Gear" then
        if ch then
            add("gear-profile","Gear evaluation: "..FCM.gearActivityLabels[FCM:GearActivity(ch)],
                "Style: "..FCM.modeLabels[FCM:Mode(ch)].." | Spec: "..tostring(ch.talentSpec or "Not selected").." | Edit dropdowns above",
                "Activity profiles: Leveling (sustain), PvP (stamina and pressure), Endgame PvE (damage priorities)."..
                "\nChoose Activity and Style in the header; saved independently for each character."..
                "\nEach activity can remember its own DPS/Balanced/Survivability style."..
                "\nEstimates use heuristic stat weights, NOT verified Icy Veins weights, hit caps, DPS simulations or set-bonus calculations."..
                "\nChange spec on Talents tab to refresh spec-based weighting.")
            local results=FCM.Gear:Candidates(ch)
            for i,r in ipairs(results) do
                local candidate=r
                local crafter=candidate.crafters and candidate.crafters[1]
                local samplePlan=FCM:CraftAvailability(candidate.recipe,crafter)
                local slotNames={ [1]="Head",[2]="Neck",[3]="Shoulders",[5]="Chest",[6]="Waist",
                    [7]="Legs",[8]="Feet",[9]="Wrist",[10]="Hands",[11]="Ring 1",
                    [12]="Ring 2",[13]="Trinket 1",[14]="Trinket 2",[15]="Back",
                    [16]="Main hand",[17]="Off-hand",[18]="Ranged" }
                add("gear:"..i, r.info.name,
                    "+"..FCM.Gear:ScoreLabel(r.delta).." points | "..(samplePlan.ready and "Materials ready" or ("Missing "..samplePlan.missing)).." | "..(slotNames[r.slot] or ("slot "..tostring(r.slot))),
                    function()
                        local crafter=candidate.crafters[1]
                        local plan=FCM:CraftAvailability(candidate.recipe,crafter)
                        local materials, ready=plan.lines,plan.ready
                        local old=candidate.current and (FCM.Gear:Info(candidate.current.link) or {}).name or "Empty slot"
                        local d={"|cffffd983"..candidate.info.name.."|r","",
                            "Current: "..old,"Current score: "..FCM.Gear:ScoreLabel(candidate.currentScore),
                            "New score: "..FCM.Gear:ScoreLabel(candidate.score),
                            "Gain: +"..FCM.Gear:ScoreLabel(candidate.delta).." weighted points",
                            "Active: "..FCM.gearActivityLabels[FCM:GearActivity(ch)].." | Style: "..FCM.modeLabels[candidate.mode],"",
                            "ALL THREE ACTIVITY COMPARISONS (weighted score, not DPS):"}
                        for _,comparison in ipairs(FCM.Gear:CompareActivities(candidate.info.link or candidate.recipe.outputID,
                            ch,candidate.current and (candidate.current.link or candidate.current.itemID),candidate.slot,candidate.info.equip)) do
                            local delta=comparison.delta
                            d[#d+1]=comparison.label.." ["..FCM.modeLabels[comparison.style].."]: "..
                                (delta and string.format("%+.1f points",delta) or "Insufficient equipment/stat data")
                        end
                        d[#d+1]=""
                        d[#d+1]="Crafter: "..FCM:DisplayCharacter(crafter)
                        d[#d+1]="Recipe: "..candidate.recipe.name
                        d[#d+1]=ready and "Materials: available*" or "Materials: missing or unverified"
                        d[#d+1]=""
                        for _,m in ipairs(materials) do
                            d[#d+1]=m.name.." - "..m.unreserved.."/"..m.required.." unreserved"
                            if m.missing>0 then d[#d+1]="  Missing: "..m.missing end
                        end
                        if candidate.recipe.complex then d[#d+1]="Complex reagent options need manual verification" end
                        d[#d+1]=""
                        d[#d+1]="*Storage snapshots may be old. Tradeability, class restrictions, set bonuses and unique item effects need verification."
                        return table.concat(d,"\n")
                    end, r.recipe, nil, r.crafters,ch and ch.key,samplePlan.ready)
            end
        end
        if ch and #FCM.Gear:Candidates(ch)==0 then add("no-gear","No calculated crafted upgrades yet",
            "Open professions on each crafter and ensure item data has loaded.",function()
                return "The gear advisor uses only recipes already recorded on your characters. It does not yet include all unlearned patterns or dungeon drops.\n\nGear ratings use approximate class weights, not exact DPS simulations. Some items, class restrictions and unique effects need manual confirmation."
            end) end
    elseif tab=="Crafting" then
        local lureLines={}
        local anyFishing=false
        for _,owner in ipairs(FCM:VisibleCharacters()) do
            for key,p in pairs(owner.professions or {}) do
                local n=string.lower(tostring((type(p)=="table" and p.name) or key))
                if n=="fishing" then anyFishing=true end
            end
            for _,where in ipairs({"bags","bank"}) do
                for _,record in pairs(owner[where] or {}) do
                    local itemID=tonumber(record.itemID)
                    local ref=itemID and FCM.externalData and FCM.externalData.items and FCM.externalData.items[itemID]
                    local name=tostring((ref and ref.name) or record.name or "")
                    local lower=string.lower(name)
                    if lower:find("lure",1,true) or lower:find("bait",1,true) or
                        lower:find("bauble",1,true) or lower:find("spinner",1,true) or
                        lower:find("nightcrawler",1,true) then
                        lureLines[#lureLines+1]=tostring(record.count or 1).."x "..name..
                            " — "..FCM:DisplayCharacter(owner).." ("..where..")"
                    end
                end
            end
        end
        if anyFishing or #lureLines>0 then
            add("fishing-lure-box","Fishing — Lure Box",
                #lureLines.." recorded lure/bait stacks (all visible characters)",function()
                local d={"|cffffd983Fishing — Lure Box|r","",
                    "Recorded lures and bait from character bags and banks:",""}
                if #lureLines==0 then d[#d+1]="No identifiable lure/bait items scanned yet." end
                for _,line in ipairs(lureLines) do d[#d+1]="  "..line end
                d[#d+1]=""
                d[#d+1]="Fishing is a gathering skill; no separate recipe tab."
                d[#d+1]="Contents are saved inventory snapshots, not live shared storage."
                return table.concat(d,"\n")
            end)
        end
        for _,recipe in ipairs(FCM:AllRecipes()) do
            local r=recipe
            local eligible={}
            for _,crafter in ipairs(r.crafters or {}) do
                if ch and FCM:CanCollaborate(crafter,ch) then eligible[#eligible+1]=crafter end
            end
            do
            local listedCrafter=eligible[1] or (r.crafters and r.crafters[1])
            local listedPlan=FCM:CraftAvailability(r,listedCrafter)
            add("recipe:"..r.id,r.name,(r.profession or "Craft").." | "..#(r.crafters or {}).." known crafter(s) | "..
                ((#eligible==0) and "Not available to selected character" or
                (listedPlan.ready and "Materials ready" or ("Missing "..listedPlan.missing.." / verify"))),function()
                local d={"|cffffd983"..r.name.."|r","","Recipe ID: "..r.id,
                    "Profession: "..(r.profession or "Unknown"),"","Known by:"}
                for _,c in ipairs(r.crafters or {}) do
                    d[#d+1]="  "..FCM:DisplayCharacter(c)..
                        ((ch and not FCM:CanCollaborate(c,ch)) and " (different faction/ruleset)" or "")
                end
                local crafter=listedCrafter
                local plan=FCM:CraftAvailability(r,crafter)
                local mats,ready=plan.lines,plan.ready
                d[#d+1]=""
                d[#d+1]=ready and "Recorded materials sufficient after existing reservations*" or "Missing / reserved / unverified materials"
                for _,m in ipairs(mats) do
                    local missing=m.missing
                    d[#d+1]=m.name..": "..m.unreserved.."/"..m.required.." (reserved "..m.reserved..")"
                    if missing>0 then d[#d+1]="  Still needed: "..missing end
                    for _,location in ipairs(m.locations) do
                        d[#d+1]="  "..short(location.name,21).." "..location.where..": "..location.count..(location.usable and "" or " [bound or different faction/ruleset]")
                    end
                end
                d[#d+1]=""
                local expanded=FCM:SmartCraftingPlan(r,ch,crafter,1)
                for _,line in ipairs(FCM:SmartCraftingPlanLines(expanded)) do
                    d[#d+1]=line
                end
                d[#d+1]=""
                d[#d+1]="*Offline counts are last-seen snapshots. Transfers may not be possible across rulesets or factions."
                return table.concat(d,"\n")
            end,(#eligible>0 and r or nil),nil,eligible,ch and ch.key,(#eligible>0 and listedPlan.ready or nil))
            end
        end
        if #rows==0 then add("no-recipes","No learned recipes scanned","Open the crafting window on each profession toon.","Use /fcm scan with a profession window open. The addon stores learned recipe information when it is visible to the game API.") end
    elseif tab=="Planner" then
        add("planner-summary","Smart Crafting Planner | unified v0.9.0",
            "Select a known recipe or pending request to calculate an account-wide crafting chain.",
            "This planner uses cached materials and learned recipes. It selects eligible crafters, reserves existing requests, recursively expands simple recipes, and shows missing ingredients and potential transfers.\n\nAlternative reagent slots and unknown bind restrictions require manual verification. Nothing is moved, bought, crafted, or mailed automatically.")
        for _,pending in ipairs(FCM:VisibleRequests()) do
            local row=pending
            if row.recipe and row.recipient then
                local r=row.recipe
                local request=row.request
                local who=row.crafter
                add("plan-request:"..tostring(request.key),"REQUEST: "..(r.name or "Recipe"),
                    "For "..FCM:DisplayCharacter(row.recipient).." | "..
                        (who and FCM:DisplayCharacter(who) or "Unassigned crafter"),
                    function()
                        local plan=FCM:SmartCraftingPlan(r,row.recipient,who,1,request.key)
                        return table.concat(FCM:SmartCraftingPlanLines(plan),"\n")
                    end)
                rows[#rows].itemID=tonumber(r.outputID)
            end
        end
        local recipeCount=0
        for _,r in ipairs(FCM:AllRecipes()) do
            -- List without calculating every plan on every UI refresh. The full
            -- plan is generated only when the user selects a recipe.
            local recipe=r
            local eligible={}
            for _,c in ipairs(recipe.crafters or {}) do
                if ch and FCM:CanCollaborate(c,ch) then eligible[#eligible+1]=c end
            end
            local available=#eligible>0
            recipeCount=recipeCount+1
            add("plan-recipe:"..tostring(recipe.id),recipe.name or ("Recipe #"..tostring(recipe.id)),
                (recipe.profession or "Craft").." | "..#(recipe.crafters or {})..
                    " scanned crafter(s) | "..(available and "Plan available" or "Not transferable to selected character"),
                function()
                    local plan=FCM:SmartCraftingPlan(recipe,ch,nil,1)
                    return table.concat(FCM:SmartCraftingPlanLines(plan),"\n")
                end,available and recipe or nil,nil,available and eligible or nil,
                ch and ch.key,available and true or false)
            rows[#rows].itemID=tonumber(recipe.outputID)
        end
        if recipeCount==0 then add("planner-empty","No learned recipes recorded",
            "Log in on profession characters and scan their recipes when the servers return.",
            "FCM does not assume an imported recipe is learned or craftable by your characters.") end
    elseif tab=="Requests" then
        for _, entry in ipairs(FCM:VisibleRequests()) do
            local req, recipe, crafter, recipient = entry.request, entry.recipe, entry.crafter, entry.recipient
            local recipeName = recipe and recipe.name or ("Recipe #"..tostring(req.recipeID))
            local recipientName = recipient and FCM:DisplayCharacter(recipient) or "Recipient record missing"
            local crafterName = crafter and FCM:DisplayCharacter(crafter) or "Unassigned - choose crafter"
            local mine = crafter and crafter.key == FCM.currentKey
            local title = (mine and "[FOR YOU] " or "") .. recipeName
            local summary = "For: " .. short(recipientName,20) .. " | Crafter: " .. short(crafterName,22)
            local captured = entry
            add("request:" .. tostring(req.key), title, summary, function()
                local d={"|cffffd983Craft Request|r", "", "Item: " .. recipeName,
                    "Requested for: " .. recipientName, "Assigned to: " .. crafterName,
                    "Requested: " .. FCM:Age(req.created), "Status: " .. (req.status or "requested"), ""}
                if crafter and crafter.key == FCM.currentKey then
                    d[#d+1]="|cff67e89bThis craft is assigned to your current character.|r"
                elseif not crafter then
                    d[#d+1]="No known crafter is assigned. Use Assign Crafter below."
                end
                if recipe and crafter then
                    local plan = FCM:CraftAvailability(recipe, crafter, req.key)
                    local mats, ready = plan.lines, plan.ready
                    d[#d+1]=""
                    d[#d+1]="Materials (last scanned):"
                    for _, m in ipairs(mats) do
                        local usable=m.unreserved
                        local missing=m.missing
                        d[#d+1]=m.name..": "..usable.." / "..m.required.." unreserved" ..
                            (missing>0 and (" (missing "..missing..")") or "")
                    end
                    if recipe.complex then d[#d+1]="Some reagents require manual verification." end
                    if ready and #mats>0 then d[#d+1]="Stock may be ready; check reserved amounts above." end
                    local transfers=plan.transfers
                    if #transfers>0 then
                        d[#d+1]=""
                        d[#d+1]="Potential transfers to crafter:"
                        for _,t in ipairs(transfers) do
                            d[#d+1]="  "..t.count.."x "..t.name.." from "..short(t.from,24).." ("..t.where..")"
                        end
                    end
                elseif not recipe then
                    d[#d+1]="Recipe missing from the current known-recipe database; scan the crafter again."
                else
                    d[#d+1]="Assign a crafter before checking transferable material quantities."
                end
                if recipe and recipient then
                    d[#d+1]=""
                    local expanded=FCM:SmartCraftingPlan(recipe,recipient,crafter,1,req.key)
                    for _,line in ipairs(FCM:SmartCraftingPlanLines(expanded)) do
                        d[#d+1]=line
                    end
                end
                d[#d+1]=""
                d[#d+1]="Use Assign/Reassign and Set Status to track requested > gathering > ready > crafted > delivered."
                d[#d+1]="Materials are not automatically moved, crafted, or mailed."
                return table.concat(d,"\n")
            end, nil, req)
            rows[#rows].itemID=recipe and tonumber(recipe.outputID)
        end
        if #rows==0 then
            add("no-requests", "No pending crafting requests", "Queue an item from Gear or Crafting.",
                "When you request a craft, it appears in the appropriate faction view. The assigned crafter receives a reminder on login. Horde and Alliance requests must remain separate.\n\nTo test: log onto your Mage, request an item from a known crafter, log out and onto that crafter, then open FCM > Requests.")
        end
    elseif tab=="Professions" then
        if ch then
            for key,profession in pairs(ch.professions or {}) do
                local p=profession
                local count=0
                for _,r in pairs(ch.recipes or {}) do if r.learned and r.profession==p.name then count=count+1 end end
                add("prof:"..key,p.name,(p.skill or 0).."/"..(p.maxSkill or "?").." | "..count.." stored recipes",
                    "Last scanned: "..FCM:Age(p.scan).."\n\nOpen this profession's recipe window to update known patterns and required reagents.")
            end
        end
        if ch then
            local plans=FCM:ProfessionPlan(ch)
            for i=1,math.min(45,#plans) do
                local p=plans[i]
                local r=p.recipe
                local label=(p.ready and "Materials ready" or ("Missing "..p.plan.missing.." reagents"))
                add("train:"..tostring(r.id),"Craft idea: "..(r.name or "?"),
                    (r.profession or "Profession").." | "..label,
                    function()
                        local lines={"|cffffd983Profession Craft Planner|r", "",r.name or "Recipe",
                            "Crafter: "..FCM:DisplayCharacter(ch),
                            "Profession: "..(r.profession or "Unknown"),
                            "Skill requirement: "..tostring(p.skill or "Unknown"),
                            "Current skill: "..tostring(p.current or "Unknown"),
                            "Skill-up estimate: "..p.hint,
                            "", "Recorded materials / outstanding reservations:"}
                        for _,m in ipairs(p.plan.lines or {}) do
                            lines[#lines+1]=m.name.." "..m.unreserved.."/"..m.required.." (missing "..m.missing..")"
                        end
                        lines[#lines+1]=""
                        lines[#lines+1]="Craft is a suggestion only. Colors and skill-up odds must be checked at the profession trainer."
                        return table.concat(lines,"\n")
                    end,r,nil,{ch},ch.key,p.ready)
            end
        end
        if #rows==0 then add("no-prof","No professions captured","Open your professions or skill book.","FCM records skill levels automatically when exposed by the client, and captures recipe details when the trade skill panel is open.") end
    elseif tab=="Reputation" then
        if ch then
            for id,record in pairs(ch.reputations or {}) do
                local r=record
                local label=standingNames[r.reaction] or "Unknown"
                local progress=(r.high and r.low and r.value) and (math.max(0,r.value-r.low).."/"..math.max(0,r.high-r.low)) or "Unknown"
                add("rep:"..id,r.name,label.." | "..progress,function()
                    local d={"|cffffd983"..r.name.."|r","",
                        "Standing: "..label,"Progress: "..progress,
                        "Faction ID: "..r.id,"Last seen: "..FCM:Age(r.updated),"",
                        "Reputation-locked recipes must be registered in the addon database or manually tagged using /fcm repgate.",""}
                    for recipeID,gate in pairs(FCM.db.gates) do
                        if gate.factionID==r.id then
                            d[#d+1]="Recipe #"..recipeID.." needs "..(standingNames[gate.standing] or "?")
                        end
                    end
                    return table.concat(d,"\n")
                end)
            end
        end
        table.sort(rows, sortByName)
        if #rows==0 then add("no-rep","No faction data yet","Open reputation pane and scan.","This module records faction standing per character, but the full vendor-recipe unlock database has not been bundled.") end
    elseif tab=="Talents" then
        if ch then
            local advice=FCM:TalentAdvice(ch)
            local report=advice.report
            local profile=report.profile
            local availability={reference="Reference only",partial="Partial verified sequence",
                variant="IV variant identified",complete="Complete verified"}
            local proof=availability[report.coverage] or "Not verified"
            local summary={"|cffffd983"..(report.guide and report.guide.name or "Talent Advisor").."|r", "",
                "Spec: "..tostring(report.spec),
                "Selected profile: "..tostring(report.profileTitle),
                "Reference quality: "..proof,
                "Source: "..(report.source=="custom" and "Your custom profile" or "Icy Veins (offline reference)"),
                "Reference checked: "..tostring(report.checked),
                "Talents last scanned: "..tostring(report.scanAge or "Not scanned"),
                "Recorded ranks spent: "..tostring(report.spent),
                "Unspent points (live character only): "..tostring(ch.key==FCM.currentKey and ch.unspentTalentPoints or "unknown"),
                "Verified exact steps: "..tostring(report.reviewedCount).." / 51", "",
                "Next: "..advice.next,"Status: "..tostring(report.status),"",
                report.summary or "", "", "Source: "..(report.url or "No source"), "",
                "FCM never spends talent points and will not recommend a respec automatically. Unknown steps stay unknown; do not extrapolate them."}
            add("advice","Talent recommendation",report.status,table.concat(summary,"\n"))
            if FCM.TalentAudit then
                local audit=FCM:TalentAudit(ch)
                add("talent-audit","Allocation audit",audit.status,table.concat(audit.lines or {},"\n"))
            end
            if FCM.TalentGearHints then
                local hints=FCM:TalentGearHints(ch,7)
                add("talent-gear","Gear priorities for this spec",
                    "Estimated stat weights - "..tostring(hints.activity),table.concat(hints.lines or {},"\n"))
            end
            local variants=report.guide and report.guide.profiles or {}
            for _,id in ipairs(FCM:TalentProfileOrder(ch)) do
                local variant=variants[id]
                if variant then
                    local lines={"|cffffd983"..variant.title.."|r", "",
                        "Status: "..(availability[variant.evidence] or "Unverified"),
                        "Purpose: "..(id=="leveling" and "Level 10-60" or (variant.purpose=="world" and "World / PvP / Leveling alternative" or "Level 60 PvE")),"",
                        variant.summary or "", ""}
                    if variant.allocation then
                        lines[#lines+1]="Talent trees (1st / 2nd / 3rd): "..table.concat(variant.allocation," / ")
                        lines[#lines+1]="This is a tree TOTAL, not verified individual talent ranks."
                    end
                    if variant.notes then lines[#lines+1]=variant.notes end
                    lines[#lines+1]=""
                    lines[#lines+1]=variant.sourceURL or "No guide URL"
                    add("profile:"..id,variant.title,
                        (id==report.profileID and "SELECTED - " or "")..(availability[variant.evidence] or "Unverified"),
                        table.concat(lines,"\n"))
                end
            end
            if report.guide and report.guide.alternativeBuilds then
                add("alternatives","Other IV builds (not selected)","Reference only",
                    table.concat(report.guide.alternativeBuilds,"\n").."\n\nOnly separately documented full builds are added as selectable profiles; smaller optional talent swaps remain source notes.")
            end
            if profile then
                local title=report.profileID=="leveling" and "Leveling milestones" or "PvE guide priorities"
                local lines={"|cffffd983"..title.."|r",""}
                if report.profileID=="leveling" then
                    for _,g in ipairs(profile.goals or {}) do
                        lines[#lines+1]="Level "..tostring(g.level)..": "..tostring(g.text)
                    end
                else
                    for _,g in ipairs(profile.goals or {}) do lines[#lines+1]="- "..tostring(g) end
                end
                if #lines==2 then lines[#lines+1]="No detailed milestone data verified for this profile." end
                lines[#lines+1]=""
                lines[#lines+1]="Milestones are NOT a complete talent point sequence."
                add("guide-goals",title,"Verified notes where available",table.concat(lines,"\n"))
            end
            local stepLines={"|cffffd983Saved exact / custom steps for this profile|r", ""}
            for _,step in ipairs(report.steps or {}) do
                local suffix=step.custom and "(your profile override, not source-verified)" or "(reviewed IV step)"
                stepLines[#stepLines+1]="Level "..tostring(step.level)..": "..step.name..
                    (step.rank and " rank "..tostring(step.rank) or "").." "..suffix
                if step.reason then stepLines[#stepLines+1]="Why: "..step.reason end
            end
            if #stepLines==2 then stepLines[#stepLines+1]="No exact points yet; open the source and record verified steps." end
            stepLines[#stepLines+1]=""
            stepLines[#stepLines+1]="Unknown levels do not mean 'no talent needed'; they mean that point order is unverified."
            add("guide-sequence","Point-by-point plan",report.exactCount.." entered/verified step(s)",table.concat(stepLines,"\n"))
            if report.source=="icy" then
                if #report.gaps>0 then
                    local diff={"|cffffd983Verified steps requiring attention|r",""}
                    for _,step in ipairs(report.gaps) do
                        diff[#diff+1]="Level "..step.level..": "..step.name.." rank "..step.rank.."; scanned "..tostring(step.actual or 0)
                    end
                    diff[#diff+1]=""
                    diff[#diff+1]="Review against the current spec and live IV calculator before considering a paid respec."
                    add("guide-differences","Talent comparison",#report.gaps.." differences in reviewed steps",table.concat(diff,"\n"))
                else
                    add("guide-differences","Talent comparison","No conflicts in known steps",
                        "Only reviewed steps are compared. This does not prove the complete build matches IV. Talent scan requires a supported live client.")
                end
            end
            if profile and profile.target then
                local lines={"|cffffd983Verified Level-60 target ranks|r",""}
                local names={}
                for name in pairs(profile.target) do names[#names+1]=name end
                table.sort(names)
                for _,name in ipairs(names) do lines[#lines+1]=name.." rank "..tostring(profile.target[name]) end
                if report.pveComparable then
                    lines[#lines+1]=""
                    lines[#lines+1]=#report.pveDifferences.." rank differences detected"
                end
                add("target","Level-60 talent ranks","Selected profile target",table.concat(lines,"\n"))
            end
            add("guide-source","Guide source and verification","Reviewed "..tostring(report.checked),
                "Original source:\n"..(report.url or "Not linked")..
                "\n\nExact rank orders require source review. The companion does not scrape Icy Veins. FCM cannot fetch URLs during gameplay.")
            add("custom-plan","Edit the selected profile","/fcm talentadd <level> <name>",
                "Choose the Spec and Profile buttons below. Custom entries are saved independently for each character, spec, and profile.\n\n"..
                "/fcm talentadd <level> <talent name>\n/fcm talentrank <level> <rank> <talent name>\n/fcm talentclear <level>\n"..
                "/fcm talentbuild leveling|sustain|output\n"..
                "/fcm talentsource icy|custom\n\n"..
                "Your old v0.7.0 custom entries are copied once into their original active profile. Other profiles are not overwritten.")
            for _,node in pairs(ch.talents or {}) do
                local n=node
                add("talent:"..tostring(n.nodeID or n.spellID or n.name or "unknown"),n.name or "Unknown talent","Rank "..tostring(n.rank),
                    "Selected talent: "..n.name.."\nRank: "..tostring(n.rank).."\nSpell ID: "..tostring(n.spellID or "Unavailable")..
                    "\nLast scanned: "..FCM:Age(ch.talentStamp))
            end
        end
    elseif tab=="Inventory" then
        local aggregate={}
        for _,person in ipairs(FCM:VisibleCharacters()) do
            for _,location in ipairs({"bags","bank"}) do
                for _,item in pairs(person[location] or {}) do
                    local row=aggregate[item.itemID]
                    if not row then row={id=item.itemID,total=0,name=item.name or FCM.ItemName(item.itemID),bound=0};aggregate[item.itemID]=row end
                    row.total=row.total+(item.count or 0)
                    if item.bound then row.bound=row.bound+(item.count or 0) end
                end
            end
        end
        for id,r in pairs(aggregate) do
            local v=r
            add("item:"..id,v.name,"Total: "..v.total.." | bound: "..v.bound,function()
                local _,_,locations=FCM:MaterialLocations(v.id,ch)
                local d={"|cffffd983"..v.name.."|r","","Item ID: "..v.id,
                    "Total recorded: "..v.total,"Bound quantity: "..v.bound,"","Saved locations:"}
                for _,place in ipairs(locations) do
                    d[#d+1]=short(place.name,24).." "..place.where..": "..place.count..(place.bound and " (bound)" or "")
                    d[#d+1]="  Last scan: "..FCM:Age(place.lastScan)
                end
                -- Evaluate every recorded holder, not merely the currently
                -- selected character. This view is account-wide.
                if type(FCM.BoEProtectionCheck)=="function" then
                    local processed=0
                    for _,holder in ipairs(FCM:Characters()) do
                        local has=false
                        for _,section in ipairs({"bags","bank"}) do
                            for _,entry in pairs(holder[section] or {}) do
                                if tonumber(entry.itemID)==tonumber(v.id) then has=true;break end
                            end
                            if has then break end
                        end
                        if has then
                            local boe=FCM:BoEProtectionCheck(v.id,holder)
                            if boe.info and boe.info.bindType==2 then
                                d[#d+1]=""
                                d[#d+1]="Holder: "..FCM:DisplayCharacter(holder)
                                for _,line in ipairs(FCM:BoEProtectionLines(boe,4)) do d[#d+1]=line end
                            end
                            processed=processed+1
                            if processed>=4 then d[#d+1]="Additional item holders omitted";break end
                        end
                    end
                end
                return table.concat(d,"\n")
            end)
        end
        table.sort(rows,sortByName)
        if #rows==0 then add("no-inventory","Inventory is empty or unscanned","Log in to each toon. Open bank to capture storage.","The item search tracks last-scanned counts, not live offline inventories.") end
    elseif tab=="Legacy" then
        if ch then add("legacy-goal","Legacy goal for "..ch.name,short(FCM:LegacyGoal(ch),70),
            "Manual goal: "..FCM:LegacyGoal(ch).."\n\nUse /fcm legacygoal <goal> to change it.\n\nThis is not an automatically validated Legacy point total.") end
        add("legacy","Legacy window and planning","Open the actual Legacy window using the button below",
            "FCM can open Forever's built-in Legacy UI when the client exposes ToggleLegacySystemUI.\n\nAutomated Legacy point and tree scanning remains unverified; this build does not invent points or unlocks.")
    elseif tab=="Settings" then
        add("minimap", "Round movable minimap icon", "Left-drag to reposition; right-click to reset.",
            "The round FCM emblem appears as soon as you log in. Drag it around the minimap to a preferred spot. Its location is saved for the whole account across sessions.\n\nRight-click the icon, click Reset Minimap Icon below, or type /fcm minimap reset to return it to its default location.")
        add("settings","Gear activity and priority","Choose both dropdowns above (saved per character)",
            "Activity: Leveling, PvP, or Endgame PvE.\nSecondary style: DPS, Balanced, or Survivability.\n\n"..
            "Each character remembers its activity and its style for EACH activity. Changing spec on Talents changes weightings.\n"..
            "Slash commands: /fcm gearprofile leveling|pvp|pve and /fcm gearstyle dps|balanced|survival.\n"..
            "Custom stat weight: /fcm gearweight spell 5 (per toon/activity); /fcm gearweight reset.\n\n"..
            "Score comparisons are approximate weighted stats, not actual DPS, PvP win rates, healing simulations, hit-cap modeling or verified IV weights.")
        add("guide","Talent plan customization","Use slash commands to add or clear planned talent steps.",
            "/fcm talentbuild <profile ID> (see Talents tab for this spec's available profiles)\n/fcm talentsource icy|custom\n/fcm talentspec <spec>\n/fcm talentadd <level> <talent name>\n/fcm talentrank <level> <rank> <talent name>\n/fcm talentclear <level>\n/fcm talentaudit\n\nGuide modules include verified notes and selected exact steps. All 27 specializations have at least three profile slots; distinct IV alternate builds are added where verified. Full exact point order remains incomplete and is labeled clearly.")
        add("window","Resizable interface","Drag the lower-right corner; /fcm ui reset to restore defaults.",
            "The window remembers its width, height and position. Resize using the small lower-right grip.\n\n/fcm ui reset resets layout to its initial size and position.")
        add("threshold","Upgrade score threshold","Minimum gain: "..tostring(FCM.db.settings.minimumUpgrade),
            "Use /fcm threshold <points> to ignore upgrades smaller than the requested weighted-score gain.\n\nThis is an estimated scoring gain, NOT a measured DPS percentage.")
        add("notify","Talent reminders","Level-up reminders: "..(FCM.db.settings.showNotifications and "On" or "Off"),
            "Use /fcm notifications on|off. Only verified guide steps are announced; no talents are automatically spent.")
        add("manual-reputation","Recipe reputation requirements","Register verified gates by recipe ID and faction ID.",
            "/fcm repgate <recipeID> <factionID> <standing 1-8>\n/fcm clearrepgate <recipeID>\n\nStanding IDs: 1 Hated through 8 Exalted. Unregistered vendors are not automatically inferred.")
    elseif tab=="Help" then
        add("advanced","What's new in unified v0.9.0","Reference provenance, safer import merges, offline data-health audit",
            "The Windows companion now records reference provider, fetch date and evidence caveats, retains multiple dungeon sources, and reports incomplete data using its Audit Reference Data button. Partial API replies no longer discard known recipe output/reagents or cached boss loot.\n\nThese are public reference records, not verified game drops or vendor stock. No live Icy Veins sync, automatic Legacy totals, DPS simulation, mailing or crafting automation is claimed.")
        add("requests", "Cross-character crafting requests", "Open Requests to see work assigned to the crafter.",
            "From Gear or Crafting choose a recipient in the top dropdown, select a recipe or suggested upgrade, and click Request Craft. If multiple characters know it, choose the crafter.\n\nLog into that crafter: FCM announces pending assignments and Requests lists the item, recipient, and materials. Assign/Reassign changes the crafter. Set Status moves it through requested, gathering, ready, and crafted; Delivered or Cancelled archives it. Nothing is crafted or mailed automatically.")
        add("delete", "Removing a saved character", "Characters tab > select a toon > Remove Saved Character",
            "You must be logged into a different toon than the record being removed. Select its row in Characters, then press Remove Saved Character and confirm the prompt.\n\nOnly FCM's saved data and that character's queued crafts are removed. The actual WoW character is untouched. Log into the removed character again if you want to re-add it.\n\nOther characters' records remain intact.")
        add("factions","Horde and Alliance support","Use Faction: All / Alliance / Horde above the list.",
            "FCM scans both factions and keeps every character's talents, gear, inventory, professions and reputation in separate records. Selecting Faction only changes the roster view.\n\nCrafts and material transfers are restricted to the same confirmed faction, region and ruleset; FCM never assumes cross-faction transfers. Auction snapshots use the companion's selected market and must match the character's faction. Log into Horde characters to capture their actual data.")
        add("start","Getting started","First login for each toon; open professions and bank once.",
            "1. Install and enable the addon.\n2. Type /fcm.\n3. Log into every character you want tracked.\n4. Open each profession to capture known recipes.\n5. Open your bank to scan stored items.\n6. Choose a character and gear priority.\n\n/fcm help displays commands.")
        add("limits","Important accuracy notes","What the addon cannot reliably verify yet.",
            "No direct website access in-game; the separate PC updater can import public reference data. Every spec has a three-profile IV guide reference; unverified rank orders remain explicitly missing.\nNo full reputation-vendor recipe catalog yet.\nDungeon drops depend on ForeverDB detail coverage; imported links are not live drop confirmations.\nUnscanned offline gear and bank counts may be stale.\nNo automated mailing, crafting, or talent spending.\nComplex and optional recipe reagents are flagged rather than guessed.")
    end
    return rows
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() or not FCM.db then return end
    local tab=self.tab or "Overview"
    if self.detailPanel then self.detailPanel:SetWidth(tab=="Dungeons" and 366 or 285) end
    self.heading:SetText(tab)
    self.factionButton:SetText(FCM:FactionView()=="all" and "All" or FCM:FactionView())
    local ch=self:GetCharacter()
    if ch then
        self.charButton:SetText(short(ch.name or "Character",13))
        self.activityButton:SetText(FCM.gearActivityLabels[FCM:GearActivity(ch)])
        self.modeButton:SetText((FCM:Mode(ch)=="survival" and "Survival") or FCM.modeLabels[FCM:Mode(ch)] or "DPS")
    else
        self.charButton:SetText("Character")
        self.activityButton:SetText(FCM.gearActivityLabels[FCM:GearActivity(nil)])
        self.modeButton:SetText(FCM.modeLabels[FCM:Mode(nil)])
    end
    self.subtitle:SetText(ch and (FCM:DisplayCharacter(ch).." | "..(FCM:NormalizeFaction(ch.faction) or "Unknown faction").." | last seen "..FCM:Age(ch.lastSeen)) or "No character in selected faction; log into one to scan")
    self:RefreshProfessionTabs(ch)
    tab=self.tab or "Overview"
    self.heading:SetText(tab:sub(1,11)=="Profession:" and
        (tab:sub(12):gsub("^%l",string.upper).." — "..(ch and ch.name or "Character")) or tab)
    for t,b in pairs(self.tabButtons) do b:SetEnabled(t~=tab) end
    local myRequests=FCM:CountAssignedRequests(FCM.currentKey)
    self.tabButtons.Requests:SetText(myRequests>0 and ("Requests ("..myRequests..")") or "Requests")
    local all=buildRows(self)
    local q=string.lower(self.appliedSearch or "")
    local entries={}
    for _,r in ipairs(all) do
        if tab=="Global Search" or q=="" or FCM:SearchMatches(r.title,q) or
                FCM:SearchMatches(r.summary,q) or
                (tab=="Item Explorer" and FCM:SearchMatches(r.id,q)) then
            local filter=FCM.db.settings.advisorFilter or "all"
            if not (tab=="Upgrades" or tab=="Gear" or tab=="Crafting" or tab=="Professions" or tab:sub(1,11)=="Profession:") or
                filter=="all" or (filter=="ready" and r.ready==true) or
                (filter=="missing" and r.ready==false) then
                entries[#entries+1]=r
            end
        end
    end
    if (FCM.db.settings.advisorSort or "recommended")=="name" then
        table.sort(entries,sortByName)
    end
    -- The box is also useful for looking up ordinary inventory items while on
    -- a profession or craft tab. If that tab has no match, offer catalogue
    -- records without falsely presenting reagents as craftable recipes.
    if #entries==0 and q~="" and tab~="Item Explorer" and tab~="Global Search" and FCM.BrowseItems then
        local matches=FCM:BrowseItems(q,"all","all","all",30)
        for _,item in ipairs(matches) do
            local entry=item
            entries[#entries+1]={id="searchitem:"..entry.id,title=entry.name,
                summary="Item database result #"..entry.id.." (not necessarily craftable)",
                detail=function() return FCM:CatalogItemDetails(entry.id,ch) end}
        end
    end
    if #entries==0 then entries={{id="no-match",title="No matching results",
        summary="Try a shorter name or clear Search; check reference-data sync",
        detail="No recorded items or recipes match this search. The companion may not have imported the item yet."}} end
    local matchedCount=#entries
    while #entries>200 do table.remove(entries) end
    local hasSelected=false
    for _,r in ipairs(entries) do if r.id==self.selectedRow then hasSelected=true end end
    if not hasSelected then
        local selectedID = self.selectedCharacter
        local foundCharacter = false
        if tab == "Characters" then
            for _,r in ipairs(entries) do
                if r.id == selectedID and FCM.db.characters[selectedID] then foundCharacter = true; break end
            end
        end
        self.selectedRow = foundCharacter and selectedID or entries[1].id
    end
    self.activeRecipe=nil
    self.activeCrafters=nil
    self.activeRequest=nil
    self.activeRecipientKey=nil
    local selected=nil
    for i,row in ipairs(entries) do
        local widget=self.rows[i]
        if not widget then
            widget=CreateFrame("Button",nil,self.scrollChild)
            widget:SetSize(438,45)
            widget.bg=background(widget,0.13,0.16,0.19,0.7)
            widget.label=text(widget,"", "GameFontNormal",8,-6,418)
            widget.desc=text(widget,"", "GameFontHighlightSmall",8,-24,416)
            widget:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            self.rows[i]=widget
        end
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT",self.scrollChild,"TOPLEFT",2,-((i-1)*47))
        widget.label:SetText(short(row.title,63))
        widget.desc:SetText(short(row.summary,80))
        widget.bg:SetColorTexture(row.id==self.selectedRow and 0.12 or 0.07,
            row.id==self.selectedRow and 0.29 or 0.12,
            row.id==self.selectedRow and 0.38 or 0.17,0.9)
        widget:SetScript("OnClick",function()
            if self.tab=="Dungeons" and self.selectedRow~=row.id then self.dungeonItemSelection=nil end
            self.selectedRow=row.id
            if self.tab=="Global Search" then self.searchSelectedItem=(row.id~="search-summary") end
            if self.detailScroll and self.detailScroll.SetVerticalScroll then self.detailScroll:SetVerticalScroll(0) end
            if (tab == "Characters" or tab == "Overview") and FCM.db.characters[row.id] then
                self.selectedCharacter = row.id
            end
            self:Refresh()
        end)
        widget:Show()
        if row.id==self.selectedRow then selected=row end
    end
    for i=#entries+1,#self.rows do self.rows[i]:Hide() end
    self.scrollChild:SetHeight(math.max(250,#entries*47+4))
    self:Reflow()
    if tab=="Global Search" then
        self.status:SetText(tostring(self.globalSearchTotal or 0).." item matches | category filters are account-wide")
    elseif tab=="Item Explorer" then
        self.status:SetText(tostring(self.itemExplorerTotal or 0).." matches; first "..tostring(math.max(0,matchedCount-1)).." listed (max 190) | Filter by name or ID")
    elseif tab=="Dungeons" then
        local dungeonMatches=0
        for _,row in ipairs(entries) do if row.id:sub(1,8)=="dungeon:" then dungeonMatches=dungeonMatches+1 end end
        self.status:SetText(tostring(dungeonMatches).." dungeon entries | last scan: "..(ch and FCM:Age(ch.lastSeen) or "none"))
    else
        self.status:SetText((matchedCount>200 and ("First 200 of "..matchedCount) or (matchedCount.." results"))..
            (q~="" and " | Search: "..short(q,24) or "")..
            " | last scan: "..(ch and FCM:Age(ch.lastSeen) or "none"))
    end
    if tab == "Characters" then
        self.resetIconButton:Hide()
        self.deleteButton:Show()
        local selectedRecord = FCM.db.characters[self.selectedRow or ""]
        self.deleteButton:SetEnabled(selectedRecord ~= nil and selectedRecord.key ~= FCM.currentKey and selectedRecord.key ~= FCM:CharacterKey())
    elseif tab == "Settings" then
        self.deleteButton:Hide()
        self.resetIconButton:Show()
    else
        self.deleteButton:Hide()
        self.resetIconButton:Hide()
    end
    if self.filterButton then
        local show=(tab=="Upgrades" or tab=="Gear" or tab=="Crafting" or tab=="Professions" or tab:sub(1,11)=="Profession:")
        local browsing=(tab=="Item Explorer" or tab=="Global Search")
        self.filterButton:SetShown(show)
        self.sortButton:SetShown(show or browsing or tab=="Inventory")
        self.itemCategoryButton:SetShown(browsing)
        self.itemTypeButton:SetShown(browsing)
        self.itemSlotButton:SetShown(browsing)
        self.itemScopeButton:SetShown(browsing)
        self.itemQualityButton:SetShown(browsing)
        self.itemResetButton:SetShown(browsing)
        self.backSearchButton:SetShown(tab=="Global Search")
        -- Move content down only while the AH-style filter toolbar is visible.
        self.listPanel:ClearAllPoints()
        self.listPanel:SetPoint("TOPLEFT",self.panel,"TOPLEFT",14,browsing and -143 or -107)
        self.listPanel:SetPoint("BOTTOMLEFT",self.panel,"BOTTOMLEFT",14,64)
        self.listPanel:SetPoint("RIGHT",self.detailPanel,"LEFT",-12,0)
        self.detailPanel:ClearAllPoints()
        self.detailPanel:SetPoint("TOPRIGHT",self.panel,"TOPRIGHT",-15,browsing and -143 or -107)
        self.detailPanel:SetPoint("BOTTOMRIGHT",self.panel,"BOTTOMRIGHT",-15,68)
        local dungeonBrowsing=(tab=="Dungeons")
        self.dungeonViewButton:SetShown(dungeonBrowsing)
        self.dungeonLevelButton:SetShown(dungeonBrowsing)
        self.dungeonLootButton:SetShown(dungeonBrowsing)
        self.dungeonBossButton:SetShown(dungeonBrowsing)
        if dungeonBrowsing then
            self.currentDungeonRecord=selected and selected.dungeonRecord or nil
            local focus=self.dungeonBossFocus
            if not self.currentDungeonRecord or (focus and focus.dungeon~=tostring(self.currentDungeonRecord.id)) then
                self.dungeonBossFocus=nil
                focus=nil
            end
            self.dungeonBossButton:SetEnabled(self.currentDungeonRecord~=nil)
            local b=self.currentDungeonRecord and focus and (self.currentDungeonRecord.bosses or {})[focus.index]
            self.dungeonBossButton:SetText(b and ("Boss: "..short(tostring(b.name or "Unknown"),13)) or "Boss: All")
            local lootScope=FCM.db.settings.dungeonLootScope or "class"
            self.dungeonLootButton:SetText(lootScope=="all" and "All items" or
                (lootScope=="upgrades" and "Upgrades only" or
                (lootScope=="spec" and "Spec-fit" or "Class loot")))
            local dview=FCM.db.settings.dungeonView or "dungeons"
            self.dungeonViewButton:SetText(dview=="raids" and "Raids" or (dview=="all" and "All references" or "Dungeons"))
            self.dungeonLevelButton:SetText(FCM.db.settings.dungeonLevelFilter=="current" and "At my level" or "All levels")
        end
        local filterLabel={all="All",ready="Ready",missing="Missing"}
        self.filterButton:SetText("Materials: "..(filterLabel[FCM.db.settings.advisorFilter] or "All"))
        if browsing then
            local sortNames={name="Name",quality="Quality",itemlevel="Item level",requiredlevel="Required level"}
            self.sortButton:SetText("Sort: "..(sortNames[FCM.db.settings.itemSort] or "Name"))
        else
            self.sortButton:SetText((FCM.db.settings.advisorSort=="name") and "Sort: Name" or "Sort: Best")
        end
        if browsing then
            local function title(options,value)
                for _,o in ipairs(options) do if o.id==value then return o.title end end
                return "All"
            end
            local config=FCM.db.settings
            self.itemCategoryButton:SetText(short(title(FCM.itemCategoryOptions,config.itemCategory),14))
            self.itemTypeButton:SetText(short(title(FCM.itemTypeOptions[config.itemCategory] or
                {{id="all",title="All types"}},config.itemType),14))
            self.itemSlotButton:SetText(short(title(FCM:ItemSlotOptions(config.itemCategory,config.itemType),config.itemSlot),13))
            self.itemScopeButton:SetText(short(title(FCM.itemScopeOptions,config.itemScope),14))
            self.itemQualityButton:SetText(short(title(FCM.itemQualityOptions,config.itemQuality),14))
        end
    end
    self.action:Hide()
    self.cancelRequestButton:Hide()
    self.talentSpecButton:Hide()
    self.talentBuildButton:Hide()
    self.talentSourceButton:Hide()
    self.openLegacyButton:Hide()
    self.clearDiagButton:Hide()
    if tab=="Legacy" then self.openLegacyButton:Show() end
    if tab=="Diagnostics" then self.clearDiagButton:Show() end
    if tab == "Talents" and ch then
        local spec=FCM:TalentSpec(ch)
        self.talentSpecButton:SetText(short(spec or "Spec",12))
        local selectedProfile=FCM:TalentProfile(ch)
        self.talentBuildButton:SetText(short(selectedProfile and (selectedProfile.shortTitle or selectedProfile.title) or "Leveling",14))
        self.talentSourceButton:SetText(ch.talentSource=="custom" and "Custom" or "Icy Veins")
        self.talentSpecButton:Show()
        self.talentBuildButton:Show()
        self.talentSourceButton:Show()
    end
    if tab=="Dungeons" and selected and selected.dungeonRecord then
        self:ResetItemPreview()
        self:RenderDungeonDetail(selected.dungeonRecord,ch)
    elseif selected then
        self:ResetDungeonWidgets()
        self.detailText:Show()
        local previewHeight=self:RenderItemPreview(selected)
        local content=type(selected.detail)=="function" and selected.detail() or selected.detail or ""
        -- The same quick red/green comparison appears wherever a real item is
        -- selected. Non-equipment rows simply retain their existing details.
        local itemID=previewItemID(selected)
        if itemID and ch and FCM.Gear and FCM.Gear.CompareItem then
            local comparison=FCM.Gear:CompareItem(itemID,ch,selected.compareSlot)
            local comparisonLines=FCM.Gear:ComparisonLines(comparison)
            if #comparisonLines>0 then
                content=table.concat(comparisonLines,"\n").."\n\n"..tostring(content)
            end
        end
        self.detailText:SetText(content)
        self.detailChild:SetHeight(math.max(345,self.detailText:GetStringHeight()+previewHeight+30))
        if selected.request then
            self.activeRequest=selected.request
            self.action:SetWidth(125)
            self.action:SetText("Assign / Reassign")
            self.action:Show()
            self.cancelRequestButton:SetText("Set Status")
            self.cancelRequestButton:Show()
        elseif selected.recipe and ch then
            self.activeRecipe=selected.recipe
            self.activeCrafters=selected.crafters
            self.activeRecipientKey=selected.recipientKey
            self.action:SetWidth(260)
            local rch=(self.activeRecipientKey and FCM.db.characters[self.activeRecipientKey]) or ch
            local queued=FCM:FindQueuedCraft(selected.recipe.id,rch.key)
            self.action:SetText(queued and "Cancel Craft Request" or "Request Craft for "..short(rch.name,15))
            self.action:Show()
        end
    else
        self:ResetDungeonWidgets()
        self:ResetItemPreview()
        self.detailText:Show()
        self.detailText:SetText("No entry selected")
    end
end

function FCM:Refresh() return self.UI:Refresh() end
function FCM:Toggle()
    self.UI:Create()
    if self.window:IsShown() then self.window:Hide() else self.window:Show(); self.UI:Refresh() end
end
