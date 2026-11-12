# Forever Character Manager v0.8.9 — Gear Comparison Readability & Stat Alias Fix

## Changes

- Replaced the unsupported Unicode triangle glyphs (seen as boxes in live WoW) with built-in WoW scroll-arrow **textures**, plus visible `GAIN`/`LOSS` labels in green/red. This is a font-safe approach, but the live Forever client still needs verification of the chosen textures.
- Moved the overall weighted-score change to the top of Smart Gear Comparison.
- Each changed stat now has a clearly labeled value transition: `equipped -> new` and the absolute/relative change; `NEW` is used when the prior value is zero.
- Displays full known normalized stat summaries for both the equipped item and candidate, not just the two preview stats and changed stats.
- Consolidates alternate `GetItemStats` fields for spell damage/spell power, attack power, crit, hit, and haste rather than adding aliases together. Specifically, generic Spell Power and Spell Damage API aliases are treated as potentially overlapping rather than independent bonuses.
- Healing-only spell bonuses are **not** counted as DPS Spell Power. This is a conservative interim rule; dedicated healer scoring is not yet implemented.
- Item previews now use the same normalized client stats as the upgrade comparison when available. This prevents the preview showing raw aliases while the scorer uses a different interpretation.
- Gear list now displays equipment slot names (e.g., `Waist`) instead of only numeric `slot 6`.

## Testing

- All 16 Lua modules compiled with the available Lua interpreter.
- Mocked client regressions passed for duplicate spell aliases, distinct intellect/stamina, crit aliases, healing-only effects, comparison deltas, texture markers, and equipped/new stat summaries.
- ZIP integrity and SHA-256 are verified when packaged.

## Important limitations

- **This build is not yet live-tested in WoW Forever.** The exact font/texture appearance still needs an in-game screenshot.
- Stat scoring is a heuristic, **not a DPS simulation**, and cannot account reliably for procs, set bonuses, hit caps, unique restrictions or unmodeled effects.
- A missing or incomplete client stat table is not interpreted as zero. Reference-only stats do not silently become official numeric values.
- Using the maximum of overlapping aliases is conservative; further verification of Forever-specific API fields is still necessary.
- Existing character SavedVariables and the generated reference-data file are deliberately not included in this ZIP.

## Installation

1. Exit WoW Forever and close the Windows FCM Data Companion.
2. Back up your current `Interface\AddOns\ForeverCharacterManager` folder and your `WTF` SavedVariables.
3. Extract the included `ForeverCharacterManager` folder over the current addon, replacing files but preserving your `ExternalData.generated.lua`.
4. Launch WoW Forever and verify **v0.8.9** appears at the top of FCM.
5. Open Gear on Frosty and select **Novice Ardent's Sash**. Inspect the new stat-difference lines and verify that the preview and comparison agree on client Spell Power values.
6. Send a screenshot if the texture symbols do not render or if the stat totals still disagree.

This is a **local test build**, not yet published to GitHub. Publish only after a successful live test.
