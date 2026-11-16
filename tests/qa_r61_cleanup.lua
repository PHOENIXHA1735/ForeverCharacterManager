-- Focused R6.1 source guidance and inventory no-match message regression.
local function has(value,fragment,label)
    assert(type(value)=="string" and value:find(fragment,1,true),label or fragment)
end
local FCM={externalData={items={
    [8001]={name="Vendor Test",soldBy="Named Test Merchant"},
    [8002]={name="Reference Test",where="Vendor purchase: Example Reference Merchant"},
    [8003]={name="Unknown Test"},
}}}
assert(loadfile("ForeverCharacterManager/FarmingAdvisor.lua"))("ForeverCharacterManager",FCM)
local alliance=FCM:FarmQuickLine(2321,{faction="Alliance"},2)
has(alliance,"Edna Mullby","Alliance Fine Thread source")
has(alliance,"Elynna","Alliance alternative vendor")
has(alliance,"verify current stock","No false guarantee about live vendor stock")
local horde=FCM:FarmQuickLine(2321,{faction="Horde"},2)
has(horde,"Ranik","Horde Fine Thread source")
assert(not horde:find("Edna Mullby",1,true),"Horde must not be directed to Alliance-only vendor")
has(FCM:FarmQuickLine(8001,nil,1),"Named Test Merchant","imported vendor field")
has(FCM:FarmQuickLine(8002,nil,1),"Example Reference Merchant","imported source hint")
has(FCM:FarmQuickLine(8003,nil,1),"No imported farm or vendor source","honest unknown source")
local lines=FCM:FarmAdviceLines(2321,2,{faction="Alliance"})
local found=false
for _,line in ipairs(lines) do if line:find("Edna Mullby",1,true) then found=true end end
assert(found,"Item Explorer should expose the vendor source")
local f=assert(io.open("ForeverCharacterManager/UI.lua","r"))
local ui=f:read("*a");f:close()
has(ui,"No matching inventory stock","Inventory no-match title")
has(ui,"A missing result does not mean the item is missing from the game","Inventory explanation")
has(ui,"use Item Explorer to search the reference database","Reference and inventory distinguished")
has(ui,"Possible source for missing materials (reference only)","Shopping should show source hints")
print("PASS: R6.1 vendor source selection and Inventory guidance")
