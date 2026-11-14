# Forever Character Manager (FCM)

An account-wide character management addon for **World of Warcraft: Forever**, with an optional Windows Data Companion for public reference-data updates.

## Current source: v0.9.1 QA4l (combined test candidate)

**QA4l aligns world-map gathering icons and adds map-header filters:** Live
testing confirmed the QA4k markers finally rendered, but spots recorded in
**Shadowglen** appeared northwest around Oracle Glade. FCM now converts the
scrolling canvas's effective scale into the overlaid pin host's scale, so
locations stay aligned at the correct map coordinates. It recalculates if
the canvas scale changes when zooming. While the world map is open, use the
**FCM Pins: On/Off** button near the top right to hide/show every gathering
marker, or the adjacent **Herbs**, **Ore**, **Fish** and **Chests** buttons
to turn those resource types on or off individually. These map settings do
not affect minimap markers or saved gathering observations. Brandon
confirmed in-game that QA4l places Shadowglen icons correctly and that the
on-map master and category visibility controls work.

**QA4k addresses invisible world-map markers:** Spotty Dotty's live
Teldrassil test found **45 matching saved gathering points on map 1438**,
but no visible icons. The map ID and records were correct. FCM now parents
the markers to the visible world-map frame, draws them over the map's detail
layers, and still anchors positions to the scrolling map canvas for panning
and zoom. The last map-open diagnostic persists when the map is closed to
open FCM and reports icon render count and first-pin visibility where the
client supports that check. Live confirmation remains necessary.

**QA4j shows bag capacity:** In FCM's Item Explorer or Global Search, select a bag
to see its slot count in the item preview and details panel. Hover an item
row to open the game's original tooltip beside the list. FCM uses an explicit
reference count or scans the loaded game's item tooltip; if neither supplies
a number, it says the capacity is unavailable instead of guessing, especially
for new Forever bags. The saved gathering database is unchanged.

**QA4j world-map follow-up:** Teldrassil's two known map IDs, 41 and 1438,
are now reconciled when displaying saved nodes. Open the map and then FCM >
Diagnostics to see the selected map ID, how many nodes matched, the available
saved-zone IDs and canvas dimensions. If the herbs still do not appear, send
that diagnostic text; the UI may be using a different map surface in Forever.
These changes have offline tests but still need live-client verification.

**QA4i adds saved resource icons to the full world map:** Open a **zone** map (such as Teldrassil) and see FCM's recorded herbs, ore, fishing locations and treasure at their original map coordinates, not just the minimap. Hover for the resource and personal gather count. **FCM > Gathering > World Map: On/Off** or `/fcm gatherpins world on|off` controls this overlay independently from the minimap pin toggle. The world-map display ignores minimap view distance and near-hide distance, so saved locations remain visible across the selected zone; it is not live-spawn tracking. The regular gathering Size control scales map icons too. Up to 500 pins per selected zone are displayed, prioritizing personally confirmed observations. This preview still needs in-game validation of the Forever world-map canvas.

**QA4h aligns distant gathering icons with the minimap's book markers:** Historical herb, ore, fishing and treasure icons on the directional rim are **centered on the circular border**, straddling it like the game's small book symbols, instead of floating outside it. With **FCM > Gathering > Size: 16 px** (default), rim icons display at about **12 px**, while closer in-map icons stay **16 px**. The size selector (10, 12, 14, 16, 18, 20, 24, 28 px) and `/fcm gatherpins size <8-32>` scale both; the launcher emblem does not change. Hide-within and Rim-beyond thresholds remain independently adjustable. Live WoW Forever testing is still pending.

The **v0.9.1 QA4f preview** includes all QA3 features (local gathering, optional GatherMate2 import, Legacy advisor, Frost Mage weights, profession/recipe filtering, Reach Total/Craft Additional, and the Windows quota-ledger repair). Crafting now has a permanent quantity box with a live right-side estimate of owned items, casts, reagents, stock by character and eligible material transfers. Gathering draws saved account-wide nodes on the minimap using distinct resource art and circular masks where the WoW client supports them. **Distant resource markers now occupy a grouped directional compass on the outer minimap ring instead of covering the map itself.** They move onto the map when within 45 yards (adjustable), then disappear within the independently adjustable 15-yard hide distance so WoW's native tracking dots are visible. Change this using **FCM > Gathering > Rim beyond** (0, 25, 35, 45, 55, 65, 85 or 100 yards), **Hide within** (0, 5, 10, 15, 20, 25, 35 or 50 yards) and **Pins: On/Off**. Slash alternatives: `/fcm gatherpins rim <0-100>`, `/fcm gatherpins near <0-50>`, `/fcm gatherpins on|off`. Hover a saved node to see its personal gather count. Named treasure chest interactions can also be recorded after an actual loot event, subject to the game reporting the chest name. Windows companion and WoW Forever in-game behavior still require player testing. This candidate is not a published GitHub release.

## Features

- Account-wide character, inventory, professions, recipes, gold and crafting tracking.
- First names and surnames recorded separately, stable character IDs, and non-destructive saved-data migrations.
- Faction, ruleset and region-aware evaluation of transfer eligibility; unknown item binding and rulesets stay unverified.
- Gear scoring, BoE protection, crafting/upgrades, talent guidance, reputation, leveling, auction data, dungeon information and search.
- Windows companion scripts for read-only public reference import, auction reference updates and local tooling.
- Gathering tab: account-wide personally observed herbs, ore and eligible named treasure chests, one-time read-only GatherMate2 import, minimap/zone world-map overlays, and versioned public resource snapshots.
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
- `INSTALL-QA4j.txt`: latest installation, bag-capacity and world-map diagnostic checks.
- `INSTALL-QA4k.txt`: previous map-overlay layer fix and live-test instructions.
- `INSTALL-QA4l.txt`: current map-position correction and world-map filter testing.

## Important limitations

Gear scores are weighted estimates, **not** simulated or measured DPS. Some procs, caps and set bonuses may not be modeled. In-game transfer permissions still must be confirmed before mailing valuable items. Recognizing rulesets depends on the game's available identity API and can remain unverified. Screenshot validation covered the faction correction and zero API errors after rescanning; not every WoW interaction was tested.

The public repository excludes personal character SavedVariables, local reference snapshots, passwords, tokens and credentials. Existing source is public, but no open-source license has been selected; do not assume redistribution rights beyond those expressly granted.
