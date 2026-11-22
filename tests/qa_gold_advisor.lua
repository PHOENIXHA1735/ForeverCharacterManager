local FCM={db={settings={}},Gear={}}
function FCM:NormalizeRuleset(x) return x end
function FCM:NormalizeFaction(x) return (x=='Alliance' or x=='Horde') and x or nil end
function FCM.Gear:Info(id) return {bindType=id==999 and 1 or 2} end
function FCM:AllRecipes() return {} end
function FCM.ItemName(id) return 'Synthetic '..tostring(id) end
time=function() return 1800000000 end
assert(loadfile('ForeverCharacterManager/ExternalData.lua'))('FCM',FCM)
assert(loadfile('ForeverCharacterManager/GoldAdvisor.lua'))('FCM',FCM)
function FCM:Now()return time()end
date=os.date
assert(loadfile('ForeverCharacterManager/HistoryProvider.lua'))('FCM',FCM)
local G=FCM.GoldAdvisor
assert(G:ConfigureFees('5 100') and FCM.db.settings.goldAdvisorFees.deposit==100,'fee controls')
assert(not G:ConfigureFees('100 0'),'invalid fee controls')
assert(G:ConfigureFarm('1|Herbalism|20|1000|100'),'farm controls')
local ch={key='Player-A',ruleset='Normal',faction='Alliance',region='us',bags={},bank={},recipes={},professions={Alchemy={}}}
FCM.db.characters={[ch.key]=ch}
local function quote(low)
    return {baseline=365,windows={7,30,90,180,365},current=low,low=low,stamp=time(),days=60,observations=120,demand=5,demandStamp=time()-60,supply=10,volatility=.1,trend=5,confidence='moderate',averages={[365]=1000,[30]=1000},coverage={[30]=20}}
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
assert(next((G:Prices(ch)))==nil,'legacy schema-1 must remain untrusted')
ch.faction='Horde';assert(next((G:Prices(ch)))==nil,'no faction fallback')
ch.faction='Alliance';ch.region='eu';assert(next((G:Prices(ch)))==nil,'no region fallback')
ch.region='us'
local rows=G:Rows(ch)
assert(#rows>8,'Gold rows and sections')
assert(G:Details(buy,ch):find('No supported best buying/selling day or hour',1,true),'weak timing withheld')
FCM_AHHistory.timing['forever/normal/alliance/us']={['1']={weekday={['0']={adequate=true,relative=.8,observations=20,days=5},['1']={adequate=true,relative=1.2,observations=20,days=5}}}}
assert(not G:Details(buy,ch):find('Lower observed prices: Monday',1,true),'unvalidated legacy timing must remain untrusted')
print('PASS: Gold Advisor actions, eligibility, fees, opportunity cost, missing data, freshness, market separation and row generation (synthetic)')
