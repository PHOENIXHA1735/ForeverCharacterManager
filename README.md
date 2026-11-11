# Forever Character Manager (FCM)

An account-wide character management addon for **World of Warcraft: Forever**, with an optional Windows Data Companion for public reference-data synchronization.

## Source version

This repository tracks the **v0.8.8 Smart Gear Comparison** source as its initial checked-in release. The matching downloadable ZIP and checksum are available in [GitHub Releases](https://github.com/PHOENIXHA1735/ForeverCharacterManager/releases/tag/v0.8.8).

## Features

- Character scans and account-wide inventory, professions, recipes, gold, and crafting requests
- Leveling / PvP / Endgame PvE gear priorities with DPS, Balanced, and Survivability styles
- Weighted stat comparisons, per-stat changes and visual gear recommendations (not simulated DPS)
- Dungeon Explorer with imported boss names and dungeon-associated loot references
- Global search, item catalog, auction-price snapshots, reputation, and talent reference views
- Windows Data Companion for ForeverDB reference synchronization and release updates

## Install

1. Download the [v0.8.8 release ZIP](https://github.com/PHOENIXHA1735/ForeverCharacterManager/releases/tag/v0.8.8).
2. Exit WoW Forever and the Windows companion; back up your FCM addon and character SavedVariables.
3. Extract `ForeverCharacterManager` into your game's `Interface\AddOns` directory.
4. Preserve local `ExternalData.generated.lua` and all `WTF/SavedVariables` files. The source repository intentionally does not include these.
5. Launch WoW and type `/fcm`.

Use `ForeverCharacterManager/FCM-Companion/OPEN-FCM-DATA-UPDATER.cmd` to launch the Windows companion. Run the updater locally to generate a new `ExternalData.generated.lua` rather than placing private or generated records in Git.

## Layout

- `ForeverCharacterManager/*.lua` — core addon and UI
- `ForeverCharacterManager/*.toc` — WoW addon manifests
- `ForeverCharacterManager/FCM-Companion/` — PowerShell companion and documentation
- `ForeverCharacterManager/Media/` — addon images
- `.github/workflows/verify-source.yml` — syntax and source-integrity check

## Development and limitations

The checked-in source corresponds to **v0.8.8**. Gameplay and companion changes should be committed to branches and verified in a running WoW client before a new release. Gear scores are **estimated weighted-stat comparisons**, not measured DPS; some proc effects, set bonuses, and hit caps are not modeled. Public external data may be incomplete and should be verified in game.

The repository deliberately excludes generated game data, private character saves, passwords, API tokens, and local configuration. No open-source license has been selected yet; do not assume redistribution rights from the source being publicly accessible.
