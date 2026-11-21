# Gathering resource browser

The browser groups confirmed fishing catches by item ID across source pools. Other resources are grouped by name and profession. Reference zones and associated items remain separate from account-wide personal observations. Legacy observations with no repeat counts appear as minimums. The selected character supplies the skill snapshot. Skill snapshots older than 24 hours or missing a timestamp produce unknown eligibility. The bundled catalog includes verified facts, provider reference hints, and explicitly unknown fields. Fishing skill-up requirements are left unknown.

A named pool observation requires a fishing cast followed by a recent recognized tooltip, game-object loot evidence, and a cleared item loot slot. If only a recent pre-cast tooltip was observed and the client independently marks the loot as fishing through IsFishingLoot, FCM retains the cleared item as an unattributed catch. It does not assign a pool or map location. If that signal is absent, use the fishing diagnostics to check why a catch was skipped. Item IDs and quantities come from the cleared slots. The marker represents the player standing position. The client event order, tooltip identification and correspondence to the pool or bobber still need live-client verification. Clients without the required loot evidence do not write a fishing record.

## Local reference staging

Use three previously acquired authorized ForeverDB Gathering endpoint responses, named herbalism.json, mining.json and fishing.json. Follow the provider terms and use the existing credentialed provider and quota ledger for any new acquisition. The offline tools make no requests and do not access SavedVariables. In the companion, close WoW and choose **Refresh ForeverDB Gathering**. The manual action uses the existing API key, UTC request ledger and backoff. Configure Python through the existing absolute interpreter-path file or an accessible Python on PATH. A matching build, verified published digest, and checkpoint younger than 24 hours skip the three gathering payloads. The meta request still counts. A changed build, old checkpoint, or file mismatch triggers a complete refresh. The provider does not advertise delta tokens here. Existing scheduled tasks are unchanged.

A malformed response, missing page or request failure aborts before publication. The Lua file is activated atomically and the receipt written afterward. If interruption occurs between those writes, the next run sees the receipt/hash mismatch and refreshes again.

From the checkout root, stage a generation in an existing private directory:

    python -B ForeverCharacterManager/FCM-Companion/import_foreverdb_gathering.py INPUT_DIRECTORY PRIVATE_DIRECTORY/GENERATION

A successful generation contains a normalized reference, addon Lua and an audit with content hashes and provider build. An identical rerun verifies the committed output and returns unchanged. For a different version or input fingerprint, use a new generation directory. Incomplete or rejected generations leave the previous directory intact. Review the output before publishing it locally. With WoW closed, the compiler can atomically replace GatheringReferenceData.lua in a test addon using the staged JSON as input, retaining the prior file as a hash-named backup.

    python -B ForeverCharacterManager/FCM-Companion/build_gather_reference.py PRIVATE_DIRECTORY/GENERATION/gathering-reference.json TEST_ADDON/GatheringReferenceData.lua

The public branch ships the reviewed, normalized snapshot. Keep original API responses and local refresh data outside Git. See https://foreverdb.net/developers and https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling for source coverage.

## Bundled catalog coverage

The bundle uses normalized ForeverDB Gathering responses for build 1.60.1.70959 plus independently reviewed Forever references. The provider explicitly documents addon bundling and requires attribution. See https://foreverdb.net/developers. No raw API response, credentials, client identifier, private observations, or coordinates are bundled.

- Herbalism: 34 rows, comprising the 28 provider herbs plus six documented scarce or endgame herbs with incomplete source details.
- Mining: 21 rows, comprising 17 named deposits and four material references. Search by a yield such as Rough Stone to find its source nodes. Quest and raid nodes such as Hakkari Thorium and Obsidian Chunks are not comprehensively covered.
- Fishing: 68 distinct selectable item IDs and 21 stand-alone source references. The source records include zones as well as known pools. Water tables, named-pool associations, and no-escape thresholds are incomplete. The provider's Classic candidate loot and Forever-observed loot retain different provenance. A zone-level catch cannot be attributed to a specific school from zone membership alone.

The catalog includes Black Lotus, Rich Thorium, Poor Copper Vein, Whimsyfin, and Iron Bound Trunk. The full set of obtainable items and spawn zones remains unverified. Difficulty colors stay unknown where guides disagree. In particular, the green breakpoints disagree between the Icy Veins and Wowhead Forever guides, so those values are omitted. Fishing remains independent of the herbalism and mining color bands. Effective Fishing is shown only when the active client's profession API reports both base skill and bonus.

## Gathering detail and material overlay

The Gathering tab uses one eight-option category dropdown, with no skill filter or pagination. The enlarged detail panel groups profession skills, deduplicated named reference zones, source nodes, fishing water-specific escape information, personal history and compact source names into separate sections. Full provider URLs are not repeated next to each zone. Displayed reference zones do not create map pins.

GatheringExtras.lua is a reviewed, data-only supplement to the generated ForeverDB snapshot. Swiftthistle, Frilled Lichen and Commonplace Herb Seeds are selectable Herbalism yields, not independently gatherable nodes. Ore, stone and gem materials are selectable under Mining and link their candidate node sources and node skill requirements; classic-only gem/stone associations are explicitly unverified for Forever. The supplement remains loaded after a companion-generated snapshot refresh and does not alter SavedVariables or community observation data.

## Live client QA follow-up

The single-page category menu opens below its button rather than covering the top toolbar. Selecting a new resource or filter resets detail scroll to the beginning. Long reference zone, source-herb zone and fishing-water lists show compact, deduplicated default summaries with a Show All Details control for expanded source provenance. Derived material zones are explicitly source-node candidate zones, not verified material drop zones. Fishing loot items, fish and pool/source objects are labeled separately. The default pane omits redundant provider-name lists while the footer keeps required attribution.
