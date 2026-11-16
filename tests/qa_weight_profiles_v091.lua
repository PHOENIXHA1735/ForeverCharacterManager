-- Offline tests for user-supplied Pawn v1 numerical stat profiles.
local function eq(got,expected,why)
    if got~=expected then error((why or "Mismatch")..": expected "..tostring(expected)..", got "..tostring(got),2) end
end
local tests={}
local function test(label,fn) tests[#tests+1]={label,fn} end

local fcm={}
GetBuildInfo=function() return 'Forever synthetic','synthetic-build' end
function fcm:GearActivity(ch) return ch.gearActivity or "leveling" end
function fcm:Mode(ch,act) return (ch.gearStyles and ch.gearStyles[act]) or "dps" end
function fcm:Now() return 1780000000 end
function fcm:Try(fn,...) return fn(...) end
fcm.gearActivityLabels={leveling="Leveling"}
fcm.modeLabels={dps="DPS"}
assert(loadfile("ForeverCharacterManager/Gear.lua"))("ForeverCharacterManager",fcm)
local G=fcm.Gear
local function mage()
    return {name="Frosty",class="MAGE",talentSpec="Frost",level=24,
        gearActivity="leveling",gearStyles={leveling="dps"}}
end
local good='( Pawn: v1: "My Frost Scale": Class=Mage, Spec=Frost, SpellDamage=1, Intellect=0.3, ' ..
    'Spirit=0.15, FrostSpellDamage=1.5, CritRating=0.2, HitRating=0.4, ScaleColor=ff2266 )'

test("Valid Pawn scale parses with named fields and school damage",function()
    local result,reason=G:ParsePawnScale(good)
    assert(result,reason)
    eq(result.class,"Mage")
    eq(result.spec,"Frost")
    eq(result.weights.spell,1)
    eq(result.weights.int,0.3)
    eq(result.weights.spell_frost,1.5)
end)
test("Imported numbers are not multiplied by FCM activity/spec heuristics",function()
    local ch=mage()
    local ok,reason=G:ImportPawnScale(ch,good)
    assert(ok,reason)
    eq(G:Weight("spell",ch),1)
    eq(G:Weight("int",ch),0.3)
    eq(G:Weight("spell_frost",ch),1.5)
    eq(G:Weight("spell_fire",ch),0) -- not a Frost mage's spell school
    eq(G:Weight("stam",ch),0) -- absent stats are zero in a complete import
    assert(G:WeightSource(ch):find("My Frost Scale",1,true))
end)
test("Custom overrides survive import and take precedence",function()
    local ch=mage()
    eq(G:SetCustomWeight(ch,"spell",5),true)
    local ok=G:ImportPawnScale(ch,good)
    eq(ok,true)
    eq(G:Weight("spell",ch),5)
    eq(ch.gearCustomWeights.leveling.spell,5)
end)
test("Other characters and activity/style keep independent default weights",function()
    local ch=mage()
    local other=mage();other.name="Alt"
    G:ImportPawnScale(ch,good)
    eq(G:ActiveWeightProfile(other),nil)
    assert(G:WeightSource(other):find("unavailable",1,true))
    eq(G:ActiveWeightProfile(ch,"balanced","leveling"),nil)
    eq(G:ActiveWeightProfile(ch,"dps","pve"),nil)
end)
test("Spec and level changes disable a scale, preserving it for return",function()
    local ch=mage()
    G:ImportPawnScale(ch,good)
    ch.talentSpec="Fire"
    eq(G:ActiveWeightProfile(ch),nil)
    ch.talentSpec="Frost";ch.level=40
    eq(G:ActiveWeightProfile(ch),nil)
    ch.level=24
    assert(G:ActiveWeightProfile(ch))
end)
test("Invalid class cannot replace existing import",function()
    local ch=mage()
    G:ImportPawnScale(ch,good)
    local ok=G:ImportPawnScale(ch,good:gsub("Class=Mage","Class=Warlock"))
    eq(ok,false)
    eq(#ch.gearImportedWeightProfiles,1)
end)
test("Unscanned nonzero attributes reject entire scale",function()
    local ch=mage()
    local ok,why=G:ImportPawnScale(ch,
        '( Pawn: v1: "Bad": Class=Mage, Spec=Frost, SpellDamage=1, MasteryRating=2 )')
    eq(ok,false)
    assert(why:find("MasteryRating",1,true))
    eq(ch.gearImportedWeightProfiles,nil)
end)
test("Code-like malformed values are rejected and never evaluated",function()
    local parsed=G:ParsePawnScale('( Pawn: v1: "Bad": SpellDamage=os.execute("date") )')
    eq(parsed,nil)
end)
test("Duplicate conflicting aliases cannot silently overwrite values",function()
    local parsed,reason=G:ParsePawnScale('( Pawn: v1: "Bad": SpellPower=1, SpellDamage=2 )')
    eq(parsed,nil)
    assert(reason:find("Conflicting",1,true))
end)
test("Imported profile reset keeps character data and custom settings",function()
    local ch=mage()
    ch.gear={chest="item:1"}
    G:SetCustomWeight(ch,"spell",3)
    G:ImportPawnScale(ch,good)
    eq(G:ResetImportedWeightProfile(ch),true)
    eq(G:ActiveWeightProfile(ch),nil)
    eq(ch.gear.chest,"item:1")
    eq(ch.gearCustomWeights.leveling.spell,3)
end)
test("Hit-rating cap applies to a swap delta only, and never assumes percentages",function()
    local ch=mage()
    G:ImportPawnScale(ch,good)
    eq(G:SetManualHitRating(ch,12,15),true)
    local capped,raw=G:CappedHitImpact(ch,{hit=1},{hit=7},"dps","leveling")
    assert(math.abs(raw-2.4)<0.000001) -- 6 rating at 0.4 each
    local expected=3*0.4 -- only 3 rating points remain before cap
    assert(math.abs(capped-expected)<0.000001)
    local drop=G:CappedHitImpact(ch,{hit=5},{hit=0},"dps","leveling")
    eq(drop,-2)
end)
test("Manual hit-rating snapshot stops applying at a new level/spec/activity",function()
    local ch=mage()
    G:SetManualHitRating(ch,10,15)
    assert(G:HitRatingContext(ch))
    ch.level=25;eq(G:HitRatingContext(ch),nil)
    ch.level=24;ch.talentSpec="Fire";eq(G:HitRatingContext(ch),nil)
    ch.talentSpec="Frost";eq(G:HitRatingContext(ch,"pve"),nil)
end)
test("Comparison explains percent as item stat score, never DPS improvement",function()
    local lines=G:ComparisonLines({status="ok",oldName="Old Chest",delta=1.4,
        scorePct=22.1,changes={},oldStats={},newStats={},
        activity="leveling",style="dps",reason="test",weightSource="Pawn user import"})
    local all=table.concat(lines,"\n")
    assert(all:find("NOT an upgrade percentage",1,true))
    assert(all:find("predicted DPS",1,true))
    assert(all:find("Weight source:",1,true))
end)

local count=0
for _,entry in ipairs(tests) do
    local ok,err=pcall(entry[2])
    if not ok then error("FAILED: "..entry[1].."\n"..tostring(err)) end
    count=count+1
end
print("PASS: "..count.." Pawn import, provenance and isolation QA tests")
