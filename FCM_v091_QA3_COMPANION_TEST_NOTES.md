# FCM v0.9.1 QA3 — Companion quota fix and Clam Meat checks

Build `QA3-20261114-Quota-Ledger-Repair` (not yet published as a GitHub release).

## Why QA3 exists

On November 14 the companion reached ForeverDB build `1.60.1.70938` but every
subsequent ForeverDB request failed with `Exception calling "Replace" with "3"
argument(s): "The path is not of a legal form."` Only one of the shared 4500
daily ForeverDB requests was counted. The TheWoWDB item-name search still
found five `clam meat` matches, yet did not refresh any individual items.

The issue was traced to the shared budget ledger's second write, when it
replaced an existing JSON file. This build supplies a full file path and a
real `.previous` backup file. No quotas, waiting limits, API keys or personal
SavedVariables were changed.

## Install and run a zero-network regression test

1. Finish/close WoW Forever and the Windows companion.
2. Back up the installed `ForeverCharacterManager` addon folder and your FCM
   SavedVariables. Merge QA3's `ForeverCharacterManager` folder over your
   installed addon. Do **not** remove local data files, keys or SavedVariables.
3. From the installed `FCM-Companion` folder, open Windows PowerShell and run:

   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-FCMQuotaLedger.ps1`

4. Expect `PASS: quota ledger created, atomically updated, and previous count preserved.`
   This test does **not** contact ForeverDB or read/reset your real quota ledger.
5. If it fails, stop and send the exact error. Do **not** delete or edit
   `%LOCALAPPDATA%\ForeverCharacterManager\foreverdb-request-budget.json`.

## Retest ForeverDB and Clam Meat

1. With WoW closed, launch the Windows companion from the installed location.
2. In public item search, enter `clam meat`; optionally add numeric `5503`.
   Select **Scan and Update** once. Do not repeat after a quota/backoff error.
3. Look for `ForeverDB catalog: ...` and actual item/recipe import counts.
   A change from `1 API calls` to multiple allowed calls without `Replace`
   errors is the first acceptance check. A manual scan will consume normal
   provider quota and obey the 4500 shared FCM UTC-day cap.
4. Record `TheWoWDB search 'clam meat': N records`, cached item count,
   catalog offset and the `REFERENCE HEALTH` summary. Five search hits do
   not necessarily mean Clam Meat item ID 5503 was written into the catalog.
5. Restart WoW and open FCM Item Explorer. Reset Category/Type/Slot/Source/
   Quality filters and search `Clam Meat`, `Clam` and `5503`.
6. Send the companion log and the in-game search result. If catalog refresh
   succeeds but 5503 remains absent, investigate provider item data and the
   Item Explorer's loading/filtering behavior separately.

## Preserve these safeguards

- Do not reset the existing daily request count or delete `.previous` files.
- The backup contains only budget metadata, not character data or credentials.
- The 22:00–11:45 Pacific overnight window is opt-in and still needs Windows
  user sign-in and an awake computer; it must not launch while WoW is running.
- This patch is not a confirmed live fix until the isolated Windows test and
  a real companion scan succeed on the affected PC.
