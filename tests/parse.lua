local directory = 'ForeverCharacterManager/'
local files={'Advisor.lua','BoEProtection.lua','Core.lua','Crafting.lua','Diagnostics.lua','DungeonCatalog.lua','ExternalData.lua','FCM-Companion/ExternalData.generated.template.lua','FarmingAdvisor.lua','Gear.lua','ItemCatalog.lua','ItemDecisions.lua','Planner.lua','Progression.lua','RecipeCatalog.lua','Scan.lua','SmartCrafting.lua','TalentAudit.lua','TalentData.lua','Talents.lua','Tooltips.lua','UI.lua','UpgradeIntelligence.lua'}
for _,name in ipairs(files) do local fn,err=loadfile(directory..name); if not fn then error(name..": "..tostring(err)) end end
print("PASS: Lua syntax parsed: "..#files.." addon and companion Lua files")
