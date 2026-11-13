-- Offline Forever character identity/ruleset tests for FCM v0.9.2.
local base='ForeverCharacterManager/'
local n=0
local function eq(a,b,title)
  if a~=b then error((title or 'mismatch')..': got '..tostring(a)..', expected '..tostring(b),2) end
end
local function check(title,fn)
  local ok,err=pcall(fn)
  if not ok then error('FAIL: '..title..': '..tostring(err),0) end
  n=n+1;print('PASS: '..title)
end
local core=assert(io.open(base..'Core.lua','r')):read('*a')
local partial=assert(core:match('^(.-)local f = CreateFrame%('),'core methods boundary')
local FCM={}
assert(load(partial))('ForeverCharacterManager',FCM)
local function copy(t)
 local o={};for k,v in pairs(t) do o[k]=v end;return o
end
check('Normalize Normal / PvE / PvP / RP / RP-PvP / Hardcore labels',function()
 for a,b in pairs({Normal='Normal',PvE='Normal',PvP='PvP',RP='RP',['RP-PvP']='RP-PvP',Roleplay='RP',Hardcore='Hardcore',['CAMWOW US1 Realm 5 PvE']='Normal',['CAMWOW US1 Realm 10 PvP']='PvP',['CAMWOW US1 Realm 8 RP']='RP',['CAMWOW US1 Realm 8 RP PvP']='RP-PvP',['Classic Beta PvE']='Normal'}) do
  eq(FCM:NormalizeRuleset(a),b,a)
 end
 eq(FCM:NormalizeRuleset('Bit'),nil)
 eq(FCM:NormalizeRuleset('Dotty'),nil)
 eq(FCM:NormalizeRuleset('Unknown'),nil)
end)
check('Backend server label is used only to detect ruleset and region',function()
 GetRealmName=function() return 'CAMWOW US1 Realm 5 PvE' end
 GetCurrentRegion=function() return 1 end
 eq(FCM:CurrentRuleset(),'Normal')
 eq(FCM:CurrentRegion(),'US')
end)
check('Unrecognized backend label leaves ruleset unknown (fails closed)',function()
 GetRealmName=function() return 'CAMWOW - Unlabeled' end
 GetCurrentRegion=nil
 eq(FCM:CurrentRuleset(),nil)
 eq(FCM:CurrentRegion(),nil)
end)
check('CharacterKey uses GUID, not surname or realm',function()
 UnitGUID=function() return 'Player-123-ABC' end
 UnitFullName=function() return 'Frosty','Bit' end
 eq(FCM:CharacterKey(),'Player-123-ABC')
end)
check('Legacy saved surname migrates without deleting any character records',function()
 FCM_DB={characters={['Player-F']={key='Player-F',name='Frosty',realm='Bit',level=22,bags={old=true}},['Player-S']={key='Player-S',name='Spotty',realm='Dotty',level=1},['Player-I']={key='Player-I',name='Itty',realm='Bittydots',level=1}},settings={}}
 FCM:InitDB()
 eq(FCM.db.characters['Player-F'].surname,'Bit')
 eq(FCM.db.characters['Player-S'].surname,'Dotty')
 eq(FCM.db.characters['Player-I'].surname,'Bittydots')
 eq(FCM.db.characters['Player-F'].bags.old,true)
 eq(FCM.db.characters['Player-F'].ruleset,nil)
 eq(FCM.db.characters['Player-F'].realm,'Bit')
end)
check('Full names are preserved correctly and never append rulesets as surnames',function()
 eq(FCM:FullCharacterName(FCM.db.characters['Player-F']),'Frosty Bit')
 eq(FCM:DisplayCharacter(FCM.db.characters['Player-S']),'Spotty Dotty')
 eq(FCM:FullCharacterName({name='New',ruleset='Normal'}),'New')
end)
check('Full-name lookup supports hyphen and spaces',function()
 eq(FCM:FindCharacter('Frosty Bit').key,'Player-F')
 eq(FCM:FindCharacter('frosty-bit').key,'Player-F')
 eq(FCM:FindCharacter('Spotty Dotty').key,'Player-S')
end)
check('Same faction+ruleset+region can collaborate regardless of surname',function()
 local a={key='F',faction='Alliance',surname='Bit',ruleset='Normal',region='US'}
 local b={key='S',faction='Alliance',surname='Dotty',ruleset='Normal',region='US'}
 eq(FCM:CanCollaborate(a,b),true)
end)
check('Different ruleset is blocked even when surname matches',function()
 local a={key='F',faction='Alliance',surname='Bit',ruleset='Normal',region='US'}
 local b={key='S',faction='Alliance',surname='Bit',ruleset='PvP',region='US'}
 eq(FCM:CanCollaborate(a,b),false)
end)
check('Opposing faction blocked on same ruleset',function()
 local a={key='F',faction='Alliance',ruleset='Normal',region='US'}
 local b={key='I',faction='Horde',ruleset='Normal',region='US'}
 eq(FCM:CanCollaborate(a,b),false)
end)
check('Unknown ruleset is not transferable even with matching surname',function()
 local a={key='F',faction='Alliance',surname='Bit',ruleset='Normal',region='US'}
 local b={key='S',faction='Alliance',surname='Bit',region='US'}
 eq(FCM:CanCollaborate(a,b),false)
end)
check('Unknown or different region is not a confirmed transfer',function()
 local a={key='F',faction='Alliance',ruleset='Normal',region='US'}
 local b={key='S',faction='Alliance',ruleset='Normal'}
 eq(FCM:CanCollaborate(a,b),false)
 b.region='EU';eq(FCM:CanCollaborate(a,b),false)
end)
check('New scan saves surname, ruleset, and region separately',function()
 GetRealmName=function() return 'CAMWOW US1 Realm 5 PvE' end
 GetCurrentRegion=function() return 1 end
 UnitFullName=function() return 'Frosty','Bit' end
 UnitClass=function() return 'Mage','MAGE' end
 UnitRace=function() return 'Gnome','Gnome' end
 UnitFactionGroup=function() return 'Alliance' end
 UnitLevel=function() return 22 end
 GetMoney=function() return 123 end
 UnitXP=function() return 400 end
 UnitXPMax=function() return 999 end
 GetXPExhaustion=function() return 0 end
 local ch=FCM.db.characters['Player-F']; FCM.currentKey='Player-F'
 FCM.TrackSession=nil
 assert(loadfile(base..'Scan.lua'))('ForeverCharacterManager',FCM)
 FCM:ScanBasic()
 eq(ch.name,'Frosty');eq(ch.surname,'Bit');eq(ch.realm,'Bit');eq(ch.ruleset,'Normal');eq(ch.region,'US')
end)
check('Unrecognized new ruleset does not convert surname to realm',function()
 GetRealmName=function() return 'unknown internal host' end
 UnitFullName=function() return 'New','Lastname' end
 local ch={key='new'}
 FCM.db.characters.new=ch;FCM.currentKey='new'
 FCM:ScanBasic()
 eq(ch.name,'New');eq(ch.surname,'Lastname');eq(ch.realm,nil);eq(ch.ruleset,nil)
end)
check('MarketPricesFor filters by character faction, ruleset and region',function()
 assert(loadfile(base..'ExternalData.lua'))('ForeverCharacterManager',FCM)
 local prices={['forever.normal.alliance.us']={[1]={cost=11}},['forever.pvp.alliance.us']={[1]={cost=22}},['forever.normal.horde.us']={[1]={cost=33}},['forever.normal.alliance.eu']={[1]={cost=44}}}
 FCM.externalData={pricesByMarket=prices,dailyAHRuleSet='pvp',dailyAHRegion='US',dailyAHExpiresAt=99999999}
 time=function() return 100 end
 eq(FCM:MarketPricesFor({faction='Alliance',ruleset='Normal',region='US'})[1].cost,11)
 eq(FCM:MarketPricesFor({faction='Alliance',ruleset='PvP',region='US'})[1].cost,22)
 eq(FCM:MarketPricesFor({faction='Horde',ruleset='Normal',region='US'})[1].cost,33)
 eq(FCM:MarketPricesFor({faction='Alliance',ruleset='Normal',region='EU'})[1].cost,44)
 eq(next(FCM:MarketPricesFor({faction='Alliance',region='US',surname='Bit'})),nil)
end)
check('BoE excludes opposite faction and different rulesets, but permits verified same ruleset',function()
 assert(loadfile(base..'BoEProtection.lua'))('ForeverCharacterManager',FCM)
 local owner={key='f',name='Frosty',surname='Bit',faction='Alliance',ruleset='Normal',region='US',level=22,gearStamp=1000,bags={['0:1']={itemID=1234,count=1,bound=false}}}
 local spotty={key='s',name='Spotty',surname='Dotty',faction='Alliance',ruleset='Normal',region='US',level=1,gearStamp=1000}
 local itty={key='i',name='Itty',surname='Bittydots',faction='Horde',ruleset='Normal',region='US',level=1,gearStamp=1000}
 local other={key='o',name='Other',surname='Test',faction='Alliance',ruleset='PvP',region='US',level=1,gearStamp=1000}
 FCM.db.settings.minimumUpgrade=1; FCM.db.settings.boeFutureLevels=10
 FCM.Gear={Info=function() return {bindType=2,level=7} end,CompareItem=function(_,id,ch) return {status='ok',delta=ch.key=='f' and 0 or (ch.key=='s' and 3.5 or 90)} end}
 FCM.Characters=function() return {owner,spotty,itty,other} end
 FCM.Current=function() return owner end
 FCM.ScanFreshness=function() return {status='current',label='Current'} end
 FCM.Now=function() return 1050 end
 local result=FCM:BoEProtectionCheck(1234,owner)
 eq(result.status,'keep')
 eq(#result.candidates,1)
 eq(result.candidates[1].name,'Spotty Dotty')
 eq(#result.excluded,2)
 eq(result.excluded[1].name,'Itty Bittydots')
 eq(result.excluded[2].name,'Other Test')
end)
check('Unverified recipient cannot justify confirmed BoE KEEP',function()
 local owner={key='f',name='Frosty',faction='Alliance',ruleset='Normal',region='US',level=22,gearStamp=1000,bags={['0:1']={itemID=1234,count=1,bound=false}}}
 local alt={key='s',name='Spotty',surname='Dotty',faction='Alliance',level=1,gearStamp=1000}
 FCM.Characters=function() return {owner,alt} end
 local report=FCM:BoEProtectionCheck(1234,owner)
 eq(report.status=='keep',false)
 eq(report.candidates[1].transferable,false)
end)
print('PASS: '..n..' v0.9.2 identity/transfer/market regression checks')
