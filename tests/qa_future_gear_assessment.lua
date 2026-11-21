-- Standalone synthetic contract test. Nothing in these fixtures is a real item.
local F={Gear={},db={settings={minimumUpgrade=1}}}
function F:GearActivity()return 'leveling' end
function F:Now()return 1800000000 end
local now=F:Now()
local ch={key='mage',class='MAGE',talentSpec='Frost',level=25,gearStamp=now-10}
assert(loadfile('ForeverCharacterManager/FutureGearAssessment.lua'))('FCM',F)
local P=F.FutureGearPlanner
local function row(id)
 return {itemID=id,characterKey=ch.key,class=ch.class,specialization=ch.talentSpec,
    levelNow=25,requiredLevel=30,eligibility='compatible',
    availabilityStatus='reference-unverified'}
end
local called={}
F.Gear.CompareItem=function(_,id,who,slot,opts)
 called[#called+1]={id=id,opts=opts}
 if id==1 then return {status='ok',delta=5,confidence='VERIFIED NUMERIC MODEL',
    modelResult={complete=true},weightSource='Synthetic verified'} end
 if id==2 then return {status='ok',delta=4,confidence='PROVISIONAL CUSTOM ESTIMATE',weightSource='User weight'} end
 if id==3 then return {status='unknown',guideVerdict='supported',reason='Safe guide support'} end
 if id==4 then return {status='ok',delta=7,confidence='VERIFIED NUMERIC MODEL',modelResult={complete=false}} end
 if id==5 then return {status='ok',delta=.4,confidence='VERIFIED NUMERIC MODEL',modelResult={complete=true}} end
 error('Should not compare excluded candidates')
end
local r1=row(1)
local r2=row(2)
local r3=row(3)
local r4=row(4)
local r5=row(5)
local r6=row(6);r6.eligibility='verify';r6.eligibilityReason='Weapon proficiency unknown'
local r7=row(7);r7.availabilityStatus='historical-beta-event'
local r8=row(8);r8.specialization='Fire'
local out=P:Assess(ch,{r1,r2,r3,r4,r5,r6,r7,r8})
assert(#out==8 and #called==5,'Only safe items reach shared Gear comparison')
assert(out[1].assessment=='verified-weighted-upgrade' and out[1].weightedDelta==5,'Verified gain')
assert(out[2].assessment=='provisional-estimate' and out[2].weightedDelta==4,'No verified claim for custom scale')
assert(out[3].assessment=='qualitative-candidate' and out[3].weightedDelta==nil,'Ordinal guidance never numeric')
assert(out[4].assessment=='insufficient-information' and out[4].weightedDelta==nil,'Partial model cannot score')
assert(out[5].assessment=='not-a-verified-upgrade' and out[5].weightedDelta==.4,'Below configured threshold')
assert(out[6].assessment=='insufficient-information' and out[7].assessment=='insufficient-information' and
    out[8].assessment=='insufficient-information','Unknown wearability, beta, or spec mismatch does not become upgrade')
assert(called[1].opts.allowFutureLevel==true and called[1].opts.activity=='leveling','Future comparisons through shared engine')
assert(out[1].comparedTo:find('not projected future',1,true),'No predicted future character stats')
assert(r1.assessment==nil and ch.gearStamp==now-10,'Source rows and saved character not mutated')
ch.gearStamp=now-900000
local stale=P:Assess(ch,{r1})
assert(stale[1].assessment=='insufficient-information' and #called==5,'Old gear snapshot withholds upgrades')
ch.gearStamp=now-10
F.Gear.CompareItem=function() error('game API failure') end
local failed=P:Assess(ch,{r1})
assert(failed[1].assessment=='insufficient-information','API failure cannot fabricate upgrade')
print('PASS: future assessments use existing Gear comparison and never promote unverified data')
