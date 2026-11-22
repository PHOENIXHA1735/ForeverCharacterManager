"""Selective release overlay. Apply and recover are limited to disposable rehearsals."""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
from zipfile import ZipFile

import fcm_security

ADDON = "Interface/AddOns/ForeverCharacterManager/"
GENERATED = {
    "ExternalData.generated.lua", "AHPrices.generated.lua", "AHHistory.generated.lua",
    "PublicHistory.generated.lua", "CommunityGathering.generated.lua", "GatheringReferenceData.lua",
}
REQUIRED_OLD = GENERATED - {"GatheringReferenceData.lua"}
MARKER = ".fcm-disposable-release-rehearsal"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def location(root, relative):
    key = PurePosixPath(relative)
    if not key.parts or key.as_posix() != relative or any(
        not re.fullmatch(r"[a-zA-Z0-9_.# -]+", part) or part in {".", ".."}
        or part.endswith((".", " ")) or re.fullmatch(
            r"(?i)(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\..*)?", part
        )
        for part in key.parts
    ):
        raise ValueError(f"Unsafe relative path: {relative}")
    result = root.joinpath(*key.parts)
    for path in (result, *result.parents):
        try:
            metadata = path.lstat()
        except FileNotFoundError:
            continue
        if (stat.S_ISLNK(metadata.st_mode) or
                getattr(metadata, "st_file_attributes", 0) & 1024 or
                stat.S_ISREG(metadata.st_mode) and metadata.st_nlink != 1):
            raise ValueError(f"Linked path: {path}")
    return result


def contents(path):
    return path.read_bytes() if path.exists() else None


def fingerprint(path):
    data = contents(path)
    return digest(data) if data is not None else None


def atomic_write(path, data, *, expected_acl=None, read_acl=fcm_security.acl,
                 write_acl=fcm_security.set_acl, replace_file=fcm_security.replace_file):
    """Write bytes atomically with ACL4 owner/group preservation on temp files.

    Any security mismatch raises instead of silently changing file permissions.
    Unpinned writes are used only for separate journal, fence and evidence files.
    """
    if expected_acl is not None and not path.parent.is_dir():
        raise ValueError(f"Approved security replacement directory does not exist: {path.parent}")
    path.parent.mkdir(parents=True, exist_ok=True)
    if expected_acl is not None and path.exists() and read_acl(path) != expected_acl:
        raise ValueError(f"Pre-write security changed: {path}")
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".fcm-overlay-", delete=False) as handle:
        temporary = Path(handle.name)
        try:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
            handle.close()
            if expected_acl is not None:
                if read_acl(temporary) != expected_acl:
                    write_acl(temporary, expected_acl)
                if read_acl(temporary) != expected_acl:
                    raise ValueError(f"Replacement cannot preserve owner/group/DACL: {path}")
            if expected_acl is not None:
                # Checked same-volume rename, including paths that did not exist.
                replace_file(path, temporary)
            else:
                temporary.replace(path)
            if expected_acl is not None and read_acl(path) != expected_acl:
                raise ValueError(f"Installed owner/group/DACL differ: {path}")
        finally:
            temporary.unlink(missing_ok=True)


def package(archive, expected):
    with archive.open("rb") as stream:
        data = stream.read(15_000_001)
    if len(data) > 15_000_000 or digest(data) != expected:
        raise ValueError("Wrong release ZIP identity or size")
    from io import BytesIO
    with ZipFile(BytesIO(data)) as bundle:
        entries = bundle.infolist()
        if not 0 < len(entries) <= 180 or sum(item.file_size for item in entries) > 40_000_000:
            raise ValueError("Release inventory exceeds limits")
        result = {}
        seen = set()
        for item in entries:
            top, separator, relative = item.filename.partition("/")
            if top != "ForeverCharacterManager" or not separator or item.is_dir():
                raise ValueError("Unexpected release entry")
            if relative.casefold() in seen:
                raise ValueError("Duplicate release entry")
            seen.add(relative.casefold())
            key = ADDON + relative
            location(Path.cwd(), key)
            if relative.startswith("AHHistory/") or relative in REQUIRED_OLD - {
                "CommunityGathering.generated.lua", "PublicHistory.generated.lua",
            } or any(part in relative.lower() for part in (
                "savedvariables", "settings.json", "reference-cache.json", ".sqlite", ".dpapi",
                "python-path.local", "request-budget", "request-backoff",
            )):
                raise ValueError("Unexpected state in release ZIP")
            result[key] = bundle.read(item)
    for name in ("ForeverCharacterManager.toc", "ForeverCharacterManager_Camelot.toc"):
        lines = result[ADDON + name].decode("utf-8-sig").splitlines()
        if not {"## Version: 0.9.4", "## SavedVariables: FCM_DB, FCM_GatherExport"} <= set(lines):
            raise ValueError("Wrong release identity")
    return result


def unsafe_static(key):
    relative = key.removeprefix(ADDON)
    return not key.startswith(ADDON) or relative in GENERATED or relative.startswith("AHHistory/") or any(
        name in relative.lower() for name in (
            "settings.json", "reference-cache.json", "python-path.local", "budget", "backoff",
            "checkpoint", ".dpapi", ".sqlite",
        )
    )


def plan(root, payload, baseline):
    protected = baseline["preserve"]
    old = baseline["static"]
    if any(unsafe_static(key) for key in old):
        raise ValueError("Baseline includes a protected or foreign static path")
    if not {ADDON + name for name in REQUIRED_OLD} <= protected.keys():
        raise ValueError("Five generated production files must be covered")
    if not any(key.startswith("WTF/Account/") and key.endswith("/SavedVariables/ForeverCharacterManager.lua")
               for key in protected):
        raise ValueError("FCM SavedVariables preflight missing")
    if not {ADDON + name for name in ("ForeverCharacterManager.toc", "ForeverCharacterManager_Camelot.toc")} <= old.keys():
        raise ValueError("Previous addon identity missing")
    if set(protected) & set(old):
        raise ValueError("Conflicting baseline ownership")
    check(root, {**old, **protected})
    managed = set(old) | set(payload)
    for item in location(root, ADDON.rstrip("/")).iterdir():
        key = ADDON + item.name
        if item.suffix.lower() in {".lua", ".toc"} and key not in managed and key not in protected:
            raise ValueError(f"Unreviewed existing addon code: {item.name}")
    operations = {}
    for key in sorted(managed):
        target = location(root, key)
        before = fingerprint(target)
        if key in protected:
            continue
        if key.removeprefix(ADDON) in GENERATED and before is not None:
            raise ValueError(f"Generated file absent from preservation baseline: {key}")
        if before is not None and key not in old:
            raise ValueError(f"Existing file lacks verified old ownership: {key}")
        after = digest(payload[key]) if key in payload else None
        if before != after:
            operations[key] = {"before": before, "after": after}
    return operations


def check(root, hashes):
    for key, expected in hashes.items():
        if fingerprint(location(root, key)) != expected:
            raise ValueError(f"File hash mismatch: {key}")


def rehearsal_guard(root, probe):
    if not location(root, MARKER).is_file() or root.name != "_forever_" or not root.is_relative_to(
        Path(tempfile.gettempdir()).resolve()
    ):
        raise ValueError("Activation is restricted to a marked disposable layout in the OS temp directory")
    state = probe()
    if state != {"complete": True, "writers": [], "unfenced": []}:
        raise ValueError("Writer state unknown, active or unfenced")


@contextmanager
def lock(recovery):
    path = location(recovery, ".fcm-overlay.lock")
    with path.open("a+b") as stream:
        stream.seek(0)
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def record(path, state):
    atomic_write(path, json.dumps(state, indent=2).encode())


def restore_locked(root, recovery, state, probe, guard=rehearsal_guard, security=None):
    guard(root, probe)
    if state["root"] != str(root):
        raise ValueError("Recovery root mismatch")
    if state["phase"] not in {"pending", "committed", "restoring"}:
        raise ValueError("Journal has no restorable transaction")
    backup = recovery / "backup"
    check(backup, state["original"])
    restore_keys = set(state["operations"]) | {
        key for key in state["original"] if key.startswith("WTF/Account/")
        and key.endswith(("/SavedVariables/ForeverCharacterManager.lua",
                          "/SavedVariables/ForeverCharacterManager.lua.bak"))
    }
    check(root, {key: value for key, value in state["original"].items() if key not in restore_keys})
    # Save current observations separately before any restore, even on retries.
    evidence = Path(tempfile.mkdtemp(prefix="failed-", dir=recovery))
    snapshot = {}
    for key in state["original"]:
        data = contents(location(root, key))
        if data is not None:
            atomic_write(location(evidence, key), data)
            snapshot[key] = digest(data)
    check(evidence, snapshot)
    state["phase"] = "restoring"
    record(recovery / "journal.json", state)
    for key in sorted(restore_keys):
        before = state["original"][key]
        guard(root, probe)
        target = location(root, key)
        if fingerprint(target) == before:
            continue
        if before is None:
            if security is not None and target.exists():
                if key not in security or fcm_security.acl(target) != security[key]:
                    raise ValueError(f"Rollback deletion security changed: {key}")
            target.unlink(missing_ok=True)
        else:
            if security is not None and key not in security:
                raise ValueError(f"Missing rollback ACL evidence: {key}")
            atomic_write(target, location(backup, key).read_bytes(),
                         expected_acl=None if security is None else security[key])
    check(root, state["original"])
    state["phase"] = "restored"
    record(recovery / "journal.json", state)


def restore(root, recovery, probe, *, guard=rehearsal_guard, security=None):
    guard(root, probe)
    with lock(root):
        state = json.loads(location(recovery, "journal.json").read_bytes())
        restore_locked(root, recovery, state, probe, guard, security)


def apply(root, payload, baseline, recovery, probe, hook=lambda _: None, *,
          guard=rehearsal_guard, verify=lambda: None, security=None):
    guard(root, probe)
    if recovery.is_relative_to(root) or not recovery.parent.exists():
        raise ValueError("Recovery must be outside the client in an existing directory")
    recovery.mkdir()
    with lock(root):
        operations = plan(root, payload, baseline)
        original = {**baseline["static"], **baseline["preserve"]}
        original.update({key: item["before"] for key, item in operations.items()})
        backup = recovery / "backup"
        for key, expected in original.items():
            if expected is not None:
                atomic_write(location(backup, key), location(root, key).read_bytes())
        check(backup, original)
        check(root, original)
        state = {"root": str(root), "phase": "pending", "original": original,
                 "operations": operations, "completed": []}
        journal = recovery / "journal.json"
        record(journal, state)
        try:
            for key in operations:
                guard(root, probe)
                target = location(root, key)
                if fingerprint(target) != operations[key]["before"]:
                    raise ValueError("Target changed after backup")
                if key in payload:
                    if security is not None and key not in security:
                        raise ValueError(f"Missing upgrade ACL evidence: {key}")
                    atomic_write(target, payload[key],
                                 expected_acl=None if security is None else security[key])
                else:
                    if security is not None and (key not in security or
                            fcm_security.acl(target) != security[key]):
                        raise ValueError(f"Retirement security changed: {key}")
                    target.unlink()
                hook(key)
                state["completed"].append(key)
                record(journal, state)
            guard(root, probe)
            check(root, {**original, **{key: item["after"] for key, item in operations.items()}})
            verify()
            state["phase"] = "committed"
            record(journal, state)
        except Exception:
            restore_locked(root, recovery, state, probe, guard, security)
            raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("client", type=Path)
    parser.add_argument("zip", type=Path)
    parser.add_argument("zip_sha256")
    parser.add_argument("baseline", type=Path)
    args = parser.parse_args()
    root = args.client.absolute()
    baseline = json.loads(args.baseline.read_text(encoding="utf-8-sig"))
    changes = plan(root, package(args.zip, args.zip_sha256), baseline)
    print(json.dumps({"mode": "dry-run", "changes": changes, "preserve": baseline["preserve"],
                      "unchanged_static": sorted(set(baseline["static"]) - changes.keys())}, indent=2))
