-- Gold Finder: strict sources, professions, faction prices, recipe knowledge,
-- vendor costs, no stale snapshots, and honest market-wide potential.
local market="forever.normal.alliance.us"
local now=os.time()
local prices={
    [6522]={median=300,minBuyout=250,quantity=200,soldPerDay=25,market=market,updated=now},
    [13889]={median=1800,quantity=10,soldPerDay=5,market=market,updated=now},
    [1001]={median=400,minBuyout=250,quantity=200,soldPerDay=40,market=market,updated=now},
    [1002]={median=600,quantity=100,soldPerDay=10,market=market,updated=now},
    [1003]={median=500,quantity=100,soldPerDay=10,market=market,updated=now},
    [1004]={median=900,quantity=100,soldPerDay=10,market=market,updated=now},
    [1005]={median=700,quantity=100,soldPerDay=10,market=market,updated=now,snapshot=true},
    [1006]={median=900,quantity=100,soldPerDay=0,market=market,updated=now},
    [2001]={median=1000,quantity=60,soldPerDay=12,market=market,updated=now},
    [2002]={median=300,quantity=60,soldPerDay=12,market=market,updated=now},
    [2003]={median=200,quantity=20,soldPerDay=3,market=market,updated=now},
}
local FCM={externalData={items={
    [6522]={name="Deviate Fish"},[13889]={name="Raw Whitescale Salmon"},
    [1001]={name="Appropriate Bear Meat",farmSources={{kind="mob",name="Bear",zone="Ashenvale",levelMin=20,levelMax=30}}},
    [1002]={name="Too-high Farming",farmSources={{kind="mob",name="Danger",levelMin=44,levelMax=50}}},
    [1003]={name="Unknown-source-level Meat",farmSources={{kind="mob",name="Unknown mob",zone="Ashenvale"}}},
    [1004]={name="Needs Mining Skill",farmSources={{kind="mining",zone="Feralas",skillRequired=175,levelMin=20,levelMax=30}}},
    [1005]={name="Bundled Snapshot Herb",farmSources={{kind="herbalism",zone="Westfall",skillRequired=1,levelMin=10,levelMax=30}}},
    [1006]={name="Not Selling Meat",farmSources={{kind="mob",name="Bear",zone="Ashenvale",levelMin=20,levelMax=30}}},
    [2001]={name="Cooked Fish"},[2002]={name="Raw Fish"},[2003]={name="Wrong Faction"},
},recipes={}},db={settings={}}}
function FCM:PriceQuote(id,ch)
    assert(ch and ch.faction=="Alliance","Prices must be character-specific")
    local p=prices[id]
    if p and p.market==market then return {median=p.median,minBuyout=p.minBuyout,quantity=p.quantity,
        soldPerDay=p.soldPerDay,market=p.market,snapshot=p.snapshot,observedAt=p.updated} end
    return nil
end
function FCM:MoneyLabel(n) return string.format("%dc",math.floor((n or 0)+0.5)) end
function FCM:TimestampLabel(ts) return tostring(ts or "unknown") end
assert(loadfile("ForeverCharacterManager/GoldOpportunities.lua"))("ForeverCharacterManager",FCM)
local ch={name="Fisher",faction="Alliance",level=25,
    professions={Fishing={name="Fishing",skill=75},Cooking={name="Cooking",skill=200},
        Herbalism={name="Herbalism",skill=1}},
    recipes={
        [21]={id=21,name="Cooked Fish",learned=true,profession="Cooking",outputID=2001,
            requiredSkill=100,reagents={{itemID=2002,count=2},{itemID=2692,count=1}},quantity=1,complex=false},
        [22]={id=22,name="Not Learned",learned=false,profession="Cooking",outputID=2003,
            reagents={{itemID=2692,count=1}},quantity=1,complex=false},
        [23]={id=23,name="Complex",learned=true,profession="Cooking",outputID=2003,
            reagents={{itemID=2692,count=1}},quantity=1,complex=true},
        [24]={id=24,name="Unpriced",learned=true,profession="Cooking",outputID=2003,
            reagents={{itemID=999999,count=1}},quantity=1,complex=false},
    }}
local list=FCM:GoldOpportunities(ch,"all")
local found={}
for _,row in ipairs(list) do found[row.itemID]=row end
assert(found[6522] and found[6522].kind=="fish","Deviate Fish available at Fishing 75")
assert(not found[13889],"Feralas salmon is beyond level 25 / Fishing 75")
assert(found[1001] and found[1001].kind=="farm","level-appropriate mob")
assert(not found[1002],"high-level mobs excluded")
assert(found[1003] and not found[1003].sourceVerifiedLevel,"unknown level flagged, not invented")
assert(not found[1004],"missing Mining profession excluded")
assert(not found[1005],"bundled price snapshot excluded")
assert(not found[1006],"items with reported zero sales do not appear as current selling opportunities")
assert(found[2001] and found[2001].kind=="cook","learned recipe appears")
assert(math.abs(found[2001].profitCraft-310)<0.01,"5% cut and regular 40c vendor spices")
assert(found[2001].marketCeiling==3720,"profit per item times market-wide daily units")
assert(not found[2003],"unlearned/complex/unpriced recipes excluded")
local lines=FCM:GoldOpportunityLines(found[2001],ch)
assert(lines:find("theoretical",1,true),"whole-market disclaimer")
assert(lines:find("vendor baseline",1,true),"spice provenance shown")
assert(FCM:GoldOpportunityLines(found[1001],ch):find("NOT profit/hour",1,true),
    "farm sale potential must not be mislabeled as gold per hour")
assert(#FCM:GoldOpportunities(ch,"cook")==1,"Cooking filter")
assert(#FCM:GoldOpportunities(ch,"fish")==1,"Fishing filter")
ch.level=50;ch.professions.Fishing.skill=205
local second=FCM:GoldOpportunities(ch,"fish")
local salmon=false
for _,row in ipairs(second) do if row.itemID==13889 then salmon=true end end
assert(salmon,"Feralas salmon unlocks at level 50 / Fishing 205")
ch.professions.Fishing.skill=0
assert(#FCM:GoldOpportunities(ch,"fish")==0,"No fishing skill -> no false fishing recommendations")
ch.bags={
    ["0:1"]={itemID=1001,count=2,bound=false,name="Appropriate Bear Meat"},
    ["0:2"]={itemID=1001,count=1,bound=nil,name="Appropriate Bear Meat"},
    ["0:3"]={itemID=1002,count=4,bound=true,name="Too-high Farming"},
    ["0:4"]={itemID=1005,count=2,bound=false,name="Bundled Snapshot Herb"},
    ["0:5"]={itemID=9000,count=3,bound=false,name="Unpriced Rabbit"},
}
local bag=FCM:BagSaleEstimate(ch)
assert(bag.confirmedNet==760,"only confirmed unbound items valued at median less 5%")
assert(bag.confirmedLowNet==475,"lowest buyout also estimates after 5% fee")
assert(bag.uncertainNet==380,"unknown binding separate and not presumed saleable")
assert(bag.bound==4 and bag.unknownBinding==1,"bound/unknown counts preserved")
assert(bag.unpriced==5,"never value bundled snapshots or missing quotes")
assert(#bag.rows==1,"bound-only records do not clutter sale candidates")
assert(FCM:BagSaleEstimateLines(bag.rows[1],ch):find("/ahl scan",1,true),
    "instructions to check the AH before posting")
prices[1001].updated=now-4*3600
local stale=FCM:BagSaleEstimate(ch)
assert(stale.confirmedNet==0 and stale.uncertainNet==0,
    "four-hour-old market observations must not be presented as current sale estimates")
prices[1001].updated=now
assert(FCM.db.settings.goldView==nil,"price results never persist in character saves")
print("PASS: Gold Finder opportunities, skills, provenance, and bag sale estimates")
