"""Activate the pinned FCM release from an approved offline Windows environment."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import re
from tempfile import mkstemp

import overlay
import writer_gate
import fcm_security

ZIP_SHA = "2ddb8f081a37f227d561c5c45dd27e03f27bfa50545fcbd0e724a85468296d06"
CLIENT = ("Program Files (x86)", "World of Warcraft", "_forever_")
RETIRE = {"GatheringZones.lua", "GatherReference.lua", "GatherSkills.lua"}
KEEP = {"FCM-Companion/FCM-HiddenTask.vbs", "FCM-Companion/Repair-FCM-BackgroundTasks.ps1"}


def approved(path, expected):
    with overlay.location(path.parent, path.name).open("rb") as stream:
        data = stream.read(1_000_001)
    if len(data) > 1_000_000 or overlay.digest(data) != expected.lower():
        raise ValueError("Approval digest mismatch")
    return json.loads(data)


def offline_serial(drive):
    if os.name != "nt" or os.environ.get("SystemDrive", "").upper() != "X:":
        raise RuntimeError("An offline Windows PE boot is required")
    if ctypes.WinDLL("user32").GetSystemMetrics(0x1000):
        raise RuntimeError("Offline maintenance requires a local console")
    import winreg
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\MiniNT"):
        pass
    if not re.fullmatch(r"[C-WY-Z]:", drive):
        raise ValueError("Expected an approved offline Windows volume")
    system = Path(drive + "/Windows/System32/config/SYSTEM")
    if not overlay.location(system.parent, system.name).is_file():
        raise ValueError("Offline Windows installation not found")
    serial = ctypes.c_ulong()
    filesystem = ctypes.create_unicode_buffer(16)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    if not kernel.GetVolumeInformationW(drive + "\\", None, 0, ctypes.byref(serial), None, None, filesystem, len(filesystem)):
        raise ctypes.WinError(ctypes.get_last_error())
    if filesystem.value != "NTFS" or kernel.GetDriveTypeW(drive + "\\") != 3:
        raise ValueError("Only a fixed NTFS target is supported")
    return f"{serial.value:08X}"


def acl(path):
    """Read the original file owner, group, and DACL exactly."""
    return fcm_security.acl(path)


def acl_preflight(root, operations, read_acl=acl, write_acl=fcm_security.set_acl,
                  desired=None):
    """Prove a temporary replacement can match every approved descriptor.

    The original file and its security descriptor are never modified here.
    For activation, existing files retain their security and new files inherit.
    For rollback, `desired` is the pinned activation evidence.
    """
    expected = {}
    for key in operations:
        target = overlay.location(root, key)
        if not target.parent.is_dir():
            raise ValueError(f"Destination directory has no reviewed ACL: {key}")
        original = read_acl(target) if target.exists() else None
        if desired is not None:
            if key not in desired:
                raise ValueError(f"Missing reviewed ACL identity: {key}")
            wanted = desired[key]
            if original is not None and original != wanted:
                raise ValueError(f"Destination permissions changed: {key}")
        else:
            wanted = original
        handle, name = mkstemp(dir=target.parent, prefix=".fcm-permission-check-")
        os.close(handle)
        temporary = Path(name)
        try:
            inherited = read_acl(temporary)
            if wanted is None:
                wanted = inherited
            elif wanted != inherited:
                write_acl(temporary, wanted)
            if read_acl(temporary) != wanted:
                raise ValueError(f"Temporary file cannot preserve permissions: {key}")
        finally:
            temporary.unlink()
        expected[key] = wanted
    return expected


def policy(baseline, payload):
    static = baseline["static"]
    preserved = baseline["preserve"]
    if {key for key in static if key not in payload} != {overlay.ADDON + name for name in RETIRE}:
        raise ValueError("Only the three reviewed legacy modules may be retired")
    if not {overlay.ADDON + name for name in KEEP | overlay.REQUIRED_OLD} <= preserved.keys():
        raise ValueError("Required local files are absent from preservation inventory")
    if any(key in payload for key in (overlay.ADDON + name for name in KEEP)):
        raise ValueError("Release would overwrite an installed task helper")
    saves = {key for key in preserved if key.startswith("WTF/Account/") and
             key.endswith("/SavedVariables/ForeverCharacterManager.lua")}
    if not saves or not all(key + ".bak" in preserved for key in saves):
        raise ValueError("SavedVariables and matching backup required")
    required = {overlay.ADDON + name for name in KEEP | RETIRE | overlay.REQUIRED_OLD}
    required |= saves | {key + ".bak" for key in saves}
    hashes = static | preserved
    if any(not isinstance(hashes.get(key), str) or not re.fullmatch(r"[0-9a-f]{64}", hashes[key])
           for key in required):
        raise ValueError("Required original files must have concrete SHA-256 identities")


def execute(record, archive, mode, *, serial=offline_serial, read_acl=acl,
            write_acl=fcm_security.set_acl, fixture=None, hook=lambda _: None):
    # The CLI never supplies a fixture or substitutes the machine checks.
    drive = record["offline_drive"].upper()
    root = fixture if fixture is not None else Path(drive + "/").joinpath(*CLIENT)
    recovery = root.parent / record["recovery"]
    if not re.fullmatch(r"FCM-Recovery-[0-9]{8}T[0-9]{6}Z", record["recovery"]):
        raise ValueError("Invalid recovery directory name")
    expected_serial = record["ntfs_serial"]
    baseline = record["baseline"]
    identity = overlay.digest(json.dumps(record, sort_keys=True).encode())
    saves = {key for key in baseline["preserve"] if key.startswith("WTF/Account/") and
             key.endswith(("/SavedVariables/ForeverCharacterManager.lua",
                           "/SavedVariables/ForeverCharacterManager.lua.bak"))}

    def guard(actual, probe):
        if actual != root or serial(drive) != expected_serial:
            raise ValueError("Approved offline volume identity mismatch")
        if not record.get("exclusive_offline_maintenance") is True:
            raise ValueError("Exclusive offline maintenance approval is required")
        if probe() != {"complete": True, "writers": [], "unfenced": []}:
            raise ValueError("Maintenance census is incomplete")

    def tasks():
        # Compare exact raw task definitions from the offline Windows tree.
        # Approval hashes are recorded during authorized, read-only preflight.
        directory = root.parents[2] / "Windows/System32/Tasks" if fixture is None else root.parent / "Tasks"
        current = {name: overlay.fingerprint(overlay.location(directory, name)) for name in writer_gate.TASKS}
        if current != record["task_files"] or any(value is None for value in current.values()):
            raise ValueError("Original scheduled-task definitions do not match approval")
        return current

    guard(root, lambda: {"complete": True, "writers": [], "unfenced": []})
    task_hashes = tasks()
    payload = overlay.package(archive, ZIP_SHA)
    policy(baseline, payload)
    recovery_acl = recovery.parent
    if not overlay.location(recovery_acl.parent, recovery_acl.name).is_dir():
        raise ValueError("Recovery parent cannot be verified")
    task_dir = root.parents[2] / "Windows/System32/Tasks" if fixture is None else root.parent / "Tasks"
    evidence = root.parent / (recovery.name + "-task-definitions")
    metadata = evidence / "activation.json"

    def verify_evidence():
        overlay.check(evidence, task_hashes)
        saved = json.loads(overlay.location(evidence, metadata.name).read_bytes())
        if saved["identity"] != identity:
            raise ValueError("Activation approval differs from recovery evidence")
        return {key: bytes.fromhex(value) for key, value in saved["permissions"].items()}

    def finish(phase):
        expected = verify_evidence()
        for key, value in expected.items():
            target = overlay.location(root, key)
            if target.exists() and read_acl(target) != value:
                raise ValueError(f"Final ACL verification failed: {key}")

    if mode == "rollback":
        expected = verify_evidence()
        journal = json.loads(overlay.location(recovery, "journal.json").read_bytes())
        old = baseline["static"]
        preserve = baseline["preserve"]
        managed = old.keys() | payload.keys()
        operations = {}
        for key in sorted(managed - preserve.keys()):
            before = old.get(key)
            after = overlay.digest(payload[key]) if key in payload else None
            if before != after:
                operations[key] = {"before": before, "after": after}
        original = {**old, **preserve, **{key: value["before"] for key, value in operations.items()}}
        if (journal["operations"] != operations or journal["original"] != original
                or journal["root"] != str(root) or set(expected) != set(operations) | saves):
            raise ValueError("Rollback journal differs from approved file identities")
        # Require a compatible destination security descriptor before any restore.
        if acl_preflight(root, expected, read_acl, write_acl, desired=expected) != expected:
            raise ValueError("Rollback ACL inheritance differs from original")
        writer_gate.transact(root, recovery, tasks, guard=guard, finish=finish,
                             identity=identity, security=expected)
        return

    expected = {}

    def prepare():
        operations = overlay.plan(root, payload, baseline)
        expected.update(acl_preflight(root, operations, read_acl, write_acl))
        # Protected SavedVariables and their .bak files can be restored after
        # a failed transaction; prove ACL-preserving restoration in advance.
        expected.update(acl_preflight(root, sorted(saves), read_acl, write_acl))
        evidence.mkdir()
        for name in task_hashes:
            overlay.atomic_write(evidence / name, overlay.location(task_dir, name).read_bytes())
        overlay.check(evidence, task_hashes)
        overlay.record(metadata, {"identity": identity, "permissions": {
            key: value.hex() for key, value in expected.items()
        }})
        verify_evidence()

    def verify_write(key):
        target = overlay.location(root, key)
        if target.exists() and read_acl(target) != expected[key]:
            raise ValueError(f"Installed permissions differ: {key}")
        hook(key)

    writer_gate.transact(root, recovery, tasks, payload, baseline, verify_write, guard=guard,
                         prepare=prepare, finish=finish, identity=identity, security=expected)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("activate", "rollback"))
    parser.add_argument("package", type=Path)
    parser.add_argument("approval", type=Path)
    parser.add_argument("--approval-sha256", required=True)
    parser.add_argument("--confirm-offline-production", action="store_true", required=True)
    args = parser.parse_args()
    execute(approved(args.approval.absolute(), args.approval_sha256), args.package, args.mode)
