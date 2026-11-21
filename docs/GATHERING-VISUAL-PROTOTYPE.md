# Gathering right-pane visual prototype (stacked on PR #8)

This is an **isolated, draft-only UI experiment**. Its base is PR #8 commit `7182a7d`. Do not merge into the public addon or install into the regular WoW client without completing in-game QA.

## Scope of this first pass

- Collected Herbalism/Mining reference materials, starting with **Rough Stone** (item 2835), use a dedicated native WoW Frame renderer instead of paragraph cards.
- Large resource icon, gold name and item type; compact metric boxes for node skill requirement, selected character profession skill, and verified eligibility.
- Gold-accented dark source/deposit, zone, how-obtained and personal history panels; compact default zone list and existing Show All Details control.
- Separate `GatherDetailModel.lua` prepares read-only display values from `GatherBrowser.lua` reference rows; `GatherDetailUI.lua` paints those values and reflows them when resized.
- Candidate Classic source deposits and associated zones are **not** proof of WoW Forever drops. For candidate materials the overall eligibility stays Unknown even when a source's mining requirement can be displayed.
- Existing fishing, node, treasure and non-Gathering details retain the prior renderer. Data ingestion, map pins, saved variables, scans and companion behavior are unchanged.

## Test gate

Before deploying, run Lua 5.1 syntax and the Gathering regression suite, Python source/reference checks, TOC checks, and Windows companion checks. Then package into a **separate isolated UI QA installation**, with checksum verification and backups. Test Rough Stone, Malachite and Commonplace Herb Seeds at minimum/default/maximum window sizes, scroll-to-top on selection, expand/collapse, and fallback on non-materials. Never replace the original `public30-smoke` Fishing QA build until separately approved.

## Known limitations

The layout uses native frame textures and font strings, not photorealistic art. The first pass does not implement drag-resizable pane dividers, independent clickable zone rows, or an equivalent structured layout for fishing and treasure. Those remain later phases after screenshots of this material prototype.
## Removing the optional GatherMate2 integration

GatherMate2 importing has been removed from the Gathering UI and Lua backend. The prior imported-only points are retained in the user's SavedVariables for possible future migration, but are no longer displayed as active FCM resource nodes, counted discoveries, minimap icons or world-map pins. Personal discoveries and community references continue to behave normally. The single Show All Details button is now anchored at the right edge below the detail pane; there is no GatherMate2 import action. Acquisition/reference notes are placed in the expanded material view, keeping the default panel compact. This does not uninstall or alter a separately installed GatherMate2 addon.

## Phase 2

The framed renderer now handles ordinary herb and mining nodes, fishing, and
treasure in addition to collected materials. Sections reuse the Gathering browser
reference and observation data. Material rows show source-node skill eligibility
separately from the unverified Forever drop. Fishing shows effective Fishing when
known, and treasure has no profession tile or difficulty ladder. Narrow panes
stack the skill tiles, and wrapped headers and section text contribute to scroll height.
The actual game font metrics and resizing still require manual in-game QA.

## Phase 3 navigation

The 145-pixel sidebar groups the 25 existing destinations under Character,
Progression, Craft & Gather, Explore & Trade, and Tools & Help. Recipe profession
entries still appear beneath Professions for the selected character. Dark rows,
gold trim, client icons and a gold active marker match the Gathering detail panel.
Mouse wheel and fixed scroll controls keep all sections accessible. The center
pane anchors and Gathering controls are unchanged.

The mock navigation test covers construction, click destinations, active row,
dynamic professions, row and heading bounds, and scroll limits. Confirm actual
fonts, icons and pointer behavior during the next manual client test.
