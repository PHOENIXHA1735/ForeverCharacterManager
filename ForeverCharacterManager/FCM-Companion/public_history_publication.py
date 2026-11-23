"""Publish a confirmed, personal-only Public30 snapshot into the bound addon."""
import argparse
import hashlib
import json
from itertools import chain
import math
import os
from pathlib import Path
import sys
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fcm_history_roots import safe_path
from public_history_stage import verified_snapshot
from public_intake import personal_archive
from public_store import MAX_EXPORT, Store, atomic

DATA = "PublicHistory.generated.lua"
CONFIRMATION = "PublicHistoryConfirmation.generated.lua"
INVALID = b"FCM_PublicHistoryConfirmations=nil\n"
def sha(data):return hashlib.sha256(data).hexdigest().encode()
def frame(v):
    if type(v) is str:v=v.encode()
    if type(v) is int:v=str(v).encode()
    return str(len(v)).encode()+b':'+v
def pack(* values):return b''.join(map(frame,values))
def commitment(domain,data):return sha(domain+b'\0'+frame(data))
def number(v):
    if v is None:return b''
    if v==0:return b'0'
    m,e=math.frexp(abs(v))
    return f'{"+" if v>0 else "-"}{int(m*2**53)}:{e}'.encode()
def record(item,r):
    fields=[item,r['currentUtc'],*(number(r[k]) for k in ('current','minimum','maximum','comparisonPct')),
            *(number(r.get(k)) for k in ('low','supply','volatility','trendPct')),
            r['observedDays'],r['observations'],r['confidence']]
    for window in ('7','30'):
        w=r['windows'][window]
        fields.extend((w['days'],number(w['average']),number(w['coverage'])))
    for mode in ('weekday','hour'):
        bins=r['timing'][mode]
        fields.append(len(bins))
        for key,b in sorted(bins.items(),key=lambda x:int(x[0])):
            fields.extend((key,number(b['relative']),b['observations'],b['days'],int(b['adequate'])))
    return pack(*fields)


def literal(value):
    return '"' + ''.join(chr(byte) if 32 <= byte <= 126 and byte not in (34, 92)
                         else '\\%03d' % byte for byte in value) + '"'


def artifacts(summary, generation, transaction):
    data, confirmation = [], []
    if len(summary["markets"]) > 32:
        raise ValueError("Public30 market limit exceeded")
    for market, items in sorted(summary["markets"].items()):
        records = sorted(items.items(), key=lambda pair: int(pair[0]))
        pages, descriptors = [], []
        for offset in range(0, len(records), 16):
            group = records[offset:offset+16]
            index = len(pages) + 1
            page = pack(1, transaction, generation[2:], market, index, len(group),
                        *(record(item, row) for item, row in group))
            pages.append(page)
            descriptors.extend((index, group[0][0], group[-1][0], len(group),
                                commitment(b"FCM30-PAGE-v1", page)))
        directory = pack(1, transaction, generation[2:], market, summary["eligibleCutoffUtc"],
                         summary["asOf"], summary["validUntil"], len(records), len(pages), *descriptors)
        if len(directory) > 65535:
            raise ValueError("Public30 authenticated directory exceeds the consumer limit")
        header = pack(1, summary["engineRevision"], summary["rootInstanceID"], summary["datasetID"],
                      summary["generation"], summary["asOf"], summary["validUntil"], summary["eligibleCutoffDate"],
                      summary["eligibleCutoffUtc"], summary["permissionSummary"],
                      commitment(b"FCM30-DIRECTORY-v1", directory), market, "committed",
                      len(records), sum(row["observations"] for _, row in records),
                      int(summary["recommendationsAllowed"]), transaction)
        key = '[' + literal(market.encode()) + ']'
        data.append(key + '={' + ','.join((literal(header), literal(directory),
                                           '{' + ','.join(map(literal, pages)) + '}')) + '}')
        confirmation.append(key + '=' + literal(commitment(b"FCM30-HANDOFF-v1", header)))
    payload = ('FCM_PublicHistoryPages={' + ','.join(data) + '}\n').encode()
    proof = ('FCM_PublicHistoryConfirmations={' + ','.join(confirmation) + '}\n').encode()
    if len(payload) > MAX_EXPORT or len(proof) > 32768:
        raise ValueError("Confirmed Public30 output exceeds its byte limit")
    return payload, proof


def replace(path, content):
    safe_path(path)
    pending = safe_path(path.with_name('.' + path.name + '.' + uuid.uuid4().hex + '.pending'))
    with pending.open('xb') as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(pending, path)
    if path.read_bytes() != content:
        raise ValueError("Publication readback mismatch")


def read_optional(path):
    try:
        return safe_path(path).read_bytes()
    except FileNotFoundError:
        return None


def publish(store, addon, clock, *, display_only=False, archives=()):
    addon = safe_path(addon)
    if not addon.is_dir() or store.root.is_relative_to(addon) or addon.is_relative_to(store.root):
        raise ValueError("Public30 store and addon paths must be separate")
    for name in ("ForeverCharacterManager.toc", "ForeverCharacterManager_Camelot.toc"):
        lines = safe_path(addon / name).read_text(encoding="utf-8-sig").splitlines()
        if DATA not in lines or CONFIRMATION not in lines or lines.index(DATA) >= lines.index(CONFIRMATION):
            raise ValueError("Public30 artifacts are not registered in TOC order")
    recovery = safe_path(store.root.parent / (store.root.name + '-publication'))
    recovery.mkdir(exist_ok=True)
    target, proof = addon / DATA, addon / CONFIRMATION
    pending = []
    retired = []
    for path in recovery.glob("g-*.json"):
        entry = json.loads(safe_path(path).read_bytes())
        if entry.get("phase") == "prepared":
            pending.append((path, entry))
        elif entry.get("phase") == "expired":
            retired.append(entry)
    if len(pending) > 1:
        raise ValueError("Multiple unfinished Public30 transactions")
    if pending:
        path, entry = pending[0]
        with store.lock():
            state = store.state()
            generation = entry["generation"]
            mode = "display" if display_only else "personal"
            if (generation not in state["generations"] or
                    path.name != generation + "-" + mode + ".json" or
                    state["current"] not in (entry["previous"], generation)):
                raise ValueError("Pending Public30 generation, pointer, or display policy differs")
            receipt = json.loads(safe_path(store.root / generation / "receipt.json").read_bytes())
            now = clock()
            if now >= receipt["validUntil"]:
                # Reconstruct the prepared artifact at its recorded evaluation time.
                # Never re-activate it now, even if all old bytes still match.
                _, historical = verified_snapshot(store, receipt["asOf"],
                                                  display_only=display_only, generation=generation)
                old_data, old_proof = artifacts(historical, generation, entry["transaction"])
                if entry["hashes"] != dict(data=sha(old_data).decode(), confirmation=sha(old_proof).decode()):
                    raise ValueError("Expired Public30 transaction digest mismatch")
                replace(proof, INVALID)
                entry["phase"] = "expired"
                entry["retiredAt"] = now
                retired.append(entry)
                replace(path, json.dumps(entry, sort_keys=True).encode())
                pending = []
    if pending and archives:
        raise ValueError("Recover the pending Public30 transaction before submitting archives")
    state = store.state()
    candidate = pending[0][1]["generation"] if pending else state["current"]
    if not pending:
        now = clock()
        prior = [entry for entry in retired if state["current"] in (entry["previous"], entry["generation"])]
        base = max(prior, key=lambda entry: entry["retiredAt"])["generation"] if prior else candidate
        if base and base not in state["generations"]:
            raise ValueError("Expired Public30 recovery source is not registered")
        current_rows = store.records(dict(state, current=base)) if base else []
        known = {(row["market"], row["item"], row["ts"]): row for row in current_rows}
        incoming = (row for archive in archives for row in personal_archive(archive))
        new = (row for row in incoming if known.get((row["market"], row["item"], row["ts"])) != row)
        first = next(new, None)
        expired = base and now >= json.loads(
            safe_path(store.root / base / "receipt.json").read_bytes())["validUntil"]
        if first is not None or expired:
            from itertools import chain
            candidates = chain((first,), new) if first is not None else ()
            candidate = store.update(candidates, now, activate=False, base_generation=base)["generation"]
    with store.lock():
        generation, data = verified_snapshot(store, clock(), display_only=display_only, generation=candidate)
        mode = "display" if display_only else "personal"
        journal_path = safe_path(recovery / (generation + '-' + mode + '.json'))
        if pending and pending[0][0] != journal_path:
            raise ValueError("Retry the pending Public30 transaction with its original display policy")
        raw = read_optional(journal_path)
        if raw is None:
            journal = dict(generation=generation, previous=store.state()["current"],
                           transaction=uuid.uuid4().hex, phase="prepared")
        else:
            journal = json.loads(raw)
            if journal["generation"] != generation or journal["phase"] not in ("prepared", "committed"):
                raise ValueError("Invalid Public30 recovery journal")
        payload, confirmation = artifacts(data, generation, journal["transaction"])
        expected = dict(data=sha(payload).decode(), confirmation=sha(confirmation).decode())
        if raw is not None and journal.get("hashes") != expected:
            raise ValueError("Public30 recovery digest mismatch")
        if (journal["phase"] == "committed" and read_optional(target) == payload
                and read_optional(proof) == confirmation):
            return "unchanged"
        if raw is None:
            for path in (target, proof):
                before = read_optional(path)
                if before is not None:
                    backup = recovery / (journal["transaction"] + '-' + path.name + '.bak')
                    replace(backup, before)
            journal["hashes"] = expected
            replace(journal_path, json.dumps(journal, sort_keys=True).encode())
        replace(proof, INVALID)
        replace(target, payload)
        state = store.state()
        if state["current"] not in (journal["previous"], generation) or clock() >= data["validUntil"]:
            raise ValueError("Public30 generation changed or expired")
        if state["current"] != generation:
            state["current"] = generation
            atomic(store.bound.file("managed.json"), state)
        if store.state()["current"] != generation:
            raise ValueError("Public30 active pointer readback mismatch")
        journal["phase"] = "committed"
        replace(journal_path, json.dumps(journal, sort_keys=True).encode())
        if clock() >= data["validUntil"]:
            raise ValueError("Public30 confirmation expired before activation")
        replace(proof, confirmation)
        return "published"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("root", "binding", "addon"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--display-only", action="store_true")
    parser.add_argument("--archive", action="append", type=Path, default=[])
    args = parser.parse_args()
    print(publish(Store(args.root, args.binding), args.addon, lambda: int(time.time()),
                  display_only=args.display_only, archives=args.archive))


if __name__ == "__main__":
    main()