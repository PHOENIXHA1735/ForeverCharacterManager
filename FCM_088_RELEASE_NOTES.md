# Forever Character Manager v0.8.8 — Smart Gear Comparison

## What's new

**At-a-glance comparisons** on item-backed detail panels (Gear, Upgrades, Global Search, Item Explorer, Auction, Inventory, Crafting, profession output items, Shopping, etc.) and the **selected Dungeon Explorer loot card**:

- Green **▲** for a gained or increased stat; red **▼** for a reduced or lost stat.
- Shows the **absolute stat difference** and the **percentage change** relative to equipped gear. A newly gained stat is marked `NEW` rather than displaying a misleading percentage; a completely lost stat shows `-100%`.
- Adds overall **weighted gear-score change**, both in points and percent when a nonzero valid baseline exists. The score is **not real DPS**.
- Gives a short explanation of the most impactful gain and loss, using the selected character's class, talent specialization, **Leveling/PvP/Endgame PvE** activity and **DPS/Balanced/Survivability** style.
- Both ring/trinket slots are evaluated; the comparison targets the more favorable valid replacement slot rather than always using the first slot. Replacing a main-hand/off-hand pair with a two-handed item accounts for the lost offhand when data is available.
- If equipped or candidate stats are not loaded, shows a clear **comparison unavailable** note instead of treating unknown stats as zero. Only the WoW client-provided numeric stats are used for precise arithmetic. Imported item names, quest effects, and item descriptions are not silently turned into numeric stats.
- Non-equipment entries such as cloth or recipes without a known equipment output do not show misleading gear comparisons.

## Optional custom stat weights

Custom baseline stat priorities can be set **per character and per activity** with the following in-game commands while logged into that character:

- `/fcm gearweight spell 5` — give Spell Power a baseline weight of 5 for the currently selected activity.
- `/fcm gearweight int 1.5` — give Intellect a baseline weight of 1.5.
- `/fcm gearweight list` — see current overrides.
- `/fcm gearweight reset` — restore defaults for the current activity.

Other supported keys include `str`, `agi`, `stam`, `spi`, `ap`, `crit`, `hit`, `haste`, `dps`, `mp5`, `armor`, `def`, and `resist`. Weights are nonnegative numbers from 0 to 100. Activity and specialization factors continue to apply, so the shown weighted impacts explain why one stat can outweigh another. These commands change **FCM's scoring**, not the game's gear or talents. This release does not provide a full visual editor for custom weights.

## Important limitations

- Weighted score percentages are **not DPS, healing, PvP success, or encounter performance percentages**.
- Trinket effects, procs, on-use effects, set bonuses, hit caps, secondary-stat caps, and all special equipment restrictions are **not fully modeled**; recommendations remain estimates.
- Comparison availability depends on the WoW client exposing actual stats and saved equipment having been scanned for the selected character. A missing stat table means **unknown**, not zero.
- The arrow characters depend on the game's installed UI font; verify legibility in game.
- The v0.8.8 ZIP has been published to GitHub. Offline regression testing passed; the live WoW client and Windows GUI companion were not run here.

## Installation

1. Completely close WoW Forever and the Windows FCM Data Companion.
2. Back up your existing `Interface\AddOns\ForeverCharacterManager` folder and your account's `WTF` SavedVariables.
3. Extract the included `ForeverCharacterManager` folder into WoW Forever's `Interface\AddOns`, merging/replacing addon files.
4. **Preserve** your existing `ExternalData.generated.lua` and all SavedVariables. Those files are intentionally **not** included in this release.
5. Restart WoW and verify `/fcm` displays `v0.8.8`.
6. Select Frosty; open Gear or Global Search and choose an equippable item whose stats are cached. Check arrows, percentages, score and explanation. Also test a ring and a Dungeon Explorer loot item.
