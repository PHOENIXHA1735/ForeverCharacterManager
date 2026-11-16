"""Reject private runtime paths in source/CI without reading or printing contents."""
from pathlib import Path


def private(path):
    parts=tuple(p.lower() for p in Path(path).parts)
    name=parts[-1] if parts else ''
    if any(p in ('savedvariables','wtf','ahledger') for p in parts): return True
    if 'ahhistory' in parts and name not in ('.gitkeep','.gitignore','readme.txt'): return True
    if name in ('ahledger.lua','ahledger_data.lua','ahhistory.generated.lua','python-path.local.txt'): return True
    return name.endswith(('.dpapi','.sqlite','.sqlite3','.db'))


if __name__=='__main__':
    bad=[p for p in Path('ForeverCharacterManager').rglob('*') if p.is_file() and private(p)]
    assert not bad, 'Private runtime files detected; refusing publication (contents withheld)'
    print('PASS: private AH history/provider/database/credential path guard')
