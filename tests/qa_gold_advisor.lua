local FCM={db={settings={}},Gear={}}
function FCM:NormalizeRuleset(x) return x end
function FCM:NormalizeFaction(x) return (x=='Alliance' or x=='Horde') and x or nil end
function FCM.Gear:Info(id) return {bindType=id==999 and 1 or 2} end
function FCM:AllRecipes() return {} end
function FCM.ItemName(id) return 'Synthetic '..tostring(id) end
local clock=1800000000
time=function() return clock end
assert(loadfile('ForeverCharacterManager/GoldAdvisor.lua'))('FCM',FCM)
local G=FCM.GoldAdvisor
assert(G:ConfigureFees('5 100') and FCM.db.settings.goldAdvisorFees.deposit==100,'fee controls')
assert(not G:ConfigureFees('100 0'),'invalid fee controls')
assert(G:ConfigureFarm('1|Herbalism|20|1000|100'),'farm controls')
local ch={ruleset='Normal',faction='Alliance',region='us',bags={},bank={},recipes={},professions={Alchemy={}}}
local function quote(low)
    return {current=low,low=low,stamp=time(),days=60,observations=120,demand=5,supply=10,volatility=.1,trend=5,confidence='moderate',averages={[365]=1000,[30]=1000},coverage={[30]=20}}
end
local buy=G:Item(1,quote(700),ch)
assert(buy.action=='BUY NOW' and buy.profit==250,'buy estimate')
ch.bags={{itemID=1,count=2,bound=false}}
assert(G:Item(1,quote(1500),ch).action=='SELL NOW','sell eligibility')
assert(G:Item(1,quote(800),ch).action=='HOLD','hold')
ch.bags[1].bound=true
assert(G:Item(1,quote(1500),ch).action=='NO CLEAR RECOMMENDATION','bound ownership')
local stale=quote(700);stale.stamp=time()-90000
assert(G:Item(1,stale,ch).action=='NO CLEAR RECOMMENDATION','freshness')
local sparse=quote(700);sparse.days=2
assert(G:Item(1,sparse,ch).action=='NO CLEAR RECOMMENDATION','coverage')
local noDemand=quote(700);noDemand.demand=nil
assert(G:Item(1,noDemand,ch).action=='NO CLEAR RECOMMENDATION','unknown demand')
local prices={[1]=quote(2000),[2]=quote(200)}
local recipe={id=11,outputID=1,quantity=1,profession='Alchemy',reagents={{itemID=2,count=2}}}
ch.recipes[11]={learned=true}
ch.bags={{itemID=2,count=2,bound=false}}
local craft=G:Craft(recipe,ch,prices,{cut=.05,deposit=50})
assert(craft.action=='CRAFT' and craft.profit==1450 and craft.materialCost==400,'owned material opportunity cost and fees')
ch.bags={}
local mats=G:Craft(recipe,ch,prices,{cut=.05,deposit=50})
assert(mats.action=='BUY MATERIALS' and mats.profit==1450,'buy cheap mats')
assert(G:Craft(recipe,ch,prices,{}).action=='NO CLEAR RECOMMENDATION','missing fees')
prices[2].low=2000
assert(G:Craft(recipe,ch,prices,{cut=.05,deposit=50}).action=='NO CLEAR RECOMMENDATION','unprofitable craft')
recipe.outputID=999;prices[999]=quote(2000)
assert(G:Craft(recipe,ch,prices,{cut=.05,deposit=50}).action=='NO CLEAR RECOMMENDATION','bop output')
recipe.outputID=1;ch.recipes={}
assert(G:Craft(recipe,ch,prices,{cut=.05,deposit=50}).action=='NO CLEAR RECOMMENDATION','unlearned')
ch.professions.Herbalism={}
local farm=G:Farm(1,quote(1000),ch,{profession='Herbalism',unitsPerHour=20,alternativeGoldPerHour=1000,depositPerHour=100})
assert(farm.action=='FARM' and farm.profit==17900,'farming net opportunity cost')
assert(G:Farm(1,quote(1000),ch,{}).action=='NO CLEAR RECOMMENDATION','unknown effort')
FCM_AHHistory={schema=1,generatedUtc=time(),timezone='America/Los_Angeles',packed={['forever/normal/alliance/us']='1,700,1800000000,650,4,2,800,900,1000,1000,1000,7,14,14,14,14,500,1500,-30,14,40,0.1,5,2'},timing={}}
assert(G:Prices(ch)[1].current==700,'compact summary decode')
local apiCalls=0
local live={median=800,minBuyout=750,quantity=12,soldPerDay=8,market='forever/normal/alliance/us',updated=clock,snapshot=false}
local tableInfo={market='forever/normal/alliance/us',updated=clock,snapshot=false}
AHledgerAPI={GetPrice=function(id,market)
    apiCalls=apiCalls+1
    assert(id==1 and market=='forever/normal/alliance/us','explicit market isolation')
    return live
end,GetTableInfo=function(market)
    assert(market=='forever/normal/alliance/us','table market isolation')
    return tableInfo
end}
local current=G:Prices(ch)[1]
assert(current.current==800 and current.low==750 and current.supply==12 and current.demand==8,'fresh API quote overlays archived current price')
assert(current.averages[365]==1000 and current.days==14 and current.observations==40,'live quote never changes historical statistics')
assert(math.abs(current.comparison+20)<.001 and current.currentSource=='AHledger live','live comparison and source label')
assert(G:Details(G:Item(1,current,ch),ch):find('LIVE AHledger quote',1,true),'fresh source visible in details')
assert(G:Details(G:Item(1,current,ch),ch):find('Price updated (local):',1,true),'quote timestamp displayed')
assert(G:Prices(ch)[1].current==800 and apiCalls==1,'live lookups cached briefly')
clock=clock+31
live.median=810;live.minBuyout=760;live.updated=clock
assert(G:Prices(ch)[1].current==810 and apiCalls==2,'live cache expires to pick up fresh quote')
clock=clock+31
tableInfo.updated=clock-8*86400
live.updated=clock
local oldDemand=G:Prices(ch)[1]
assert(oldDemand.current==810 and oldDemand.demand==2,'fresh personal scan cannot refresh old provider sales pace')
clock=clock+31
tableInfo.updated=clock;tableInfo.snapshot=true;live.updated=clock
assert(G:Prices(ch)[1].demand==2,'bundled provider table is not trusted for demand')
clock=clock+31
tableInfo.snapshot=false
live.snapshot=true
local fallback=G:Prices(ch)[1]
assert(fallback.current==700 and fallback.priceStatus:find('bundled snapshot',1,true),'bundled fallback is not treated as live')
clock=clock+31
live.snapshot=false;live.market='forever/normal/horde/us'
fallback=G:Prices(ch)[1]
assert(fallback.current==700 and fallback.priceStatus:find('market mismatch',1,true),'no cross-faction price leak')
clock=clock+31
live.market='forever/normal/alliance/us';live.updated=clock-90000
fallback=G:Prices(ch)[1]
assert(fallback.current==700 and fallback.priceStatus:find('stale',1,true),'stale provider quote rejected')
clock=clock+31
live.updated=clock;live.median=nil
fallback=G:Prices(ch)[1]
assert(fallback.current==700 and fallback.priceStatus:find('incomplete',1,true),'incomplete live quote rejected')
clock=clock+31
live.median=800;live.updated=clock+3600
fallback=G:Prices(ch)[1]
assert(fallback.current==700 and fallback.priceStatus:find('timestamp',1,true),'future quote rejected')
AHledgerAPI=nil
fallback=G:Prices(ch)[1]
assert(fallback.current==700 and fallback.priceStatus:find('unavailable',1,true),'optional dependency fallback')
assert(FCM_AHHistory.packed['forever/normal/alliance/us']:find('1,700',1,true),'on-disk history remains unchanged')
ch.faction='Horde';assert(next((G:Prices(ch)))==nil,'no faction fallback')
ch.faction='Alliance';ch.region='eu';assert(next((G:Prices(ch)))==nil,'no region fallback')
ch.region='us'
local rows=G:Rows(ch)
assert(#rows>8,'Gold rows and sections')
assert(G:Details(buy,ch):find('No supported best buying/selling day or hour',1,true),'weak timing withheld')
FCM_AHHistory.timing['forever/normal/alliance/us']={['1']={weekday={['0']={adequate=true,relative=.8,observations=20,days=5},['1']={adequate=true,relative=1.2,observations=20,days=5}}}}
assert(G:Details(buy,ch):find('Lower observed prices: Monday',1,true),'supported timing comparison')
print('PASS: Gold Advisor actions, historical isolation, live AHledger API, stale/missing fallbacks, market separation and row generation (synthetic)')
