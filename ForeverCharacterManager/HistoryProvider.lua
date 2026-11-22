-- Schema-2 public adapter and common interface. No private implementation ships here.
local _,FCM=...
local H={revision='fcm-statistics-2.0.0',interfaceVersion=2};FCM.HistoryProvider=H
local function num(v)return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function integer(v)return num(v) and v==math.floor(v)end
local function civil(y,m,d)
 y=y-(m<=2 and 1 or 0);local era=math.floor(y/400);local yy=y-era*400
 local mm=m+(m>2 and -3 or 9)
 return era*146097+yy*365+math.floor(yy/4)-math.floor(yy/100)+math.floor((153*mm+2)/5)+d-1-719468
end
local function offset(ts)
 local dt=(date or os.date)('!*t',ts);local y=dt.year
 local mar=civil(y,3,1);local nov=civil(y,11,1)
 local start=(mar+7+(7-(mar+4)%7)%7)*86400+36000
 local finish=(nov+(7-(nov+4)%7)%7)*86400+32400
 return ts>=start and ts<finish and -25200 or -28800
end
local function day(ts)return math.floor((ts+offset(ts))/86400)end
local function uuid(v)
 if type(v)~='string' then return false end
 local a,b,c,d,e=v:match('^(%x+)%-(%x+)%-(%x+)%-(%x+)%-(%x+)$')
 return a and #a==8 and #b==4 and #c==4 and #d==4 and #e==12
end
-- Independent, short-lived authorization state, never supplied by an export.
-- Default unavailable: provider-containing history is denied without a reviewed
-- integration delivering current state. Payloads cannot authorize themselves.
function H:NotifyAuthorizationChange()
 local g=FCM.GoldAdvisor
 if g and type(g.InvalidateHistoryViews)=='function' then g:InvalidateHistoryViews('History authorization state changed; refresh required.') end
end
function H:SetAuthorizations(state)
 local now=FCM:Now()
 if type(state)~='table' or not integer(state.generation) or state.generation<1 then self.authorizationState=nil;self:NotifyAuthorizationChange();return false end
 if state.generation<=(self.lastAuthorizationGeneration or 0) then return false end
 if not integer(state.asOf) or not integer(state.validUntil) or state.asOf>now or
 state.validUntil<=now or state.validUntil<=state.asOf or state.validUntil-state.asOf>300 or type(state.grants)~='table' then self.authorizationState=nil;self:NotifyAuthorizationChange();return false end
 local copy={generation=state.generation,asOf=state.asOf,validUntil=state.validUntil,grants={}}
 for digest,g in pairs(state.grants)do
  if type(digest)~='string' or #digest~=64 or not digest:match('^%x+$') or type(g)~='table' or
   not integer(g.expiresUtc) or not integer(g.retentionDays) or g.retentionDays<1 or g.retentionDays>365 or type(g.revoked)~='boolean' then
    self.authorizationState=nil;self:NotifyAuthorizationChange();return false
  end
  copy.grants[digest]={expiresUtc=g.expiresUtc,retentionDays=g.retentionDays,revoked=g.revoked}
 end
 self.authorizationState=copy;self.lastAuthorizationGeneration=state.generation;self:NotifyAuthorizationChange();return true
end
function H:AuthorizationCurrent(grant)
 local state=self.authorizationState;local now=FCM:Now()
 if not state or state.asOf>now or now>=state.validUntil then return false end
 local g=state.grants[grant.digest]
 return g and not g.revoked and now<g.expiresUtc and g.expiresUtc>=grant.expiresUtc and g.retentionDays>=grant.retentionDays
end
function H:Validate(d,id,classification,windows,baseline)
 local now=FCM:Now()
 if type(d)~='table' or d.packed~=nil or d.schema~=2 or d.interfaceVersion~=2 or d.engineRevision~=self.revision or d.providerID~=id or
 d.classification~=classification or d.timezone~='America/Los_Angeles' or d.baselineHorizon~=baseline or
 not uuid(d.rootInstanceID) or not uuid(d.datasetID) or not integer(d.generation) or d.generation<1 or
 d.authorizationPolicy~=1 or type(d.authorizations)~='table' or type(d.recommendationsAllowed)~='boolean' or
 not integer(d.asOf) or d.asOf>now or now-d.asOf>90000 or not integer(d.validUntil) or
 d.validUntil<=d.asOf or d.validUntil-d.asOf>90000 or day(now)~=day(d.asOf) or
 type(d.windows)~='table' or #d.windows~=#windows or type(d.markets)~='table' or (d.demandMaxAge~=nil and (not num(d.demandMaxAge) or d.demandMaxAge<=0 or d.demandMaxAge>604800)) then return nil,'History metadata unavailable/incompatible' end
 local y,m,n=tostring(d.eligibleCutoffDate):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
 if not y or tonumber(m)<1 or tonumber(m)>12 or tonumber(n)<1 or tonumber(n)>31 or (date or os.date)('!%Y-%m-%d',civil(tonumber(y),tonumber(m),tonumber(n))*86400)~=d.eligibleCutoffDate or civil(tonumber(y),tonumber(m),tonumber(n))~=day(now)-baseline+1 or
 not integer(d.eligibleCutoffUtc) or day(d.eligibleCutoffUtc)~=day(now)-baseline+1 or day(d.eligibleCutoffUtc-1)~=day(now)-baseline or
 not integer(d.dayBoundaryUtc) or day(d.dayBoundaryUtc)~=day(now)+1 or day(d.dayBoundaryUtc-1)~=day(now) or d.validUntil>d.dayBoundaryUtc then return nil,'History cutoff is invalid' end
 -- Count actual keys, never Lua 5.1's undefined sparse-table length.
 -- Every key must be an integer in 1..count, with no holes or proxy entries.
 if getmetatable(d.authorizations)~=nil then return nil,'Invalid authorization array' end
 local authorizationCount=0
 for key in pairs(d.authorizations)do
  if not integer(key) or key<1 then return nil,'Invalid authorization array' end
  authorizationCount=authorizationCount+1
 end
 for i=1,authorizationCount do
  if rawget(d.authorizations,i)==nil then return nil,'Invalid authorization array' end
 end
 local providers=type(d.provenanceSummary)=='table' and d.provenanceSummary.providerObservations
 if not integer(providers) or providers<0 or
 (providers==0 and (d.variant~='personal-only' or authorizationCount~=0)) or
 (providers>0 and (d.variant~='with-provider' or authorizationCount==0)) then return nil,'Invalid provider authorization metadata' end
 local seen={}
 for i=1,authorizationCount do
  local g=rawget(d.authorizations,i)
  if type(g)~='table' or
   type(g.digest)~='string' or #g.digest~=64 or not g.digest:match('^%x+$') or seen[g.digest] or
   not integer(g.expiresUtc) or g.expiresUtc<=d.asOf or d.validUntil>g.expiresUtc or
   not integer(g.retentionDays) or g.retentionDays<1 or g.retentionDays>365 then
    return nil,'Invalid provider authorization metadata'
  end
  seen[g.digest]=true
 end
 local allowed={}
 for i,w in ipairs(windows)do if d.windows[i]~=w then return nil,'Unsupported history windows'end;allowed[tostring(w)]=true end
 for market,items in pairs(d.markets)do
  if type(market)~='string' or not market:match('^forever/[%w]+/[a-z]+/[a-z]+$') or type(items)~='table' then return nil,'Invalid history market'end
  for item,r in pairs(items)do
   if not tonumber(item) or type(r)~='table' or (r.currentSource~='scan' and r.currentSource~='table') or (r.currentSource=='table' and providers==0) or not integer(r.observedDays) or r.observedDays<1 or r.observedDays>baseline or
    not integer(r.observations) or r.observations<r.observedDays or not num(r.currentUtc) or r.currentUtc>d.asOf or
    r.currentUtc<d.eligibleCutoffUtc or not num(r.current) or r.current<=0 or type(r.windows)~='table' or
    (r.confidence~='low' and r.confidence~='moderate' and r.confidence~='high') or
    (r.confidence=='high' and r.observedDays<60) or (r.confidence=='moderate' and r.observedDays<14) then return nil,'Invalid history evidence'end
   for w,v in pairs(r.windows)do
    if not allowed[tostring(w)] or type(v)~='table' or not integer(v.days) or v.days<0 or v.days>tonumber(w) or
    v.days>r.observedDays or (v.average~=nil and (not num(v.average) or v.average<=0)) then return nil,'Invalid historical window'end
   end
   for _,w in ipairs(windows)do if not r.windows[tostring(w)] then return nil,'Missing historical window'end end
   if r.windows[tostring(baseline)].days~=r.observedDays or not num(r.minimum) or not num(r.maximum) or
    r.minimum<=0 or r.maximum<r.minimum or r.current<r.minimum or r.current>r.maximum or
    (r.volatility~=nil and (not num(r.volatility) or r.volatility<0)) or
    (r.trendPct~=nil and not num(r.trendPct)) or
    (r.low~=nil and (not num(r.low) or r.low<=0)) or
    (r.supply~=nil and (not num(r.supply) or r.supply<0)) then return nil,'Invalid price/evidence measures'end
  end
 end
 -- Only authorization usability failures, after full structural validation,
 -- permit selection of independently calculated personal-only fallback.
 for i=1,authorizationCount do
  local g=rawget(d.authorizations,i)
  if not self:AuthorizationCurrent(g) then return nil,'Provider authorization expired, revoked, stale or unavailable','authorization' end
 end
 if now>=d.validUntil then
  return nil,'History validity expired'
 end
 return d
end
function H:SelectValidated(data,id,classification,windows,baseline)
 local d,problem,failure=self:Validate(data,id,classification,windows,baseline)
 if d then return d end
 if failure~='authorization' then return nil,problem end
 -- Fallback is an independently calculated personal-only dataset, never a
 -- relabelled mixed aggregate. Its scope/identity must match the primary.
 local f=type(data)=='table' and data.personalFallback
 if type(data)=='table' and data.schema==2 and data.interfaceVersion==2 and data.engineRevision==self.revision and data.providerID==id and data.classification==classification and data.baselineHorizon==baseline and data.timezone=='America/Los_Angeles' and data.authorizationPolicy==1 and data.variant=='with-provider' and type(f)=='table' and
  f.providerID==data.providerID and f.datasetID==data.datasetID and f.rootInstanceID==data.rootInstanceID and
  f.generation==data.generation and f.asOf==data.asOf and f.eligibleCutoffDate==data.eligibleCutoffDate and f.eligibleCutoffUtc==data.eligibleCutoffUtc and f.dayBoundaryUtc==data.dayBoundaryUtc and f.variant=='personal-only' and f.recommendationsAllowed==false then
   local valid=self:Validate(f,id,classification,windows,baseline)
   if valid then return valid,'Personal-only history; provider authorization unavailable; recommendations disabled' end
 end
 return nil,problem
end
function H:RegisterPrivate(id,getter)
 local fn=IsAddOnLoaded or (C_AddOns and C_AddOns.IsAddOnLoaded)
 if id~='FCMPrivateHistory' or type(getter)~='function' or not fn or not fn(id) then return false end
 self.private={id=id,get=getter};return true
end
function H:Selected()
 local expected=FCM.db and FCM.db.settings and FCM.db.settings.historyProvider
 local data,problem
 if expected~=nil then
  if type(expected)~='table' or expected.providerID~='FCMPrivateHistory' or not self.private then
   self.status='Expected private history provider unavailable; public fallback disabled';return nil,self.status
  end
  local ok,a,b=pcall(self.private.get);if ok then data,problem=a,b else problem='Private provider failed validation' end
  if data and (data.rootInstanceID~=expected.rootInstanceID or data.generation~=expected.generation)then data=nil;problem='Private history binding/generation mismatch'end
 else data,problem=self:SelectValidated(FCM_PublicHistory,'FCMPublicHistory','public30',{7,30},30) end
 self.status=data and (problem or ('Validated '..data.classification..' history')) or (problem or 'History unavailable')
 return data,self.status
end
