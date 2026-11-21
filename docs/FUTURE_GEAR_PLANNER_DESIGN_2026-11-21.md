# Future Gear Planner — isolated research and implementation specification
Status: DESIGN / REFERENCE AUDIT ONLY (not implemented, not released)
Date: 2026-11-21
Owner: FCM project
Tracking: https://github.com/PHOENIXHA1735/ForeverCharacterManager/issues/10
Research branch: feature/future-gear-planner-research
Source snapshot: draft PR #9 at bbe09dd8cbf40eaaf77051d6597279fc0de5f4b3 (which builds on draft PR #8).

## Purpose
For each selected saved character, build a forward-looking equipment roadmap for current level through +5 or +10 levels, without altering equipment or pretending unknown records are confirmed upgrades.
Include dungeon/boss-associated loot, learned and unlearned crafting recipes, source-labelled external reference candidates, known compatible account crafters, required skill/reputation, materials and acquisition paths.
Keep this branch independent from the published addon and PR #8/#9; no production SavedVariables changes, client launch, account automation or unapproved scraping.

## Verified current code inventory (PR #9 snapshot)
- Gear.lua: G:CompareItem supports explicit allowFutureLevel; current-level eligibility remains the default. G:FutureCandidates looks only at learned recipes with a compatible crafter, and sorts eligible future items by required level. It does not comprehensively plan future dungeon items, future external/unlearned recipe outputs, or rate future equipment.
- Gear.lua: G:DungeonCandidates looks at imported boss/dungeon source IDs but compares only currently equippable items; unknown item stats cannot be upgraded with a guess.
- Gear.lua: G:Candidates and G:UnlearnedCandidates already cover certain current-level crafting opportunities; compare through the existing shared comparison mechanism. Maintain that single mechanism, do not duplicate formulas.
- StatWeightEngine.lua / Gear.lua: no bundled complete verified 27-spec numerical profile catalog. G:DefaultReferenceProfile returns nil. Verified profiles require matching client build, class/spec, activity/style, level bracket, source, methodology, units and normalization. Former Zygor numerical coefficients are deprecated, not an active default. User Pawn imports and manual weights are provisional, not independently validated. Do not reactivate old profiles or silently shift coefficients.
- PriorityGuides.lua and docs/GEAR_SOURCES_2026-11-16.md: 54 source references, representing leveling and level-60 PvE ordinal guidance across 9 classes / 27 specializations. Priority ordering is not a numeric weight model; PvP references remain incomplete.
- Crafting.lua: FCM:AllRecipes aggregates learned recipes from saved characters; FCM:UnlearnedRecipes covers observed unlearned records; FCM:RecipeSkillStatus checks skill; FCM:EligibleCraftCrafters and FCM:CanCollaborate enforce compatibility; FCM:ReputationGate supports recorded acquisition requirements; craft request and material mechanisms already exist.
- SmartCrafting.lua: account-wide read-only inventory and nested reagent planning, reservations, binding and transfer checks; always show scan age and uncertain status.
- Scan.lua/Core.lua: recorded gear, bags, bank, professions, recipe and reputation snapshots with independent scan times. Offline character records must never be treated as live inventory.
- ExternalData.lua / companion: imported items, recipes, dungeons, prices, source/provenance and timestamps. In-game Lua must not directly fetch providers.
- UI.lua: current Upgrade Plan tab is account-wide scored-opportunity list, not the full future +5/+10 gear roadmap. Character Leveling page shows a narrow future-craft list.

## Canonical plan record (proposed)
A planner opportunity must preserve:
- characterKey, class, specialization, activity/style, levelNow, targetLevel, gearStamp, talent/spec scan stamp, clientBuild;
- itemID, item name, requiredLevel, slot, class/armor/weapon/hand restrictions, binding, faction/ruleset, availability/raid release caveats;
- currentEquippedItemID(s), replacement slot(s), current stats, candidate stats, unknown stat identifiers, unmodelled proc/set/weapon interactions;
- sourceKind (dungeon-boss, dungeon-unknown-boss, crafted-known, crafted-unlearned, external-reference, quest/vendor/reputation when verified), source ID, display name, source URL/provider, provider build, observation/evidence category, importedAt, lastVerifiedAt;
- recipeID, profession, requiredSkill, learnedStatus, knownCrafterKeys, skillStatus, reputation requirement/status, materials, reserved/available/missing stock, stock freshness, binding/trade check;
- evidenceStatus and comparison status, model provenance, explanation, warnings, and any allowed weighted-point delta.

Keep ID relationships explicit. Do not merge two sources simply because they point to the same item; deduplicate the item candidate while retaining all sources.

## Scoring and recommendation rules
1. Use current equipped gear as the named comparison baseline. Future-level character stats are NOT projected unless an independently verified future snapshot exists. Label all forward comparisons as "versus currently scanned gear", not future DPS.
2. Compare at a permitted target level only when lookahead is explicitly selected. Respect required level, class masks, armor, hand/weapon limitations, faction/ruleset, binding, two-hand/offhand displacement, unique-equip and reputation limits where known. Missing restrictions require review, not automatic eligibility.
3. Verified weighted upgrade: only an exact-match validated profile and complete supported item stat comparison. Show weighted-point changes, not DPS/HPS percentages or invented confidence.
4. Provisional user model: may show its own clearly marked estimate only when explicitly active for this character, game build, activity/style and level bracket. Never represent it as verified or compare its points across different profiles/characters.
5. Qualitative candidate: use ordered PriorityGuides only for conservative, non-contradictory comparisons; identify stat gains and losses. A mixed-stat tradeoff, unknown effect/weapon behavior, cap mismatch or incomplete baseline requires review rather than positive upgrade status.
6. Insufficient information: missing item stats, ambiguous suffix/procs, uncertain slots, unavailable gear scan, unsupported model, no source evidence or hidden beta-only/future items must not become ranked recommendations.
7. Do not treat unknown stats as zero; do not silently convert rating to percent, reinterpret spell schools or automatically apply level-60 raid hit caps to leveling.
8. Allow filters for +5/+10 levels, all/crafting/dungeons, equipment slot, class/spec and acquisition confidence; never overstate whether an item is obtainable on the live client.

## Reference hierarchy and provider audit
Current integrated providers:
1. In-game scans / client-visible item stats and own saved characters: direct evidence for observed gear, recipes, skills, reputations and bags/bank; still limited by scan age and local client coverage.
2. ForeverDB (https://foreverdb.net/developers): already used by the Windows companion. Read-only keyed API exposes items, dungeons/boss loot, professions/recipes, trainers/vendors, acquisition sources, reputation/favor, builds, changes observed and item sets. Its Classic fallback, speculation, beta event and seen-in-Forever indicators must remain distinguishable. Free tier is documented at 5,000 account requests/day, 30/min; FCM's existing internal limit/quota must remain authoritative; never commit credentials.
3. AHledger (https://ahledger.com/data and /developers): historical faction/market-specific auctions, client item/recipe reference and observed sources. Attribution, cache restrictions and provider terms apply; prices are not real-time purchase guarantees.
4. TheWoWDB (https://thewowdb.com/developers): supplementary item reference; check coverage and provenance before promoting as acquisition evidence.
5. Icy Veins (54 named WoW Forever leveling/endgame sources, listed in docs/GEAR_SOURCES_2026-11-16.md): ordinal class/spec priorities, not transferable numerical coefficients.

Additional candidates for evaluation, not integrated by this design commit:
- WoWSims Forever (https://www.wowsims.com/forever/ ; https://github.com/wowsims/forever): possible build-specific marginal/EP weight production, but as of this review the simulator labels class coverage Alpha and has open model/weight questions. Require exact version, talents, gear, encounter context, measured output, reproducibility and permitted licensing before accepting numeric data.
- Warcraft Forever developer data (https://warcraftforever.com/developers/data/): public bounded profession-focused item/recipe/skill datasets and reference values, with no loot/quest/NPC corpus. Do not mistake this for a complete game item source or automatically assume publisher affiliation.
- Wowhead Forever gear planner (https://www.wowhead.com/forever/gear-planner/shaman): manual comparison and spec weights; assess provenance and terms; do not copy numerical coefficients without validating context.
- Zockify Forever gear planner (https://www.zockify.com/forever/gear/): explicitly preliminary, non-simulated stat weights; useful as qualitative comparison only.
- Eternadex (https://eternadex.com/en/datenbank/), GearInsight (https://gearinsight.app/wow/en/forever/db), other public item/dungeon sites: cross-check particular disputed item/acquisition records only after checking data provenance, update cadence and reuse terms.

## Proposed implementation sequence
Milestone 0 — Reference matrix and fixture design: catalogue exact fields available from installed generated data and current provider schema; create sanitized mocked test records; mark verified/unverified, provider build and timestamps. No game/client access.
Milestone 1 — Pure future-candidate aggregation: extract a read-only planner module, reusing Gear and FCM data accessors. +5/+10 window; separate learned, unlearned, reference crafting and dungeon/boss sources; deduplicate preserving provenance; filter slot, restrictions, hidden/unreleased sources.
Milestone 2 — Comparison engine integration: route each candidate through one validated Gear comparison; support verified/provisional/qualitative/unknown results; explicit reason strings and testable evidence; do not create a second score formula.
Milestone 3 — Craft/acquisition intelligence: add compatible known crafters, required profession skill, recipe acquisition source, rep gate, BoP/BoE/tradability, nested material plan, stock freshness and existing request-board handoff.
Milestone 4 — UI: per-character Future Gear Planner inside or linked from Upgrade Plan. Controls for +5/+10, All/Crafting/Dungeons, slot and availability; grouped by slot with explanations and source labels; links to Crafting, Dungeons and Shopping.
Milestone 5 — CI and isolated/manual QA: Lua 5.1 syntax, fixtures, consistency checks, scan-age tests, mock reference builds; user alone tests the isolated WoW client; no release until approved.

## Acceptance and regression tests
- 9 classes/27 specs have ordinal guide coverage for leveling and level-60 PvE; absent PvP data stays explicit. Same item against incompatible spec must not be silently promoted.
- Character at level 25: +5 includes required level 26–30 only; +10 includes 26–35; max level stays 60; no current-level items falsely described as future.
- Mage cannot equip a higher-armor class item; class-mask restrictions and weapon usability are separately tested (not inferred from armor type alone).
- Two-handed weapons displace offhand; offhand-only comparisons cannot replace an occupied two-hander; duplicate ring/trinket slots choose the legal replacement.
- Unlearned recipe appears as an acquisition goal, never "can craft now"; known recipe with insufficient skill is blocked, unknown skill remains verify.
- Same-faction/region/ruleset crafter and BoP conditions are enforced; missing binding must be labelled verify.
- Reputation-locked recipe stays locked/verify until a current relevant rep record supports access.
- Unscanned/stale gear, profession, bank, bags, recipes and rep data produces explicit freshness flags and no guaranteed stock claim.
- Boss-linked and boss-unknown dungeon references are distinct; source record imported from Classic does not become a confirmed Forever drop.
- Item with missing stats, proc, ambiguous suffix, missing weight profile or mixed-stat qualitative tradeoff has no fabricated numeric gain.
- Verified weights require matching build, level, spec, activity and units; old Zygor weights stay deprecated; user imports never become verified automatically.
- No cross-character comparison of incompatible weight scores; no DPS/HPS percentages inferred from weighted-point deltas.
- Tests do not create live player records, auto-launch WoW, or use real provider credentials.

## Integration / chat handoff
- This branch carries planning documentation only. Neither draft PR #8/#9, main, production install, nor any SavedVariables were changed by its creation.
- After PR #8/#9 stabilize or merge, inspect the actual current branch head, reconcile code differences, then create a separate implementation branch and draft pull request for the planner.
- Use GitHub issue #10 and this document as the source of truth across ChatGPT chats. Another chat cannot literally import this transcript; it can read the issue, branch, and future PR.
- Never merge/release automatically without manual QA acceptance.
