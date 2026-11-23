-- FCM PR #8 reviewed material overlay. Data only; no account records or coordinates.
-- Keep generated ForeverDB snapshot separate so a companion refresh cannot erase these curated entries.
local _,FCM=...
local reference=FCM.gatheringReference
if not reference or type(reference.resources)~='table' then return end
reference.sources=reference.sources or {}
local addedSources={
  {id='forever-swiftthistle',name='WoW Forever Swiftthistle item sources',url='https://db.icy-veins.com/wow-forever/items/2452',status='reference_reviewed'},
  {id='forever-frilled',name='WoW Forever Frilled Lichen item sources',url='https://warcraft.wiki.gg/wiki/Frilled_Lichen',status='reference_reviewed'},
  {id='forever-herb-seeds',name='WoW Forever Commonplace Herb Seeds item sources',url='https://guide.wow4ever.se/en/items/268415',status='reported_reference'},
  {id='classic-mining-yields',name='Classic Mining ore, stone and gem candidate sources',url='https://www.wowhead.com/classic/guide/mining-leveling-1-300-wow-classic',status='classic_reference_only'}
}
for _,src in ipairs(addedSources) do reference.sources[#reference.sources+1]=src end
local entries={
 {id="herbalism:swiftthistle",name="Swiftthistle",category="herbalism",itemID=2452,material=true,materialType="Herbalism bonus herb",materialSources={"Mageroyal","Briarthorn"},environment="Herb item harvested as an additional yield; not a standalone herb node.",sourceIDs={"forever-swiftthistle"},verificationStatus='reported_reference',locations={},loot={}},
 {id="herbalism:commonplace-herb-seeds",name="Commonplace Herb Seeds",category="herbalism",itemID=268415,material=true,materialType="Herbalism seed",materialSources={"Peacebloom","Silverleaf"},environment="Greenhouse seeds occasionally obtained while gathering qualifying herbs; not their own plant node.",sourceIDs={"forever-herb-seeds"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:rough-stone",name="Rough Stone",category="mining",itemID=2835,material=true,materialType="Stone",materialSources={"Copper Vein","Poor Copper Vein"},environment="Classic mining source mapping; confirm Forever-specific deposits.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:coarse-stone",name="Coarse Stone",category="mining",itemID=2836,material=true,materialType="Stone",materialSources={"Tin Vein"},environment="Classic mining source mapping; Forever verification pending.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:heavy-stone",name="Heavy Stone",category="mining",itemID=2838,material=true,materialType="Stone",materialSources={"Iron Deposit"},environment="Classic mining source mapping; Forever verification pending.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:solid-stone",name="Solid Stone",category="mining",itemID=7912,material=true,materialType="Stone",materialSources={"Mithril Deposit"},environment="Classic mining source mapping; Forever verification pending.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:dense-stone",name="Dense Stone",category="mining",itemID=12365,material=true,materialType="Stone",materialSources={"Small Thorium Vein","Rich Thorium Vein"},environment="Classic mining source mapping; Forever verification pending.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:copper-ore",name="Copper Ore",category="mining",itemID=2770,material=true,materialType="Ore",materialSources={"Copper Vein","Poor Copper Vein"},environment="Copper-bearing nodes; source skill, not a separate ore skill.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:tin-ore",name="Tin Ore",category="mining",itemID=2771,material=true,materialType="Ore",materialSources={"Tin Vein"},environment="Tin-bearing nodes; source skill, not a separate ore skill.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:silver-ore",name="Silver Ore",category="mining",itemID=2775,material=true,materialType="Ore",materialSources={"Silver Vein","Ooze Covered Silver Vein"},environment="Silver-bearing nodes; source skill, not a separate ore skill.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:iron-ore",name="Iron Ore",category="mining",itemID=2772,material=true,materialType="Ore",materialSources={"Iron Deposit"},environment="Iron-bearing nodes; source skill, not a separate ore skill.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:gold-ore",name="Gold Ore",category="mining",itemID=2776,material=true,materialType="Ore",materialSources={"Gold Vein","Ooze Covered Gold Vein"},environment="Gold-bearing nodes; source skill, not a separate ore skill.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:mithril-ore",name="Mithril Ore",category="mining",itemID=3858,material=true,materialType="Ore",materialSources={"Mithril Deposit","Ooze Covered Mithril Deposit"},environment="Mithril-bearing nodes; source skill, not a separate ore skill.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:truesilver-ore",name="Truesilver Ore",category="mining",itemID=7911,material=true,materialType="Ore",materialSources={"Truesilver Deposit","Ooze Covered Truesilver Deposit"},environment="Truesilver-bearing nodes; source skill, not a separate ore skill.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:thorium-ore",name="Thorium Ore",category="mining",itemID=10620,material=true,materialType="Ore",materialSources={"Small Thorium Vein","Rich Thorium Vein","Ooze Covered Thorium Vein","Ooze Covered Rich Thorium Vein"},environment="Thorium-bearing nodes; source skill, not a separate ore skill.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:dark-iron-ore",name="Dark Iron Ore",category="mining",itemID=11370,material=true,materialType="Ore",materialSources={"Dark Iron Deposit"},environment="Dark Iron-bearing nodes; source skill, not a separate ore skill.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:malachite",name="Malachite",category="mining",itemID=774,material=true,materialType="Gem",materialSources={"Copper Vein"},environment="Classic candidate gem source; Forever drop unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:tigerseye",name="Tigerseye",category="mining",itemID=818,material=true,materialType="Gem",materialSources={"Copper Vein"},environment="Classic candidate gem source; Forever drop unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:shadowgem",name="Shadowgem",category="mining",itemID=1210,material=true,materialType="Gem",materialSources={"Tin Vein"},environment="Classic candidate gem source; Forever drop unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:moss-agate",name="Moss Agate",category="mining",itemID=1206,material=true,materialType="Gem",materialSources={"Tin Vein"},environment="Classic candidate gem source; Forever drop unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:lesser-moonstone",name="Lesser Moonstone",category="mining",itemID=1705,material=true,materialType="Gem",materialSources={"Tin Vein","Iron Deposit"},environment="Classic candidate gem sources; Forever drops unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:jade",name="Jade",category="mining",itemID=1529,material=true,materialType="Gem",materialSources={"Iron Deposit","Mithril Deposit"},environment="Classic candidate gem sources; Forever drops unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:citrine",name="Citrine",category="mining",itemID=3864,material=true,materialType="Gem",materialSources={"Iron Deposit","Mithril Deposit"},environment="Classic candidate gem sources; Forever drops unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:aquamarine",name="Aquamarine",category="mining",itemID=7909,material=true,materialType="Gem",materialSources={"Iron Deposit","Mithril Deposit"},environment="Classic candidate gem sources; Forever drops unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:star-ruby",name="Star Ruby",category="mining",itemID=7910,material=true,materialType="Gem",materialSources={"Mithril Deposit","Rich Thorium Vein"},environment="Classic candidate gem sources; Forever drops unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:large-opal",name="Large Opal",category="mining",itemID=12799,material=true,materialType="Gem",materialSources={"Rich Thorium Vein"},environment="Classic candidate gem sources; Forever drops unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:blue-sapphire",name="Blue Sapphire",category="mining",itemID=12361,material=true,materialType="Gem",materialSources={"Rich Thorium Vein"},environment="Classic candidate gem sources; Forever drops unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:azerothian-diamond",name="Azerothian Diamond",category="mining",itemID=12800,material=true,materialType="Gem",materialSources={"Rich Thorium Vein"},environment="Classic candidate gem sources; Forever drops unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:huge-emerald",name="Huge Emerald",category="mining",itemID=12364,material=true,materialType="Gem",materialSources={"Rich Thorium Vein"},environment="Classic candidate gem sources; Forever drops unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
 {id="mining:arcane-crystal",name="Arcane Crystal",category="mining",itemID=12363,material=true,materialType="Gem",materialSources={"Rich Thorium Vein"},environment="Classic candidate gem sources; Forever drops unverified.",sourceIDs={"classic-mining-yields"},verificationStatus='reported_reference',locations={},loot={}},
}
-- Convert the legacy Frilled Lichen alias into the actual selectable item rather than duplicating it.
for _,r in ipairs(reference.resources) do
 if r.category=='herbalism' and r.name=='Scarce Frilled Lichen' then
  r.name='Frilled Lichen';r.id='herbalism:frilled-lichen';r.itemID=249399
  r.material=true;r.materialType='Scarce herb yield'
  r.materialSources={'Earthroot','Mageroyal','Briarthorn','Kingsblood'}
  r.environment='Scarce additional yield from eligible herb nodes; candidate source list is not exhaustive and Grave Moss is excluded.'
  r.sourceIDs={'forever-frilled'};r.verificationStatus='reported_reference'
 end
end
local index={}
for _,r in ipairs(reference.resources) do index[r.category..':'..r.name:lower()]=true end
for _,r in ipairs(entries) do
 if not index[r.category..':'..r.name:lower()] then
  reference.resources[#reference.resources+1]=r
  index[r.category..':'..r.name:lower()]=true
 end
end
reference.coverage=reference.coverage or {}
reference.coverage.complete=false
reference.coverage.materialOverlay=true
-- Overlay entries are not counted as personally discovered points and have no map coordinates.
