local function slurp(path)
    local f=assert(io.open(path,'rb'));local data=f:read('*a');f:close();return data
end
local root='ForeverCharacterManager/'
local toc=slurp(root..'ForeverCharacterManager.toc')
local accepted={
    ['ExternalData.generated.lua']='local _,f=...; f.externalData={ahFetchedUtc=1700000000}',
    ['PublicHistory.generated.lua']='FCM_PublicHistory={asOf=1700000001}',
    ['GatheringReferenceData.lua']='local _,f=...; f.gatheringReference={generatedUtc=1700000002}',
}
local function loadSession()
    local f={Age=function(_,stamp)return 'age '..stamp end,TimestampLabel=function(_,stamp)return tostring(stamp) end}
    local seen={}
    for line in toc:gmatch('[^\r\n]+') do
        if accepted[line] then assert(loadstring(accepted[line]))('FCM',f);seen[line]=true end
    end
    for path in pairs(accepted) do assert(seen[path],path..' must be registered') end
    -- Gold reports the selected provider's validated dataset, not raw globals.
    f.GoldAdvisor={providerData=FCM_PublicHistory}
    assert(loadfile(root..'UI.lua'))('FCM',f)
    return f.UI
end
local ui=loadSession()
local expected=ui:PublishedDataStatus('Auction')
assert(expected:find('1700000000',1,true) and expected:find('age',1,true))
assert(ui:PublishedDataStatus('Gold'):find('1700000001',1,true))
assert(ui:PublishedDataStatus('Gathering'):find('1700000002',1,true))
local reloads=0
ReloadUI=function()reloads=reloads+1 end
ui:ReloadPublishedData()
ui:ReloadPublishedData()
assert(reloads==2,'reload works with or without a newer generation')
accepted['ExternalData.generated.lua']='local _,f=...; f.externalData={ahFetchedUtc=1700000003}'
assert(ui:PublishedDataStatus('Auction')==expected,'loaded tables are unchanged until reload')
ui=loadSession()
assert(ui:PublishedDataStatus('Auction'):find('1700000003',1,true))
print('PASS: TOC-listed generations are adopted on fresh load, timestamps and unconditional reload')
