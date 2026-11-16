-- Focused regression: learned != currently skilled enough to craft.
-- No WoW API or SavedVariables files are used by this fixture.
local function eq(a,b,label)
    assert(a==b,(label or "mismatch")..": expected "..tostring(b)..", got "..tostring(a))
end
local recipe={id=4501,name="Test Linen Vest",outputID=5501,quantity=1,
    profession="Tailoring",learned=true,requiredSkill=65,complex=false,
    reagents={{itemID=6001,count=2}}}
local function crafter(key,skill)
    return {key=key,name=key,faction="Alliance",ruleset="Normal",region="US",
        recipes={[4501]=recipe},professions={Tailoring={skill=skill}},
        bags={cloth={itemID=6001,count=2,bound=false}},bank={}}
end
local low=crafter("Frosty",61)
local high=crafter("Tator",75)
local unknown=crafter("Unscanned",nil)
local recipient={key="Spotty",name="Spotty",faction="Alliance",
    ruleset="Normal",region="US",recipes={},bags={},bank={}}
local fcm={db={characters={Frosty=low,Tator=high,Unscanned=unknown,Spotty=recipient},
    craftingQueue={},settings={}},currentKey="Frosty"}
function fcm:Characters()return {low,high,unknown,recipient}end
function fcm:CanCollaborate(a,b)
    return a and b and a.faction==b.faction and a.ruleset==b.ruleset and a.region==b.region
end
function fcm:DisplayCharacter(ch)return ch and ch.name or "Unknown"end
function fcm:Try(fn,...)if fn then return fn(...)end end
function fcm:Now()return 12345 end
function fcm:Refresh()end
function fcm:IsPendingRequest(req)return req and req.status=="requested" end
function fcm.ItemName(id)return "Item #"..id end
assert(loadfile("ForeverCharacterManager/Crafting.lua"))("ForeverCharacterManager",fcm)
assert(loadfile("ForeverCharacterManager/Advisor.lua"))("ForeverCharacterManager",fcm)
assert(loadfile("ForeverCharacterManager/SmartCrafting.lua"))("ForeverCharacterManager",fcm)
local merged=fcm:AllRecipes()[1]
eq(merged.requiredSkill,65,"aggregated recipes preserve requirements")
eq(fcm:RecipeSkillStatus(merged,low),"blocked","61 below 65")
eq(fcm:RecipeSkillStatus(merged,high),"ready","75 meets 65")
eq(fcm:RecipeSkillStatus(merged,unknown),"verify","missing skill scan not proof")
local choices=fcm:EligibleCraftCrafters(merged,recipient)
eq(#choices,2,"low skill not listed; verified plus unverified are possible")
eq(fcm:QueueCraft(4501,"Spotty",nil,1,"additional"),true)
local req=fcm.db.craftingQueue[1]
eq(#fcm:RequestEligibleCrafters(req,merged),2,"request excludes known low skill")
eq(fcm:CanCraftRequest(req,low,merged),false,"low skill cannot fulfill request")
eq(fcm:CanCraftRequest(req,high,merged),true,"qualified crafter can fulfill")
local availability=fcm:CraftAvailability(merged,low,nil,1)
eq(availability.ready,false,"materials alone cannot clear a skill blocker")
eq(availability.skillStatus,"blocked","skill blocker visible in availability")
local plan=fcm:SmartCraftingPlan(merged,recipient,low,1)
eq(plan.ready,false,"never select insufficient-skilled preferred crafter")
assert(#plan.blockers>0,"blocked smart plan explains ineligibility")
print("PASS: learned skill gates, provenance, verified/unverified states and craft planning")
