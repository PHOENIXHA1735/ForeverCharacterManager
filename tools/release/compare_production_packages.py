"""Compare the uncompressed identities of two 89-file FCM distribution ZIPs."""
import argparse
import hashlib
from pathlib import Path
from zipfile import ZipFile


def inventory(path):
    with ZipFile(path) as archive:
        files = [item for item in archive.infolist() if not item.is_dir()]
        if len(files) != 89 or len({item.filename.casefold() for item in files}) != 89:
            raise ValueError(f"Expected exactly 89 uniquely named files: {path}")
        return {item.filename: hashlib.sha256(archive.read(item)).hexdigest() for item in files}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("local", type=Path)
    parser.add_argument("github", type=Path)
    args = parser.parse_args()
    first, second = inventory(args.local), inventory(args.github)
    changed = sorted(key for key in first.keys() | second.keys() if first.get(key) != second.get(key))
    if changed:
        raise SystemExit("Content or path differences:\n" + "\n".join(changed))
    print("89 extracted file identities match. Any ZIP difference comes from archive encoding or metadata.")
