-- Offline verification of the user-recorded Zygor Frost Mage Item Score scale.
local function eq(actual, expected, why)
    if actual ~= expected then
        error((why or "Mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end
local function approx(actual, expected, why)
    if type(actual)~="number" or math.abs(actual-expected)>0.000001 then
        error((why or "Mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end
local tests={}
local function test(label,fn) tests[#tests+1]={label,fn} end
local fcm={}
function fcm:GearActivity(ch) return ch.gearActivity or "leveling" end
function fcm:Mode(ch,act) return (ch.gearStyles and ch.gearStyles[act]) or "dps" end
function fcm:Now() return 1780000000 end
function fcm:Try(fn,...) return fn(...) end
fcm.gearActivityOrder={"leveling","pvp","pve"}
fcm.gearActivityLabels={leveling="Leveling",pvp="PvP",pve="Endgame PvE"}
fcm.modeLabels={dps="DPS",balanced="Balanced",survival="Survivability"}
assert(loadfile("ForeverCharacterManager/Gear.lua"))("ForeverCharacterManager",fcm)
local G=fcm.Gear
local function frost()
    return {name="Frosty Bit",class="MAGE",talentSpec="Frost",level=24,
        gearActivity="leveling",gearStyles={leveling="dps",pve="dps",pvp="survival"}}
end

test("All nonzero recorded Zygor Frost values are represented",function()
    local expected={
        agi=0.05,int=0.87,spi=0.06,stam=0.5,armor=0.005,
        spell_crit_pct=0.58,def=0.05,haste=0.63,
        health_regen=1,health=0.05,spell_hit_pct=1.22,
        mana=0.032,mp5=0.8,spell=1,spell_pen=0.07,
        spell_fire=0.05,spell_frost=0.95,spell_arcane=0.13,resist=0.04,
    }
    local seen=0
    for stat,val in pairs(expected) do
        approx(G:Weight(stat,frost()),val,stat)
        seen=seen+1
    end
    eq(seen,19)
    -- Spell percentages must NOT be treated as spell hit/crit rating points.
    eq(G:Weight("hit",frost()),0)
    eq(G:Weight("crit",frost()),0)
end)
test("Preset applies to Frost DPS leveling and PvE, without changing other builds",function()
    local ch=frost()
    assert(G:WeightSource(ch):find("Zygor Frost Mage",1,true))
    approx(G:Weight("int",ch,"dps","pve"),0.87)
    assert(G:Weight("int",ch,"balanced","leveling")~=0.87)
    assert(not G:WeightSource(ch,"survival","pvp"):find("Zygor",1,true))
    ch.talentSpec="Fire"
    assert(not G:WeightSource(ch):find("Zygor",1,true))
    ch.talentSpec="Arcane"
    assert(not G:WeightSource(ch):find("Zygor",1,true))
    ch.talentSpec="Frost";ch.class="PRIEST"
    assert(not G:WeightSource(ch):find("Zygor",1,true))
end)
test("Zygor explicitly values Frost Mage off-school spell damage",function()
    approx(G:Weight("spell_frost",frost()),0.95)
    approx(G:Weight("spell_fire",frost()),0.05)
    approx(G:Weight("spell_arcane",frost()),0.13)
    eq(G:Weight("spell_shadow",frost()),0)
end)
test("Spell hit/crit percent is separate from rating and school tooltip damage",function()
    C_Item={
        GetItemStats=function()
            return {ITEM_MOD_INTELLECT_SHORT=2,
                ITEM_MOD_SPELL_HIT_RATING_SHORT=15,
                ITEM_MOD_SPELL_CRIT_RATING_SHORT=11,
                ITEM_MOD_SPELL_DAMAGE_DONE_SHORT=10}
        end,
    }
    C_TooltipInfo={
        GetHyperlink=function()
            return {lines={
                {leftText="Equip: Increases your chance to hit with spells by 1%."},
                {leftText="Equip: Increases your chance to get a critical strike with spells by 2%."},
                {leftText="Equip: Increases damage done by Frost spells and effects by up to 10."},
            }}
        end,
    }
    local stats=G:StatValues("item:1234")
    eq(stats.hit,15)
    eq(stats.crit,11)
    eq(stats.spell_hit_pct,1)
    eq(stats.spell_crit_pct,2)
    eq(stats.spell_frost,10)
    eq(stats.spell,nil)
    local score=G:Score("item:1234",frost())
    approx(score,2*0.87+1.22+2*0.58+10*0.95)
    C_Item=nil
    C_TooltipInfo=nil
end)
test("A rating-only item does not inherit Zygor percentage-point weights",function()
    C_Item={GetItemStats=function()
        return {ITEM_MOD_HIT_RATING_SHORT=15,ITEM_MOD_CRIT_RATING_SHORT=11}
    end}
    C_TooltipInfo=nil
    local score=G:Score("item:rating",frost())
    approx(score,0)
    C_Item=nil
end)
test("A user Pawn profile still takes precedence, custom overrides are retained",function()
    local ch=frost()
    local ok,why=G:ImportPawnScale(ch,
        '( Pawn: v1: "Custom Frost": Class=Mage, Spec=Frost, SpellDamage=2, Intellect=0.25 )')
    assert(ok,why)
    approx(G:Weight("spell",ch),2)
    approx(G:Weight("int",ch),0.25)
    assert(G:WeightSource(ch):find("Pawn user import",1,true))
    G:SetCustomWeight(ch,"spell",3)
    approx(G:Weight("spell",ch),3)
    G:ResetImportedWeightProfile(ch)
    approx(G:Weight("spell",ch),3)
    approx(G:Weight("int",ch),0.87)
    assert(G:WeightSource(ch):find("Zygor Frost Mage",1,true))
end)

for _,entry in ipairs(tests) do
    local ok,err=pcall(entry[2])
    if not ok then error("FAILED: "..entry[1].."\n"..tostring(err)) end
end
print("PASS: "..#tests.." Zygor Frost Mage numerical-weight tests")
