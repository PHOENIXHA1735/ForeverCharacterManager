"""Cross-process writer admission and interrupted maintenance rehearsals."""
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from qa_release_overlay import OverlayTests, PowerLoss, overlay
import writer_gate


class WriterGateTests(OverlayTests):
    def setUp(self):
        super().setUp()
        self.task_file = self.client / "tasks.json"
        self.task_bytes = json.dumps({
            name: {"enabled": index != 1, "action": f"fixture-{index}.cmd",
                   "minutes": (30, 720, 30, 5)[index]}
            for index, name in enumerate(sorted(writer_gate.TASKS))
        }).encode()
        self.task_file.write_bytes(self.task_bytes)
        self.baseline["preserve"]["tasks.json"] = overlay.digest(self.task_bytes)

    def task_inventory(self):
        return json.loads(self.task_file.read_bytes())

    def child(self, name):
        return subprocess.Popen(
            [sys.executable, "-B", str(Path(__file__).resolve()), "writer", str(self.client), name],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )

    def denied(self, name):
        with self.child(name) as child:
            output, error = child.communicate(timeout=15)
            self.assertEqual((23, ""), (child.returncode, error), output)
            self.assertFalse((self.client / "writer-touched").exists())

    def deploy(self, hook=lambda _: None):
        writer_gate.transact(self.client, self.recovery, self.task_inventory,
                             self.payload, self.baseline, hook)

    def recover(self):
        writer_gate.transact(self.client, self.recovery, self.task_inventory)

    def test_all_writers_denied_mid_deployment(self):
        seen = []
        def hook(key):
            if not seen:
                for name in sorted(writer_gate.TASKS | {"manual"}):
                    self.denied(name)
            seen.append(key)
        self.deploy(hook)
        self.assertEqual("committed", self.phase()["phase"])
        self.assertFalse((self.client / writer_gate.FENCE).exists())
        overlay.check(self.client, self.baseline["preserve"])

    def test_running_writer_and_lease_contention(self):
        for name in ("FCM-AHHistory", "manual"):
            with self.child(name) as child:
                try:
                    self.assertEqual("entered", child.stdout.readline().strip())
                    with self.assertRaises(writer_gate.Busy):
                        self.deploy()
                    self.assertFalse(self.recovery.exists())
                finally:
                    child.communicate(input="exit\n",timeout=15)
            (self.client / "writer-touched").unlink()

    def test_interrupted_and_failed_recovery_keep_gate(self):
        def interrupt(key):
            raise PowerLoss()
        with self.assertRaises(PowerLoss):
            self.deploy(interrupt)
        self.denied("manual")
        key = overlay.ADDON + "Retired.lua"
        backup = self.recovery / "backup" / key
        content = backup.read_bytes()
        backup.write_bytes(b"bad backup")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            self.recover()
        self.denied("FCM-Private365-Update")
        backup.write_bytes(content)
        self.recover()
        self.original()
        self.assertFalse((self.client / writer_gate.FENCE).exists())

    def test_incomplete_task_census(self):
        self.task_file.write_text("{}")
        with self.assertRaisesRegex(ValueError, "incomplete"):
            self.deploy()
        self.assertFalse(self.recovery.exists())

    def test_task_and_protected_permissions_unchanged(self):
        paths = [self.client / key for key in self.baseline["preserve"] | self.baseline["static"]]
        def permissions():
            if os.name != "nt":
                return [p.stat().st_mode for p in paths]
            return [subprocess.check_output(["icacls.exe", str(p)]) for p in paths]
        before = permissions()
        def fail(key):
            raise OSError("fixture rollback")
        with self.assertRaisesRegex(OSError, "fixture rollback"):
            self.deploy(fail)
        self.original()
        self.assertEqual(before, permissions())
        self.assertEqual(self.task_bytes, self.task_file.read_bytes())


if __name__ == "__main__":
    if sys.argv[1:2] == ["writer"]:
        try:
            with writer_gate.writer(Path(sys.argv[2]), sys.argv[3]):
                print("entered", flush=True)
                sys.stdin.readline()
                (Path(sys.argv[2]) / "writer-touched").touch()
        except writer_gate.Busy:
            sys.exit(23)
    else:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(WriterGateTests)
        selected = unittest.TestSuite(t for t in suite if t._testMethodName not in dir(OverlayTests))
        sys.exit(not unittest.TextTestRunner(verbosity=2).run(selected).wasSuccessful())
