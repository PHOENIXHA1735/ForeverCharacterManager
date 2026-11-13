# Forever Character Manager (FCM)

An account-wide character management addon for **World of Warcraft: Forever**, with an optional Windows Data Companion for public reference-data updates.

## Current source: v0.9.0 (consolidated)

The **v0.9.0** release combines the v0.9.0 development work and subsequent QA1 / QA2 corrections in one source revision. Older v0.8.x source versions, tags, and releases remain in Git history.

## Features

- Account-wide character, inventory, professions, recipes, gold and crafting tracking.
- First names and surnames recorded separately, stable character IDs, and non-destructive saved-data migrations.
- Faction, ruleset and region-aware evaluation of transfer eligibility; unknown item binding and rulesets stay unverified.
- Gear scoring, BoE protection, crafting/upgrades, talent guidance, reputation, leveling, auction data, dungeon information and search.
- Windows companion scripts for read-only public reference import, auction reference updates and local tooling.

## Installation

1. Back up the existing addon folder and your WoW SavedVariables before replacing code.
2. Exit World of Warcraft and the Windows companion.
3. Copy `ForeverCharacterManager/` into the game's `Interface\AddOns` directory, **merging** with the existing folder and replacing matching source files only.
4. Preserve the game's `WTF`/SavedVariables, `ExternalData.generated.lua`, `AHPrices.generated.lua` and companion-generated data.
5. Launch WoW, open `/fcm`, and check the version and diagnostics.

Windows companion entry point: `ForeverCharacterManager/FCM-Companion/OPEN-FCM-DATA-UPDATER.cmd`.

## ForeverDB API key (optional)

FCM **does not ship with anybody's API key**. For authenticated ForeverDB imports, each user must request and create their own key at [ForeverDB's developer portal](https://foreverdb.net/developers): sign in with Battle.net, ask for API access for a local Windows application/plugin, and after approval create a key. Enter it **only** in the FCM Windows companion's **ForeverDB API key** field, optionally select **Remember encrypted for this Windows user**, then select **Scan and Update**. FCM itself works without a key. See the [step-by-step key setup instructions](docs/FOREVERDB_API_KEY_SETUP.md) and the [v0.9.0 release notes](FCM_v090_RELEASE_NOTES.md).


## Files and verification

- `ForeverCharacterManager/*.lua`, `*.toc`: addon source and manifests.
- `ForeverCharacterManager/FCM-Companion/`: Windows companion scripts, instructions and local tooling.
- `ForeverCharacterManager/Media/`: emblem and preview.
- `tests/`: portable offline Lua regressions (`texlua` from repository root).
- `SOURCE_MANIFEST_SHA256.txt`: release-source file hashes.
- `FCM_v090_RELEASE_NOTES.md`, `INSTALL_v0.9.0.txt`, `TEST_REPORT_v0.9.0.txt`: release documentation.

## Important limitations

Gear scores are weighted estimates, **not** simulated or measured DPS. Some procs, caps and set bonuses may not be modeled. In-game transfer permissions still must be confirmed before mailing valuable items. Recognizing rulesets depends on the game's available identity API and can remain unverified. Screenshot validation covered the faction correction and zero API errors after rescanning; not every WoW interaction was tested.

The public repository excludes personal character SavedVariables, local reference snapshots, passwords, tokens and credentials. Existing source is public, but no open-source license has been selected; do not assume redistribution rights beyond those expressly granted.
