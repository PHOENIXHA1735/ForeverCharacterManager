local now=1800043200 -- 2027-01-15 12:00 Pacific (invented).
local f={db={settings={}}}
function f:Now() return now end
function f:AuctionMarketFor() return "forever/normal/alliance/us" end
time=function() return now end
assert(loadfile("ForeverCharacterManager/HistoryProvider.lua"))("FCM",f)
assert(loadfile("ForeverCharacterManager/GoldAdvisor.lua"))("FCM",f)
local h,g=f.HistoryProvider,f.GoldAdvisor
local root="00000000-0000-0000-0000-000000000001"
local dataset="00000000-0000-0000-0000-000000000002"
local function data(id,classification,baseline,windows,cutoff,cutoffUtc)
    local averages={}
    for _,days in ipairs(windows) do averages[tostring(days)]={days=1,average=100} end
    return {schema=2,interfaceVersion=2,engineRevision=h.revision,providerID=id,
        classification=classification,baselineHorizon=baseline,windows=windows,
        timezone="America/Los_Angeles",rootInstanceID=root,datasetID=dataset,generation=1,
        authorizationPolicy=1,authorizations={},recommendationsAllowed=true,variant="personal-only",
        asOf=now,validUntil=now+60,dayBoundaryUtc=1800086400,eligibleCutoffDate=cutoff,eligibleCutoffUtc=cutoffUtc,
        provenanceSummary={providerObservations=0},markets={["forever/normal/alliance/us"]={
            ["42"]={currentSource="scan",observedDays=1,observations=1,currentUtc=now,current=100,
                minimum=100,maximum=100,confidence="low",windows=averages},
        }}}
end
FCM_AHHistory={schema=1}
assert(next((g:Prices({})))==nil and g.providerStatus)
local public=data("FCMPublicHistory","public30",30,{7,30},"2026-12-17",1797494400)
FCM_PublicHistory=public
local price=g:Prices({})
assert(price[42].averages[30]==100 and price[42].averages[365]==nil)
local private=data("FCMPrivateHistory","private365",365,{7,30,90,180,365},"2026-01-16",1768550400)
f.db.settings.historyProvider={providerID="FCMPrivateHistory",rootInstanceID=root,generation=1}
assert(next((g:Prices({})))==nil and g.providerStatus:find("public fallback disabled",1,true))
IsAddOnLoaded=function(id) return id=="FCMPrivateHistory" end
local function readPrivate()
    return h:SelectValidated(private,"FCMPrivateHistory","private365",{7,30,90,180,365},365)
end
assert(h:RegisterPrivate("FCMPrivateHistory",readPrivate))
price=g:Prices({})
assert(price[42].classification=="private365" and price[42].averages[365]==100)
f.db.settings.historyProvider.generation=2
assert(next((g:Prices({})))==nil and not g.providerData and g.providerStatus:find("binding/generation",1,true))
f.db.settings.historyProvider.generation=1
private.authorizations={[2]={digest=string.rep("a",64),expiresUtc=now+60,retentionDays=30}}
assert(next((g:Prices({})))==nil and g.providerStatus=="Invalid authorization array")
private.authorizations={}
now=now+60
assert(next((g:Prices({})))==nil and g.providerStatus=="History validity expired")
print("PASS: schema-2 public limits, private selection, binding, sparse authorization, expiry, legacy refusal")
