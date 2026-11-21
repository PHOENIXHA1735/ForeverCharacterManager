"""Run the overlay and guarded recovery against invented client layouts."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/release"))
import overlay


class PowerLoss(BaseException):
    pass


class OverlayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.client = self.base / "_forever_"
        self.client.mkdir()
        (self.client / overlay.MARKER).touch()
        self.recovery = self.base / "timestamped-backup"
        self.journal = self.recovery / "journal.json"
        self.state = {"complete": True, "writers": [], "unfenced": []}
        self.static = {overlay.ADDON + name: b"original" for name in (
            "Core.lua", "Retired.lua", "ForeverCharacterManager.toc",
            "ForeverCharacterManager_Camelot.toc", "FCM-Companion/FCMDataUpdater.ps1",
        )}
        self.saved = "WTF/Account/invented/SavedVariables/ForeverCharacterManager.lua"
        self.protected = {overlay.ADDON + name: b"local generated data" for name in overlay.REQUIRED_OLD}
        for key in (
            self.saved, self.saved + ".bak", overlay.ADDON + "FCM-Companion/settings.json",
            overlay.ADDON + "FCM-Companion/reference-cache.json",
            overlay.ADDON + "FCM-Companion/foreverdb-request-budget.json",
            overlay.ADDON + "AHHistory/Parsed/invented.sqlite3",
            "Interface/AddOns/FCMPrivateHistory/invented.lua",
            "mock-task-inventory.json",
        ):
            self.protected[key] = b"invented protected bytes"
        for key, data in {**self.static, **self.protected}.items():
            overlay.atomic_write(self.client / key, data)
        self.baseline = {
            "static": {key: overlay.digest(data) for key, data in self.static.items()},
            "preserve": {key: overlay.digest(data) for key, data in self.protected.items()},
        }
        self.payload = {key: b"release bytes" for key in self.static if not key.endswith("Retired.lua")}
        self.payload.update({overlay.ADDON + name: b"release seed" for name in (
            "HistoryProvider.lua", "GatheringReferenceData.lua", "PublicHistory.generated.lua",
            "CommunityGathering.generated.lua",
        )})

    def apply(self, hook=lambda _: None):
        overlay.apply(self.client, self.payload, self.baseline, self.recovery, lambda: self.state, hook)

    def phase(self):
        return json.loads(self.journal.read_bytes())

    def original(self):
        overlay.check(self.client, {**self.baseline["static"], **self.baseline["preserve"]})
        overlay.check(self.recovery / "backup", self.phase()["original"])
        self.assertFalse((self.client / (overlay.ADDON + "HistoryProvider.lua")).exists())

    def test_dry_run_and_apply(self):
        changes = overlay.plan(self.client, self.payload, self.baseline)
        self.assertEqual(7, len(changes))
        self.assertIsNone(changes[overlay.ADDON + "Retired.lua"]["after"])
        self.assertFalse(self.recovery.exists())
        overlay.check(self.client, self.baseline["static"])
        self.apply()
        self.assertEqual("committed", self.phase()["phase"])
        overlay.check(self.client, self.baseline["preserve"])
        self.assertFalse((self.client / (overlay.ADDON + "Retired.lua")).exists())

    def test_failure_before_commit_rolls_back(self):
        def fail(key):
            raise OSError("fixture write failure")
        with self.assertRaises(OSError):
            self.apply(fail)
        self.assertEqual("restored", self.phase()["phase"])
        self.original()

    def test_interruption_recovery(self):
        def interrupt(key):
            raise PowerLoss()
        with self.assertRaises(PowerLoss):
            self.apply(interrupt)
        self.assertEqual("pending", self.phase()["phase"])
        overlay.restore(self.client, self.recovery, lambda: self.state)
        self.original()

    def test_post_commit_recovery_preserves_failed_state(self):
        self.apply()
        overlay.atomic_write(self.client / self.saved, b"new client save")
        overlay.restore(self.client, self.recovery, lambda: self.state)
        self.original()
        evidence, = self.recovery.glob("failed-*")
        self.assertEqual(b"new client save", (evidence / self.saved).read_bytes())

    def test_guard_missing_inventory_active_or_unfenced(self):
        for state in (
            {}, {"complete": True, "writers": ["Wow.exe"], "unfenced": []},
            {"complete": True, "writers": [], "unfenced": ["FCM-AHHistory"]},
        ):
            with self.subTest(state=state):
                self.state = state
                with self.assertRaisesRegex(ValueError, "Writer state"):
                    self.apply()
                self.assertFalse(self.recovery.exists())

    def test_guard_change_blocks_resume_until_clear(self):
        def new_writer(key):
            self.state["writers"] = ["pythonw.exe"]
        with self.assertRaisesRegex(ValueError, "Writer state"):
            self.apply(new_writer)
        self.assertEqual("pending", self.phase()["phase"])
        self.state["writers"] = []
        overlay.restore(self.client, self.recovery, lambda: self.state)
        self.original()

    def test_unapproved_existing_code_rejected(self):
        overlay.atomic_write(self.client / (overlay.ADDON + "Unknown.lua"), b"do not touch")
        with self.assertRaisesRegex(ValueError, "Unreviewed"):
            overlay.plan(self.client, self.payload, self.baseline)

    def test_changed_baseline_and_corrupt_backup_rejected(self):
        self.apply()
        key = overlay.ADDON + "Retired.lua"
        overlay.atomic_write(self.recovery / "backup" / key, b"corruption")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            overlay.restore(self.client, self.recovery, lambda: self.state)
        self.assertEqual("committed", self.phase()["phase"])

    def test_initial_hash_mismatch(self):
        overlay.atomic_write(self.client / (overlay.ADDON + "Core.lua"), b"changed")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            overlay.plan(self.client, self.payload, self.baseline)


if __name__ == "__main__":
    unittest.main()
