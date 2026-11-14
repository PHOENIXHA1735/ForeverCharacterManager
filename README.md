# Forever Character Manager (FCM)

An account-wide character management addon for **World of Warcraft: Forever**, with an optional Windows Data Companion for public reference-data updates.

## Current source: v0.9.1 QA4e (combined test candidate)

The **v0.9.1 QA4e preview** includes all QA3 features (local gathering, optional GatherMate2 import, Legacy advisor, Frost Mage weights, profession/recipe filtering, Reach Total/Craft Additional, and the Windows quota-ledger repair). Crafting now has a permanent quantity box, with a live right-side estimate of owned items, crafts, reagents, stock by character and possible eligible material transfers. The Crafting request button saves the draft explicitly; the Requests quantity editor retains its popup for editing existing requests. Gathering draws nearby saved nodes inside the minimap using FCM's account-wide records. Resource icons now use circular masks where WoW's client supports them, while Peacebloom, Silverleaf and other resources retain their distinct images. Named treasure chest interactions can be recorded when an actual loot event occurs; ordinary loot must not create false chest pins. Hover a saved node to see FCM's personal gather count at that location; older discoveries report minimum counts because prior builds did not track repeat gathers. Saved gathering markers automatically hide within **15 yards (recommended default)** so they do not obscure native minimap dots. Change this on **FCM > Gathering** with the **Hide within** dropdown (0, 5, 10, 15, 20, 25, 35 or 50 yards); the neighboring **Pins: On/Off** button toggles historical resource markers independently of the launcher. Slash alternatives are `/fcm gatherpins near <0-50>` and `/fcm gatherpins on|off`. Windows companion and WoW Forever in-game behavior still require player testing. This candidate is not a published GitHub release.

## Features

- Account-wide character, inventory, professions, recipes, gold and crafting tracking.
- First names and surnames recorded separately, stable character IDs, and non-destructive saved-data migrations.
- Faction, ruleset and region-aware evaluation of transfer eligibility; unknown item binding and rulesets stay unverified.
- Gear scoring, BoE protection, crafting/upgrades, talent guidance, reputation, leveling, auction data, dungeon information and search.
- Windows companion scripts for read-only public reference import, auction reference updates and local tooling.
- Gathering tab: account-wide personally observed herbs, ore and eligible named treasure chests, one-time read-only GatherMate2 import, and versioned public resource snapshots.
- Tree-specific Legacy goals and manual point/rank tracking (not automatic spending); numerically imported Zygor/Pawn weight profiles for character-specific gear comparisons.
- Crafting requests accept finished-item quantities (including multi-output recipes), with a client-safe Enter/Continue popup handler.
- The Crafting tab offers a saved profession dropdown and a separate search covering learned recipes, their output items and recipe IDs only.
- New craft requests default to **Reach Total**: only the recipient's last-scanned bags and bank count toward the target. **Craft Additional** always requests new items; older saved requests retain their original additional-item meaning. Reservations and shopping lists adjust to the needed amount.

## Installation

1. Back up the existing addon folder and your WoW SavedVariables before replacing code.
2. Exit World of Warcraft and the Windows companion.
3. Copy `ForeverCharacterManager/` into the game's `Interface\AddOns` directory, **merging** with the existing folder and replacing matching source files only.
4. Preserve the game's `WTF`/SavedVariables, `ExternalData.generated.lua`, `AHPrices.generated.lua`, `CommunityGathering.generated.lua` and companion-generated data.
5. Launch WoW, open `/fcm`, and check the version and diagnostics.

Windows companion entry point: `ForeverCharacterManager/FCM-Companion/OPEN-FCM-DATA-UPDATER.cmd`.

### Overnight catalog refresh (v0.9.1 Windows QA preview)

The optional [overnight catalog task](ForeverCharacterManager/FCM-Companion/OVERNIGHT_CATALOG_SETUP.txt) updates the *actual* ForeverDB item and recipe cache every 15 minutes from **10:00 PM through 11:45 AM Pacific** when WoW is closed. It is separate from the low-cost build-number checker and AHledger. The companion enforces four-second spacing across **manual, automated and build-check** ForeverDB calls, a shared **4,500-request UTC-day budget**, and a reserve of 500 when ForeverDB reports remaining requests. Local item cache and generated Lua files are preserved if a refresh is skipped or fails. New items appear after restarting WoW; a missing item such as Clam Meat may still be absent upstream or hidden by search filters.

On the Windows PC, save the approved key with **Remember encrypted**, then double-click `FCM-Companion/ENABLE-FCM-OVERNIGHT.cmd` from the **installed** FCM folder. This registers the Windows task for your logged-in user; the ZIP alone does not activate it. First-night Windows validation remains pending. Details, verification and uninstall instructions are in the linked setup file.

## Gathering v0.9.1 testing

1. With WoW closed, install the preview and keep GatherMate2 installed for the first import.
2. If using GatherMate2_Data, import its data inside GatherMate2 first.
3. Log into WoW and select **FCM > Gathering**, or type `/fcm gather`.
4. Select **Import GatherMate2** or type `/fcm gather import`, then `/fcm gather status`. The imported locations are copied into FCM's private SavedVariables; no dependency is retained.
5. Gather an actual named herb or ore vein, switch characters, and confirm the shared count changes. If Forever does not report the node name in its spell event, FCM deliberately does not invent a node; report that test result.
6. Fully close WoW, run the Windows companion and click **Sync Gathering (GitHub)**. Launch WoW again to merge the snapshot. Version 1 is intentionally empty until independently verified contributions are reviewed.
7. With WoW closed, **Export Gathering Contribution** writes `fcm-gathering-contribution.json` locally. Inspect it before submitting via a GitHub issue or pull request. Nothing is uploaded automatically.

The community snapshot contains no character IDs, inventory, accounts, passwords or GatherMate2 proprietary data. Never upload `WTF` files or complete FCM SavedVariables. The local private data and imported nodes survive removal of GatherMate2; **do not remove GatherMate2 until the in-game tests confirm import and independent recording**.

Nearby historical gathering markers are now available on the minimap, subject to the WoW client exposing world-coordinate and minimap-radius APIs. Full world-map overlays, optimized routes, and automatically connecting crafting queues to gathering spots are not enabled in this preview. No server or NAS hosting is required.

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

## Important limitations

Gear scores are weighted estimates, **not** simulated or measured DPS. Some procs, caps and set bonuses may not be modeled. In-game transfer permissions still must be confirmed before mailing valuable items. Recognizing rulesets depends on the game's available identity API and can remain unverified. Screenshot validation covered the faction correction and zero API errors after rescanning; not every WoW interaction was tested.

The public repository excludes personal character SavedVariables, local reference snapshots, passwords, tokens and credentials. Existing source is public, but no open-source license has been selected; do not assume redistribution rights beyond those expressly granted.
