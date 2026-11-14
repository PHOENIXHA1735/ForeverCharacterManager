# FCM v0.9.1 — Local Gathering / GitHub Community Preview

## QA4 inline crafting and gathering minimap preview (November 14; not published)

- **QA4l world-map positioning and controls:** QA4k's layer change made all
  saved herb icons visible, but live Teldrassil testing placed them around
  Oracle Glade instead of their recorded Shadowglen locations. The map canvas
  and overlaid buttons have different effective scales; pin offsets now
  compensate for their ratio and refresh if zoom changes. The open world map
  also gets **FCM Pins: On/Off** and independent **Herbs**, **Ore**, **Fish**,
  **Chests** buttons near the upper right. Controls change SavedVariables
  visibility preferences only; they do not delete or move any nodes and leave
  the minimap toggle alone. In-game QA4l testing confirmed corrected
  Shadowglen placement and working map-header visibility controls.
- **QA4k world-map layering fix:** The QA4j live diagnostic detected map
  1438 and **45 matching saved points** while the Teldrassil map was open,
  but no icons were rendered visibly. The addon had been parenting its pin
  buttons to the scrolling map canvas, which can be obscured by Forever's
  detail layers. The icon buttons now live on the visible world-map frame
  with a high overlay stratum, while their anchors still follow the scrolling
  canvas. The last open map diagnostic is preserved when closing the map;
  it now reports pin count and first-pin visibility if available. In-game
  confirmation of the visual result is still required.
- **QA4j bag-slot details and hover:** When an item is a container, FCM Item
  Explorer / Global Search now shows `Bag capacity: N slots` in the preview
  and details. FCM uses explicit saved reference capacity or the local game's
  cached tooltip, including a hidden-tooltip fallback on older clients. It
  does not infer the size of custom Forever bags from their names. Item-list
  rows open the client's full tooltip on hover, beside the panel, without
  changing the previous dungeon loot right-click behavior.
- **QA4j Teldrassil world-map compatibility and diagnostics:** World-map
  overlays accept the two observed Teldrassil zone-ID conventions, 41 and
  1438, without altering saved coordinates or source data. FCM Diagnostics
  now reports map ID, matching saved-node count, sampled saved map IDs and
  surface dimensions when the world map is open. Offline validation covers
  both ID directions; actual WoW Forever rendering remains unverified.
- **QA4i full world-map gathering overlay:** The zone map now displays saved
  historical herb, mining, named fishing-pool and treasure locations at their
  normalized recorded map coordinates, even far from the active character.
  Hover icons to read the resource name, source status and personal gather
  count. The new **World Map: On/Off** control in FCM > Gathering operates
  independently of minimap Pins: On/Off, and `/fcm gatherpins world on|off`
  provides the same switch. Map icons follow the existing Size setting; the
  minimap-specific 45-yard rim and 15-yard near-hide settings do **not** hide
  world-map discoveries. Only locations on the selected zone map are drawn,
  with a defensive 500-pin display cap prioritizing personal confirmations.
  Client compatibility, zoom, map switching and hover need live verification.
- **QA4h book-style rim alignment:** Directional historical gathering pins
  now **straddle the circular minimap border**, like the native book symbols,
  instead of sitting detached beyond it. To match their smaller visual scale,
  rim symbols display at approximately 75% of the configured gathering Size:
  the default 16-pixel selection gives a roughly **12-pixel rim icon** and a
  full 16-pixel in-map icon. The size control continues to resize both.
  Settings for the 45-yard rim transition and 15-yard near-hide remain
  unchanged; this does not alter the separate FCM launcher emblem.
- **QA4g adjustable gathering-marker size:** FCM > Gathering now has a
  **Size: 16 px** menu for historical herb, ore, fishing and chest icons
  both inside the minimap and on its outer rim. Presets are 10, 12, 14,
  16 (default), 18, 20, 24 and 28 pixels. For precise whole-pixel control,
  `/fcm gatherpins size <8-32>` accepts any size in that range. Item art,
  optional round masks and rim grouping remain intact. The separate round
  launcher button is not resized; sizes persist across characters.
- **QA4f minimap rim compass:** Saved herb, mining, fishing and treasure pins
  farther than **45 yards** (default) now appear along the outer edge of the
  minimap, in their actual relative direction. Within that distance, pins
  move onto their precise saved map positions, and the independently
  adjustable **Hide within** setting still removes them when very close.
  The 16 compass sectors group distant nodes with similar bearings and
  display a count on the grouped icon and a tooltip explaining the grouping.
  The new **FCM > Gathering > Rim beyond: 45 yd** dropdown offers 0, 25, 35,
  45, 55, 65, 85 or 100 yards; 0 disables rim mode. Advanced users may choose
  any whole value 0–100 with `/fcm gatherpins rim <yards>`.
- **QA4e round minimap resource icons:** FCM's small saved herb, ore, fishing
  and treasure icons now use a circular alpha mask on clients exposing native
  `MaskTexture`; each resource keeps its distinct item artwork. On older
  clients without masks, the original working square icons remain. The
  separate round FCM launcher emblem is unchanged.
- **QA4e treasure chest recording:** Previously, treasure was an import-only
  category. FCM now observes named chest/coffer/cache interactions and actual
  `LOOT_READY`/`LOOT_OPENED` events, using a `GameObject` loot GUID when the
  client supplies one. A hover alone does not save a location, and corpse
  loot is rejected when distinguishable. The stored point is the player's
  position at looting time, so the exact chest position may differ by a few
  yards; reliable discovery requires the client to expose the chest name.
- **QA4d close-range markers:** Saved herb, mining, fishing and treasure
  markers automatically hide once the character is within **15 yards** of
  the saved location, leaving the game's native tracking dot unobscured.
  Set the cutoff on **FCM > Gathering > Hide within: 15 yd**, choosing 0, 5,
  10, 15 (recommended), 20, 25, 35 or 50 yards. The adjacent **Pins:
  On/Off** button independently controls all FCM historical node markers.
  `/fcm gatherpins near 0` disables the proximity hiding; use any whole
  number up to 50 yards to choose a different cutoff. The FCM launcher icon
  remains visible. The Diagnostics tab now displays the complete build ID
  directly, to help identify installs still running older QA4 files.
- **QA4c repeat-harvest counts:** Hovering a saved minimap node shows how many
  successful personal gathers FCM has recorded there across characters.
  Repeated harvests at the same spot (including small standing-position changes
  within eight yards) increment that count. Imported nodes start with no
  personal harvests; older personal discoveries show "At least 1" because
  earlier addon builds did not track repeated gathers. The Gathering tab's
  details show the same count. No historical totals are invented or uploaded.
- **QA4b icon refinement:** Gathering minimap nodes use resource-item icons
  where possible. Wilted Peacebloom and Silverleaf now have distinct flower
  and herb icons, even without a warm client item cache; other gathering
  nodes use a client icon or profession-specific fallback. The FCM launcher
  emblem remains unchanged.

- Crafting replaces its quantity popup with a compact `Qty` field beside the
  Reach Total / Craft More goal selector. Edits refresh the right-hand preview
  after a short debounce; typing never creates or alters a saved request.
- Preview shows finished output already owned by the selected recipient,
  additional items required, actual recipe casts/yield, and reagent quantities
  adjusted for that need. Reaching a target of zero more produces zero material
  requirements instead of an artificial one-craft estimate.
- Show recorded material locations and safe candidate sends to the selected
  eligible crafter. Cross-faction/ruleset, unknown-binding, and soulbound
  character stock never becomes an automatic transfer suggestion. Snapshot,
  bank withdrawal and in-game trade restrictions remain explicit.
- The Crafting footer `Request Craft` is the submission step; for recipes
  already queued, it becomes `Update Craft Request`. Cancel from Requests.
  The legacy quantity popup remains available in Requests and Gear.
- Nearby personally gathered and imported nodes now appear as small resource
  markers inside the minimap, positioned from actual world coordinates and
  view radius. This display uses FCM-owned saved node data and remains after
  GatherMate2 is removed. Node markers are historical, not live spawn signals.
  `/fcm gatherpins off|on` toggles them without affecting the round launcher.
  If the client lacks necessary map/radius APIs, the markers safely hide.
- See `FCM_v091_QA4_INLINE_CRAFTING_TEST_NOTES.md` for live verification.

## QA3 companion hotfix preview (November 14; not published)

- Correct the shared ForeverDB quota-ledger atomic rewrite path after live
  Windows logs showed `File.Replace` throwing `The path is not of a legal form`
  on the second request. The ledger now writes using a full path and a valid
  same-directory `.previous` backup; it never resets or deletes the live count.
- Include an isolated, zero-network Windows regression test
  `FCM-Companion/Test-FCMQuotaLedger.ps1` that writes twice and checks the
  original budget record survives as a backup.
- No API behavior, request caps, or user-data formats were changed.
  Run the Windows test before trying another ForeverDB scan. See
  `FCM_v091_QA3_COMPANION_TEST_NOTES.md`.

## QA2 crafting preview (November 14; not published)

- The Crafting tab now has a **Profession** dropdown listing only professions
  found in the account-wide learned recipe library. The dedicated **Recipe
  search** matches learned recipe names, output-item names and recipe IDs,
  without returning ordinary item-catalog hits.
- **Goal: Reach Total** is the default for new requests. The requested number
  represents the total finished items the recipient should have; the plan
  subtracts matching items in that character's last-recorded bags/bank.
  **Goal: Craft More** preserves the alternative "make N additional items".
- Shopping lists, material reservations, Requests and Planner use the number
  still needed, with recipe-yield rounding. A satisfied target requires zero
  new materials. Items on other toons are not silently counted as delivered.
- Existing requests without a quantity-mode field keep their original
  **Craft Additional** meaning; upgrading the addon does not reinterpret them.
- Live bank/character inventory and interface validation is still required.
  See `FCM_v091_QA2_CRAFTING_TEST_NOTES.md`.

## QA1 combined candidate (awaiting player verification)

The QA1 source and install test package also include the QA6e finished-output
crafting quantity popup fix, Zygor/Pawn numerical Frost Mage weight profiles,
and the complete tree-specific Legacy Point Advisor with manual snapshots.
Both addon `.toc` variants load `LegacyAdvisor.lua`, `Gathering.lua`, and the
optional community data stub. See `FCM_v091_QA1_COMBINED_TEST_NOTES.md` for
the combined test checklist. This candidate has **not** been published to
GitHub; the release workflow is manual-only until those tests pass.

## Companion QA addition: shared ForeverDB budget and extended schedule

- Automatic catalog imports can run every 15 minutes from **10 PM through
  11:45 AM Pacific**, using two Windows Task Scheduler jobs (28 starts each).
- A persistent, per-Windows-user budget shared by the manual companion, the
  overnight catalog importer, and the metadata build-check job caps their
  combined ForeverDB requests at **4,500 per UTC day**.
- All FCM ForeverDB requests are spaced at least four seconds apart; HTTP
  429 Retry-After cooldowns and an optional provider-reported 500-request
  reserve are shared too.
- The request budget and cooldown live under
  `%LOCALAPPDATA%\ForeverCharacterManager`, so running the companion from a
  different extracted folder on the same PC does not create another budget.
- Existing item caches, generated Lua files, credentials, SavedVariables and
  previous overnight quota records are preserved. The Windows tasks need
  explicit registration through `ENABLE-FCM-OVERNIGHT.cmd` after installation.
- All changes are offline-tested; live PowerShell/Task Scheduler and provider
  behavior still require validation on the user's Windows PC.

## Implemented

- Added a **Gathering** sidebar tab and `/fcm gather`, `/fcm gather status`, `/fcm gather import`.
- One-time read-only GatherMate2 import of four node types, saving FCM-owned records into `FCM_DB`.
- Independent tracking of explicitly named, successfully cast herbalism/mining nodes. Fishing locations require an explicitly named pool/school; ordinary open-water catches are not misleadingly recorded as a pool.
- Private, account-wide node cache with source labels: personal, GatherMate2 and community; duplicates merge without overwriting personal evidence.
- Versioned read-only public JSON snapshots at `CommunityData/`, initially empty.
- Windows companion **Sync Gathering (GitHub)** downloads and validates the static public data, generates a Lua data file without executing remote code, and leaves the private FCM DB untouched.
- Windows companion **Export Gathering Contribution** reads only the sanitized `FCM_GatherExport` marker in saved variables and creates a local, reviewable JSON file. **No automatic uploads, account data, names or credentials.**
- Existing code installer and GitHub release updater preserve a downloaded community snapshot during future addon updates.

## Important caveats

1. Tested under offline Lua simulation only. Live WoW Forever events may omit or secret node names, which FCM intentionally refuses to guess. Verify on real characters before uninstalling GatherMate2.
2. QA4 adds nearby saved markers on the minimap. Full world-map overlays,
   route optimization and crafting-queue-to-resource navigation remain follow-up phases.
3. A freshly published snapshot contains zero nodes; community submissions must be reviewed and merged, and `CommunityData/manifest.json` version incremented, before other users receive them.
4. The Windows companion is Windows PowerShell 5.1/WinForms code. It requires testing on an actual Windows machine; a Linux Lua regression suite cannot verify Windows controls.
5. For updates, always close WoW before the companion installs generated Lua. Restart the game to load the new data.

## Initial field test

1. Back up your installed FCM folder and SavedVariables. Install FCM v0.9.1 while WoW is fully closed.
2. Keep GatherMate2 installed. Open `/fcm gather`, click **Import GatherMate2** and note the count.
3. Gather one named herb as Spotty Dotty and one vein on your miner. Check `/fcm gather status` after each; switch characters to verify account-wide persistence.
4. Log out completely. Run the companion, use **Sync Gathering (GitHub)**, then **Export Gathering Contribution** and inspect the local JSON.
5. Send the number of imported/personal nodes and any errors or screenshots. Do not remove GatherMate2 yet.

## Verification

- `texlua tests/parse.lua`
- `texlua tests/qa_gathering_v091.lua`
- `texlua tests/qa_crafting_professions_v090.lua`
- `texlua tests/qa_regressions_v092.lua`
- `texlua tests/qa_v092_identity.lua`
