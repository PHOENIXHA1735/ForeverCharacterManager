# FCM v0.9.1 QA1 — combined Gathering, Legacy and Crafting preview

This test candidate merges the v0.9.0 QA6e player-tested crafting quantity
popup and tree-specific Legacy Advisor with v0.9.1 Gathering Preview (local
Git commit `2766a08`). It retains the Windows companion, account-wide roster,
BoE safety and Zygor/Pawn numerical weight imports.

## What changed

- `Core.lua`: gathered-resource event registration/forwarding, slash commands,
  community snapshot merge on login; both the Legacy commands and imported
  weight commands remain in place.
- `UI.lua`: Gathering tab, read-only GatherMate2 import button and node list;
  QA6e finished-item quantity popup and Legacy tree/goal controls are preserved.
- Both `.toc` files: version `0.9.1`, account-wide gathering export variable,
  Gathering and Legacy Advisor modules and optional community snapshot.
- Companion: GitHub community synchronization and voluntary anonymous export.
- Combined tests: all focused Gathering/Legacy/crafting/weight and BoE regressions.

## Do not lose personal data

1. Close WoW and the Windows companion completely.
2. Back up the installed `ForeverCharacterManager` directory **and** WoW's
   `WTF/Account/.../SavedVariables/FCM_DB.lua` before installing.
3. Merge the ZIP's `ForeverCharacterManager` directory into your installed
   `Interface/AddOns`, replacing matching source files only. **Do not delete**
   the installed directory or `WTF` records.
4. Keep your existing `ExternalData.generated.lua`, `AHPrices.generated.lua`,
   and updated `CommunityGathering.generated.lua`. The package's community
   snapshot is an empty starter and should not overwrite existing discoveries.

## In-game verification

1. **Version:** Open FCM Diagnostics. Confirm v0.9.1 build
   `QA1-20261114-Gathering-Craft-Legacy`, no new Lua errors, correct characters.
2. **Craft quantity:** On Spotty Dotty request *three* Red Linen Bags. Type
   `3` and press Enter. Verify the request is for **3 finished bags**, then
   try six with the Continue button and confirm the material multiplication.
3. **Legacy:** Choose each of Adventure, Professions and Resourcefulness.
   Confirm each shows only its own goals; `Professions -> Skill-Ups` recommends
   skill-up perks, `Adventure -> Leveling` recommends leveling perks, and
   `Resourcefulness -> Gathering` does not appear as a mislabeled goal.
4. **Weight profile:** On Frosty Bit verify the recorded numerical Zygor/Pawn
   Frost Mage weights remain active, character-specific, and unmodified by
   gathering tests.
5. **Gather import:** Keep GatherMate2 installed. Run `/fcm gather import`,
   then `/fcm gather status`. Record the imported herb, ore, pool and chest
   totals. Repeat import; the second run should add zero duplicates.
6. **Independent gathering:** Gather named herbs on Spotty Dotty, then a named
   vein on the miner; after each, run `/fcm gather status`. **If the game
   doesn't expose the node target, recording will be skipped.** Report that.
7. **Account-wide persistence:** Log out normally, switch characters and
   recheck counts. Test without GatherMate2 only after you have backups and
   verified independent recording with it enabled.
8. **Companion:** Close WoW, open the Windows companion and inspect
   `Sync Gathering (GitHub)` and `Export Gathering Contribution`. Public
   GitHub community files are not yet published, so sync cannot yield nodes.
   Exports should contain only node kind, map, coordinates and resource name.

## What is not yet done

- Actual WoW Forever client validation and Windows PowerShell/WinForms UI
  validation; those cannot be established by offline tests.
- Map/minimap resource markers, route optimization and direct crafting
  requirement-to-gathering integration (future increments).
- A populated community dataset or automatic contribution uploading; the
  starter JSON contains zero contributions, and publishing is not yet enabled.
- A published v0.9.1 GitHub release. The release workflow is manual-only until
  the tester confirms this combined build works.
