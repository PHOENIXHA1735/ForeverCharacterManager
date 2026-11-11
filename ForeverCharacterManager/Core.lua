-- Forever Character Manager, integrated preview 0.5.0
-- All lookups are advisory and read-only; no protected action automation.
local addonName, addon = ...
local FCM = addon or {}
_G.ForeverCharacterManager = FCM
FCM.version = "0.8.8"
FCM.name = addonName or "ForeverCharacterManager"
FCM.currentKey = nil
FCM.events = {}
FCM.modeLabels = { dps = "DPS", balanced = "Balanced", survival = "Survivability" }
FCM.gearActivityLabels = { leveling = "Leveling", pvp = "PvP", pve = "Endgame PvE" }
FCM.gearActivityOrder = {"leveling", "pvp", "pve"}

function FCM:Say(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff69c7ffFCM:|r " .. tostring(message))
    end
end

function FCM:Try(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(func, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m, n end
    if self.RecordError then self:RecordError("API", a) end
    return nil
end

function FCM:Now()
    return (type(time) == "function" and time()) or 0
end

function FCM:CharacterKey()
    local guid = UnitGUID and UnitGUID("player")
    local name, realm = UnitFullName and UnitFullName("player")
    if not name and UnitName then name = UnitName("player") end
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() or "Unknown" end
    return (guid and guid ~= "" and guid) or ((name or "Unknown") .. "-" .. realm)
end

function FCM:InitDB()
    if type(FCM_DB) ~= "table" then FCM_DB = {} end
    local db = FCM_DB
    db.schema = math.max(tonumber(db.schema) or 0, 5)
    db.characters = db.characters or {}
    db.settings = db.settings or { mode = "dps", minimumUpgrade = 1, tooltip = true }
    db.settings.mode = db.settings.mode or "dps"
    -- Gear activity is saved on each character. Retain legacy DPS/Balanced/
    -- Survival selection as the starting secondary preference for old saves.
    db.settings.gearActivity = db.settings.gearActivity or "leveling"
    db.settings.minimumUpgrade = db.settings.minimumUpgrade or 1
    -- Minimap coordinates are saved as offsets from the minimap center.
    -- An existing v0.1.0 SavedVariables file remains compatible.
    db.settings.minimap = db.settings.minimap or { x = -66, y = 66 }
    db.craftingQueue = db.craftingQueue or {}
    db.gates = db.gates or {} -- User-entered recipe ID -> { factionID, standing, note }
    db.notes = db.notes or {}
    db.requestHistory = db.requestHistory or {}
    db.catalog = db.catalog or {}
    db.diagnostics = db.diagnostics or {errors={}, scans={}}
    db.settings.window = db.settings.window or {width=1010,height=635}
    db.settings.showNotifications = db.settings.showNotifications ~= false
    db.settings.advisorFilter = db.settings.advisorFilter or "all"
    db.settings.advisorSort = db.settings.advisorSort or "recommended"
    db.settings.itemCategory = db.settings.itemCategory or "all"
    db.settings.itemType = db.settings.itemType or "all"
    db.settings.itemSlot = db.settings.itemSlot or "all"
    db.settings.itemSort = db.settings.itemSort or "name"
    db.settings.itemScope = db.settings.itemScope or "all"
    db.settings.itemQuality = db.settings.itemQuality or "all"
    db.settings.dungeonView = db.settings.dungeonView or "dungeons"
    db.settings.dungeonLevelFilter = db.settings.dungeonLevelFilter or "all"
    db.settings.dungeonLootScope = db.settings.dungeonLootScope or "class"
    if db.settings.dungeonLootScope ~= "all" and db.settings.dungeonLootScope ~= "upgrades" then
        db.settings.dungeonLootScope = "class"
    end
    if db.settings.factionView ~= "Alliance" and db.settings.factionView ~= "Horde" then
        db.settings.factionView = "all"
    end
    db.settings.minimumUpgrade = math.max(0,tonumber(db.settings.minimumUpgrade) or 1)
    self.db = db
    -- Character identity becomes reliable on PLAYER_LOGIN, not ADDON_LOADED.
end

function FCM:Current()
    if not self.db then return nil end
    local key = self.currentKey or self:CharacterKey()
    local char = self.db.characters[key]
    if not char then
        char = { key = key, bags = {}, bank = {}, gear = {}, recipes = {}, professions = {},
                 reputations = {}, talents = {}, customTalents = {}, created = self:Now() }
        self.db.characters[key] = char
    end
    char.bags = char.bags or {}
    char.bank = char.bank or {}
    char.gear = char.gear or {}
    char.recipes = char.recipes or {}
    char.professions = char.professions or {}
    char.reputations = char.reputations or {}
    char.talents = char.talents or {}
    char.customTalents = char.customTalents or {}
    char.talentBuild = char.talentBuild or "leveling"
    char.talentSource = char.talentSource or "icy"
    char.legacyGoal = char.legacyGoal or ""
    return char
end

function FCM:Characters()
    local list = {}
    if self.db then
        for _, char in pairs(self.db.characters) do list[#list + 1] = char end
    end
    table.sort(list, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return (a.name or a.key or "") < (b.name or b.key or "")
    end)
    return list
end

-- Both Horde and Alliance characters share FCM's account-wide SavedVariables.
-- Separating the roster view does not delete characters or restrict scanning.
function FCM:NormalizeFaction(faction)
    if type(faction) ~= "string" then return nil end
    local value=string.lower(faction)
    if value=="horde" then return "Horde" end
    if value=="alliance" then return "Alliance" end
    return nil
end

function FCM:FactionView()
    local view=self.db and self.db.settings and self.db.settings.factionView
    return (view=="Horde" or view=="Alliance") and view or "all"
end

function FCM:InFactionView(ch)
    local view=self:FactionView()
    return ch and (view=="all" or self:NormalizeFaction(ch.faction)==view)
end

function FCM:VisibleCharacters()
    local result={}
    for _,ch in ipairs(self:Characters()) do
        if self:InFactionView(ch) then result[#result+1]=ch end
    end
    return result
end

-- Conservative eligibility: cross-faction or cross-ruleset crafting/material
-- exchange must not be promised. Empty faction/realm values are NOT permission.
-- Characters can still be compared and inspected regardless of these restrictions.
function FCM:CanCollaborate(a,b)
    if not a or not b then return false,"Unknown character" end
    if a.key and b.key and a.key==b.key then return true,"Same character" end
    local af,bf=self:NormalizeFaction(a.faction),self:NormalizeFaction(b.faction)
    if not af or not bf then return false,"Faction not recorded" end
    if af~=bf then return false,"Opposing factions cannot directly transfer items" end
    local ar,br=type(a.realm)=="string" and string.lower(a.realm) or "",
                type(b.realm)=="string" and string.lower(b.realm) or ""
    if ar=="" or br=="" or ar=="unknown" or br=="unknown" then
        return false,"Realm or ruleset not recorded"
    end
    if ar~=br then return false,"Different realms or rulesets" end
    return true,"Same faction and realm"
end

function FCM:VisibleRequests()
    local result={}
    for _,row in ipairs(self:QueuedRequests()) do
        if row.recipient and self:InFactionView(row.recipient) then result[#result+1]=row end
    end
    return result
end

function FCM:ViewGold()
    local sum=0
    for _,ch in ipairs(self:VisibleCharacters()) do sum=sum+(tonumber(ch.gold) or 0) end
    return sum
end

function FCM:FindCharacter(query)
    if not self.db or not query then return nil end
    if self.db.characters[query] then return self.db.characters[query] end
    local q = string.lower(query)
    for _, ch in pairs(self.db.characters) do
        if string.lower(ch.name or "") == q or string.lower((ch.name or "") .. "-" .. (ch.realm or "")) == q then return ch end
    end
    return nil
end

-- Remove exactly one saved character record (by unique key, not by name).
-- Never erase the record for the logged-in toon, which would be recreated by scans.
-- Also remove queued crafts that name the deleted character as recipient.
function FCM:DeleteCharacter(key)
    if not self.db or not key or type(key) ~= "string" then
        return false, "No saved character was selected."
    end
    local target = self.db.characters[key]
    if not target then return false, "This character is no longer in the database." end
    if key == self.currentKey or key == self:CharacterKey() then
        return false, "Log into a different character before removing this character's saved record."
    end
    local label = self:DisplayCharacter(target)
    self.db.characters[key] = nil
    local queue = self.db.craftingQueue or {}
    for i = #queue, 1, -1 do
        if queue[i].recipientKey == key then
            table.remove(queue, i)
        elseif queue[i].crafterKey == key then
            queue[i].crafterKey = nil -- preserve request so another crafter can take it
        end
    end
    for i=#(self.db.requestHistory or {}),1,-1 do
        local r=self.db.requestHistory[i]
        if r.recipientKey==key or r.crafterKey==key then table.remove(self.db.requestHistory,i) end
    end
    -- Cached aggregate recipes must not continue advertising the deleted crafter.
    self.allRecipesCache = nil
    if self.UI then
        self.UI.selectedCharacter = self.currentKey
        self.UI.selectedRow = nil
        if self.UI.menu then self.UI.menu:Hide(); self.UI.menu = nil end
    end
    self:Say("Removed saved data for " .. label .. ". Requests for it were removed; its assigned crafts can be reassigned. The WoW character was not deleted.")
    if self.Refresh then self:Refresh() end
    return true
end

-- Activity and secondary style belong to the SELECTED character, not the
-- logged-in character. A separate style is remembered for each activity.
function FCM:GearActivity(char)
    local value=(char and char.gearActivity) or
        (self.db and self.db.settings and self.db.settings.gearActivity) or "leveling"
    return self.gearActivityLabels[value] and value or "leveling"
end
function FCM:SetGearActivity(char, activity)
    if not self.gearActivityLabels[activity] then return false end
    if char then char.gearActivity=activity
    elseif self.db and self.db.settings then self.db.settings.gearActivity=activity
    else return false end
    return true
end
function FCM:Mode(char, activity)
    local selected=activity or self:GearActivity(char)
    local styles=char and char.gearStyles
    local mode=(type(styles)=="table" and styles[selected]) or
        (char and char.mode) or (self.db and self.db.settings and self.db.settings.mode)
    return self.modeLabels[mode] and mode or "dps"
end
function FCM:SetGearStyle(char, style, activity)
    if not self.modeLabels[style] then return false end
    local selected=activity or self:GearActivity(char)
    if not self.gearActivityLabels[selected] then return false end
    if char then
        char.gearStyles=type(char.gearStyles)=="table" and char.gearStyles or {}
        char.gearStyles[selected]=style
    elseif self.db and self.db.settings then self.db.settings.mode=style
    else return false end
    return true
end

function FCM:DisplayCharacter(ch)
    return (ch and ch.name or "Unknown") .. " - " .. (ch and ch.realm or "Unknown")
end

function FCM:Age(timestamp)
    if not timestamp or timestamp == 0 then return "Never" end
    local delta = math.max(0, self:Now() - timestamp)
    if delta < 60 then return "just now" end
    if delta < 3600 then return math.floor(delta / 60) .. "m ago" end
    if delta < 86400 then return math.floor(delta / 3600) .. "h ago" end
    return math.floor(delta / 86400) .. "d ago"
end

function FCM:KnownNamesForRecipe(recipeID)
    local found = {}
    for _, ch in ipairs(self:Characters()) do
        if ch.recipes and ch.recipes[recipeID] and ch.recipes[recipeID].learned then
            found[#found + 1] = self:DisplayCharacter(ch)
        end
    end
    return found
end

local f = CreateFrame("Frame")
FCM.eventFrame = f
f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local requested = ...
        if requested == FCM.name then FCM:InitDB() end
        return
    end
    if event == "PLAYER_LOGIN" then
        if not FCM.db then FCM:InitDB() end
        FCM.currentKey = FCM:CharacterKey()
        local active=FCM:Current()
        -- Start a new leveling session without carrying elapsed time over logout.
        active.sessionAnchor=FCM:Now()
        active.sessionXP=active.xp or 0
        active.sessionXPMax=active.xpMax or 0
        active.sessionGain=0
        active.sessionLevel=active.level or 1
        FCM:ScanBasic()
        FCM:ScanBags()
        FCM:ScanGear()
        FCM:ScanProfessions()
        FCM:ScanReputations()
        FCM:ScanTalents()
        if FCM.TrackSession then FCM:TrackSession() end
        -- Initialize the minimap button at login; opening the main window is optional.
        if FCM.UI and FCM.UI.CreateMinimap then FCM.UI:CreateMinimap() end
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                FCM:ScanBasic(); FCM:ScanProfessions(); FCM:ScanReputations(); FCM:ScanTalents()
                if FCM.NotifyCraftRequests then FCM:NotifyCraftRequests() end
                if FCM.Refresh then FCM:Refresh() end
            end)
        end
        FCM:Say("Loaded. Type /fcm to open. Open each profession and bank once to save their contents.")
        return
    end
    if not FCM.db then return end
    if event == "PLAYER_LOGOUT" then
        FCM:ScanBasic(); FCM:ScanBags(); FCM:ScanGear()
    elseif event == "BAG_UPDATE_DELAYED" then
        FCM:ScanBags()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        FCM:ScanGear(); FCM:ScanBasic()
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_UPDATE" then
        FCM:ScanProfessions(); FCM:ScanRecipes()
    elseif event == "SKILL_LINES_CHANGED" then
        FCM:ScanProfessions()
    elseif event == "BANKFRAME_OPENED" then
        FCM.bankOpen = true; FCM:ScanBank()
    elseif event == "BANKFRAME_CLOSED" then
        FCM.bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        if FCM.bankOpen then FCM:ScanBank() end
    elseif event == "UPDATE_FACTION" then
        FCM:ScanReputations()
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "TRAIT_NODE_CHANGED" then
        FCM:ScanTalents()
    elseif event == "PLAYER_MONEY" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_XP_UPDATE" then
        FCM:ScanBasic()
        if FCM.TrackSession then FCM:TrackSession() end
        if event == "PLAYER_LEVEL_UP" and FCM.db.settings.showNotifications and FCM.TalentReminder then
            local tip=FCM:TalentReminder(FCM:Current())
            if tip then FCM:Say(tip .. ". Open /fcm > Talents for source and verification.") end
        end
    end
    if FCM.Refresh and FCM.window and FCM.window:IsShown() then FCM:Refresh() end
end)

function FCM:Listen(event)
    local ok = pcall(f.RegisterEvent, f, event)
    if ok then self.events[event] = true end
end

FCM:Listen("ADDON_LOADED")
FCM:Listen("PLAYER_LOGIN")
for _, event in ipairs({"PLAYER_LOGOUT", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "SKILL_LINES_CHANGED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED",
    "UPDATE_FACTION", "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "PLAYER_MONEY", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE"}) do
    FCM:Listen(event)
end

SLASH_FOREVERCHARACTERMANAGER1 = "/fcm"
SLASH_FOREVERCHARACTERMANAGER2 = "/forevercm"
SlashCmdList.FOREVERCHARACTERMANAGER = function(message)
    local cmd, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    if cmd == "scan" then
        local ok, count, total=FCM:ScanAll()
        FCM:Say("Manual scan "..(ok and "completed" or "partially completed").." ("..tostring(count).."/"..tostring(total).."). Open profession and bank windows for those snapshots.")
    elseif cmd == "diag" or cmd == "diagnostics" then
        if FCM.UI then FCM.UI.tab="Diagnostics" end
        if FCM.Toggle then
            if not FCM.window or not FCM.window:IsShown() then FCM:Toggle() else FCM:Refresh() end
        end
    elseif cmd == "upgrades" or cmd == "upgrade" then
        if FCM.UI then FCM.UI.tab="Upgrades" end
        if FCM.Toggle then
            if not FCM.window or not FCM.window:IsShown() then FCM:Toggle() else FCM:Refresh() end
        end
    elseif cmd == "item" then
        if FCM.UI then
            FCM.UI.tab="Item Explorer"
            FCM.UI.searchPending=rest or ""
            if FCM.UI.search then FCM.UI.search:SetText(rest or "") end
        end
        if FCM.Toggle then
            if not FCM.window or not FCM.window:IsShown() then FCM:Toggle()
            else if FCM.UI and FCM.UI.search then FCM.UI.search:SetText(rest or "") end; FCM:Refresh() end
        end
    elseif cmd == "shopping" then
        if FCM.UI then FCM.UI.tab="Shopping" end
        if FCM.Toggle then
            if not FCM.window or not FCM.window:IsShown() then FCM:Toggle() else FCM:Refresh() end
        end
    elseif cmd == "legacygoal" then
        FCM:Current().legacyGoal=rest or ""
        FCM:Say("Legacy goal updated (manual note; not a verified point count).")
        if FCM.Refresh then FCM:Refresh() end
    elseif cmd == "catalogadd" then
        local profession,name=(rest or ""):match("^(%S+)%s+(.+)$")
        if profession and name and FCM:CatalogAdd(name,profession) then
            FCM:Say("Added unverified catalog note: "..name)
        else FCM:Say("Usage: /fcm catalogadd <profession> <recipe name>") end
    elseif cmd == "threshold" then
        local n=tonumber(rest)
        if n and n>=0 and n<=9999 then FCM.db.settings.minimumUpgrade=n; FCM:Say("Minimum score gain: "..n)
        else FCM:Say("Usage: /fcm threshold <0-9999>") end
        if FCM.Refresh then FCM:Refresh() end
    elseif cmd == "ui" then
        if string.lower(rest or "")=="reset" then
            FCM.db.settings.window={width=1010,height=635}
            if FCM.UI and FCM.UI.ResetWindow then FCM.UI:ResetWindow() end
            FCM:Say("Window position and size reset.")
        else FCM:Say("Usage: /fcm ui reset") end
    elseif cmd == "notifications" then
        local r=string.lower(rest or "")
        if r=="on" or r=="off" then
            FCM.db.settings.showNotifications=(r=="on")
            FCM:Say("Level-up talent reminders: "..r)
        else FCM:Say("Usage: /fcm notifications on|off") end
    elseif cmd == "requeststatus" then
        local number,status=(rest or ""):match("^(%d+)%s+(%S+)$")
        local req=FCM.db.craftingQueue[tonumber(number or "") or 0]
        local ok,reason=FCM:ChangeRequestStatus(req,string.lower(status or ""))
        FCM:Say(ok and "Request updated." or (reason or "Invalid request"))
    elseif cmd == "respec" then
        if FCM.UI then FCM.UI.tab="Talents" end
        if FCM.Toggle and (not FCM.window or not FCM.window:IsShown()) then FCM:Toggle() end
    elseif cmd == "minimap" then
        if string.lower(rest or "") == "reset" then
            if FCM.UI and FCM.UI.ResetMinimap then FCM.UI:ResetMinimap() end
            FCM:Say("Minimap button position reset.")
        else
            FCM:Say("Drag the FCM emblem to move it. Right-click it or type /fcm minimap reset to reset its position.")
        end
    elseif cmd == "gearprofile" or cmd == "gearactivity" then
        local requested=string.lower(rest or "")
        local ch=FCM:Current()
        if FCM:SetGearActivity(ch,requested) then
            FCM:Say("Gear activity for "..(ch.name or "character")..": "..FCM.gearActivityLabels[requested])
            if FCM.Refresh then FCM:Refresh() end
        else FCM:Say("Usage: /fcm gearprofile leveling|pvp|pve") end
    elseif cmd == "mode" or cmd == "gearstyle" then
        local requested=string.lower(rest or "")
        local ch=FCM:Current()
        if FCM:SetGearStyle(ch,requested) then
            FCM:Say("Gear style ("..FCM.gearActivityLabels[FCM:GearActivity(ch)].."): "..FCM.modeLabels[requested])
            if FCM.Refresh then FCM:Refresh() end
        else FCM:Say("Usage: /fcm gearstyle dps|balanced|survival") end
    elseif cmd == "gearweight" then
        local ch=FCM:Current()
        local input=string.lower(rest or "")
        local key,value=input:match("^(%S+)%s+([%d%.]+)$")
        local aliases={intellect="int",stamina="stam",strength="str",agility="agi",
            spirit="spi",spellpower="spell",["spell power"]="spell",attackpower="ap",
            critical="crit",criticalstrike="crit",hitrating="hit",hasterating="haste",
            mana="mp5",defense="def",resistance="resist"}
        key=aliases[key] or key
        if input=="list" or input=="show" then
            local activity=FCM:GearActivity(ch)
            local override=ch and ch.gearCustomWeights and ch.gearCustomWeights[activity] or {}
            local report={}
            for stat,weight in pairs(override) do report[#report+1]=stat.."="..tostring(weight) end
            table.sort(report)
            FCM:Say("Custom weights for "..activity..": "..(#report>0 and table.concat(report,", ") or "none (defaults)"))
        elseif input=="reset" and ch then
            ch.gearCustomWeights=ch.gearCustomWeights or {}
            ch.gearCustomWeights[FCM:GearActivity(ch)]=nil
            FCM:Say("Custom stat weights reset for "..FCM:GearActivity(ch)..".")
            if FCM.Refresh then FCM:Refresh() end
        elseif ch and key and value and FCM.Gear and FCM.Gear:SetCustomWeight(ch,key,tonumber(value)) then
            FCM:Say("Set "..key.." base weight to "..tostring(value).." for "..ch.name.." / "..FCM:GearActivity(ch)..".")
            if FCM.Refresh then FCM:Refresh() end
        else
            FCM:Say("Usage: /fcm gearweight spell 5 | intellect 1 | list | reset (current toon/activity; value 0-100)")
        end
    elseif cmd == "talentbuild" or cmd == "talentprofile" then
        local ch=FCM:Current()
        local requested=string.lower(rest or "")
        if FCM:SetTalentProfile(ch,requested) then
            FCM:Say("Talent profile for "..tostring(ch.name)..": "..FCM:TalentProfileID(ch))
            if FCM.Refresh then FCM:Refresh() end
        else
            local current=FCM:Current()
            local options=FCM:TalentProfileOrder(current)
            FCM:Say("Available talent profiles: "..table.concat(options," | ").." (pve = sustain)")
        end
    elseif cmd == "talentsource" then
        local ch=FCM:Current()
        local requested=string.lower(rest or "")
        if requested=="icy" or requested=="custom" then
            ch.talentSource=requested
            FCM:Say("Talent guide source: "..(requested=="icy" and "Icy Veins" or "Custom"))
            if FCM.Refresh then FCM:Refresh() end
        else FCM:Say("Usage: /fcm talentsource icy|custom") end
    elseif cmd == "talentspec" then
        local ch=FCM:Current()
        local candidate=string.lower(rest or "")
        local found=nil
        for _, spec in ipairs(FCM.talentSpecChoices[ch.class] or {}) do
            if string.lower(spec)==candidate then found=spec; break end
        end
        if found then
            if not ch.talentOverridesMigrated then FCM:TalentOverrides(ch) end
            ch.talentSpec=found
            FCM:Say("Talent specialization: "..found)
            if FCM.Refresh then FCM:Refresh() end
        else FCM:Say("Choose a supported specialization for your class on the Talents tab.") end
    elseif cmd == "talentadd" then
        local level, name = (rest or ""):match("^(%d+)%s+(.+)$")
        level = tonumber(level)
        if level and level >= 1 and level <= 100 and name then
            FCM:SetTalentOverride(FCM:Current(),level,name)
            FCM:Say("Custom talent for "..FCM:TalentProfileID(FCM:Current())..": level " .. level .. " => " .. name)
            if FCM.Refresh then FCM:Refresh() end
        else FCM:Say("Usage: /fcm talentadd <level> <talent name>") end
    elseif cmd == "talentclear" then
        local level = tonumber(rest)
        if level and FCM:SetTalentOverride(FCM:Current(),level,nil) then
            FCM:Say("Removed custom talent entry for current profile at level " .. level)
        end
        if FCM.Refresh then FCM:Refresh() end
    elseif cmd == "repgate" then
        local recipe, faction, standing = (rest or ""):match("^(%d+)%s+(%d+)%s+(%d+)$")
        recipe, faction, standing = tonumber(recipe), tonumber(faction), tonumber(standing)
        if recipe and faction and standing and standing >= 1 and standing <= 8 then
            FCM.db.gates[recipe] = { factionID = faction, standing = standing }
            FCM:Say("Recorded reputation gate for recipe " .. recipe .. ".")
        else FCM:Say("Usage: /fcm repgate <recipeID> <factionID> <standing 1-8>") end
    elseif cmd == "clearrepgate" then
        local recipe = tonumber(rest)
        if recipe then FCM.db.gates[recipe] = nil; FCM:Say("Removed gate for recipe " .. recipe) end
    elseif cmd == "help" then
        FCM:Say("/fcm | scan | upgrades | shopping | item <name or ID> | diag | minimap reset | ui reset")
        FCM:Say("/fcm threshold <score> | notifications on|off | legacygoal <goal>")
        FCM:Say("/fcm requeststatus <number> requested|gathering|ready|crafted|delivered|cancelled")
        FCM:Say("Characters tab: select a saved character and choose Remove Saved Character. Confirmation required. The active character is protected.")
        FCM:Say("Requests tab: see crafts assigned to you, mark them complete, or cancel them.")
        FCM:Say("/fcm talentbuild <profile ID> | /fcm talentsource icy|custom | /fcm talentspec <name>")
        FCM:Say("Available profile IDs for this spec: "..table.concat(FCM:TalentProfileOrder(FCM:Current())," | "))
        FCM:Say("/fcm talentadd <level> <talent> | /fcm talentclear <level>")
        FCM:Say("/fcm repgate <recipeID> <factionID> <standing 1-8> | /fcm clearrepgate <recipeID>")
    else
        if FCM.Toggle then FCM:Toggle() else FCM:Say("UI not loaded; use /reload") end
    end
end
