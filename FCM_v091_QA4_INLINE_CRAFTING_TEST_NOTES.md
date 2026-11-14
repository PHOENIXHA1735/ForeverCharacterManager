# FCM v0.9.1 QA4e — Inline crafting and gathering minimap QA

Build `QA4e-20261114-Round-Pins-Treasure` (not a GitHub release).

## Install

1. Close WoW Forever and the Windows companion. Back up the installed
   `ForeverCharacterManager` folder and FCM SavedVariables under `WTF/Account`.
2. Merge the included `ForeverCharacterManager` folder into your installed
   AddOns folder. Never delete the companion's encrypted key, its generated
   reference files, account data or SavedVariables.
3. Restart WoW and check Diagnostics for the QA4 build marker above.

## Test 1 — quantity updates without popups

1. On Frosty Bit, open the bank and use Scan. Confirm Inventory shows two
   already-made Red Linen Bags in Frosty Bit's bank.
2. Choose Crafting > Tailoring, search `red`, select Red Linen Bag.
3. Set Goal: Reach Total and enter `3` in the persistent Qty box.
   The right panel should show owned 2, need 1, casts 1 and materials for
   **one** Red Linen Bag (4 Bolt of Linen Cloth, 1 Fine Thread, 1 Red Dye).
4. Without clicking Request, change Qty to `5`. The right panel must update
   to need 3 and casts 3; no request should be created or updated by typing.
5. Toggle Goal: Craft More (keeping Qty 5): now need 5, casts 5 and materials
   for five bags. Toggle back to Reach Total: need 3 again.
6. Enter blank, zero, or nonnumeric text. The preview must show an error and
   the Request button must not submit an invalid quantity.
7. Select a different recipe, then Red Linen Bag again. Its unsaved Qty should
   remain available during the same game session; other recipes' drafts must
   not silently inherit its value.

## Test 2 — explicit request/update

1. Restore Reach Total, Qty 3. Click Request Craft (no quantity popup should
   appear on this tab), then assign the eligible crafter when prompted.
2. Open Requests. Expect total 3, owned 2, additional needed 1, casts 1.
3. If this recipe already had a request, the Crafting action says Update Craft
   Request. Editing Qty or goal changes only the preview until that button is
   clicked; then Requests must reflect the updated quantity and mode.
4. Cancel a test request from Requests > Status / Qty when finished. Requests
   may still use a popup for editing; the request popup was not removed.

## Test 3 — what needs to be sent to another toon

1. On two same-faction/same-ruleset toons, scan bags and bank with reagent
   stock present. Choose a recipe that the other toon can craft.
2. Select the requesting toon in Crafting; choose the recipe and Qty.
3. The right panel should show each reagent's required quantity, accessible
   unreserved stock, missing amount and recorded locations. Stock stored on
   the requesting toon should be labelled `possible transfer` when it is
   explicitly unbound and otherwise eligible to reach the selected crafter.
4. Under POSSIBLE MATERIAL TRANSFERS, check the item, amount, source toon,
   bag/bank location and recipient crafter. If materials are banked, withdraw
   them in-game before mailing; FCM itself does not move anything.
5. Bound, unknown-binding or opposite-faction/ruleset stock must not be
   suggested for sending. Old scans are advisory only: verify item binding
   and actual mailing/trading rules in the game before sending.
6. If multiple eligible crafters exist, the preview assumes the first recorded
   compatible crafter. Confirm the assignment choice; other crafters may have
   different stock and transfer requirements.

## Test 4 — nearby saved gathering locations on the minimap

1. Log in with Spotty Dotty in Shadowglen, Teldrassil, where the Gathering tab
   already records Wilted Peacebloom on Map 1438 at **54.38, 46.35** and
   **55.19, 45.94**. You do not have to import GatherMate2 again.
2. Stand near the first saved location. Look **inside the minimap**, distinct
   from the large round FCM launcher button outside the minimap edge. You
   should see a small **flower icon for Wilted Peacebloom** and a different
   **leaf icon for Silverleaf**, rather than the same green FCM emblem on both.
   Other resource names use their known client item icons when available,
   otherwise a profession-specific fallback image.
3. Walk away and return. Markers should enter/leave view based on distance;
   hovering them shows the recorded herb name and saved location. Rotating
   the minimap should rotate the pins with the scene.
4. Type `/fcm gatherpins off` and verify only gathering pins disappear (the
   FCM launcher button and saved Gathering list stay). Type
   `/fcm gatherpins on` to restore nearby markers.
5. Switch to another zone or character to confirm only records for the
   current map appear, with account-wide personal discoveries still saved.
6. Marker means **previously reported**, not that a herb is currently spawned.
   If none appear at a location that is known to be in minimap range, send a
   screenshot and any FCM Diagnostics errors. This Forever build must expose
   `C_Map.GetWorldPosFromMapPos` plus either `Minimap:GetViewRadius()` (common
   on Ascension clients) or `C_Minimap.GetViewRadius()` to position pins safely;
   if unavailable, FCM hides pins instead of drawing inaccurate markers.
   To check, use `/run print(type(C_Map.GetWorldPosFromMapPos),type(Minimap.GetViewRadius),C_Minimap and type(C_Minimap.GetViewRadius))`
   and share what it prints.

## Test 5 — number of times a herb was gathered

1. On Spotty Dotty, hover one of the existing Peacebloom icons. The tooltip
   should now say `At least 1 personal gather (older history unknown)` if the
   node came from QA4/QA4b, which recorded discovery but not repeat totals.
2. When that herb respawns, successfully gather it again from the same spot.
   Hover its minimap icon and confirm the minimum count increases. Slight
   position changes of up to eight yards should stay with the saved point.
3. Check that harvesting Peacebloom does **not** increment Silverleaf's count
   or another more distant Peacebloom location's count.
4. Newly found locations in QA4c start at `1 personal gather`; after a second
   confirmed gather, they show `2 personal gathers` without the "at least"
   warning. Imported locations not personally gathered say `No personal
   gathers recorded`.
5. Open Gathering, select the saved node and confirm its detail panel agrees
   with the hover tooltip. Relog and make sure the number persists.

Only completed named gathering casts increment a count. Earlier repeat visits
cannot be reconstructed from saved locations, and different nearby plants with
the same name may require manual confirmation if they are within eight yards.

## Test 6 — do not cover the game's own gathering dot

1. In-game, open `/fcm` > **Gathering**, set **Pins: On** and choose
   **Hide within: 15 yd** from the dropdown; it is the recommended default.
   The equivalent commands are `/fcm gatherpins on` and `/fcm gatherpins near 15`.
2. Walk toward a previously recorded herb, ore vein or fishing school while
   any relevant native tracking is enabled. FCM's historical item icon should
   disappear once you are within 15 yards, exposing the native minimap dot.
3. Back away beyond 15 yards while still within minimap range. The FCM icon
   should reappear, retaining its name, count, and icon art.
4. In the Gathering tab change the dropdown to 25 yards, then 0 yards to
   verify the cutoff adjusts and that zero disables close-range hiding.
   Also toggle **Pins: Off** then **Pins: On** to check the separate control.
5. The round launcher button must remain visible throughout. FCM only hides
   its *own* location markers; it does not control Blizzard tracking dots.

## Test 7 — round item markers

1. Restart WoW with QA4e installed and open the minimap with visible saved
   Peacebloom and Silverleaf records (stand more than 15 yards away).
2. Both symbols should be **circular**, retain their distinct resource art,
   and still show their normal hover name and personal gather count.
3. The larger FCM launcher remains round and separate from the item markers.
   On a client without `MaskTexture` support, the original square item pins
   deliberately remain visible rather than causing a Lua error.

## Test 8 — treasure chests recorded by looting

1. Find an unopened world treasure chest, such as Battered Chest. Hover it
   long enough for the game tooltip to show its object name, then open it
   and allow the loot event to complete. Do not use an inventory lockbox.
2. Open **FCM > Gathering** and look for the chest under the Treasure records.
   Move more than 15 yards away, while within minimap view, to check its
   distinct saved marker and hover tooltip.
3. Hover a chest but do not open it; no new entry should appear.
4. Loot an ordinary defeated creature after hovering a chest: no extra
   treasure location should be recorded if the client identifies the loot
   source as a creature. Reopening the same chest within one interaction
   should not double-count `LOOT_READY` and `LOOT_OPENED`.
5. If chests do not record, note the exact chest name, whether loot opened,
   and whether the item minimap icons appear round; this client may omit
   the name or expose a different loot event or texture-mask API.

The map records the character's position while looting; this is a few yards
from the chest, not a client-provided coordinate for the chest object.

## Confirm that the installed files actually updated

The previously provided PowerShell check showed `QA4-20261114-Inline-Crafting-Gathering-Pins`
still installed, which is older than QA4b/QA4c and explains the identical
emblem markers. See `INSTALL-QA4e.txt` and check the installed `Core.lua` after
merging this release. The expected build marker is
`QA4e-20261114-Round-Pins-Treasure`.

## Offline regressions

`texlua tests/qa_craft_inline_preview_v091.lua`

`texlua tests/qa_craft_target_and_filter_v091.lua`

`texlua tests/qa_gathering_v091.lua`

`texlua tests/parse.lua`

Windows PowerShell and actual WoW Forever UI behavior must still be tested
on the player's PC. The QA3 companion quota repair remains included.
