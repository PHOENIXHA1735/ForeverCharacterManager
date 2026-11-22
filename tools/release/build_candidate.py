"""Build a reproducible public addon candidate from a committed tree."""
import argparse
import hashlib
import subprocess
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

PREFIX = "ForeverCharacterManager/"
VERSION = "0.9.4"
LOCAL = {"ExternalData.generated.lua", "AHPrices.generated.lua", "AHHistory.generated.lua"}
STUBS = {"PublicHistory.generated.lua", "CommunityGathering.generated.lua"}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def build(ref, out):
    def git(*args):
        return subprocess.check_output(["git", *args])

    commit = git("rev-parse", "--verify", ref + "^{commit}").decode().strip()
    source = {}
    for row in git("ls-tree", "-r", commit, "--", PREFIX).decode().splitlines():
        info, path = row.split("\t", 1)
        mode, kind, object_id = info.split()
        relative = path.removeprefix(PREFIX)
        if relative.startswith("AHHistory/"):
            continue
        if mode != "100644" or kind != "blob" or relative in LOCAL:
            raise ValueError(f"Unexpected distribution source: {path}")
        source[path] = git("cat-file", "blob", object_id)

    for path, data in source.items():
        low = path.lower()
        if any(token in low for token in (
            "savedvariables", "private365", "fcmprivatehistory", "settings.json",
            "reference-cache.json", "python-path.local", ".dpapi", ".sqlite", "fixture",
        )) or b"FCM_PR9_QA_" in data:
            raise ValueError(f"Private or QA artifact: {path}")
    for toc in ("ForeverCharacterManager.toc", "ForeverCharacterManager_Camelot.toc"):
        lines = source[PREFIX + toc].decode("utf-8-sig").splitlines()
        required = {f"## Version: {VERSION}", "## SavedVariables: FCM_DB, FCM_GatherExport"}
        if not required <= set(lines):
            raise ValueError(f"Unexpected TOC metadata: {toc}")
        for line in (line.strip() for line in lines):
            if line and not line.startswith("#") and line not in LOCAL and PREFIX + line not in source:
                raise ValueError(f"TOC dependency missing: {line}")
    if f'FCM.version = "{VERSION}"'.encode() not in source[PREFIX + "Core.lua"]:
        raise ValueError("Core version mismatch")
    for name in STUBS:
        if source[PREFIX + name] != git("show", "bbc25cf133230d24b5b913d8c39e4fa70e89fd2b:" + PREFIX + name):
            raise ValueError(f"Unexpected generated content: {name}")
    out.mkdir(parents=True, exist_ok=False)
    manifest = "".join(f"{digest(data)}  {name}\n" for name, data in sorted(source.items())).encode()
    (out / "PACKAGE-SHA256.txt").write_bytes(manifest)
    path = out / f"FCM-v{VERSION}.zip"
    with ZipFile(path, "x") as archive:
        for name, data in sorted(source.items()):
            archive.writestr(ZipInfo(name), data, compress_type=ZIP_DEFLATED)
    with ZipFile(path) as archive:
        if archive.testzip() or archive.namelist() != sorted(source):
            raise ValueError("ZIP inventory verification failed")
        if any(archive.read(name) != data for name, data in source.items()):
            raise ValueError("ZIP bytes differ from reviewed source")
    checksum = digest(path.read_bytes())
    (out / (path.name + ".sha256")).write_text(f"{checksum}  {path.name}\n", encoding="ascii")
    print(f"{commit} | {len(source)} files | ZIP {checksum} | manifest {digest(manifest)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path)
    parser.add_argument("--ref", default="HEAD")
    args = parser.parse_args()
    build(args.ref, args.out)
