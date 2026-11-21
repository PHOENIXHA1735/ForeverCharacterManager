-- Synthetic, read-only Future Gear Planner contract checks. No client calls.
local F={Gear={slots={INVTYPE_CHEST={5},INVTYPE_2HWEAPON={16},INVTYPE_HEAD={1}}},
  externalData={items={},recipes={},dungeons={}}}
local items={
 [100]={name='Craft cloth',requiredLevel=30,equip='INVTYPE_CHEST',classID=4,subclassID=1,allowableClassMask=128,bindType=2},
 [101]={name='Unlearned cloth',requiredLevel=34,equip='INVTYPE_CHEST',classID=4,subclassID=1,allowableClassMask=128},
 [102]={name='Boss cloth',requiredLevel=35,equip='INVTYPE_CHEST',classID=4,subclassID=1,allowableClassMask=128},
 [103]={name='Plate',requiredLevel=28,equip='INVTYPE_HEAD',classID=4,subclassID=4},
 [104]={name='Axe',requiredLevel=28,equip='INVTYPE_2HWEAPON',classID=2,subclassID=1},
 [105]={name='Other-class',requiredLevel=27,equip='INVTYPE_CHEST',classID=4,subclassID=1,allowableClassMask=1},
 [106]={name='Too high',requiredLevel=36,equip='INVTYPE_CHEST',classID=4,subclassID=1},
 [107]={name='Missing required level',itemLevel=30,equip='INVTYPE_CHEST',classID=4,subclassID=1},
 [108]={name='Unclassified source',requiredLevel=29,equip='INVTYPE_CHEST',classID=4,subclassID=1},
 [109]={name='Conflict',requiredLevel=32,equip='INVTYPE_CHEST',classID=4,subclassID=1},
}
F.externalData.items=items
F.Gear.Info=function(_,id)
 local r=items[id]
 if id==109 then return {name=r.name,level=31,equip=r.equip,classID=r.classID,subclassID=r.subclassID} end
 return nil
end
local mine={key='me',class='MAGE',level=25,faction='Alliance',ruleset='Forever',region='US'}
local allied={key='friend',class='MAGE',level=30,faction='Alliance',ruleset='Forever',region='US'}
local opposing={key='horde',class='MAGE',level=30,faction='Horde',ruleset='Forever',region='US'}
F.AllRecipes=function()
 return {{id=10,name='Learned cloth',outputID=100,profession='Tailoring',requiredSkill=150,crafters={allied,opposing}},
  {id=11,name='Learned axe',outputID=104,profession='Blacksmithing',crafters={allied}},
  {id=12,name='Not in window',outputID=106,crafters={mine}}}
end
F.UnlearnedRecipes=function()
 return {{id=20,name='Unlearned cloth recipe',outputID=101,profession='Tailoring',seenOn={mine}}}
end
F.CanCollaborate=function(_,a,b)return a.faction==b.faction and a.ruleset==b.ruleset and a.region==b.region end
F.RecipeSkillStatus=function(_,r,c)return c.key=='horde' and 'blocked' or 'ready','synthetic scanned status' end
F.externalData.recipes={
 [20]={name='External unlearned',resultID=101,profession='Tailoring',skill=140,sourceProvider='Synthetic'},
 [31]={name='Plate recipe',resultID=103},
 [32]={name='Other class recipe',resultID=105},
 [33]={name='Unknown level recipe',resultID=107},
 [34]={name='Level conflicting',resultID=109},
}
F.externalData.dungeons={
 d1={name='Synthetic Dungeon',kind='dungeon',sourceProvider='Synthetic',bosses={
  {name='Boss A',loot={{id=102}}},{name='Boss B',loot={{id=102}}}},lootIDs={102,108}},
 raid={name='Synthetic Raid',kind='raid',lootIDs={100}},
 misc={name='Mystery Instance',lootIDs={108}},
}
assert(loadfile('ForeverCharacterManager/FutureGearPlanner.lua'))('FCM',F)
local P=F.FutureGearPlanner
local function indexed(rows)
 local out={}
 for _,r in ipairs(rows) do out[r.itemID]=r end
 return out
end
local rows,err=P:Candidates(mine,10)
assert(not err and #rows==5,'Five safe future references, without blocked or level-unverified records')
local by=indexed(rows)
assert(rows[1].itemID==104 and rows[2].itemID==108 and rows[3].itemID==100 and
 rows[4].itemID==101 and rows[5].itemID==102,'Required-level then item-id order')
assert(by[100].comparison=='not-evaluated' and by[100].scored==false,'Never claim an upgrade')
assert(#by[100].sources==1 and by[100].sources[1].learnedStatus=='learned','Learned recipe status')
assert(#by[100].sources[1].knownCrafters==2 and by[100].sources[1].knownCrafters[1].compatible,'Saved crafter metadata')
assert(by[100].sources[1].knownCrafters[2].compatible==false and
 by[100].sources[1].knownCrafters[2].recipientStatus=='blocked',
 'Opposing faction never offered as compatible')
assert(by[100].sources[1].knownCrafters[1].recipientStatus=='eligible-scan-only',
 'Compatible learned crafter remains scan-only')
assert(#by[101].sources==2 and by[101].sources[1].kind=='crafted-reference' and by[101].sources[2].kind=='crafted-unlearned','Reference and unlearned kept separately')
assert(#by[102].sources==2 and by[102].sources[1].boss~=by[102].sources[2].boss,'Two boss links retained and flat duplicate removed')
assert(by[104].eligibility=='verify' and by[104].eligibilityReason:find('Weapon subtype',1,true),'Weapon never presumed wearable')
assert(by[108].sources[1].classification=='unverified' or by[108].sources[2].classification=='unverified','Unclassified dungeon source marked')
assert(not by[103] and not by[105] and not by[106] and not by[107] and not by[109],'Known restrictions, upper bound, missing level and conflicting level excluded')
local short=P:Candidates(mine,5)
assert(#short==3 and short[1].itemID==104 and short[2].itemID==108 and short[3].itemID==100,'Level 26 through 30 only')
local crafted=P:Candidates(mine,10,{source='crafting'})
assert(#crafted==3 and indexed(crafted)[102]==nil,'Crafting filter')
local dungeons=P:Candidates(mine,10,{source='dungeons'})
assert(#dungeons==2 and indexed(dungeons)[101]==nil,'Dungeon filter')
local chest=P:Candidates(mine,10,{slot=5})
assert(#chest==4 and indexed(chest)[104]==nil,'Slot filter')
assert(#(P:Candidates(mine,9))==0,'Reject arbitrary lookahead')
local level60={key='end',class='MAGE',level=60}
assert(#(P:Candidates(level60,10))==0,'Never go beyond level 60')
items[100].bindType=1
local bop=indexed(P:Candidates(mine,10))[100]
assert(bop.sources[1].knownCrafters[1].recipientStatus=='blocked' and
 not bop.sources[1].hasPotentialCrafter,'BoP crafted output not transferred from alt')
items[100].bindType=nil
local unknownBind=indexed(P:Candidates(mine,10))[100]
assert(unknownBind.sources[1].knownCrafters[1].recipientStatus=='verify',
 'Unknown binding cannot become ready')
items[100].bindType=2
assert(mine.level==25 and items[100].requiredLevel==30 and #F.externalData.dungeons.d1.lootIDs==2,'All inputs remain read-only')
-- Actual companion serializes human-readable subclass/binding, numbered slotID,
-- and resultID for references; check adapters against those exact field names.
local originalRecipe=F.externalData.recipes
local originalDungeons=F.externalData.dungeons
F.externalData.recipes={
 [901]={name='Companion cloth',profession='Tailoring',resultID=201,
     skill=125,sourceProvider='ForeverDB',acquisition='Vendor unverified'},
 [902]={name='Companion bad metadata',resultID=202},
 [903]={name='Companion unknown bind',resultID=203},
 [904]={name='Companion two hand',resultID=204},
 [905]={name='Companion beta-only',resultID=205},
}
F.externalData.dungeons={}
items[201]={name='Companion-only chest',requiredLevel='29',itemLevel='47',
    classID='4',subclass='Cloth',equipLoc='Chest',slotID='5',binding='Bind on Equip',
    sourceProvider='ForeverDB',referenceCheckedAt='2026-11-21T16:00:00Z'}
items[202]={name='Contradiction',requiredLevel=29,classID=4,subclass='Cloth',
    equipLoc='Chest',slotID=1}
items[203]={name='Unknown bind',requiredLevel=30,classID=4,subclass='Cloth',
    equipLoc='INVTYPE_CHEST',binding='No binding data'}
items[204]={name='Two handed axe',requiredLevel=28,classID=2,
    equipLoc='Two-Hand',slotID=17,binding='Binds when equipped'}
items[205]={name='Old beta item',requiredLevel=28,classID=4,subclass='Cloth',
    equipLoc='Chest',betaEvent=true}
local imported=indexed(P:Candidates(mine,10,{source='crafting'}))
assert(imported[201] and imported[201].slot==5 and imported[201].requiredLevel==29,
 'Companion-specific equipLoc and string level are recognized')
assert(imported[201].bindType==2 and imported[201].subclassID==1,
 'Companion binding and named armor subtype normalized conservatively')
assert(imported[201].itemSourceProvider=='ForeverDB' and imported[201].itemCheckedAt,
 'Reference provenance retained')
assert(not imported[202], 'Contradictory equipLoc and slotID must not be accepted')
assert(imported[203].bindType==nil and imported[203].eligibility=='verify',
 'Unverified binding and class restrictions remain unknown')
assert(imported[204].eligibility=='verify', 'Named two-hand weapon cannot bypass proficiency')
assert(imported[205].availabilityStatus=='historical-beta-event',
 'Historical beta items must be visibly flagged as uncertain')
F.externalData.recipes=originalRecipe
F.externalData.dungeons=originalDungeons
print('PASS: future candidate aggregation, levels, filters, restrictions, provenance and read-only handling')
