# Forever Character Manager (FCM)

Account-wide character, crafting, gathering, inventory, progression, and market-data guidance for **World of Warcraft: Forever**. An optional Windows companion handles local files and public reference updates when the game is closed.

**Current release:** v0.9.3, including the Gold quote freshness correction ([PR #5](https://github.com/PHOENIXHA1735/ForeverCharacterManager/pull/5)) and the in-game-verified Gold toolbar spacing fix ([PR #3](https://github.com/PHOENIXHA1735/ForeverCharacterManager/pull/3)) · [GitHub Releases](https://github.com/PHOENIXHA1735/ForeverCharacterManager/releases). Install the intended version and preserve your personal data.

## Start here

1. [Full installation and usage instructions](docs/INSTALL_AND_USE.md) — exact Windows folder, first login, all 27 tabs, crafting, gathering, troubleshooting and privacy.
2. [Personal AH history and Gold Advisor](docs/AH_HISTORY.md) — optional private 365-day observations, local processing and scheduler controls.
3. [Gear source audit](docs/GEAR_SOURCES_2026-11-16.md) — evidence-based Forever stat priorities and limitations.
4. [Offline tests and validation](tests/README.md) — reproducible Lua/Python checks; in-game QA remains separate.
5. [Previous QA and feature notes](FCM_v091_RELEASE_NOTES.md) — historical changes, superseded where later corrections apply.

### Current behavior worth knowing

- **No bundled Zygor numerical weights.** The addon uses current Icy Veins WoW Forever **ordinal stat priorities** and keeps unvalidated numeric comparisons unavailable. Imported manual/Pawn coefficients are separately identified as provisional and need matching context. An ordering such as Spell Power > Spirit cannot be converted into numeric gain or DPS without measured evidence.
- **Crafting quantities:** Reach Total counts the recipient's recorded finished items; Craft Additional requests new output. The recipe's output count, skill requirement, recorded bags/bank, reservations and binding matter. A request is stored locally for all characters and does **not** assign an automatic maker.
- **Gathering pins:** Local, personally confirmed herbs/ore, named fishing schools and chests can appear on the minimap and world map, with source/quantity caveats. A named fishing school needs hover evidence, a cast and actual loot before a standing-location marker is recorded; open-water catches do not manufacture pool locations.
- **Gold:** Public source code lets each player use **their own available AHledger data**. Nobody receives somebody else's 30-day tables or private 365-day history through GitHub. Provider retention and licensing must be respected. Quotes and listing trends do not prove completed sales.
- **Live state:** Character snapshots, bank and profession data can be stale; the addon cannot poll game state while WoW is closed or read arbitrary Windows folders without the optional companion.

## Features

- Account-wide character, inventory, professions, recipes, gold and crafting tracking.
- First names and surnames recorded separately, stable character IDs, and non-destructive saved-data migrations.
- Faction, ruleset and region-aware evaluation of transfer eligibility; unknown item binding and rulesets stay unverified.
- Evidence-labelled gear priority guidance, BoE protection, crafting/upgrades, talent guidance, reputation, leveling, auction data, dungeon information and search.
- Windows companion scripts for read-only public reference import, auction reference updates and local tooling.
- Gathering tab: account-wide personally observed herbs, ore and eligible named treasure chests, one-time read-only GatherMate2 import, minimap/zone world-map overlays, and versioned public resource snapshots.
- Tree-specific Legacy goals and manual point/rank tracking (not automatic spending); Icy Veins WoW Forever stat-priority references for every supported spec, with no active bundled numerical weights. New explicit user scales are provisional; deprecated Zygor scales stay inactive.
- Crafting requests accept finished-item quantities (including multi-output recipes), with an inline quantity preview and guarded Enter/Continue handling where an older popup is still used.
- The Crafting tab offers a saved profession dropdown and a separate search covering learned recipes, their output items and recipe IDs only.
- New craft requests default to **Reach Total**: only the recipient's last-scanned bags and bank count toward the target. **Craft Additional** always requests new items; older saved requests retain their original additional-item meaning. Reservations and shopping lists adjust to the needed amount.

## Installation

For full Windows and first-login steps, see [Install and use FCM](docs/INSTALL_AND_USE.md).

1. Back up the existing addon folder and your WoW SavedVariables before replacing code.
2. Exit World of Warcraft and the Windows companion.
3. Copy `ForeverCharacterManager/` into the game's `Interface\AddOns` directory, **merging** with the existing folder and replacing matching source files only.
4. Preserve the game's `WTF`/SavedVariables, `ExternalData.generated.lua`, `AHPrices.generated.lua`, `CommunityGathering.generated.lua` and companion-generated data.
5. Launch WoW, open `/fcm`, and check the version and diagnostics.

Windows companion entry point: `ForeverCharacterManager/FCM-Companion/OPEN-FCM-DATA-UPDATER.cmd`.

### Overnight catalog refresh (v0.9.1 optional Windows companion)

The optional [overnight catalog task](ForeverCharacterManager/FCM-Companion/OVERNIGHT_CATALOG_SETUP.txt) updates the *actual* ForeverDB item and recipe cache every 15 minutes from **10:00 PM through 11:45 AM Pacific** when WoW is closed. It is separate from the low-cost build-number checker and AHledger. The companion enforces four-second spacing across **manual, automated and build-check** ForeverDB calls, a shared **4,500-request UTC-day budget**, and a reserve of 500 when ForeverDB reports remaining requests. Local item cache and generated Lua files are preserved if a refresh is skipped or fails. New items appear after restarting WoW; a missing item such as Clam Meat may still be absent upstream or hidden by search filters.

On the Windows PC, save the approved key with **Remember encrypted**, then double-click `FCM-Companion/ENABLE-FCM-OVERNIGHT.cmd` from the **installed** FCM folder. This registers the Windows task for your logged-in user; the ZIP alone does not activate it. First-night Windows validation remains pending. Details, verification and uninstall instructions are in the linked setup file.

## Gathering v0.9.1 setup and verification

1. With WoW closed, install the preview and keep GatherMate2 installed for the first import.
2. If using GatherMate2_Data, import its data inside GatherMate2 first.
3. Log into WoW and select **FCM > Gathering**, or type `/fcm gather`.
4. Select **Import GatherMate2** or type `/fcm gather import`, then `/fcm gather status`. The imported locations are copied into FCM's private SavedVariables; no dependency is retained.
5. Gather an actual named herb or ore vein, switch characters, and confirm the shared count changes. If Forever does not report the node name in its spell event, FCM deliberately does not invent a node; report that test result.
6. Fully close WoW, run the Windows companion and click **Sync Gathering (GitHub)**. Launch WoW again to merge the snapshot. Version 1 is intentionally empty until independently verified contributions are reviewed.
7. With WoW closed, **Export Gathering Contribution** writes `fcm-gathering-contribution.json` locally. Inspect it before submitting via a GitHub issue or pull request. Nothing is uploaded automatically.

The community snapshot contains no character IDs, inventory, accounts, passwords or GatherMate2 proprietary data. Never upload `WTF` files or complete FCM SavedVariables. The local private data and imported nodes survive removal of GatherMate2; **do not remove GatherMate2 until the in-game tests confirm import and independent recording**.

Historical gathering markers are available on the minimap, subject to the WoW client exposing world-coordinate and minimap-radius APIs. Saved markers also appear on the selected zone's full world map via the client's map canvas or legacy map button; verify this display in-game. Optimized routes and automatically connecting crafting queues to gathering spots are not enabled in this preview. No server or NAS hosting is required.

## ForeverDB API key (optional)

FCM **does not ship with anybody's API key**. For authenticated ForeverDB imports, each user must request and create their own key at [ForeverDB's developer portal](https://foreverdb.net/developers): sign in with Battle.net, ask for API access for a local Windows application/plugin, and after approval create a key. Enter it **only** in the FCM Windows companion's **ForeverDB API key** field, optionally select **Remember encrypted for this Windows user**, then select **Scan and Update**. FCM itself works without a key. See the [step-by-step key setup instructions](docs/FOREVERDB_API_KEY_SETUP.md) and the [v0.9.0 release notes](FCM_v090_RELEASE_NOTES.md).


## Files and verification

- `ForeverCharacterManager/*.lua`, `*.toc`: addon source and manifests.
- `ForeverCharacterManager/FCM-Companion/`: Windows companion scripts, instructions and local tooling.
- `ForeverCharacterManager/Media/`: emblem and preview.
- `tests/`: portable offline Lua regressions (`texlua` from repository root).
- `SOURCE_MANIFEST_SHA256.txt`: release-source file hashes.
- `FCM_v091_RELEASE_NOTES.md`: gathering preview and manual test notes; older release documentation retained.
- `FCM_v091_QA1_COMBINED_TEST_NOTES.md`: the QA6e/Gathering merge and first combined in-game test checklist.
- `FCM_v091_QA2_CRAFTING_TEST_NOTES.md`: follow-up profession-search and Reach Total QA checklist.
- `FCM_v091_QA3_COMPANION_TEST_NOTES.md`: focused companion quota-ledger repair and Clam Meat search checks.
- `FCM_v091_QA4_INLINE_CRAFTING_TEST_NOTES.md`: inline quantity, candidate material-transfer, and nearby gathering-minimap live tests.
- `INSTALL-QA4d.txt`: exact in-place Windows installation steps and PowerShell build verification.
- `INSTALL-QA4e.txt`: current safe install and live test steps for circular markers and chest tracking.
- `INSTALL-QA4f.txt`: previous compass-rim test instructions.
- `INSTALL-QA4g.txt`: prior safe installation and marker-sizing test guide.
- `INSTALL-QA4h.txt`: previous book-style rim placement test guide.
- `INSTALL-QA4i.txt`: previous full world-map overlay test guide.
- `INSTALL-QA4j.txt`: historical installation, bag-capacity and world-map diagnostic checks.
- `INSTALL-QA4k.txt`: previous map-overlay layer fix and live-test instructions.
- `INSTALL-QA4l.txt`: historical map-position correction and world-map filter testing.

## Important limitations

There are **no active bundled numerical gear weights**. Guide priorities are ordinal; numerical estimates, if explicitly supplied by a player and context-matched, are **provisional**, not simulated or measured DPS. Unknown caps, procs, effects and class restrictions prevent definitive numeric comparison. In-game transfer permissions, binding and skill prerequisites still require verification before mailing valuable items. Recognizing rulesets depends on the game's available identity API. Automated checks do not replace in-game QA.

The public repository excludes personal character SavedVariables, local reference snapshots, passwords, tokens and credentials. Existing source is public, but no open-source license has been selected; do not assume redistribution rights beyond those expressly granted.
