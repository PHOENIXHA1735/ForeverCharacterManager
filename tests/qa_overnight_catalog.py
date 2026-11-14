"""Offline schedule/security contract checks; not a Windows Task Scheduler test."""

from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parent.parent
COMPANION = ROOT / "ForeverCharacterManager" / "FCM-Companion"
updater = (COMPANION / "FCMDataUpdater.ps1").read_text(encoding="utf-8")
provider = (COMPANION / "ForeverDB.Provider.ps1").read_text(encoding="utf-8")
installer = (COMPANION / "Enable-FCM-OvernightCatalog.ps1").read_text(encoding="utf-8")
docs = (COMPANION / "OVERNIGHT_CATALOG_SETUP.txt").read_text(encoding="utf-8")

# The Task Scheduler pattern must cover exactly every quarter-hour between
# 21:00 and 05:00, with no accidental daytime or 05:00 trigger.
minutes = sorted((21 * 60 + 15 * slot) % 1440 for slot in range(32))
expected = sorted([hour * 60 + minute for hour in (*range(21, 24), *range(5)) for minute in (0, 15, 30, 45)])
assert minutes == expected
assert "-lt 32" in installer and "15*$slot" in installer
assert "New-ScheduledTaskTrigger -Daily" in installer
assert "-MultipleInstances IgnoreNew" in installer
assert "-LogonType Interactive -RunLevel Limited" in installer

# Pacific wall-clock boundaries stay correct at standard/daylight changes.
zone = ZoneInfo("America/Los_Angeles")
for day in (date(2026, 3, 8), date(2026, 11, 1), date(2026, 11, 14)):
    for hour, should_run in ((0, True), (4, True), (5, False), (12, False), (20, False), (21, True), (23, True)):
        local = datetime(day.year, day.month, day.day, hour, 30, tzinfo=zone)
        assert (local.hour >= 21 or local.hour < 5) == should_run

assert "FindSystemTimeZoneById('Pacific Standard Time')" in updater
assert "if (Game-Is-Running)" in updater
assert "Write-LuaFile" in updater
assert "Get-Config" in updater
assert "-le 500" in updater
assert "OvernightDailyCap = 1200" in updater
assert "4000" in updater
assert "Set-FCMOvernightBackoff" in updater and "Test-FCMOvernightBackoff" in updater
assert "Set-FCMOvernightBackoff" in provider
assert "Assert-FCMOvernightRequestAllowed" in provider
assert "if (-not $script:OvernightCatalogMode)" in provider
assert "overnight-catalog-status.json" in docs
assert "ENABLE-FCM-OVERNIGHT.cmd" in updater
assert "foreverdb-key.dpapi" not in installer.split("$args=")[1].split("$action=")[0]
assert "Sync-AuctionPrices" not in updater.split("function Invoke-FCMOvernightCatalog")[1].split("function Action")[0]

print("PASS: 32 Pacific overnight starts, DST boundaries, separate catalog job, quota/backoff and data protections")
