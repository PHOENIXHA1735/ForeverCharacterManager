"""FCM v0.9.4 V2 preservation regression checks; disposable fixture only.

Usage (from the isolated FCM repository root):
    python -B tests/qa_v094_preservation_regression.py PATH_TO_PINNED_ZIP

This imports the existing synthetic activation fixture. It never targets an
installed WoW directory, scheduled tasks, or the production companion.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPOSITORY / "tools" / "release"))
sys.path.insert(0, str(REPOSITORY / "tests"))

import qa_production_activation as activation_tests
import activate_production as activation
import overlay

PINNED_ZIP_SHA256 = "2ddb8f081a37f227d561c5c45dd27e03f27bfa50545fcbd0e724a85468296d06"
PRESERVED_TEMPLATES = (
    overlay.ADDON + "PublicHistory.generated.lua",
    overlay.ADDON + "CommunityGathering.generated.lua",
)


def verify_installed_fixture(root: Path, payload: dict, baseline: dict) -> None:
    """Implement V2's managed-versus-preserved verification rule.

    The helper is test-only: it verifies synthetic installed file bytes, not
    WinPE approval, NTFS identity, ACL evidence, or live writer exclusion.
    """
    for key, data in payload.items():
        if key in baseline["preserve"]:
            continue
        if overlay.fingerprint(overlay.location(root, key)) != overlay.digest(data):
            raise AssertionError("Installed managed file differs from release ZIP: " + key)

    for key, expected in baseline["preserve"].items():
        if overlay.fingerprint(overlay.location(root, key)) != expected:
            raise AssertionError("Preserved file differs from approved baseline: " + key)

    for key in set(baseline["static"]) - set(payload):
        if overlay.location(root, key).exists():
            raise AssertionError("Retired file still exists: " + key)


class V2PreservationRegression(unittest.TestCase):
    def setUp(self) -> None:
        # Reuse the already established, disposable FCM activation fixture.
        self.fixture = activation_tests.ProductionTests("test_activate_and_rollback")
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root.resolve()
        temp_root = Path(tempfile.gettempdir()).resolve()
        if not self.root.is_relative_to(temp_root) or self.root.name != "_forever_":
            raise RuntimeError("Refusing to test outside disposable fixture")
        self.baseline = self.fixture.record["baseline"]
        self.payload = self.fixture.payload
        self.fixture.execute("activate")

    def check(self) -> None:
        verify_installed_fixture(self.root, self.payload, self.baseline)

    def test_preserved_templates_use_baseline_not_release_zip(self) -> None:
        for key in PRESERVED_TEMPLATES:
            self.assertIn(key, self.payload)
            self.assertIn(key, self.baseline["preserve"])
            self.assertNotEqual(overlay.digest(self.payload[key]), self.baseline["preserve"][key])
            self.assertEqual(overlay.fingerprint(overlay.location(self.root, key)), self.baseline["preserve"][key])
        self.check()

    def test_modified_managed_file_detected(self) -> None:
        self.check()
        overlay.location(self.root, overlay.ADDON + "Core.lua").write_bytes(b"tampered managed fixture")
        with self.assertRaisesRegex(AssertionError, "Installed managed file differs"):
            self.check()

    def test_modified_protected_file_detected(self) -> None:
        self.check()
        overlay.location(self.root, PRESERVED_TEMPLATES[0]).write_bytes(b"tampered protected fixture")
        with self.assertRaisesRegex(AssertionError, "Preserved file differs"):
            self.check()

    def test_retired_file_reappearance_detected(self) -> None:
        self.check()
        obsolete = overlay.ADDON + "GatheringZones.lua"
        self.assertNotIn(obsolete, self.payload)
        self.assertIn(obsolete, self.baseline["static"])
        path = overlay.location(self.root, obsolete)
        path.write_bytes(b"unexpected retired fixture")
        with self.assertRaisesRegex(AssertionError, "Retired file still exists"):
            self.check()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: qa_v094_preservation_regression.py PINNED_FCM_v0.9.4_ZIP")
    release_zip = Path(sys.argv.pop(1)).resolve()
    if not release_zip.is_file():
        raise SystemExit("STOP: Pinned ZIP not found")
    with release_zip.open("rb") as f:
        archive_hash = hashlib.file_digest(f, "sha256").hexdigest()
    if archive_hash.lower() != PINNED_ZIP_SHA256:
        raise SystemExit("STOP: Pinned ZIP SHA-256 mismatch")
    activation_tests.ARCHIVE = release_zip
    unittest.main(verbosity=2)
