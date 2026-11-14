-- Offline QA for the two-stage Legacy tree + goal recommendation engine.
local fcm={}
function fcm:Now() return 1780000000 end
function fcm:Characters() return self.chars or {} end
assert(loadfile("ForeverCharacterManager/Progression.lua"))("ForeverCharacterManager",fcm)
assert(loadfile("ForeverCharacterManager/LegacyAdvisor.lua"))("ForeverCharacterManager",fcm)
local tests={}
local function test(name,fn) tests[#tests+1]={name,fn} end
local function eq(a,b,label)
    if a~=b then error((label or "Mismatch")..": "..tostring(a).." ~= "..tostring(b),2) end
end
local function mage()
    return {name="Frosty Bit",class="MAGE",talentSpec="Frost",level=25,
        legacyAvailable=1,gearActivity="pve",gearStyles={pve="dps"},
        professions={Cooking={name="Cooking",skill=60,maxSkill=75},
            Fishing={name="Fishing",skill=121,maxSkill=150}}}
end
test("Tree-specific priority choices and three real tree names",function()
    eq(#fcm.legacyPriorityOrder,11)
    eq(#fcm.legacyTreeOrder,4)
    eq(fcm.legacyTreeLabels.Professions,"Professions")
    eq(fcm.legacyTreeLabels.Resourcefulness,"Resourcefulness")
    eq(fcm.legacyPriorityLabels.skills,"Skill-Ups")
    eq(table.concat(fcm:LegacyPriorityChoices("Adventure"),","),
        "leveling,travel,survival,balanced")
    eq(table.concat(fcm:LegacyPriorityChoices("Professions"),","),
        "skills,gathering,crafting,gold,balanced")
    eq(table.concat(fcm:LegacyPriorityChoices("Resourcefulness"),","),
        "pve,pvp,reputation,gold,balanced")
    eq(#fcm:LegacyPriorityChoices("all"),11)
    local ch=mage()
    eq(fcm:LegacyTree(ch),"all")
    eq(fcm:LegacyPriority(ch),"leveling")
    eq(ch.legacyTree,nil)
    eq(ch.legacyPriority,nil)
    eq(fcm:SetLegacyTree(ch,"Adventure"),true)
    eq(fcm:SetLegacyPriority(ch,"travel"),true)
    eq(fcm:LegacyTree(ch),"Adventure")
    eq(fcm:LegacyPriority(ch),"travel")
    assert(not fcm:SetLegacyPriority(ch,"gathering"),"Adventure excludes gathering")
    eq(ch.gearActivity,"pve","gear settings remain independent")
    assert(not fcm:SetLegacyTree(ch,"Unknown"))
    assert(not fcm:SetLegacyPriority(ch,"raidboss"))
end)
test("Switching trees remembers a distinct goal for each toon and tree",function()
    local a,b=mage(),mage()
    b.name="Spotty Dotty";b.class="PRIEST"
    fcm:SetLegacyTree(a,"Adventure")
    fcm:SetLegacyPriority(a,"survival")
    fcm:SetLegacyTree(a,"Professions")
    eq(fcm:LegacyPriority(a),"skills","Professions default")
    fcm:SetLegacyPriority(a,"crafting")
    fcm:SetLegacyTree(a,"Resourcefulness")
    eq(fcm:LegacyPriority(a),"pve","Resourcefulness default")
    fcm:SetLegacyPriority(a,"reputation")
    eq(fcm:LegacyRecommendations(a,nil,nil,1)[1].perk.id,"diplomat")
    fcm:SetLegacyTree(a,"Adventure")
    eq(fcm:LegacyPriority(a),"survival")
    fcm:SetLegacyTree(a,"Professions")
    eq(fcm:LegacyPriority(a),"crafting")
    fcm:SetLegacyTree(a,"Resourcefulness")
    eq(fcm:LegacyPriority(a),"reputation")
    eq(fcm:LegacyPriority(b),"leveling")
    eq(b.legacyPriorities,nil)
end)
test("Old QA6b choice is preserved before first tree switch",function()
    local ch=mage()
    ch.legacyTree="Professions"
    ch.legacyPriority="gathering"
    eq(fcm:LegacyPriority(ch),"gathering")
    fcm:SetLegacyTree(ch,"Adventure")
    eq(fcm:LegacyPriority(ch),"leveling")
    fcm:SetLegacyPriority(ch,"survival")
    fcm:SetLegacyTree(ch,"Professions")
    eq(fcm:LegacyPriority(ch),"gathering")
end)
test("Every visible goal is relevant to its tree and key new goals rank sensibly",function()
    local ch=mage()
    for _,tree in ipairs(fcm.legacyTreeOrder) do
        for _,goal in ipairs(fcm:LegacyPriorityChoices(tree)) do
            local picks=fcm:LegacyRecommendations(ch,tree,goal,1)
            assert(#picks==1,"No matching perk for "..tree.." / "..goal)
        end
    end
    eq(fcm:LegacyRecommendations(ch,"Adventure","travel",1)[1].perk.id,"frequent-flier")
    eq(fcm:LegacyRecommendations(ch,"Adventure","survival",1)[1].perk.id,"thrill-of-adventure")
    eq(fcm:LegacyRecommendations(ch,"Professions","crafting",1)[1].perk.id,"master-chef")
    eq(fcm:LegacyRecommendations(ch,"Resourcefulness","reputation",1)[1].perk.id,"diplomat")
    eq(fcm:LegacyRecommendations(ch,"Resourcefulness","gold",1)[1].perk.id,"reagent-economy")
    eq(fcm:LegacyPriorityLabel("Resourcefulness","gold"),"Cost Savings")
end)
test("Frosty level 25 receives a real explanation, not an automatic purchase",function()
    local ch=mage()
    local picks=fcm:LegacyRecommendations(ch,"Adventure","leveling",3)
    eq(#picks,3)
    eq(picks[1].perk.id,"thrill-of-adventure")
    eq(picks[1].nextRank,1)
    eq(picks[1].access,"unknown")
    eq(picks[1].recordedRank,false)
    assert(type(picks[1].reason)=="string" and #picks[1].reason>10)
    eq(ch.legacyRanks,nil)
    eq(ch.legacyAvailable,1)
end)
test("Changing trees filters recommendations to the chosen in-game tree",function()
    local ch=mage()
    for _,tree in ipairs({"Adventure","Professions","Resourcefulness"}) do
        local picks=fcm:LegacyRecommendations(ch,tree,"balanced")
        assert(#picks>0)
        for _,pick in ipairs(picks) do eq(pick.tree,tree) end
    end
    eq(fcm:LegacyRecommendations(ch,"Professions","gold",1)[1].perk.id,"bartering")
    eq(fcm:LegacyRecommendations(ch,"Resourcefulness","pvp",1)[1].perk.id,"for-great-honor")
    eq(fcm:LegacyRecommendations(ch,"Professions","skills",1)[1].perk.id,"working-overtime")
    eq(fcm:LegacyRecommendations(ch,"Professions","gathering",1)[1].perk.id,"luremaster")
end)
test("A goal-tree mismatch does not suggest unrelated perks",function()
    local ch=mage()
    local picks=fcm:LegacyRecommendations(ch,"Resourcefulness","gathering",3)
    eq(#picks,0,"Resourcefulness has no directly applicable gathering perk")
    local trees=fcm:LegacyMatchingTrees("gathering")
    eq(table.concat(trees,","),"Adventure,Professions")
    for _,candidate in ipairs(fcm:LegacyRecommendations(ch,"all","gathering")) do
        assert(candidate.perk.id~="reagent-economy")
        assert(candidate.perk.id~="for-great-honor")
    end
end)
test("Available nodes outrank unverified; confirmed locked are excluded",function()
    local ch=mage()
    eq(fcm:SetLegacyAccess(ch,"Frequent Flier","available"),true)
    local picks=fcm:LegacyRecommendations(ch,"Adventure","leveling")
    eq(picks[1].perk.id,"frequent-flier")
    eq(picks[1].access,"available")
    eq(fcm:SetLegacyAccess(ch,"Frequent Flier","locked"),true)
    for _,pick in ipairs(fcm:LegacyRecommendations(ch,"Adventure","leveling")) do
        assert(pick.perk.id~="frequent-flier")
    end
    eq(fcm:SetLegacyAccess(ch,"Frequent Flier","unknown"),true)
    eq(ch.legacyAccess["frequent-flier"],nil)
    assert(not fcm:SetLegacyAccess(ch,"Frequent Flier","foo"))
end)
test("Recorded ranks adjust the next recommendation and cap excludes maxed perks",function()
    local ch=mage()
    local ok,why=fcm:SetLegacyRank(ch,"Thrill of Adventure",1)
    assert(ok,why)
    local picks=fcm:LegacyRecommendations(ch,"Adventure","leveling")
    local found
    for _,pick in ipairs(picks) do if pick.perk.id=="thrill-of-adventure" then found=pick end end
    assert(found)
    eq(found.nextRank,2)
    eq(found.recordedRank,true)
    ok=fcm:SetLegacyRank(ch,"Thrill of Adventure",5)
    eq(ok,true)
    for _,pick in ipairs(fcm:LegacyRecommendations(ch,"Adventure","leveling")) do
        assert(pick.perk.id~="thrill-of-adventure")
    end
end)
test("Two characters preserve independent tree, goal, ranks and point snapshots",function()
    local a,b=mage(),mage()
    b.name="Spotty Dotty";b.class="PRIEST";b.legacyAvailable=0
    fcm:SetLegacyTree(a,"Professions")
    fcm:SetLegacyPriority(a,"gold")
    fcm:SetLegacyRank(a,"Bartering",1)
    eq(fcm:LegacyPriority(b),"leveling")
    eq(fcm:LegacyTree(b),"all")
    eq(fcm:LegacySpent(b),0)
    eq(b.legacyAvailable,0)
    eq(a.legacyAvailable,1)
    local picks=fcm:LegacyRecommendations(a,nil,nil,1)
    eq(#picks,1)
    eq(picks[1].tree,"Professions")
    eq(picks[1].priority,"gold")
end)
test("Full 16-point recorded allocation stops suggesting purchases",function()
    local ch=mage()
    local targets={{"Working Overtime",5},{"Thrill of Adventure",5},
        {"Bountiful Harvest",5},{"Talented",1}}
    for _,entry in ipairs(targets) do
        local ok,why=fcm:SetLegacyRank(ch,entry[1],entry[2])
        assert(ok,why)
    end
    eq(fcm:LegacySpent(ch),16)
    eq(#fcm:LegacyRecommendations(ch,"all","balanced"),0)
    eq(ch.legacyAvailable,1,"never rewrite a manually recorded available snapshot")
end)
test("Reference UI and slash-command controls are wired",function()
    local file=assert(io.open("ForeverCharacterManager/UI.lua","r"))
    local ui=file:read("*a");file:close()
    assert(ui:find("ShowLegacyTreeMenu",1,true))
    assert(ui:find("ShowLegacyPriorityMenu",1,true))
    assert(ui:find("LegacyRecommendations",1,true))
    local core=assert(io.open("ForeverCharacterManager/Core.lua","r"))
    local text=core:read("*a");core:close()
    assert(text:find('cmd == "legacypriority"',1,true))
    assert(text:find('cmd == "legacytree"',1,true))
    assert(text:find('cmd == "legacyaccess"',1,true))
end)
for _,entry in ipairs(tests) do
    local ok,why=pcall(entry[2])
    if not ok then error("FAIL: "..entry[1].."\n"..tostring(why)) end
end
print("PASS: "..#tests.." tree/goal Legacy advisor tests")
