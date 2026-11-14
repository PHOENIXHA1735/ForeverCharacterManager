# FCM v0.9.1 — Local Gathering / GitHub Community Preview

## QA1 combined candidate (awaiting player verification)

The QA1 source and install test package also include the QA6e finished-output
crafting quantity popup fix, Zygor/Pawn numerical Frost Mage weight profiles,
and the complete tree-specific Legacy Point Advisor with manual snapshots.
Both addon `.toc` variants load `LegacyAdvisor.lua`, `Gathering.lua`, and the
optional community data stub. See `FCM_v091_QA1_COMBINED_TEST_NOTES.md` for
the combined test checklist. This candidate has **not** been published to
GitHub; the release workflow is manual-only until those tests pass.

## Implemented

- Added a **Gathering** sidebar tab and `/fcm gather`, `/fcm gather status`, `/fcm gather import`.
- One-time read-only GatherMate2 import of four node types, saving FCM-owned records into `FCM_DB`.
- Independent tracking of explicitly named, successfully cast herbalism/mining nodes. Fishing locations require an explicitly named pool/school; ordinary open-water catches are not misleadingly recorded as a pool.
- Private, account-wide node cache with source labels: personal, GatherMate2 and community; duplicates merge without overwriting personal evidence.
- Versioned read-only public JSON snapshots at `CommunityData/`, initially empty.
- Windows companion **Sync Gathering (GitHub)** downloads and validates the static public data, generates a Lua data file without executing remote code, and leaves the private FCM DB untouched.
- Windows companion **Export Gathering Contribution** reads only the sanitized `FCM_GatherExport` marker in saved variables and creates a local, reviewable JSON file. **No automatic uploads, account data, names or credentials.**
- Existing code installer and GitHub release updater preserve a downloaded community snapshot during future addon updates.

## Important caveats

1. Tested under offline Lua simulation only. Live WoW Forever events may omit or secret node names, which FCM intentionally refuses to guess. Verify on real characters before uninstalling GatherMate2.
2. No resource map overlays, route optimizer or automatic crafting-queue-to-resource navigation yet. These are follow-up phases.
3. A freshly published snapshot contains zero nodes; community submissions must be reviewed and merged, and `CommunityData/manifest.json` version incremented, before other users receive them.
4. The Windows companion is Windows PowerShell 5.1/WinForms code. It requires testing on an actual Windows machine; a Linux Lua regression suite cannot verify Windows controls.
5. For updates, always close WoW before the companion installs generated Lua. Restart the game to load the new data.

## Initial field test

1. Back up your installed FCM folder and SavedVariables. Install FCM v0.9.1 while WoW is fully closed.
2. Keep GatherMate2 installed. Open `/fcm gather`, click **Import GatherMate2** and note the count.
3. Gather one named herb as Spotty Dotty and one vein on your miner. Check `/fcm gather status` after each; switch characters to verify account-wide persistence.
4. Log out completely. Run the companion, use **Sync Gathering (GitHub)**, then **Export Gathering Contribution** and inspect the local JSON.
5. Send the number of imported/personal nodes and any errors or screenshots. Do not remove GatherMate2 yet.

## Verification

- `texlua tests/parse.lua`
- `texlua tests/qa_gathering_v091.lua`
- `texlua tests/qa_crafting_professions_v090.lua`
- `texlua tests/qa_regressions_v092.lua`
- `texlua tests/qa_v092_identity.lua`
