"""Exercise production policy with the pinned package and disposable Windows files."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/release"))
import activate_production as activation
import overlay


class Interrupted(BaseException):
    pass


class ProductionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.parent = Path(temporary.name).resolve()
        self.root = self.parent / "_forever_"
        self.payload = overlay.package(ARCHIVE, activation.ZIP_SHA)
        static, keep = {}, {}
        for key in self.payload:
            (self.root / key).parent.mkdir(parents=True, exist_ok=True)
        for name in activation.RETIRE | {"Core.lua", "ForeverCharacterManager.toc", "ForeverCharacterManager_Camelot.toc"}:
            static[overlay.ADDON + name] = self.put(overlay.ADDON + name, b"original " + name.encode())
        for name in activation.KEEP | overlay.REQUIRED_OLD:
            key = overlay.ADDON + name
            keep[key] = self.put(key, b"protected " + name.encode())
        fixture_save = (b'FCM_DB={characters={fixture={name="Synthetic"}},craftingQueue={{itemID=123}}}\n'
                        b'FCM_GatherExport={fixture={mapID=1}}\n')
        for name in ("ForeverCharacterManager.lua", "ForeverCharacterManager.lua.bak"):
            key = f"WTF/Account/fixture/SavedVariables/{name}"
            keep[key] = self.put(key, fixture_save)
        for relative, data in {
            "AHHistory/RawScans/fixture.lua": b"-- invented archive",
            "AHHistory/Parsed/fixture.sqlite3": b"synthetic history sentinel",
            "FCM-Companion/settings.json": b'{"fixture":true}',
            "FCM-Companion/reference-cache.json": b'{"entries":[]}',
            "FCM-Companion/foreverdb-request-budget.json": b'{"remaining":123}',
        }.items():
            key = overlay.ADDON + relative
            keep[key] = self.put(key, data)
        private = "Interface/AddOns/FCMPrivateHistory/History.lua"
        keep[private] = self.put(private, b"-- invented private export")
        directory = self.parent / "Tasks"
        self.task_directory = directory
        directory.mkdir()
        tasks = {}
        for name in activation.writer_gate.TASKS:
            data = json.dumps({"action": name, "enabled": True, "schedule": "fixture"}).encode()
            (directory / name).write_bytes(data)
            tasks[name] = overlay.digest(data)
        self.record = {"offline_drive": "D:", "ntfs_serial": "ABCD0123",
                       "exclusive_offline_maintenance": True, "recovery": "FCM-Recovery-20261121T120000Z",
                       "task_files": tasks, "baseline": {"static": static, "preserve": keep}}
        self.recovery = self.parent / self.record["recovery"]

    def put(self, key, data):
        path = self.root / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return overlay.digest(data)

    def execute(self, mode, hook=lambda _: None, serial=lambda _: "ABCD0123"):
        activation.execute(self.record, ARCHIVE, mode, serial=serial, read_acl=activation.acl,
                           fixture=self.root, hook=hook)

    def restored(self):
        overlay.check(self.task_directory, self.record["task_files"])
        baseline = self.record["baseline"]
        overlay.check(self.root, baseline["static"] | baseline["preserve"])
        state = json.loads((self.recovery / "journal.json").read_bytes())
        overlay.check(self.recovery / "backup", state["original"])
        self.assertEqual(state["phase"], "restored")

    def test_activate_and_rollback(self):
        self.execute("activate")
        for name in activation.RETIRE:
            self.assertFalse((self.root / (overlay.ADDON + name)).exists())
        overlay.check(self.root, self.record["baseline"]["preserve"])
        self.execute("rollback")
        self.restored()

    def test_fault_automatically_rolls_back(self):
        def fault(key):
            raise OSError("disposable failure")
        with self.assertRaisesRegex(OSError, "disposable"):
            self.execute("activate", fault)
        self.restored()

    def test_interruption_keeps_fence_and_recovers(self):
        def interrupt(key):
            raise Interrupted()
        with self.assertRaises(Interrupted):
            self.execute("activate", interrupt)
        self.assertTrue((self.root / activation.writer_gate.FENCE).is_file())
        self.execute("rollback")
        self.restored()

    def test_wrong_disk_and_altered_tasks_rejected(self):
        with self.assertRaisesRegex(ValueError, "volume"):
            self.execute("activate", serial=lambda _: "different")
        task = next(iter(self.record["task_files"]))
        (self.parent / "Tasks" / task).write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "definitions"):
            self.execute("activate")
        self.assertFalse(self.recovery.exists())

    def test_rollback_rejects_journal_edits_before_writes(self):
        self.execute("activate")
        file = self.recovery / "journal.json"
        state = json.loads(file.read_bytes())
        key = overlay.ADDON + "Core.lua"
        state["original"][key] = overlay.digest(b"unexpected backup")
        file.write_text(json.dumps(state))
        before = (self.root / key).read_bytes()
        with self.assertRaisesRegex(ValueError, "journal differs"):
            self.execute("rollback")
        self.assertEqual(before, (self.root / key).read_bytes())

    def test_required_backup_cannot_be_marked_absent(self):
        key = overlay.ADDON + "PublicHistory.generated.lua"
        self.record["baseline"]["preserve"][key] = None
        with self.assertRaisesRegex(ValueError, "concrete SHA-256"):
            self.execute("activate")
        self.assertFalse(self.recovery.exists())

    def test_normal_windows_cannot_activate(self):
        with self.assertRaises((RuntimeError, OSError)):
            activation.offline_serial("D:")


if __name__ == "__main__":
    ARCHIVE = Path(sys.argv.pop(1))
    unittest.main()
