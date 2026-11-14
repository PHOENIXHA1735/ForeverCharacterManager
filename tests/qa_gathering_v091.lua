-- FCM gathering regression harness: no WoW client, external network or SavedVariables needed.
local function eq(actual,expected,context)
    if actual~=expected then error((context or "mismatch")..": "..tostring(actual).." expected "..tostring(expected),2) end
end
local FCM={db={},communityGathering={schema=1,version=2,nodes={}}}
function FCM:Now() return 12345 end
function FCM:Try(fn,...)
    local ok,a,b,c=pcall(fn,...)
    if ok then return a,b,c end
end
assert(loadfile('ForeverCharacterManager/Gathering.lua'))('ForeverCharacterManager',FCM)

eq(FCM:AddGatherNode('mining',37,4590,6780,'Copper Vein','personal'),true,'first discovery')
eq(FCM:AddGatherNode('mining',37,4590,6780,'Copper Vein','personal'),false,'duplicate')
eq(FCM:AddGatherNode('mining',37,-1,6780,'Copper Vein','personal'),false,'invalid coordinate')
eq(FCM:AddGatherNode('mining',37,4590,6780,'Copper|Vein','personal'),false,'invalid node name')
eq(FCM:GatherCounts().mining,1,'local count')
eq(FCM:GatherCounts().personal,1,'personal count')
eq(type(FCM_GatherExport),'table','companion export markers')
local token=next(FCM_GatherExport)
eq(token,'FCMG1|mining|37|4590|6780|Copper Vein','export contains only node fields')

-- GM2's public GetNodesForZone returns packed map coordinates, node ID.
local gm={gmdbs={['Herb Gathering']={__gm2_base_storage={[41]={}}}}}
function gm:GetNodesForZone(zone,kind,all)
    eq(zone,41);eq(kind,'Herb Gathering');eq(all,true)
    return pairs({[2314000000+452100]='257'})
end
function gm:GetNameForNode(kind,id) return kind=='Herb Gathering' and id=='257' and 'Silverleaf' or nil end
_G.GatherMate2=gm
local count=FCM:ImportGatherMate()
eq(count,1,'gm import')
eq(FCM:ImportGatherMate(),0,'idempotent import')
eq(FCM:GatherCounts().herbalism,1,'GM2 herb count')
_G.GatherMate2=nil
eq(FCM:GatherCounts().herbalism,1,'import persists without GM2')

FCM.communityGathering.nodes={{kind='mining',mapID=37,x=4590,y=6780,name='Copper Vein'},
  {kind='fishing',mapID=37,x=1234,y=5678,name='School of Fish'},
  {kind='mining',mapID=37,x=100001,y=0,name='Untrusted'}}
eq(FCM:MergeCommunityGathering(),1,'community merge ignores duplicates and rejects invalid')
eq(FCM:MergeCommunityGathering(),0,'community merge idempotent')
eq(FCM:GatherCounts().fishing,1,'fishing counted')
eq(FCM.db.gathering.communityVersion,2,'community version')
eq(FCM:AddGatherNode('fishing',37,1234,5678,'School of Fish','personal'),false,
    'personal confirmation of existing community point is not a duplicate')
eq(FCM_GatherExport['FCMG1|fishing|37|1234|5678|School of Fish'],true,
    'personal confirmation is exportable independently of community data')

C_Map={GetBestMapForUnit=function()return 77 end,
    GetPlayerMapPosition=function()return {GetXY=function()return .4421,.7612 end} end}
FCM:GatherEvent('UNIT_SPELLCAST_SENT','player','Peacebloom','cast42',2366)
FCM:GatherEvent('UNIT_SPELLCAST_SUCCEEDED','player','cast42',2366)
eq(FCM:GatherCounts().herbalism,2,'independent herbalism recording')
FCM:GatherEvent('UNIT_SPELLCAST_SENT','player',nil,'cast43',2575)
FCM:GatherEvent('UNIT_SPELLCAST_SUCCEEDED','player','cast43',2575)
eq(FCM:GatherCounts().mining,1,'unknown target must not invent a node')
FCM:GatherEvent('UNIT_SPELLCAST_SENT','player','Fishing','cast44',7620)
FCM:GatherEvent('UNIT_SPELLCAST_SUCCEEDED','player','cast44',7620)
eq(FCM:GatherCounts().fishing,1,'open-water fishing is not a pool')
FCM:GatherEvent('UNIT_SPELLCAST_SENT','player','Rich Thorium Vein','cast45',2575)
FCM:GatherEvent('UNIT_SPELLCAST_INTERRUPTED','player','cast45',2575)
FCM:GatherEvent('UNIT_SPELLCAST_SUCCEEDED','player','cast45',2575)
eq(FCM:GatherCounts().mining,1,'interrupted cast not recorded')
print('PASS: FCM local discovery, GatherMate import, GitHub snapshot merge and sanitized export')
