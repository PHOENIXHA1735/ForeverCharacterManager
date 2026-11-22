"""Public30 owned generations. Cleanup is explicit and restricted to registered files."""
from contextlib import closing,contextmanager
from pathlib import Path
import hashlib,json,os,sqlite3,uuid,time,itertools
from fcm_history_roots import BoundRoot,initialize_empty,safe_path
from fcm_history_records import export,eligible,lua,ZONE
from fcm_history_permissions import Permissions
from public_export import payload as public_payload
from fcm_history_engine import window_start

MAX_ROWS=500_000
MAX_STORE_BYTES=512*1024*1024
MAX_NORMALIZED_BYTES=128*1024*1024
MAX_GENERATIONS=64
MAX_EXPORT=8*1024*1024
FIELDS={'market','item','ts','price','low','supply','pace','source','provenance'}
def atomic(path,obj):
    raw=json.dumps(obj,sort_keys=True).encode()
    with path.with_suffix('.tmp').open('wb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
    os.replace(path.with_suffix('.tmp'),path)
class Store:
    @staticmethod
    def initialize(root,binding):
        initialize_empty(root,binding,'public30')
        atomic(Path(root)/'managed.json',dict(schema=1,current=None,generations=[]))
    def __init__(self,root,binding):
        self.bound=BoundRoot(root,binding,'public30');self.root=self.bound.root
        self.permissions=Permissions()
    def state(self):
        self.bound.validate()
        state=json.loads(self.bound.file('managed.json').read_bytes())
        if set(state)!={'schema','current','generations'} or state['schema']!=1:raise ValueError('Unknown managed state')
        if not isinstance(state['generations'],list) or len(set(state['generations']))!=len(state['generations']):raise ValueError('Invalid generation set')
        for name in state['generations']:
            if not isinstance(name,str) or len(name)!=34 or not name.startswith('g-'):raise ValueError('Invalid generation name')
            uuid.UUID(hex=name[2:])
        if state['current'] is not None and state['current'] not in state['generations']:raise ValueError('Invalid active generation')
        if len(state['generations'])>MAX_GENERATIONS:raise ValueError('Generation budget exceeded')
        allowed={'root.identity.json','managed.json','managed.tmp','.public.lock',*state['generations']}
        for path in self.root.iterdir():
            safe_path(path)
            if path.name not in allowed:raise ValueError('Unmanaged root content; cleanup refused')
        for name in state['generations']:
            folder=safe_path(self.root/name)
            if folder.exists():
                if not folder.is_dir():raise ValueError('Generation is not a directory')
                for p in folder.iterdir():
                    safe_path(p)
                    if not p.is_file() or p.name not in {'records.sqlite3','records.sqlite3-journal','PublicHistory.generated.lua','receipt.json','receipt.tmp'}:raise ValueError('Unmanaged generation content')
        return state
    @contextmanager
    def lock(self):
        path=self.bound.file('.public.lock')
        with path.open('a+b') as f:
            if os.name=='nt':
                import msvcrt
                f.seek(0)
                msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,1)
                try:yield
                finally:
                    f.seek(0)
                    msvcrt.locking(f.fileno(),msvcrt.LK_UNLCK,1)
            else:
                import fcntl
                fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
                try:yield
                finally:fcntl.flock(f,fcntl.LOCK_UN)
    def records(self,state):
        if state['current'] is None:return []
        folder=self.root/state['current']
        receipt=json.loads((folder/'receipt.json').read_bytes())
        if set(receipt.get('hashes',{}))!={'records.sqlite3','PublicHistory.generated.lua'}:raise ValueError('Incomplete receipt')
        for name,digest in receipt['hashes'].items():
            if name not in ('records.sqlite3','PublicHistory.generated.lua'):raise ValueError('Invalid receipt')
            if hashlib.sha256((folder/name).read_bytes()).hexdigest()!=digest:raise ValueError('Generation hash mismatch')
        with closing(sqlite3.connect((folder/'records.sqlite3').as_uri()+'?mode=ro&immutable=1',uri=True)) as db:
            if db.execute('pragma integrity_check').fetchall()!=[('ok',)]:raise ValueError('Store integrity failed')
            if db.execute('select count(*) from records').fetchone()[0]>MAX_ROWS:raise ValueError('Stored row bound')
            return [json.loads(row[0]) for row in db.execute('select record from records order by market,item,stamp,source')]
    def update(self,incoming,now,*,approve_cleanup=False,activate=True):
        with self.lock():
            state=self.state()
            # Build the full bounded input before mutating active state.
            merged={};rejected={};input_bytes=0
            for index,r in enumerate(itertools.chain(self.records(state),incoming)):
                encoded_size=len(json.dumps(r).encode());input_bytes+=encoded_size
                if index>=2*MAX_ROWS or encoded_size>4096 or input_bytes>2*MAX_NORMALIZED_BYTES:raise ValueError('Intake resource limit')
                if not isinstance(r,dict) or set(r)-FIELDS or not isinstance(r.get('source'),str) or not r['source']:
                    raise ValueError('Invalid normalized personal record')
                if r.get('provenance')!='personal_scan':raise ValueError('Only verified personal scans supported; provider intake denied')
                good,_,why=eligible([r],now,30,self.permissions)
                if not good:
                    for reason,n in why.items():rejected[reason]=rejected.get(reason,0)+n
                    continue
                key=(r['market'],r['item'],r['ts'])
                if key in merged and any(merged[key].get(k)!=r.get(k) for k in ('price','low','supply','pace')):
                    raise ValueError('Conflicting personal observation; active state preserved')
                if key not in merged or r['source']<merged[key]['source']:merged[key]=r
                if len(merged)>MAX_ROWS:raise ValueError('Observation budget exceeded')
            data=export(list(merged.values()),now,30,(7,30),self.bound.marker,'FCMPublicHistory',self.permissions)
            payload=public_payload(data)
            if len(payload)>MAX_EXPORT:raise ValueError('Public output exceeds 8 MiB per-file budget')
            if len(state['generations'])>=MAX_GENERATIONS:raise ValueError('Review or approve cleanup before more generations')
            normalized_bytes=sum(len(json.dumps(r).encode()) for r in merged.values())
            if normalized_bytes>MAX_NORMALIZED_BYTES:raise ValueError('Normalized byte budget')
            existing_bytes=sum(p.stat().st_size for name in state['generations'] for p in (self.root/name).glob('*') if p.is_file())
            if existing_bytes+3*normalized_bytes+len(payload)+1024*1024>MAX_STORE_BYTES:raise ValueError('Stage storage budget; review cleanup first')
            name='g-'+uuid.uuid4().hex
            state['generations'].append(name);atomic(self.bound.file('managed.json'),state)
            folder=self.root/name;folder.mkdir()
            with closing(sqlite3.connect(folder/'records.sqlite3')) as db,db:
                db.execute('pragma secure_delete=on')
                db.execute('create table records(market text,item integer,stamp integer,source text,record text,primary key(market,item,stamp)) without rowid')
                db.executemany('insert into records values(?,?,?,?,?)',[(r['market'],r['item'],r['ts'],r['source'],json.dumps(r,sort_keys=True)) for r in merged.values()])
                db.commit()
                if db.execute('pragma integrity_check').fetchall()!=[('ok',)]:raise ValueError('Generation integrity failed')
                assert db.execute('pragma freelist_count').fetchone()==(0,)
            (folder/'PublicHistory.generated.lua').write_bytes(payload)
            hashes={n:hashlib.sha256((folder/n).read_bytes()).hexdigest() for n in ('records.sqlite3','PublicHistory.generated.lua')}
            atomic(folder/'receipt.json',dict(asOf=now,validUntil=data['validUntil'],hashes=hashes,observations=len(merged),rejected=rejected))
            # The immutable generation is complete before a single atomic pointer switch.
            if activate:state['current']=name
            self.bound.validate();atomic(self.bound.file('managed.json'),state)
            if approve_cleanup:self._cleanup(now)
            return dict(generation=name,observations=len(merged),rejected=rejected,bytes=len(payload))
    def activate(self,name,now):
        with self.lock():
            state=self.state()
            if name not in state['generations']:raise ValueError('Unregistered candidate')
            candidate=dict(state,current=name)
            self.records(candidate)
            receipt=json.loads((self.root/name/'receipt.json').read_bytes())
            if not receipt['asOf']<=now<receipt['validUntil']:raise ValueError('Candidate not current')
            state['current']=name;atomic(self.bound.file('managed.json'),state)

    def plan(self,now):
        state=self.state()
        active=self.records(state)
        expired=sum(r['ts']<window_start(now,30,ZONE) for r in active)
        if state['current']:
            receipt=json.loads((self.root/state['current']/'receipt.json').read_bytes())
            stale_export=not receipt['asOf']<=now<receipt['validUntil']
        else:stale_export=False
        return dict(classification='public30',activeExpiredRows=expired,activeExportExpired=stale_export,
                    cleanup=[name for name in state['generations'] if name!=state['current']],
                    exactFiles=[str(self.root/name/p.name) for name in state['generations'] if name!=state['current']
                                for p in sorted((self.root/name).glob('*')) if p.is_file()],
                    unknownFilesAllowed=False,approvalRequired=True,
                    scope='owned DB generations/exports/receipts; external originals are never copied, retained or cleaned')
    def cleanup(self,now,*,approve=False):
        if not approve:return self.plan(now)
        with self.lock():return self._cleanup(now)
    def _cleanup(self,now,protected=(),allow_expired=False):
        state=self.state()
        if not allow_expired and (self.plan(now)['activeExpiredRows'] or self.plan(now)['activeExportExpired']):
            raise ValueError('Rebuild a current filtered generation before cleanup')
        for name in list(state['generations']):
            if name==state['current'] or name in protected:continue
            folder=self.root/name
            if folder.exists():
                for n in ('records.sqlite3-journal','records.sqlite3','PublicHistory.generated.lua','receipt.json','receipt.tmp'):
                    p=folder/n
                    if p.exists():p.unlink()
                folder.rmdir()
            state['generations'].remove(name);atomic(self.bound.file('managed.json'),state)
        return self.plan(now)
