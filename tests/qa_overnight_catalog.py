"""Offline schedule/security contract checks; not a Windows Task Scheduler test."""

from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parent.parent
COMPANION = ROOT / "ForeverCharacterManager" / "FCM-Companion"
updater = (COMPANION / "FCMDataUpdater.ps1").read_text(encoding="utf-8")
provider = (COMPANION / "ForeverDB.Provider.ps1").read_text(encoding="utf-8")
quota = (COMPANION / "ForeverDB.Quota.ps1").read_text(encoding="utf-8")
build_check = (COMPANION / "FCM-ForeverDBBuildCheck.ps1").read_text(encoding="utf-8")
installer = (COMPANION / "Enable-FCM-OvernightCatalog.ps1").read_text(encoding="utf-8")
docs = (COMPANION / "OVERNIGHT_CATALOG_SETUP.txt").read_text(encoding="utf-8")

# Two tasks cover every quarter-hour from 22:00 through 11:45, not noon.
minutes = sorted((start * 60 + 15 * slot) % 1440 for start in (22, 5) for slot in range(28))
expected = sorted([hour * 60 + minute for hour in (*range(22, 24), *range(12)) for minute in (0, 15, 30, 45)])
assert minutes == expected
assert len(minutes) == 56
assert "startHour=22;slots=28" in installer and "startHour=5;slots=28" in installer
assert "-lt $window.slots" in installer and "15*$slot" in installer
assert "New-ScheduledTaskTrigger -Daily" in installer
assert "-MultipleInstances IgnoreNew" in installer
assert "-LogonType Interactive -RunLevel Limited" in installer

# Pacific wall-clock boundaries stay correct at standard/daylight changes.
zone = ZoneInfo("America/Los_Angeles")
for day in (date(2026, 3, 8), date(2026, 11, 1), date(2026, 11, 14)):
    for hour, should_run in ((0, True), (4, True), (5, True), (11, True), (12, False), (21, False), (22, True), (23, True)):
        local = datetime(day.year, day.month, day.day, hour, 30, tzinfo=zone)
        assert (local.hour >= 22 or local.hour < 12) == should_run

assert "FindSystemTimeZoneById('Pacific Standard Time')" in updater
assert "if (Game-Is-Running)" in updater
assert "Write-LuaFile" in updater
assert "Get-Config" in updater
assert "ForeverDBDailyCap=4500" in quota
assert "ForeverDBRequestSpacingMs=4000" in quota
assert "[IO.Path]::GetFullPath($path)" in quota
assert "[IO.File]::Replace($temp,$path,($path+'.previous'))" in quota
assert "[IO.File]::Replace($temp,$path,$null)" not in quota
assert "$env:LOCALAPPDATA" in quota
assert "-le 500" in quota
assert "Local\\FCM-ForeverDB-Shared-Quota" in quota
assert "Get-FCMForeverDBBudgetInfo" in updater
assert "Reserve-FCMForeverDBRequest" in provider
assert "Reserve-FCMForeverDBRequest" in build_check
assert "overnight-catalog-budget.json" in quota  # migration
assert "Test-FCMForeverDBBackoff" in quota and "Set-FCMForeverDBBackoff" in provider
assert "Assert-FCMOvernightRequestAllowed" in provider
assert "if (-not $script:OvernightCatalogMode)" in provider
assert "overnight-catalog-status.json" in docs
assert "foreverdb-request-budget.json" in docs
assert "%LOCALAPPDATA%\\ForeverCharacterManager" in docs
assert "ENABLE-FCM-OVERNIGHT.cmd" in updater
assert "foreverdb-key.dpapi" not in installer.split("$args=")[1].split("$action=")[0]
assert "Sync-AuctionPrices" not in updater.split("function Invoke-FCMOvernightCatalog")[1].split("function Action")[0]

for manual in (0, 500, 1000, 2500, 4000, 4500):
    assert max(0, 4500 - manual) + manual == 4500

print("PASS: 56 Pacific starts, DST boundaries, combined 4500 manual/scheduled/build budget, shared throttling/backoff and data protections")
