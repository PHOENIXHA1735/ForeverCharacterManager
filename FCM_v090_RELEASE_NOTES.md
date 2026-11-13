# Forever Character Manager v0.9.0 — consolidated release

Date: November 12, 2026

This single release consolidates the original v0.9.0 development with the subsequent QA1 and QA2 fixes. The interim v0.9.1 and v0.9.2 builds were **test iterations**, not separately published releases.

## Included

- Complete in-game addon, Windows companion scripts, media/emblem, talent guides, gear scoring, crafting, shopping, dungeon catalog, planning and diagnostics.
- Account-wide characters recorded by GUID with **first name and surname** retained separately; non-destructive migration of older character records.
- Explicit ruleset and region handling. Recognized rulesets include Normal, PvP, RP, RP-PvP and Hardcore. Unverified rulesets remain unknown rather than assumed.
- Faction, region, and ruleset checks for transfers, gear recommendations, crafting collaboration and auction market isolation.
- Item-binding API safety checks and reliable handling of a confirmed `false` binding result; invalid locations are treated as unknown.
- Previously developed BoE decisions, item upgrade recommendations, item exploration, farming, reference imports, and companion functionality.

## Verification

- 23 addon Lua modules parsed successfully using `texlua` in development QA.
- 33 deterministic offline regression checks passed in QA2 development (16 prior + 17 new).
- In-game screenshot validation: opposing-faction Itty excluded and allied Spotty considered appropriately; the error log showed zero errors after clearing and rescanning.
- Remaining limitations: live ruleset detection is not guaranteed by the upstream client API; actual mail/trade permissions and item upgrade weighting should continue to be verified. An eligible candidate does not guarantee an item can be transferred.

## Data safety

This source package deliberately excludes personal SavedVariables, account records, logs, downloaded/generated auction and reference data, credentials and tokens. Do not delete existing WoW folders or private companion data during upgrades.

## GitHub policy

Publish to the existing repository as a **new forward commit**, preserving prior v0.8.x history, tags and releases. Tag v0.9.0 only if that tag does not already exist; never force-push.
