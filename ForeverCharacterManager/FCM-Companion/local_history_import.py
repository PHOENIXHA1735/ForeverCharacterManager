"""Call the existing local classified-history importer for explicitly approved scans."""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fcm_history_roots import safe_path


def absolute(value):
    path = Path(value)
    if not path.is_absolute():
        raise ValueError("Local history configuration requires absolute paths")
    return safe_path(path)


def overlaps(left, right):
    return left.is_relative_to(right) or right.is_relative_to(left)


def run(config_file, public_root, addon, clock):
    config_file = absolute(config_file)
    if overlaps(config_file, addon) or overlaps(config_file, public_root):
        raise ValueError("Private configuration must remain outside public storage")
    if not config_file.exists():
        return {"status": "not-configured"}
    config = json.loads(config_file.read_bytes())
    if config.get("enabled") is False:
        return {"status": "disabled"}
    if config.get("schema") != 1 or config.get("enabled") is not True:
        raise ValueError("Invalid local history configuration")
    root, binding, modules, source, reference = (
        absolute(config[key]) for key in ("store", "binding", "importer", "source", "reference"))
    if any(overlaps(path, protected) for path in (root, binding, modules)
           for protected in (public_root, addon)):
        raise ValueError("Private and public history paths must stay separate")
    if overlaps(source, public_root) or overlaps(reference, public_root):
        raise ValueError("Legacy input must remain outside the Public30 store")
    # The host collector may own the legacy input under AHHistory. It remains
    # read-only and distinct from both derived stores.
    if ((overlaps(source, addon) and not source.is_relative_to(addon / "AHHistory" / "RawScans"))
            or (overlaps(reference, addon) and not reference.is_relative_to(addon / "AHHistory" / "Parsed"))):
        raise ValueError("Unexpected legacy input location")
    if any(overlaps(root, path) for path in (modules, source, reference)):
        raise ValueError("Private intake must be separate from the derived store")
    if not root.is_dir() or not source.is_dir() or not modules.is_dir():
        raise ValueError("Private history bindings are unavailable")
    module_paths = {name: safe_path(modules / (name + ".py"))
                    for name in ("fcm_private_history", "legacy_import")}
    for name, path in module_paths.items():
        if hashlib.sha256(path.read_bytes()).hexdigest() != config["importerHashes"][name]:
            raise ValueError("Private importer hash differs from local approval")

    sys.path.insert(0, str(modules))
    from fcm_private_history import Private365
    from legacy_import import _import_verified, checked_archive_size, configured_limit

    history = Private365(root, binding)
    approved = config["archives"]
    if not isinstance(approved, dict):
        raise ValueError("Private archive approvals must be explicit")
    if not approved:
        return {"status": "unchanged", "committed": 0, "replayed": 0}

    if reference.stat().st_size > 512 * 1024**2:
        raise ValueError("Legacy reference exceeds its read budget")
    with reference.open("rb") as stream:
        header = stream.read(100)
    if (header[18:20] != b"\x01\x01"
            or any(Path(str(reference) + suffix).exists() for suffix in ("-wal", "-shm", "-journal"))):
        raise ValueError("Legacy reference has an unsupported or busy journal state")
    committed = replayed = 0
    now = clock()
    limit = configured_limit(history.root)
    for name, approval in sorted(approved.items()):
        if Path(name).name != name or Path(name).suffix.lower() != ".lua":
            raise ValueError("Invalid private archive filename")
        archive = safe_path(source / name)
        sidecar = safe_path(archive.with_suffix(".lua.json"))
        with sidecar.open("rb") as stream:
            encoded = stream.read(16385)
        if len(encoded) > 16384:
            raise ValueError("Private archive sidecar exceeds its limit")
        meta = json.loads(encoded.decode("utf-8-sig"))
        original = str(meta["source"])
        origin = Path(original)
        if (meta.get("schema") != 1 or meta.get("kind") != "RawScans" or meta.get("file") != name
                or meta.get("sha256") != approval["sha256"] or meta.get("sourceId") != config["sourceId"]
                or origin.name.lower() != "ahledger.lua" or origin.parent.name.lower() != "savedvariables"
                or hashlib.sha256(original.lower().encode()).hexdigest()[:16].upper() != config["sourceId"]):
            raise ValueError("Private archive does not match approved personal source")
        size = checked_archive_size(history.root, archive, limit)
        # A read-only SQLite connection supplies a consistent read transaction.
        with closing(sqlite3.connect(reference.as_uri() + "?mode=ro", uri=True)) as legacy, archive.open("rb") as stream:
            result = _import_verified(history, legacy, stream, meta, size, True, limit, now)
        if result == "committed":
            committed += 1
        elif result == "unchanged":
            replayed += 1
        else:
            raise ValueError("Unexpected private import result")
    return {"status": "committed" if committed else "unchanged", "committed": committed, "replayed": replayed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("config", "public-root", "addon"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    try:
        result = run(args.config, absolute(args.public_root), absolute(args.addon), lambda: int(time.time()))
    except (OSError, ValueError, KeyError, sqlite3.Error):
        print(json.dumps({"status": "unavailable"}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
