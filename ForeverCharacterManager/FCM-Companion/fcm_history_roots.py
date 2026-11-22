"""Fail-closed root identities. No automatic adoption, deletion or discovery."""
from pathlib import Path
import os,json,uuid,hashlib
ENGINE='fcm-statistics-2.0.0'
POLICY=2

def safe_path(path):
    path=Path(path).absolute()
    if '..' in path.parts:raise ValueError('Traversal path refused')
    for p in [*reversed(path.parents),path]:
        if p.is_symlink():raise ValueError('Linked/reparse path refused')
        try:info=p.lstat()
        except FileNotFoundError:continue
        if getattr(info,'st_file_attributes',0)&1024:raise ValueError('Linked/reparse path refused')
    return path

def safe_tree(root):
    """Check each directory before enumerating it; never recursively follow links."""
    pending=[safe_path(root)]
    while pending:
        directory=safe_path(pending.pop())
        for entry in sorted(directory.iterdir()):
            safe_path(entry)
            yield entry
            if entry.is_dir():pending.append(entry)

def read_json(path):
    return json.loads(safe_path(path).read_text(encoding='utf-8'))

def identity(path):
    st=safe_path(path).stat();return [st.st_dev,st.st_ino]

def initialize_empty(root,binding,classification):
    # Generic identity primitive; installed controllers decide their capability.
    root=safe_path(root);binding=safe_path(binding)
    if classification not in ('public30','private365'):raise ValueError('No active legacy/backup adoption')
    if not root.is_dir() or any(root.iterdir()) or binding.exists() or binding.is_relative_to(root):
        raise ValueError('Only an explicitly created EMPTY root and external new binding may initialize')
    marker=dict(schema=1,datasetID=str(uuid.uuid4()),rootInstanceID=str(uuid.uuid4()),classification=classification,
        role='active',generation=1,engineRevision=ENGINE,policy=POLICY)
    text=json.dumps(marker,sort_keys=True)
    # Exclusive creation: never overwrite a root marker or binding.
    with (root/'root.identity.json').open('x',encoding='utf-8') as f:f.write(text)
    record=dict(marker,root=str(root),directoryIdentity=identity(root))
    try:
        with binding.open('x',encoding='utf-8') as f:json.dump(record,f,sort_keys=True)
    except Exception:
        # Preserve partial initialization; operator review required, no auto-fallback.
        raise ValueError('Binding creation failed; partial root preserved, activation refused')
    return record

class BoundRoot:
    def __init__(self,root,binding,classification):
        self.root=safe_path(root);self.binding=safe_path(binding);self.classification=classification
        if self.binding.is_relative_to(self.root):raise ValueError('Binding must be separately stored')
        self.initial_binding=self.binding.read_bytes()
        self.validate()
    def validate(self):
        safe_path(self.root);safe_path(self.binding)
        if self.binding.read_bytes()!=self.initial_binding:raise ValueError('Binding changed')
        b=read_json(self.binding);m=read_json(self.root/'root.identity.json')
        required={'schema','datasetID','rootInstanceID','classification','role','generation','engineRevision','policy'}
        if set(m)!=required or any(m.get(k)!=b.get(k) for k in required):raise ValueError('Root binding conflict')
        for k in ('datasetID','rootInstanceID'):uuid.UUID(m[k])
        if m['schema']!=1 or m['policy']!=POLICY or m['engineRevision']!=ENGINE or m['classification']!=self.classification or m['role']!='active' or type(m['generation']) is not int or m['generation']<1:
            raise ValueError('Wrong capability/classification/role/revision')
        if b['root']!=str(self.root) or b['directoryIdentity']!=identity(self.root):raise ValueError('Wrong physical root')
        self.marker=m
        return m
    def file(self,name):
        if Path(name).name!=name or name in ('.','..'):raise ValueError('Only named root files allowed')
        self.validate();return safe_path(self.root/name)
    def read_records(self):
        path=self.file('observations.jsonl')
        paths=([path] if path.exists() else [])+sorted(self.root.glob('intake-*.jsonl'))
        result=[]
        for source in paths:
            safe_path(source);self.validate()
            result.extend(json.loads(line) for line in source.read_text(encoding='utf-8').splitlines() if line.strip())
        return result
    def write_new(self,name,text):
        # Prototype root writes are serialized and never overwrite files.
        lock=self.file('.writer.lock')
        with lock.open('x',encoding='ascii') as f:f.write('isolated controller')
        try:
            path=self.file(name)
            with path.open('x',encoding='utf-8',newline='\n') as f:f.write(text)
        finally:
            # Only this exact lock was created here; no recursive cleanup.
            self.validate();lock.unlink()
