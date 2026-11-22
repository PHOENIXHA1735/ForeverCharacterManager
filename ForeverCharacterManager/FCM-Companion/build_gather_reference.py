"""Offline Gathering reference compiler. No network, Lua execution or SavedVariables.

Input is a reviewed JSON document, never a downloaded script. Nulls mean unknown.
The compiler imports the complete supported input or refuses it; no row truncation.
"""
from pathlib import Path
import argparse,copy,hashlib,json,os,shutil,tempfile
from datetime import datetime

MAX_INPUT=16*1024*1024
MAX_OUTPUT=8*1024*1024
MAX_RECORDS=20000
MAX_LOCATIONS=200
CATEGORIES={'herbalism','mining','fishing','treasure'}
FISHING={'pool','school','wreckage','oil_spill','open_water','lake','river','coast','unknown'}
WATER_TYPES={'ocean','coastal','freshwater','lake','river','unknown'}
LOOT_EVIDENCE={'classic_reference','provider_reference','forever_observed'}
FIELDS={'id','name','category','objectID','itemID','iconID','profession','minimumSkill',
        'orange','yellow','green','gray','locations','environment','loot','fishingSourceType',
        'fishingMinimum','fishingNoGetAways','sourceIDs','verificationStatus',
        'lastReferenceUpdate','itemIDStatus','itemIconStrategy','objectType','candidateItemID','reportedObjectIDs'}

def text(value,limit=500):
    if not isinstance(value,str) or not value or len(value)>limit or any(ord(c)<32 or c=='|' for c in value):
        raise ValueError('Invalid reference text')
    return value

def integer(value,maximum=2**31-1):
    if value is not None and (type(value) is not int or not 0<value<=maximum):
        raise ValueError('Invalid numeric reference field')

def validate(document):
    d=copy.deepcopy(document)
    if not isinstance(d,dict) or set(d)-{'schema','game','generatedAt','lastSuccessfulSync','sourceVersion','sources','resources','coverage'}:raise ValueError('Unsupported document field')
    if type(d.get('schema')) is not int or d.get('schema')!=1 or d.get('game')!='WoW Forever':raise ValueError('Unsupported reference schema/game')
    at=datetime.fromisoformat(d['generatedAt'])
    if at.tzinfo is None or at.utcoffset().total_seconds()!=0:raise ValueError('UTC generation time required')
    if not isinstance(d.get('sources'),list) or len(d['sources'])>100:raise ValueError('Source budget')
    sources={}
    for source in d['sources']:
        if not isinstance(source,dict) or set(source)-{'id','name','url','permission','version','status'}:raise ValueError('Unsupported source field')
        sid=text(source['id']);text(source['name']);url=text(source['url'])
        if not url.startswith('https://') or sid in sources:raise ValueError('Invalid source identity/URL')
        text(source['permission'],1000);sources[sid]=source
    if not isinstance(d.get('resources'),list) or len(d['resources'])>MAX_RECORDS:raise ValueError('Resource budget')
    seen=set();objects=set()
    for r in d['resources']:
        if not isinstance(r,dict) or set(r)-FIELDS:raise ValueError('Unsupported resource field')
        rid=text(r['id']);text(r['name']);kind=r['category']
        if rid in seen or kind not in CATEGORIES:raise ValueError('Duplicate/invalid resource')
        seen.add(rid)
        for k in ('objectID','itemID','candidateItemID','iconID','minimumSkill','orange','yellow','green','gray','fishingMinimum','fishingNoGetAways'):integer(r.get(k))
        aliases=r.get('reportedObjectIDs',[])
        if not isinstance(aliases,list) or len(aliases)>1000:raise ValueError('Invalid reported object IDs')
        for alias in aliases:integer(alias)
        if r.get('objectID'):
            key=(kind,r['objectID'])
            if key in objects:raise ValueError('Duplicate object relationship')
            objects.add(key)
            if rid!='object:'+str(r['objectID']):raise ValueError('Object identity mismatch')
        if kind=='fishing' and r.get('fishingSourceType') not in FISHING:raise ValueError('Unknown fishing source type')
        if kind!='fishing' and r.get('fishingSourceType') is not None:raise ValueError('Fishing category mismatch')
        if kind=='treasure' and (not r.get('objectID') or r.get('objectType') not in ('chest','coffer','strongbox','footlocker') or r.get('verificationStatus')!='reference_reviewed'):
            raise ValueError('Treasure requires a verified gathering object, not fished loot')
        skills=[r.get(k) for k in ('orange','yellow','green','gray')]
        if all(v is not None for v in skills) and skills!=sorted(skills):raise ValueError('Invalid skill order')
        if r.get('fishingMinimum') and r.get('fishingNoGetAways') and r['fishingNoGetAways']<r['fishingMinimum']:raise ValueError('Invalid water skills')
        if not isinstance(r.get('sourceIDs'),list) or not r['sourceIDs'] or len(r['sourceIDs'])>100 or any(s not in sources for s in r['sourceIDs']):raise ValueError('Missing source attribution')
        if r.get('verificationStatus') not in ('reference_reviewed','legacy_unverified','imported_reference','unknown'):raise ValueError('Unknown verification status')
        if r.get('environment') is not None:text(r['environment'])
        if not isinstance(r.get('locations'),list) or len(r['locations'])>MAX_LOCATIONS:raise ValueError('Location budget')
        seen_locations=set()
        for loc in r['locations']:
            if not isinstance(loc,dict) or set(loc)-{'zone','continent','continentCandidate','sourceID','verificationStatus','continentVerification'}:raise ValueError('Unsupported location field; coordinates/observations refused')
            text(loc['zone']);sid=loc['sourceID']
            if sid not in sources or (sid,loc['zone']) in seen_locations:raise ValueError('Duplicate/unattributed location')
            seen_locations.add((sid,loc['zone']))
            if loc.get('continent') is not None:text(loc['continent'])
        if not isinstance(r.get('loot'),list) or len(r['loot'])>100:raise ValueError('Loot budget')
        for item in r['loot']:
            allowed={'name','itemID','sourceID','verificationStatus','waterType','seasonWindow'}
            if not isinstance(item,dict) or set(item)-allowed:raise ValueError('Unsupported loot field')
            text(item['name']);integer(item.get('itemID'))
            if item.get('sourceID') not in sources:raise ValueError('Unattributed loot')
            if item.get('verificationStatus') is not None and item['verificationStatus'] not in LOOT_EVIDENCE:
                raise ValueError('Unsupported loot evidence status')
            # These are facts about the identified fish item; never infer them
            # from its zone name, pool proximity or date of a single catch.
            if item.get('waterType') is not None:
                if kind!='fishing' or item['waterType'] not in WATER_TYPES:
                    raise ValueError('Invalid item water type')
            if item.get('seasonWindow') is not None:
                season=item['seasonWindow']
                if kind!='fishing' or not isinstance(season,dict) or set(season)!={'start','end'}:
                    raise ValueError('Invalid item season')
                for boundary in ('start','end'):
                    date=season[boundary]
                    if (not isinstance(date,str) or len(date)!=5 or date[2]!='-' or
                        not date[:2].isdigit() or not date[3:].isdigit()):
                        raise ValueError('Invalid seasonal date')
                    month,day=int(date[:2]),int(date[3:])
                    days=(31,29,31,30,31,30,31,31,30,31,30,31)
                    if month<1 or month>12 or day<1 or day>days[month-1]:
                        raise ValueError('Invalid seasonal date')
    d['resources'].sort(key=lambda r:r['id'])
    d['sources'].sort(key=lambda s:s['id'])
    d['contentSHA256']=hashlib.sha256(json.dumps(d['resources'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
    d['generatedUtc']=int(at.timestamp())
    d['recordCount']=len(d['resources'])
    d['categoryCounts']={kind:sum(r['category']==kind for r in d['resources']) for kind in sorted(CATEGORIES)}
    return d

def literal(v):
    if v is None:return 'nil'
    if v is True:return 'true'
    if v is False:return 'false'
    if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
    if type(v) is int:return str(v)
    if isinstance(v,list):return '{'+','.join(literal(x) for x in v)+'}'
    if isinstance(v,dict):return '{'+','.join('['+literal(k)+']='+literal(v[k]) for k in sorted(v) if v[k] is not None)+'}'
    raise ValueError('Unsupported literal')

def compile_reference(document):
    d=validate(document)
    raw=('-- Generated offline Gathering reference; no coordinates, observations or market history.\n'
         'local _,FCM=...\nFCM.gatheringReference='+literal(d)+'\n').encode('utf-8')
    if len(raw)>MAX_OUTPUT:raise ValueError('Reference exceeds 8 MiB output budget; previous data retained')
    return raw,d

def publish(document,target,fault=lambda phase:None):
    raw,d=compile_reference(document);target=Path(target)
    if target.is_symlink() or any(p.is_symlink() for p in target.parents):raise ValueError('Linked target refused')
    if any(getattr(p.lstat(),'st_file_attributes',0)&1024 for p in [*target.parents,target] if p.exists()):raise ValueError('Reparse target refused')
    target.parent.mkdir(parents=True,exist_ok=True)
    old=target.read_bytes() if target.exists() else None
    if old==raw:return dict(changed=False,bytes=len(raw),records=d['recordCount'])
    fd,name=tempfile.mkstemp(dir=target.parent,prefix=target.name+'.',suffix='.pending')
    temp=Path(name)
    try:
        with os.fdopen(fd,'wb') as stream:stream.write(raw);stream.flush();os.fsync(stream.fileno())
        if temp.read_bytes()!=raw:raise ValueError('Incomplete reference output')
        fault('validated')
        if old is not None:
            backup=target.with_name(target.name+'.previous-'+hashlib.sha256(old).hexdigest())
            if backup.exists():
                if backup.read_bytes()!=old:raise ValueError('Backup conflict')
            else:
                with backup.open('xb') as f:f.write(old);f.flush();os.fsync(f.fileno())
        if (target.read_bytes() if target.exists() else None)!=old:raise ValueError('Reference target changed concurrently')
        os.replace(temp,target)
        return dict(changed=True,bytes=len(raw),records=d['recordCount'],sha256=hashlib.sha256(raw).hexdigest())
    finally:
        if temp.exists():temp.unlink() # Only this invocation's exact temporary file.

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args()
    if args.input.stat().st_size>MAX_INPUT:raise ValueError('Reference input budget exceeded')
    print(json.dumps(publish(json.loads(args.input.read_text(encoding='utf-8')),args.output),sort_keys=True))
