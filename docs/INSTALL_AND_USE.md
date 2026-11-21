# Installing and using Forever Character Manager

Updated 2026-11-16. This guide covers **v0.9.3**, including optional companion features that require separate setup. Automated tests passed; some individual in-game paths, client APIs and background schedules still need validation on each installation.

## 1. Download and install the addon

1. Exit World of Warcraft fully. Close the Windows FCM companion if it is open.
2. Back up the existing `Interface\\AddOns\\ForeverCharacterManager` folder and the game's `WTF` SavedVariables. Do not delete or replace the `WTF` directory.
3. Download the intended v0.9.3 package from [GitHub Releases](https://github.com/PHOENIXHA1735/ForeverCharacterManager/releases), or the latest source from the [FCM repository](https://github.com/PHOENIXHA1735/ForeverCharacterManager). The GitHub **Source code (zip)** contains the outer repository folder; unzip it first.
4. Copy the **inner** `ForeverCharacterManager` directory (the one containing `ForeverCharacterManager.toc`) into:
   `C:\\Program Files (x86)\\World of Warcraft\\_forever_\\Interface\\AddOns\\`
5. Merge with the existing folder, replacing matching addon **program files**, but retain the existing private `AHHistory` folder and companion configuration.
6. Do **not** erase local `WTF` records, `FCM_DB`, `FCM_GatherExport`, API credentials, or local generated data. Before accepting any overwrite of `ExternalData.generated.lua`, `AHPrices.generated.lua` or `AHHistory.generated.lua`, keep a backup.
7. Log into WoW. Type `/fcm`, then open **Diagnostics** to verify the addon loads without API errors.

There should be a single addon folder, not `ForeverCharacterManager/ForeverCharacterManager/ForeverCharacterManager`. The game's displayed version is `0.9.3`; when diagnosing a problem, compare the actual source commit or release tag as well as the version number.

### First scan and cross-character information

- Log in to **every** character whose data you want. Open that character's bags, each profession panel, and bank; bank and profession inventories only update when their respective in-game interfaces are accessible.
- Log out normally so WoW writes SavedVariables. Then visit other characters.
- FCM separates Alliance and Horde and checks region/ruleset when determining whether stock can be **transferred**. Both factions may appear in account-wide views; appearing in a list is not permission to mail items.
- FCM retains older snapshots if an interface could not be scanned. **Old or unverified** is not the same as **zero items**. Check the per-character ages in **Characters** or **Diagnostics**.
- Saved crafting requests are an **unassigned board**; the eligible crafter is chosen by the player when fulfilling the request. No game mail, purchase, profession cast, or trade is automated.

## 2. Where to find things in FCM

Type `/fcm`, use the round minimap emblem, or choose a tab on the left.

| Tab | What it is for |
| --- | --- |
| Overview | Account/character summary and pending crafting requests |
| Upgrade Plan | Gear opportunities grouped by character; verify source and feasibility |
| Upgrades | Suggested gear, dungeon, crafting and milestone opportunities |
| Characters | Saved level, gold, professions and **scan freshness** |
| Gear | Class/spec/activity priorities and gear-source limitations |
| Crafting | Learned recipe search, profession filter, quantity and material preview |
| Planner | Recipe steps, estimated shortages, possible transfers and blockers |
| Requests | Unassigned craft requests; record crafted quantities and delivery |
| Shopping | Aggregated missing crafting materials from recorded requests |
| Professions | Character skills, recipes and training opportunities |
| Enchanting | Recorded enchanting recipes and equipment/enchant guidance |
| Tailoring | Tailoring progress and recipes |
| Gathering | Personally saved herbs, ore, named fishing schools and treasure |
| Catalog | Imported reference item/recipe records; may be incomplete |
| Item Explorer | Broad item search and human-readable item relationships |
| Dungeons | Imported dungeon details and **unverified** source/loot associations |
| Auction | Available current market quotes and source freshness |
| Gold | AH history summaries and conservative buy/hold/sell/craft/farm guidance |
| Reputation | Saved reputations and goals |
| Talents | Recorded build, priorities and unverified/uncaptured ranks |
| Leveling | Character progression guidance |
| Inventory | Last-scanned bags, bank and item counts |
| Legacy | Manual tracking for Adventure, Resourcefulness and Professions trees |
| QA Tests | In-game verification checklist; open steps are not passed tests |
| Settings | View preferences and controls |
| Diagnostics | API errors, snapshot ages and reference-data health |
| Help | Explanations for each feature and its limits |

The **Gear, Upgrades and Upgrade Plan** tabs use sourced Icy Veins WoW Forever **stat-priority guidance**, not a universal stat-weight table. Deprecated Zygor numerical weights remain inactive. If a genuinely validated matching model is unavailable, the addon can show priorities and known stats **without an invented numeric upgrade score or percentage**. Explicit player-imported Pawn/manual coefficients are labeled *provisional*.

### Crafting example

1. On **Crafting**, choose the recipient character and a scanned compatible profession/recipe.
2. Choose **Reach Total** to target a total number of finished items owned by that recipient; choose **Craft Additional** to make that many new items regardless of existing stock.
3. Change **Qty**. The preview changes only the displayed calculation until you explicitly save/update the request.
4. Review recorded bags, bank, reservations, recipe casts, learned crafters, required skill, unknown binding and transfers.
5. Save the request. **Requests** and **Planner** display the work; when a real crafter has finished an item, record progress. A crafted item is not assumed to have been delivered.
6. Reopen the recipient's bags and bank to refresh the known finished-item count.

A learned recipe does not prove that the character currently meets its **profession skill requirement**. The addon blocks candidates known to be below the required skill and labels missing scans as unverified. Do not mail material based solely on an old snapshot.

### Gathering

- `/fcm gather` opens Gathering; `/fcm gather status` reports saved counts.
- `/fcm gather import` imports from an optional installed GatherMate2 **once, read-only**. Saved FCM locations remain after GatherMate2 is removed.
- `/fcm gatherpins on|off` toggles minimap history pins; `/fcm gatherpins world on|off` toggles world-map pins.
- `/fcm gatherpins near 15`, `/fcm gatherpins rim 45` and `/fcm gatherpins size 16` control proximity, rim mode and marker size (examples).
- `/fcm gather fishstatus` displays the latest named fishing-pool tooltip/cast/loot evidence.
- For fishing pools, the game must expose a **named school/pool** hover and an actual Fishing cast followed by loot. A fishing cast alone or open-water catch is not enough. FCM stores the player's standing position, **not** independently measured bobber/pool intersection.
- Personal observations can be exported for review by the companion. Nothing is automatically published to the community.

## 3. Optional Windows data companion

Open the installed `FCM-Companion\\OPEN-FCM-DATA-UPDATER.cmd` while WoW is closed to run public reference updates. A personally approved ForeverDB API key may be needed; keep it private. A reference update is optional, and cached data can be absent/expired.

The companion writes data files that WoW reads at the **next login or reload**. An in-game addon cannot freely read an arbitrary Windows folder, run Python, scrape websites or poll a local SQLite database while WoW is running.

### AHledger: public setup versus personal history

**Other players:** They download FCM's **program code only** from GitHub, install their own compatible AHledger tooling, and process their **own** locally available scans/authorized reference tables. Their Gold tab can show the data that their installation actually has. **No shared 30-day auction database comes with the addon**, and a full 30 days of observations is not guaranteed. Do not archive or redistribute AHledger provider tables past allowed cache limits without appropriate permission/licensing.

**Personal long history:** The optional private processor can examine an observation window up to **365 days** using eligible personal scans (and additional third-party tables **only if explicitly authorized for that retention**). The Gold tab can show the most recent quote separately from 7/30/90/180/365-day observed averages, coverage, and missing days. Older data is not copied to GitHub or other users. See [private AH history and math](AH_HISTORY.md).

**Private setup steps (Windows):**

1. Exit WoW and protect `WTF`. Run the repository's `SETUP-FCM-AH-HISTORY.cmd` once to create folders without deleting existing files.
2. Locate `FCM-Companion\\FCM-AHHistory.ps1` inside the installed addon.
3. From PowerShell in that folder, run `powershell.exe -NoProfile -File .\\FCM-AHHistory.ps1 -Mode Sync` for a **manual** safe archive/analysis, or `-Mode Status` to check scheduled status. Only **personal AHledger.lua scans** are archived by default; provider tables require separately verified permission and the explicit `-IncludeProviderTables` switch.
4. To explicitly schedule future checks every 30 minutes while signed in, run the provided `ENABLE-FCM-HISTORY.cmd`. The task is configured to use `FCM-AHHistory-Hidden.vbs` through `wscript.exe` to avoid a flashing PowerShell window; a successful scheduled run should return `0`. This is **optional**, not enabled by installing FCM. Updating the addon files alone will **not** change an existing scheduled-task action. Before intentionally re-enabling an existing task, export its original XML configuration; re-enabling can reset its trigger/action.
5. To stop future runs without deleting the archive, use `DISABLE-FCM-HISTORY.cmd`. Examine `AHHistory\\Index\\status.json` and `AHHistory\\Logs` for results.
6. Python 3.10+ and Windows `tzdata` may be required for the history processor. Test on the actual Windows PC. A scheduler reporting errors is **not** an active history pipeline.
7. Restart WoW to load the generated summary. **Do not delete or publish** the `AHHistory`, `WTF` or private companion-configuration folders.

Price observations are **listing prices** unless confirmed personal-sale mail records are separately identified. Day/hour patterns are descriptive, not guaranteed sale windows. Advisory entries must display uncertainty and require real fees/market/recipe data; FCM never buys, sells or mails items.

### Overnight ForeverDB catalog updater

This is separate from AH processing. See [overnight catalog setup](../ForeverCharacterManager/FCM-Companion/OVERNIGHT_CATALOG_SETUP.txt). It needs each user's approved ForeverDB key, honors a shared request budget and can be enabled/disabled explicitly. It is **not automatically active** when the addon is installed.

## 4. Safe updates and troubleshooting

- **Blank character profession/bank:** Log into the character and open the relevant profession or bank window; check **Diagnostics** freshness.
- **Item shows zero when you expected bank stock:** Verify both bag and bank scan timestamps; check the output item ID and reservations; unknown bank contents must not be treated as authoritative zero.
- **Recipe visible but cannot craft:** Check learned status, required profession skill, faction/ruleset/region and binding. A *possible transfer* is only advice.
- **No numerical gear upgrade score:** Correct by design unless a sourced, build/context-matched numerical model exists. An ordinal guide is not a numeric stat weight.
- **No fish marker:** Hover a specifically named school, cast Fishing, actually loot; use `/fcm gather fishstatus` and verify zone/map.
- **No AH price/history:** Check your local AHledger refresh, authorized data retention, history status/coverage, market faction/ruleset and generated file timestamp. Reopen the client after updates.
- **Window position off screen:** `/fcm ui reset`. Minimap icon position: `/fcm minimap reset`.
- **Unexpected API errors:** Open **Diagnostics**, preserve the error text and current source commit ID. Report the steps, character (no account credentials), game build and the exact tab.
- **Testing status:** Automated tests run on synthetic fixture data in GitHub Actions. They do **not** prove in-game rendering, Windows Task Scheduler activation, live AH connectivity, client-specific tooltip events or every class/spec is correct.

## 5. Private-data and publication rules

The public repository contains addon source, documentation, synthetic test data and approved public reference structures only. It must **never** contain actual `WTF` files, private scan histories, SQLite databases, source paths with account identifiers, credentials, provider raw tables, or community contributions without review. Do not assume source availability means unrestricted licensing; third-party data and addon code are separately licensed.

For the current limitations and test results, see [the tests guide](../tests/README.md), [gear evidence register](GEAR_SOURCES_2026-11-16.md) and [AH-history model](AH_HISTORY.md). Previous QA notes are historical; later corrections take precedence.
