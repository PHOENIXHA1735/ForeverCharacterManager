# FCM v0.9.1 QA4j — Inline crafting, bag capacity and gathering map QA

Build `QA4j-20261114-Bag-Slots-Map-Diagnostics` (not a GitHub release).

## Test A — bag size and item hover

1. Open FCM > Item Explorer, search `Linen Bag`, and select the bag item.
2. Check that the preview and the text details show `Bag capacity: 6 slots`
   if the Forever client has cached the original item's slot count.
3. Hover the item row and verify the game's full item tooltip appears beside
   the FCM window. Move the cursor away and check that it closes.
4. Repeat with a bag of another capacity, then a custom Forever bag. Capacity
   must reflect a real reference/client tooltip, not be guessed by name.
5. Also check Global Search and a crafting recipe producing a bag. Non-bag
   equipment previews must still show normal stats and comparisons.

## Test B — herbs on the full world map

1. Select FCM > Gathering > World Map: On, then open M > Kalimdor > Teldrassil.
2. Previously saved herbs should appear whether they were indexed under
   Teldrassil 41 or 1438. The addon does not erase or re-import records.
3. With the world map still open, open FCM > Diagnostics. Copy the line that
   starts `Gathering world map:`; it should show the selected map ID, matching
   saved locations, saved-zone IDs and map surface size.
4. If you see a positive matching count but no icons, send that line and a
   screenshot. It likely indicates a live map-layer/canvas mismatch. If the
   count is zero, send the same diagnostic so zone IDs can be checked.

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

## Test 9 — uncluttered outer gathering compass

1. Log into Spotty Dotty in a location with several saved herb nodes. Open
   `/fcm` > Gathering and set **Pins: On**, **Hide within: 15 yd**, and
   **Rim beyond: 45 yd** (the new default).
2. Look at the minimap: saved nodes farther than 45 yards, but within the
   game-reported minimap view, should appear **centered on the circular
   edge**, in the direction of the saved spots. Nodes inside 45 yards should
   remain positioned on the map; nodes within 15 yards should disappear.
3. Walk toward a rim icon. It should move onto the minimap when you come
   within 45 yards, then disappear when you reach the near-hide distance.
   This must not change the separate FCM launcher button.
4. When multiple saved spots point in almost the same direction, the outer
   ring should show one resource icon with a number; hovering it should say
   how many additional discoveries are grouped there.
5. Change **Rim beyond** to 25 or 65, then select Off (0). Verify the
   threshold changes and that Off returns to ordinary in-map placement.
   The slash alternative `/fcm gatherpins rim 45` accepts any whole number
   between 0 and 100 yards.
6. Pan or rotate the minimap and change zoom to check bearings. If icons
   appear in the wrong direction, provide a screenshot and current zoom.

## Test 10 — gathering marker size control

1. Open `/fcm` > Gathering. Set **Pins: On**, **Rim beyond: 45 yd** and
   **Size: 16 px** (the original marker size).
2. Select 12 pixels. Both visible in-map herb symbols and grouped outer-rim
   resource symbols should shrink immediately, while retaining their
   individual pictures and hover details.
3. Select 24 pixels. Markers should grow without changing their saved
   locations, current grouping or close-range hiding behavior. Rim symbols
   remain centered on the circular border (about 18 px with Size: 24 px).
4. Try `/fcm gatherpins size 19` for an exact size not in the preset menu.
   The control should update to 19 px and markers should resize accordingly.
5. Relog a different character. The size should remain saved account-wide;
   the separate FCM launcher emblem must not change dimensions.

## Test 11 — book-style markers directly on the rim

1. On a character with previously recorded herb/ore nodes, set **Pins: On**,
   **Rim beyond: 45 yd**, **Hide within: 15 yd**, and **Size: 16 px**.
2. Compare distant gathering icons with the small book symbols on the game's
   minimap border. FCM icons should be **centered on the border**, not
   detached outside the circle. Their default diameter is about **12 px**;
   closer nodes positioned inside the map still use **16 px**.
3. Move toward a saved node. At the 45-yard transition it should shift to
   its saved position inside the map, with full 16-pixel size; within 15
   yards, it should disappear so native tracking is not covered.
4. Choose **Size: 24 px** and repeat. Rim icons should grow to about 18 px
   but **stay centered on the same circular rim**. The launcher and native
   book markers must remain unchanged.
5. Rotate and zoom the map while watching a rim icon. Report screenshots if
   the icon drifts off the border or its relative direction is inaccurate.

## Test 12 — saved gathering locations on the full world map

1. With a character logged in, open **FCM > Gathering**, set **World Map: On**
   and **Size: 16 px**. Keep the minimap **Pins: Off** temporarily to verify
   that the world-map overlay works independently.
2. Press **M** to open the world map and select **Kalimdor > Teldrassil**.
   Previously saved **Wilted Peacebloom**, **Silverleaf** and any qualifying
   treasures should appear as distinct item icons at their recorded zone
   coordinates, even if they are well outside the current minimap view.
3. Hover an icon. Check the exact resource name, map coordinates, and personal
   gathering count. These are historical locations, not proof of a live spawn.
4. Zoom or pan the map and compare each icon with roads and terrain. It must
   follow the same spot rather than stay fixed on the screen. Switch to a
   different zone map; Teldrassil icons should disappear and only nodes
   recorded for the newly selected zone should remain.
5. Turn **World Map: Off** (or `/fcm gatherpins world off`). The zone-map
   resource icons should disappear. Turn it on again to restore them. The
   minimap pin toggle and FCM launcher remain unchanged.
6. Change **Size** to 24 px. World-map markers should resize on the next
   refresh. Change **Hide within** to 50 yd and return to a gathered spot;
   the full map should still show it, while the minimap may hide the icon.
7. If no world-map pins display, check Diagnostics for errors and share a
   screenshot showing the currently selected zone and map UI. Client map
   internals can differ from the offline mock; do not delete or reimport data.

World-map rendering is capped at 500 visible markers per selected zone to
protect performance. All original locations remain in SavedVariables.

## Confirm that the installed files actually updated

The November 14 Diagnostics screenshots show **QA4h** currently installed.
QA4h predates the **QA4i** world-map overlay; its absence there is expected.
See `INSTALL-QA4j.txt` and check the installed `Core.lua` after merging the
new combined source. The expected build marker is
`QA4j-20261114-Bag-Slots-Map-Diagnostics`.

## Offline regressions

`texlua tests/qa_craft_inline_preview_v091.lua`

`texlua tests/qa_craft_target_and_filter_v091.lua`

`texlua tests/qa_gathering_v091.lua`

`texlua tests/qa_bag_capacity_v091.lua`

`texlua tests/parse.lua`

Windows PowerShell and actual WoW Forever UI behavior must still be tested
on the player's PC. The QA3 companion quota repair remains included.
