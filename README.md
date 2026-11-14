# Forever Character Manager (FCM)

An account-wide character management addon for **World of Warcraft: Forever**, with an optional Windows Data Companion for public reference-data updates.

## Current source: v0.9.1 (local gathering preview)

The **v0.9.1 preview** adds local resource tracking, optional GatherMate2 import, and community snapshot downloads from GitHub. The v0.9.0 improvements and QA corrections remain intact. Live WoW Forever gathering events and the Windows companion UI still require player testing.

## Features

- Account-wide character, inventory, professions, recipes, gold and crafting tracking.
- First names and surnames recorded separately, stable character IDs, and non-destructive saved-data migrations.
- Faction, ruleset and region-aware evaluation of transfer eligibility; unknown item binding and rulesets stay unverified.
- Gear scoring, BoE protection, crafting/upgrades, talent guidance, reputation, leveling, auction data, dungeon information and search.
- Windows companion scripts for read-only public reference import, auction reference updates and local tooling.
- Gathering tab: account-wide personally observed nodes, one-time read-only GatherMate2 import, and versioned public resource snapshots.

## Installation

1. Back up the existing addon folder and your WoW SavedVariables before replacing code.
2. Exit World of Warcraft and the Windows companion.
3. Copy `ForeverCharacterManager/` into the game's `Interface\AddOns` directory, **merging** with the existing folder and replacing matching source files only.
4. Preserve the game's `WTF`/SavedVariables, `ExternalData.generated.lua`, `AHPrices.generated.lua`, `CommunityGathering.generated.lua` and companion-generated data.
5. Launch WoW, open `/fcm`, and check the version and diagnostics.

Windows companion entry point: `ForeverCharacterManager/FCM-Companion/OPEN-FCM-DATA-UPDATER.cmd`.

## Gathering v0.9.1 testing

1. With WoW closed, install the preview and keep GatherMate2 installed for the first import.
2. If using GatherMate2_Data, import its data inside GatherMate2 first.
3. Log into WoW and select **FCM > Gathering**, or type `/fcm gather`.
4. Select **Import GatherMate2** or type `/fcm gather import`, then `/fcm gather status`. The imported locations are copied into FCM's private SavedVariables; no dependency is retained.
5. Gather an actual named herb or ore vein, switch characters, and confirm the shared count changes. If Forever does not report the node name in its spell event, FCM deliberately does not invent a node; report that test result.
6. Fully close WoW, run the Windows companion and click **Sync Gathering (GitHub)**. Launch WoW again to merge the snapshot. Version 1 is intentionally empty until independently verified contributions are reviewed.
7. With WoW closed, **Export Gathering Contribution** writes `fcm-gathering-contribution.json` locally. Inspect it before submitting via a GitHub issue or pull request. Nothing is uploaded automatically.

The community snapshot contains no character IDs, inventory, accounts, passwords or GatherMate2 proprietary data. Never upload `WTF` files or complete FCM SavedVariables. The local private data and imported nodes survive removal of GatherMate2; **do not remove GatherMate2 until the in-game tests confirm import and independent recording**.

The next phases (precise map markers, optimized routes, and automatically connecting crafting queues to gathering spots) are not enabled in this preview. No server or NAS hosting is required.

## ForeverDB API key (optional)

FCM **does not ship with anybody's API key**. For authenticated ForeverDB imports, each user must request and create their own key at [ForeverDB's developer portal](https://foreverdb.net/developers): sign in with Battle.net, ask for API access for a local Windows application/plugin, and after approval create a key. Enter it **only** in the FCM Windows companion's **ForeverDB API key** field, optionally select **Remember encrypted for this Windows user**, then select **Scan and Update**. FCM itself works without a key. See the [step-by-step key setup instructions](docs/FOREVERDB_API_KEY_SETUP.md) and the [v0.9.0 release notes](FCM_v090_RELEASE_NOTES.md).


## Files and verification

- `ForeverCharacterManager/*.lua`, `*.toc`: addon source and manifests.
- `ForeverCharacterManager/FCM-Companion/`: Windows companion scripts, instructions and local tooling.
- `ForeverCharacterManager/Media/`: emblem and preview.
- `tests/`: portable offline Lua regressions (`texlua` from repository root).
- `SOURCE_MANIFEST_SHA256.txt`: release-source file hashes.
- `FCM_v091_RELEASE_NOTES.md`: gathering preview and manual test notes; older release documentation retained.

## Important limitations

Gear scores are weighted estimates, **not** simulated or measured DPS. Some procs, caps and set bonuses may not be modeled. In-game transfer permissions still must be confirmed before mailing valuable items. Recognizing rulesets depends on the game's available identity API and can remain unverified. Screenshot validation covered the faction correction and zero API errors after rescanning; not every WoW interaction was tested.

The public repository excludes personal character SavedVariables, local reference snapshots, passwords, tokens and credentials. Existing source is public, but no open-source license has been selected; do not assume redistribution rights beyond those expressly granted.
