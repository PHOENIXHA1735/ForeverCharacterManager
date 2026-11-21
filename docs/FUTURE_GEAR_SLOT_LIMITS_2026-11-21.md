# Future Gear Planner — per-slot display limits

User decision (2026-11-21): keep the planner readable with **5–10 potential items per ordinary equipment slot** and **3–5 candidates per weapon slot, only if the character can equip them**.

## Implementation contract

- The collector and shared comparison engine process ALL source candidates before limits; do not truncate early and hide a potentially better upgrade.
- Compact defaults: **5** ordinary items per logical slot, **3** verified weapons per weapon slot. Expanded: **10** ordinary and **5** weapons.
- The shortlist accepts item limits in range 5–10 and weapon limits in range 3–5; no SavedVariables mutation. This is a display-only view.
- Rings share a logical group; trinkets share a logical group; main-hand, offhand and ranged weapons have separate groups. Nonweapon offhand items use the ordinary equipment limit.
- The shortlist preserves source references/evidence and reports how many rows are hidden by display limits or withheld because weapon eligibility is not proven.
- For a weapon to be displayed, FCM must have trusted in-game client evidence for the exact item, character class, equipment location, character level and game build. The prototype requires a verified in-game proof record matched to all of these fields. A scraped item class/type or a known priority list is NOT proof of a trained weapon skill.
- With no verified eligible weapons, show **zero** weapon rows and an honest withheld count. Do not fill the quota with potentially unusable weapons.
- Armor/accessories with unknown eligibility may be presented as labeled unverified candidates, never confident upgrades.
- Rank verified, build-matched weighted upgrades first; then safe qualitative guide candidates; then provisional estimates; then unknown candidates; then known non-upgrades. Numeric values only rank items within the same evidence tier. For other rows, use deterministic required-level/item-ID ordering, not invented DPS.
- A view limited to 5/3 (or expanded 10/5) never discards the source catalog, original comparisons or acquisition links.

## QA status

Synthetic test source: tests/qa_future_gear_shortlist.lua. It covers the initial limits, expansion, scoring after full collection, conflicting/wrong-build weapon proof, character/spec mismatches, ring grouping, and input immutability.

The two new Lua files (shortlist module and test fixture) are committed to the isolated research branch but were not executed in the current runtime. Lua 5.1 CI, actual in-game proficiency verification, and UI loading/integration are outstanding. No change to production TOC, SavedVariables, PR #8/#9 or main.
