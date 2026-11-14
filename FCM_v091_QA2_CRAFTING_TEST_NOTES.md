# FCM v0.9.1 QA2 — Crafting profession, search and inventory-aware targets

Build: `QA2-20261114-Crafting-Target-Search`

## Before testing

1. Exit WoW and the Windows companion.
2. Back up `Interface/AddOns/ForeverCharacterManager` and the FCM SavedVariables
   files under your `WTF/Account` folder. Merge the new addon source into the
   installed folder; **do not delete personal SavedVariables, generated data,
   or encrypted companion settings**.
3. Log in as Frosty Bit. Open the bank and your bag windows, use **Scan**, then
   confirm Inventory shows **two Red Linen Bags in Frosty Bit's bank**.
4. Open Diagnostics. Expected version `0.9.1` and QA2 build ID above.

## Test A — profession-only recipe browsing

1. Open Crafting. Choose **All Professions**, then **Tailoring** and confirm
   only learned Tailoring recipes remain. Repeat with **Alchemy**, **Cooking**,
   or another profession actually known by your characters.
2. In the dedicated **Recipe search**, enter `Red Linen Bag` and check the
   Tailoring result. Try a fragment (`linen`), a known recipe ID, and a recipe
   with a cached output-item name.
3. Try a reagent name without a matching recipe. It must **not** inject an
   ordinary Item Explorer item into the Crafting list. The global item search
   is intentionally hidden on Crafting and still available elsewhere.
4. Clear the recipe search. Switch tabs and return; confirm the saved
   profession selection remains usable. Restore All Professions.

## Test B — Reach Total with Frosty Bit's two banked bags

1. On Crafting select Frosty Bit as recipient and Red Linen Bag as recipe.
2. Set **Goal: Reach Total**. Click **Request Craft**. The quantity popup
   should show **Recorded owned: 2** and suggest a target of `3`.
3. Enter `3` and press **Enter**, then select the eligible crafter.
4. Open Requests: expected **target 3**, **recorded owned 2**, **additional
   needed 1**, and **one craft** (assuming one bag per cast). Materials should
   be counted for one bag, and Shopping must reserve at most those reagents.
5. Open the Planner request row: it should explain the target and plan one
   cast, not three. Check material shortages against your last-scanned stock.

## Test C — Craft Additional and changes to recorded inventory

1. Cancel/archive the test request (or edit its mode under **Status / Qty**).
2. Switch Crafting to **Goal: Craft More**, request `3` Red Linen Bags and
   confirm the planner now requests **three additional bags** and materials
   for three. The existing two bags remain in inventory, not subtracted.
3. If you actually have three bags recorded after a legitimate bank rescan,
   a Reach Total request for three should show **0 additional needed** and
   reserve **no materials**. Do not change inventory records manually.
4. For any request created on a previous FCM version, confirm its saved
   meaning remains **Craft Additional** until you explicitly change its mode.

## Important safety notes

- Frosty Bit's own scanned bags and bank count toward its target. Other
  characters' finished bags **do not** count as already delivered.
- Bag/bank records are last-seen snapshots, not continuously synchronized
  online. Verify the bank was scanned recently before trusting the shortage.
- Recipe output IDs must be known to match finished inventory. When missing,
  the Requests panel reports the owned count as unknown.
- Quantity mode changes planning only. FCM does not automatically craft,
  withdraw, mail, or complete existing requests.
- Report the FCM Diagnostics build ID, any error lines, and screenshots of
  the target/request/shopping details if they disagree.

## Offline checks

`texlua tests/qa_craft_target_and_filter_v091.lua`

`texlua tests/qa_craft_quantity_v090.lua`

`texlua tests/qa_craft_quantity_popup_v090.lua`

`texlua tests/parse.lua`

These tests simulate game data and do not verify actual client bank events.
