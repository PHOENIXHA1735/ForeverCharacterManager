"""Stage a TOC payload from one explicitly bound Public30 generation."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

# Embeddable Windows Python does not add the entry script's directory.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from fcm_history_engine import local_date
from fcm_history_records import ZONE, export, eligible
from fcm_history_roots import safe_path
from public_export import payload
from public_intake import personal_archive
from public_store import MAX_EXPORT, Store


def stage(store, output, now, *, display_only=False):
    with store.lock():
        state = store.state()
        if not state['current']:
            raise ValueError('No Public30 history generation is available')
        directory = store.root / state['current']
        receipt = json.loads(safe_path(directory / 'receipt.json').read_bytes())
        as_of, valid_until = receipt['asOf'], receipt['validUntil']
        if (type(as_of) is not int or type(valid_until) is not int
                or not as_of <= now < valid_until or local_date(as_of, ZONE) != local_date(now, ZONE)):
            raise ValueError('Public30 history generation expired or is unavailable')
        path = safe_path(directory / 'PublicHistory.generated.lua')
        if not 0 < path.stat().st_size <= MAX_EXPORT:
            raise ValueError('Public30 export size limit')
        records = store.records(state)
        if any(not isinstance(row, dict) or row.get('provenance') != 'personal_scan' for row in records):
            raise ValueError('Only personal scan provenance may be published')
        _, _, rejected = eligible(records, as_of, 30, store.permissions)
        if rejected:
            raise ValueError('Generation contains ineligible observations')
        data = export(records, as_of, 30, (7, 30), store.bound.marker, 'FCMPublicHistory', store.permissions)
        if data['validUntil'] != valid_until or payload(data) != path.read_bytes():
            raise ValueError('Generation disagrees with validated observations or binding')
        if display_only:
            data['recommendationsAllowed'] = False
            data['permissionSummary'] = 'Display-only reference; recommendations disabled'
        raw = payload(data)
        if len(raw) > MAX_EXPORT:
            raise ValueError('Public30 staged output exceeds 8 MiB')
        with safe_path(output).open('xb') as stream:
            stream.write(raw)
        return {'sha256': hashlib.sha256(raw).hexdigest(), 'asOf': as_of, 'validUntil': valid_until}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--binding', required=True, type=Path)
    parser.add_argument('--initialize-empty', action='store_true')
    parser.add_argument('--archive', action='append', type=Path, default=[])
    parser.add_argument('--output', type=Path)
    parser.add_argument('--display-only', action='store_true')
    args = parser.parse_args()
    if args.initialize_empty:
        Store.initialize(args.root, args.binding)
    store = Store(args.root, args.binding)
    now = int(time.time())
    if args.archive:
        store.update((row for archive in args.archive for row in personal_archive(archive)), now)
    if args.output:
        print(json.dumps(stage(store, args.output, now, display_only=args.display_only)))


if __name__ == '__main__':
    main()
