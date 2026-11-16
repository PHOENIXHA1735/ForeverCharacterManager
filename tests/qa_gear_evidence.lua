-- Synthetic coefficients below test engine math only; never an installed scale.
local F={db={settings={minimumUpgrade=0}},gearActivityOrder={'leveling','pvp','pve'},gearActivityLabels={leveling='Leveling',pve='PvE',pvp='PvP'},modeLabels={dps='DPS'}}
function F:Try(fn,...) if type(fn)=='function' then return fn(...) end end
function F:GearActivity(ch) return ch.gearActivity or 'leveling' end
function F:Mode(ch,act) return (ch.gearStyles or {})[act or self:GearActivity(ch)] or 'dps' end
function F:Now() return 1800000000 end
function F:AllRecipes() return self.recipes or {} end
function F:CanCollaborate() return true end
GetBuildInfo=function()return 'Forever synthetic','synthetic-build' end
local raw={
 [1]={ITEM_MOD_SPELL_POWER_SHORT=10,ITEM_MOD_INTELLECT_SHORT=5},
 [2]={ITEM_MOD_SPELL_POWER_SHORT=12,ITEM_MOD_INTELLECT_SHORT=4},
 [3]={ITEM_MOD_DEFENSE_SKILL_RATING_SHORT=2,ITEM_MOD_DODGE_RATING_SHORT=3,ITEM_MOD_PARRY_RATING_SHORT=4,ITEM_MOD_EXPERTISE_RATING_SHORT=5,ITEM_MOD_HEALING_DONE_SHORT=6},
 [4]={RESISTANCE0_NAME=10,ITEM_MOD_ARMOR_SHORT=10,ITEM_MOD_BONUS_ARMOR_SHORT=10,ITEM_MOD_SPELL_POWER_SHORT=4,ITEM_MOD_SPELL_DAMAGE_DONE_SHORT=4},
 [5]={ITEM_MOD_SPELL_POWER_SHORT=8,ITEM_MOD_MASTERY_RATING_SHORT=9},
 [6]={ITEM_MOD_SPELL_PENETRATION_SHORT=7},
 [7]={ITEM_MOD_FIRE_RESISTANCE_SHORT=10,ITEM_MOD_FROST_RESISTANCE_SHORT=20,ITEM_MOD_ATTACK_POWER_SHORT=3,ITEM_MOD_RANGED_ATTACK_POWER_SHORT=4},
}
local function id(x)return tonumber(tostring(x):match('(%d+)')) end
C_Item={GetItemInfo=function(x)return 'Synthetic '..id(x),'item:'..id(x),2,20,1,'Armor','Cloth',1,'INVTYPE_CHEST',0,0,4,1,2 end,
 GetItemStats=function(x)return raw[id(x)] end}
assert(loadfile('ForeverCharacterManager/StatWeightEngine.lua'))('FCM',F)
assert(loadfile('ForeverCharacterManager/PriorityGuides.lua'))('FCM',F)
assert(loadfile('ForeverCharacterManager/Gear.lua'))('FCM',F)
local G,E,P=F.Gear,F.StatWeightEngine,F.PriorityGuides
local function char()return {key='synthetic',class='MAGE',talentSpec='Frost',level=24,gearActivity='leveling',gearStamp=1,gear={[5]={itemID=1}},bags={{itemID=9,count=2}},recipes={},gold=123}end
local ch=char()
assert(G:DefaultReferenceProfile(ch)==nil and G:Weight('spell',ch)==nil and G:Score(2,ch)==nil,'No bundled fallback')
assert(G:CompareItem(2,ch).status=='unknown' and G:CompareItem(2,ch).delta==nil,'No invented upgrade')
assert(G:WeightSource(ch):find('Icy Veins WoW Forever ordinal',1,true),'Correct source')
local v=G:StatValues(3)
assert(v.def==2 and v.dodge==3 and v.parry==4 and v.expertise==5 and v.healing==6,'Distinct defensive/role stats')
v=G:StatValues(4);assert(v.armor==10 and v.spell==4,'Alias deduplication')
local _,diag=G:StatValues(5);assert(#diag.unknown==1,'Unknown client identifier retained')
assert(G:CompareItem(5,ch).status=='unknown','Unknown stats cannot score')
v=G:StatValues(6);assert(v.spell_pen==7 and not v.spell_pierce,'Piercing is not resistance penetration')
v=G:StatValues(7);assert(v.resist_fire==10 and v.resist_frost==20 and not v.resist and v.ap==3 and v.rap==4,'Distinct schools and ranged power')
assert(P:Coverage()==27,'All supported specs')
for cls,specs in pairs({DRUID={'Balance','Feral','Restoration'},HUNTER={'Beast Mastery','Marksmanship','Survival'},MAGE={'Arcane','Fire','Frost'},PALADIN={'Holy','Protection','Retribution'},PRIEST={'Discipline','Holy','Shadow'},ROGUE={'Assassination','Combat','Subtlety'},SHAMAN={'Elemental','Enhancement','Restoration'},WARLOCK={'Affliction','Demonology','Destruction'},WARRIOR={'Arms','Fury','Protection'}})do
 for _,spec in ipairs(specs)do
  local c={class=cls,talentSpec=spec,level=24}
  local g=P:Reference(c,'leveling');assert(g and g.reviewedAt=='2026-11-16' and g.url:find('/wow-forever/',1,true))
  assert(P:Reference(c,'pve')==nil,'No endgame substitution')
  if cls=='PRIEST' and spec=='Discipline' then assert(P:Reference(c,'pvp').sourceName:find('Hydra',1,true))
  else assert(P:Reference(c,'pvp')==nil,'No PvE-to-PvP substitution') end
  c.level=60;assert(P:Reference(c,'pve') and P:Reference(c,'pve').activity=='pve')
 end
end
local saved={name='Legacy scale',source='Pawn',weights={spell=42},class='MAGE',spec='Frost',activity='leveling',style='dps',levelMin=1,levelMax=39}
ch.gearImportedWeightProfiles={saved};ch.gearCustomWeights={leveling={spell=42,int=99}}
assert(G:ActiveWeightProfile(ch)==nil and G:Weight('spell',ch)==nil,'Legacy coefficients inactive')
assert(ch.gearImportedWeightProfiles[1]==saved and ch.bags[1].count==2 and ch.gold==123 and ch.gearCustomWeights.leveling.int==99,'Character data preserved')
assert(G:SetCustomWeight(ch,'spell',2));assert(G:Weight('spell',ch)==2 and G:Weight('int',ch)==nil,'No legacy coefficient reactivation')
ch=char()
local p={schema=1,verified=true,class='MAGE',spec='Frost',activity='leveling',style='dps',levelMin=1,levelMax=39,
 source='Synthetic measurement',sourceURL='https://example.invalid/synthetic',reviewedAt='2026-11-16',methodology='Synthetic finite-difference fixture only',
 normalization={method='marginal/reference',referenceStat='spell'},weights={spell={value=1,unit='point'},int={value=.25,unit='point'}}}
F.statWeightCatalog={schema=1,game='wow-forever',version='synthetic',gameBuild='synthetic-build',profiles={p}}
assert(E:VerifiedProfile(F.statWeightCatalog,ch,'dps','leveling','synthetic-build')==p)
assert(G:Weight('spell',ch)==1 and G:Weight('int',ch)==.25,'Shared validated coefficients')
local c=G:CompareItem(2,ch);assert(c.status=='ok' and c.delta==1.75 and c.scorePct==nil,'Consistent comparison math without upgrade percentage')
local perspectives=G:CompareActivities(2,ch,nil,5,'INVTYPE_CHEST')
assert(perspectives[1].delta==c.delta and perspectives[2].delta==nil and perspectives[3].delta==nil,'One comparison path and activity separation')
F.recipes={{id=10,outputID=2,crafters={ch}}}
local candidates=G:Candidates(ch);assert(#candidates==1 and candidates[1].delta==c.delta,'Gear/Upgrades use same comparison')
ch.talentSpec='Fire';assert(G:Score(2,ch)==nil,'Spec separation');ch.talentSpec='Frost';ch.class='WARLOCK';assert(G:Score(2,ch)==nil,'Class separation');ch.class='MAGE'
p.source='Deprecated Zygor';assert(G:VerifiedStatProfile(ch,'dps','leveling')==nil,'Catalog cannot restore deprecated source');p.source='Synthetic measurement'
p.weights.int.unit='percentage_point';assert(G:VerifiedStatProfile(ch,'dps','leveling')==nil,'Wrong units rejected');p.weights.int.unit='point'
p.weights.unknown_stat={value=2,unit='point'};assert(G:VerifiedStatProfile(ch,'dps','leveling')==nil,'Unknown coefficient rejected');p.weights.unknown_stat=nil
F.statWeightCatalog.profiles={p,p};assert(G:VerifiedStatProfile(ch,'dps','leveling')==nil,'Duplicate profiles rejected');F.statWeightCatalog.profiles={p}
local measured=E:WeightsFromSamples(100,{spell={delta=2,output=104},int={delta=4,output=102}},'spell')
assert(measured.weights.spell==1 and measured.weights.int==.25,'Consistent marginal normalization')
local capped={schema=1,weights={hit={value=1,unit='point'}}}
local capResult=E:ScoreChanges({hit=2},{hit=5},capped,{caps={hit={value=5,unit='point'}},current={hit={value=4,unit='point'}}})
assert(capResult.score==1,'Cap-aware change uses current character total')
assert(E:ScoreChanges({hit=2},{hit=5},capped,{caps={hit={value=5,unit='percentage_point'}},current={hit={value=4,unit='point'}}})==nil,'Rating is never equated to percent')
assert(ch.gold==123 and ch.bags[1].count==2 and ch.gear[5].itemID==1,'Read-only scoring preserves snapshots')
print('PASS: evidence-based gear policy, mappings, provenance, 27 specs, contexts, unified comparisons and SavedVariables preservation')
