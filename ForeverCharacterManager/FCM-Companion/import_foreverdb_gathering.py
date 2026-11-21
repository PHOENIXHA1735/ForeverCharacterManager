"""Normalize the three reviewed, nonpaginated ForeverDB gathering responses."""
from pathlib import Path
import json, sys, hashlib, re, tempfile
from datetime import datetime, timezone
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_gather_reference import MAX_INPUT, compile_reference
incoming,out=map(Path,sys.argv[1:])
seed=Path(__file__).with_name('gathering-reference.json')
seed_bytes=seed.read_bytes()
doc=json.loads(seed_bytes)
records=doc['resources']
index={(r['category'],r['name'].casefold()):r for r in records}
stats={}
build=None
def add(kind,name):
    key=kind,name.casefold()
    if key not in index:
        row=dict(id='foreverdb:'+kind+':'+name.casefold(),name=name,category=kind,
                 locations=[],loot=[],sourceIDs=[],verificationStatus='imported_reference')
        records.append(row)
        index[key]=row
    row=index[key]
    if source not in row['sourceIDs']:row['sourceIDs'].append(source)
    return row
def location(row,z):
    if not any(x['sourceID']==source and x['zone']==z for x in row['locations']):
        row['locations'].append(dict(sourceID=source,zone=z,verificationStatus='reported_reference'))
def loot(row,items):
    for item in items:
        name,ident=item['name'],item['itemId']
        assert type(ident) is int and ident>0
        if not any(i['itemID']==ident and i['sourceID']==source for i in row['loot']):
            row['loot'].append(dict(name=name,itemID=ident,sourceID=source))
for kind in ('herbalism','mining','fishing'):
    with (incoming/(kind+'.json')).open('rb') as stream:
        raw=stream.read(MAX_INPUT+1)
    if len(raw)>MAX_INPUT:raise ValueError('Reference response exceeds input budget')
    env=json.loads(raw)
    d,m=env['data'],env['meta']
    if d['profession']!=kind or not d['url'].startswith('https://foreverdb.net/profession/'):
        raise ValueError('Unexpected provider response source')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){2,3}',m['build']) or 'ForeverDB' not in m['attribution']:
        raise ValueError('Unrecognized provider build or attribution')
    if build is not None and build!=m['build']:raise ValueError('Mixed provider builds')
    build=m['build']
    if any(m.get(k) or d.get(k) for k in ('next','nextPage','nextOffset','hasMore')):
        raise ValueError('Incomplete provider response')
    source='foreverdb-'+kind
    doc['sources'].append(dict(id=source,name='ForeverDB.net '+kind,url=d['url'],
        permission='Documented API reference with attribution',version=m['build'],status='imported_reference'))
    zones=d['zones']
    if not isinstance(zones,list) or not zones:raise ValueError('Empty provider zone data')
    assert len({z['mapId'] for z in zones})==len(zones)
    stats[kind]=dict(zones=len(zones),sha256=hashlib.sha256(raw).hexdigest(),conflicts=[])
    if kind!='fishing':
        nodes={n['name']:n for n in d['nodes']}
        if not nodes:raise ValueError('Empty provider node data')
        assert len(nodes)==len(d['nodes'])
        ids={}
        stats[kind]['nodes']=len(nodes)
        for name,n in nodes.items():
            row=add(kind,name)
            for ident in n['objectIds']:
                assert type(ident) is int and ident>0
                if ident in ids and ids[ident]!=name:stats[kind]['conflicts'].append(['object',ident,ids[ident],name])
                ids[ident]=name
            row['reportedObjectIDs']=sorted(set(n['objectIds']))
            for key,val in [('minimumSkill',n['skill']),('itemID',(n.get('item') or {}).get('itemId'))]:
                if type(val) is not int or val <= 0:continue
                if row.get(key) not in (None,val):
                    stats[kind]['conflicts'].append([name,key,row[key],val])
                else:row[key]=val
            loot(row,n['alsoGives'])
            for z in n['topZones']:location(row,z['name'])
        unknown=set()
        for z in zones:
            for n in z['nodes']:
                if n['name'] not in nodes:unknown.add(n['name'])
                row=add(kind,n['name'])
                location(row,z['name'])
        stats[kind]['zoneOnlyNames']=sorted(unknown)
    else:
        poolNames=set(d['pools'])
        if not poolNames:raise ValueError('Empty provider fishing pool data')
        assert len(poolNames)==len(d['pools'])
        stats[kind]['poolNames']=len(poolNames)
        for name in sorted(poolNames):
            row=add(kind,name)
            row['fishingSourceType']={'Floating Wreckage':'wreckage','Oil Spill':'oil_spill'}.get(name,'school' if 'school' in name.lower() else 'pool')
        for z in zones:
            row=add(kind,'Zone fishing reference: '+z['name'])
            row.update(fishingSourceType='unknown',fishingMinimum=max(z['skill'] or 0,0) or None,
                       fishingNoGetAways=max(z['noEscapeSkill'] or 0,0) or None)
            location(row,z['name'])
            loot(row,z['loot']+z['caughtInForever'])
            for name in z['pools']:
                row=add(kind,name)
                row.setdefault('fishingSourceType','pool')
                location(row,z['name'])
now=datetime.now(timezone.utc).replace(microsecond=0).isoformat()
if any(stat['conflicts'] for stat in stats.values()):raise ValueError('Conflicting provider IDs or requirements')
doc.update(generatedAt=now,lastSuccessfulSync=now,sourceVersion=build,
    coverage=dict(complete=False,scope='Three ForeverDB Gathering responses imported; worldwide and per-water coverage incomplete',
    gaps=['No treasure endpoint in acquisition','Provider zones may reflect Classic reference','Fishing loot is zone-level and not assigned to named pools','Continents, icons and color thresholds are not supplied']))
lua,validated=compile_reference(doc)
fingerprint=dict(seed=hashlib.sha256(seed_bytes).hexdigest(), build=build,
    importer=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    compiler=hashlib.sha256(Path(__file__).with_name('build_gather_reference.py').read_bytes()).hexdigest(),
    responses={kind:row['sha256'] for kind,row in stats.items()})
if out.exists():
    previous=json.loads((out/'audit.json').read_bytes())
    if previous.get('inputIdentity')!=fingerprint:raise SystemExit('Inputs changed; use a new generation directory')
    if set(previous['outputs'])!={'gathering-reference.json','GatheringReferenceData.lua'}:
        raise SystemExit('Invalid generation inventory')
    for name,digest in previous['outputs'].items():
        if hashlib.sha256((out/name).read_bytes()).hexdigest()!=digest:
            raise SystemExit('Existing generation failed integrity verification')
    print('Unchanged: verified staged generation')
    raise SystemExit(0)
reference=json.dumps(doc,indent=2).encode('utf8')
outputs={'gathering-reference.json':reference,'GatheringReferenceData.lua':lua}
audit=dict(responses=stats,total=len(records),counts=validated['categoryCounts'],inputIdentity=fingerprint,
    outputs={name:hashlib.sha256(data).hexdigest() for name,data in outputs.items()})
with tempfile.TemporaryDirectory(prefix='.gather-reference-',dir=out.parent) as directory:
    stage=Path(directory)/'generation'
    stage.mkdir()
    for name,data in outputs.items():(stage/name).write_bytes(data)
    (stage/'audit.json').write_text(json.dumps(audit,indent=2),encoding='utf8')
    stage.rename(out)
print('Validated and staged',len(records),'reference records')
