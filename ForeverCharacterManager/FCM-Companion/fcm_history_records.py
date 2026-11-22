"""Explicit record validation / source eligibility, shared by separate controllers."""
import re,math
from datetime import timedelta,datetime,timezone
from zoneinfo import ZoneInfo
from fcm_history_engine import local_date,window_start,REVISION,calculate
MARKET=re.compile(r'forever/(normal|pvp|rp|rppvp)/(alliance|horde)/(us|eu|cn)')
ZONE=ZoneInfo('America/Los_Angeles')
def number(n):return type(n) in (int,float) and math.isfinite(n)
def _eligible(records,now,horizon,permissions):
    accepted=[];rejected={};sales=[];admitted=[]
    for r in records:
        reason=None;provenance=r.get('provenance') if isinstance(r,dict) else None
        if provenance not in ('personal_scan','provider_snapshot','personal_sale'):reason='unknown provenance'
        elif not number(r.get('ts')) or r['ts']>now or r['ts']<946684800:reason='invalid/future timestamp'
        else:
            days=horizon
            if provenance=='provider_snapshot':days=min(days,permissions.days(r.get('source'),r.get('permissionID'),now))
            if days<=0:reason='provider permission unavailable'
            elif r['ts']<window_start(now,days,ZONE):reason='expired observation date'
            elif provenance=='personal_sale':
                if not all(number(r.get(k)) and r[k]>=0 for k in ('item','qty','gross','cut','deposit')) or r['qty']<=0 or type(r['item']) is not int or r['item']<0 or type(r.get('seq')) is not int or r['seq']<=0 or not isinstance(r.get('source'),str) or not r['source'] or r['cut']>r['gross']:reason='invalid sale'
                else:sales.append(r);continue
            elif not MARKET.fullmatch(str(r.get('market',''))) or type(r.get('item')) is not int or r['item']<=0:reason='invalid market/item'
            elif not number(r.get('price')) or r['price']<=0:reason='invalid price'
            elif any(r.get(k) is not None and (not number(r[k]) or r[k]<0) for k in ('low','supply','pace')):reason='invalid optional measure'
            else:
                accepted.append((r['market'],r['item'],r['ts'],'scan' if provenance=='personal_scan' else 'table',r['price'],r.get('low'),r.get('supply'),r.get('pace')));admitted.append(r);continue
        rejected[reason]=rejected.get(reason,0)+1
    return accepted,sales,rejected,admitted

def eligible(records,now,horizon,permissions):
    return _eligible(records,now,horizon,permissions)[:3]

def export(records,now,horizon,windows,root,provider,permissions):
    records=list(records)
    rows,sales,rejected,admitted=_eligible(records,now,horizon,permissions)
    # Exactly the rows chosen by the engine's stable personal-first dedup order.
    chosen=[];seen_rows=set()
    for row,record in sorted(zip(rows,admitted),key=lambda pair:(pair[0][0],pair[0][1],pair[0][2],0 if pair[0][3]=='scan' else 1)):
        if row[:3] not in seen_rows:chosen.append(record);seen_rows.add(row[:3])
    included_providers=[r for r in chosen if r['provenance']=='provider_snapshot']
    grants={}
    for record in included_providers:
        grant=permissions.authorization(record.get('source'),record.get('permissionID'),now)
        if not grant:raise ValueError('Authorization changed during export; no output permitted')
        grants[grant['digest']]=grant
    markets=calculate(rows,now,windows,horizon,ZONE)
    first=local_date(now,ZONE)-timedelta(days=horizon-1)
    tomorrow=local_date(now,ZONE)+timedelta(days=1)
    valid_until=int(datetime.combine(tomorrow,datetime.min.time(),tzinfo=ZONE).timestamp())
    day_boundary=valid_until
    if grants:valid_until=min(valid_until,min(g['expiresUtc'] for g in grants.values()))
    # Sales are account-scoped, never assigned an invented faction market.
    sale_data={};seen=set()
    for r in sales:
        key=(r.get('source'),r.get('seq'),r['ts'],r['item'])
        if key in seen:continue
        seen.add(key);q=sale_data.setdefault(str(r['item']),dict(events=0,units=0,gross=0,cut=0,netProceeds=0,refundedDeposits=0))
        for key,value in [('events',1),('units',r['qty']),('gross',r['gross']),('cut',r['cut']),('netProceeds',r['gross']-r['cut']),('refundedDeposits',r['deposit'])]:q[key]+=value
        q['latestRecordedUtc']=max(q.get('latestRecordedUtc',0),r['ts']);q['latestRecordedLocal']=datetime.fromtimestamp(q['latestRecordedUtc'],timezone.utc).astimezone(ZONE).isoformat()
    data=dict(schema=2,interfaceVersion=2,engineRevision=REVISION,providerID=provider,
        rootInstanceID=root['rootInstanceID'],datasetID=root['datasetID'],generation=root['generation'],
        classification=root['classification'],timezone='America/Los_Angeles',asOf=now,validUntil=valid_until,dayBoundaryUtc=day_boundary,
        authorizationPolicy=1,authorizations=sorted(grants.values(),key=lambda g:g['digest']),
        variant='with-provider' if included_providers else 'personal-only',recommendationsAllowed=True,
        eligibleCutoffDate=str(first),eligibleCutoffUtc=window_start(now,horizon,ZONE),windows=list(windows),baselineHorizon=horizon,
        demandMaxAge=min([604800]+[g['retentionDays']*86400 for g in grants.values()]),
        markets=markets,personalSales=sale_data,permissionSummary='Personal observations; provider records require reviewed pinned permission',
        rejected=rejected,provenanceSummary=dict(eligibleObservations=len(chosen),providerObservations=len(included_providers),eligibleSales=len(seen)))

    if included_providers:
        personal=[r for r in records if isinstance(r,dict) and r.get('provenance') in ('personal_scan','personal_sale')]
        data['personalFallback']=export(personal,now,horizon,windows,root,provider,permissions)
        # Personal data can remain visible, but automatic fallback is never a
        # replacement authorization for recommendations after provider failure.
        data['personalFallback']['recommendationsAllowed']=False
    return data

def lua(v):
    if v is None:return 'nil'
    if v is True:return 'true'
    if v is False:return 'false'
    if isinstance(v,str):
        import json
        return json.dumps(v,ensure_ascii=False)
    if isinstance(v,(int,float)):return repr(v)
    if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
    return '{'+','.join('['+lua(str(k))+']='+lua(x) for k,x in v.items())+'}'
