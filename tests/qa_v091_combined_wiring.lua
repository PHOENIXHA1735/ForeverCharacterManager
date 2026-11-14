-- Verify the merged QA6e + Gathering Preview entry points remain connected.
-- The gameplay/API assertions live in the focused regression harnesses.
local function file(path)
    local f=assert(io.open(path,"rb"),"Missing "..path)
    local value=f:read("*a")
    f:close()
    return value
end
local function includes(source, needle, explanation)
    assert(source:find(needle,1,true),explanation.." missing: "..needle)
end
local addon="ForeverCharacterManager/"
local core=file(addon.."Core.lua")
local ui=file(addon.."UI.lua")
local crafting=file(addon.."Crafting.lua")
local companion=file(addon.."FCM-Companion/FCMDataUpdater.ps1")

includes(core,'FCM.version = "0.9.1"','version')
includes(core,'FCM:MergeCommunityGathering()','login-time community merge')
includes(core,'FCM:GatherEvent(event,...)','game-event forwarding')
for _,event in ipairs({'UNIT_SPELLCAST_SENT','UNIT_SPELLCAST_SUCCEEDED',
                       'UNIT_SPELLCAST_FAILED','UNIT_SPELLCAST_INTERRUPTED'}) do
    includes(core,'"'..event..'"','gathering event registration')
end
includes(core,'cmd == "gather" or cmd == "gathering"','gathering slash commands')
includes(core,'cmd == "legacypriority"','Legacy tree priority command')
includes(core,'cmd == "pawnimport"','Zygor/Pawn stat weight import')
includes(ui,'"Professions", "Gathering", "Catalog"','Gathering tab')
includes(ui,'elseif tab=="Gathering"','Gathering list and action')
includes(ui,'self:PromptCraftQuantity(','craft quantity popup')
includes(ui,'"Import GatherMate2"','read-only import button')
includes(ui,'self.legacyPriorityButton:Show()','tree-specific Legacy UI')
includes(crafting,'requestedQuantity','finished-item quantity support')
includes(companion,'GatheringSync.ps1','Windows gathering synchronization')
includes(companion,'Export Gathering Contribution','Windows opt-in contribution export')
for _,name in ipairs({'ForeverCharacterManager.toc','ForeverCharacterManager_Camelot.toc'}) do
    local manifest=file(addon..name)
    includes(manifest,'## Version: 0.9.1','addon version')
    includes(manifest,'## SavedVariables: FCM_DB, FCM_GatherExport','private storage')
    includes(manifest,'Gathering.lua','gathering module load')
    includes(manifest,'CommunityGathering.generated.lua','community snapshot load')
    includes(manifest,'LegacyAdvisor.lua','Legacy Advisor module load')
end
print('PASS: combined v0.9.1 source wires QA6e, Legacy and Gathering in both toc variants')
