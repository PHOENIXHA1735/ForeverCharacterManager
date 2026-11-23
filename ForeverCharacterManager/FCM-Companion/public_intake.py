"""Strict full-file personal archive intake. Original files are never copied or cleaned."""
import hashlib,json,re,time
from pathlib import Path
from fcm_history_roots import safe_path
from fcm_history_parse import LuaData,scans,ruleset
from fcm_history_records import MARKET
MAX_BYTES=30*1024*1024
class BoundedLua(LuaData):
    def __init__(self,text):
        super().__init__(text);self.left=250000;self.deadline=time.monotonic()+60
    def value(self,depth=0):
        self.left-=1
        if self.left<0 or time.monotonic()>self.deadline:raise ValueError('Personal literal parsing budget')
        return super().value(depth)
def personal_archive(path):
    path=safe_path(path);size=path.stat().st_size
    if not 0<size<=MAX_BYTES:raise ValueError('Public archive exceeds 30 MiB input bound')
    side=safe_path(Path(str(path)+'.json'))
    with side.open('rb') as stream:raw=stream.read(16385)
    if len(raw)>16384:raise ValueError('Sidecar too large')
    meta=json.loads(raw.decode('utf-8-sig'))
    src=meta.get('source')
    if not isinstance(src,str) or Path(src).name.lower()!='ahledger.lua' or Path(src).parent.name.lower()!='savedvariables':
        raise ValueError('Personal SavedVariables origin required')
    source=hashlib.sha256(src.lower().encode()).hexdigest()[:16].upper()
    if not(meta.get('schema')==1 and meta.get('kind')=='RawScans' and meta.get('sourceId')==source and
           meta.get('file')==path.name and meta.get('sourceLength')==size):
        raise ValueError('Invalid source attribution')
    before=path.stat()
    with path.open('rb') as stream:payload=stream.read(size+1)
    after=path.stat()
    if (before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns) or len(payload)!=size:
        raise ValueError('Archive changed')
    digest=hashlib.sha256(payload).hexdigest().upper()
    if meta.get('sha256')!=digest or not path.name.endswith('_'+digest+'.lua'):raise ValueError('Archive digest mismatch')
    return normalize_personal(payload,source)

def normalize_personal(payload,source):
    if not isinstance(source,str) or not re.fullmatch('[0-9A-F]{16}',source):raise ValueError('Approved personal source required')
    if not 0<len(payload)<=MAX_BYTES:raise ValueError('Personal scan byte limit')
    text=payload.decode('utf-8-sig');data=BoundedLua(text).database()
    values=data.get('scans')
    if not isinstance(values,dict) or not values:raise ValueError('No personal scans')
    total=0
    for r in values.values():
        if not isinstance(r,dict) or r.get('full') is not True or type(r.get('ts')) is not int or not isinstance(r.get('data'),str):raise ValueError('Incomplete scan')
        mk=f"forever/{ruleset(str(r.get('realm','')))}/{str(r.get('faction','')).lower()}/{str(r.get('region','')).lower()}"
        if not MARKET.fullmatch(mk):raise ValueError('Unknown scan market')
        n=1+r['data'].count(';')+r['data'].count('\n');total+=n
        if n>300000 or total>1000000 or r.get('count',n)!=n:raise ValueError('Packed listing bound/count mismatch')
    rows=[]
    for market,item,ts,kind,price,low,supply,pace in scans(text):
        rows.append(dict(market=market,item=item,ts=ts,price=price,low=low,supply=supply,pace=pace,source=source,provenance='personal_scan'))
        if len(rows)>131072:raise ValueError('Normalized archive row bound')
    return rows
