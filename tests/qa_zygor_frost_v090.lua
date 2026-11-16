-- Regression guard: the obsolete numerical profile must never return.
local f={}
function f:Try(fn,...) return fn(...) end
function f:GearActivity() return 'leveling' end
function f:Mode() return 'dps' end
GetBuildInfo=function() return 'Forever synthetic','synthetic-build' end
assert(loadfile('ForeverCharacterManager/Gear.lua'))('FCM',f)
local ch={class='MAGE',talentSpec='Frost',level=24,gearImportedWeightProfiles={{
 name='Deprecated Zygor scale',source='Zygor',sourceType='user-import',policyVersion=2,
 gameBuild='synthetic-build',class='MAGE',spec='Frost',activity='leveling',style='dps',
 levelMin=1,levelMax=39,weights={spell=42}}}}
assert(f.Gear:DefaultReferenceProfile(ch)==nil)
assert(f.Gear:ActiveWeightProfile(ch)==nil)
assert(f.Gear:Weight('spell',ch)==nil)
assert(f.Gear:ParsePawnScale('( Pawn: v1: "Zygor old": SpellDamage=42 )')==nil)
assert(#ch.gearImportedWeightProfiles==1,'Saved profiles must be preserved, not deleted')
print('PASS: deprecated numerical source stays inactive; saved data preserved')