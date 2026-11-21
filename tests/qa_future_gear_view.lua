-- Synthetic UI view-model integration: no real item data, no WoW frames.
local F={}
assert(loadfile("ForeverCharacterManager/FutureGearView.lua"))("FCM",F)
local P=F.FutureGearPlanner
local ch={key="mage",class="MAGE",talentSpec="Frost",level=25}
local original={
    itemID=900,itemName="Synthetic Staff",requiredLevel=30,
    equip="INVTYPE_2HWEAPON",classID=2,slot=16,
    characterKey="mage",class="MAGE",specialization="Frost",
    levelNow=25,targetLevel=35,eligibility="verify",
    sources={{kind="instance-unassigned",name="Synthetic Instance",
        classification="unverified",provider="Synthetic"}},
}
local called={}
P.Candidates=function(_,who,window)
    called[#called+1]="candidates:"..window
    assert(who==ch)
    return {original},nil
end
P.WithWeaponEvidence=function(_,who,rows)
    called[#called+1]="weapon"
    assert(#rows==1)
    return rows,1
end
P.Assess=function(_,who,rows)
    called[#called+1]="assessment"
    local row={}
    for k,v in pairs(rows[1]) do row[k]=v end
    row.assessment="insufficient-information"
    row.assessmentReason="Unverified weapon"
    return {row},nil
end
P.Shortlist=function(_,who,rows,limits)
    called[#called+1]="shortlist"
    assert(#rows==1)
    if limits.itemsPerSlot==5 and limits.weaponsPerSlot==3 then
        return {groups={},totalShown=0,withheldWeapons=1,hiddenByLimit=0},nil
    end
    assert(limits.itemsPerSlot==10 and limits.weaponsPerSlot==5)
    return {groups={
        {key="weapon:16",label="Main hand weapons",total=1,hidden=0,
         rows={rows[1]}}
    },totalShown=1,withheldWeapons=0,hiddenByLimit=0},nil
end
local first,meta=P:ViewRows(ch,5,false)
assert(#first==2 and first[1].id=="future-status" and
    first[2].id=="future-no-gear" and meta.withheldWeapons==1,
    "No verified weapons creates transparent empty view")
local expanded,m=P:ViewRows(ch,10,true)
assert(#expanded==3 and expanded[2].id=="future-section:weapon:16",
    "Expanded view includes section")
assert(expanded[3].futurePlan and expanded[3].itemID==900 and
    expanded[3].compareSlot==16,"Selected item can use existing preview")
assert(expanded[3].detail:find("ACQUISITION REFERENCES",1,true) and
    expanded[3].detail:find("Instance type unclassified",1,true),
    "Detail provenance and unclassified instance label retained")
assert(expanded[3].detail:find("NOT an equip test",1,true),
    "Future items never claim to be equipped")
assert(original.assessment==nil and original.eligibility=="verify",
    "Input records remain unchanged")
assert(table.concat(called,",")==
    "candidates:5,weapon,assessment,shortlist,candidates:10,weapon,assessment,shortlist",
    "Candidates are validated, assessed, then limited")
local empty=P:ViewRows(nil,5,false)
assert(#empty==1 and empty[1].id=="future-empty","No character is handled")
print("PASS: future gear UI model shows controls, evidence and source details safely")
