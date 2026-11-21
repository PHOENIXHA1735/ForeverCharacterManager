# Gathering resource browser

The browser groups saved points by resource name and profession. Reference zones and associated items remain separate from account-wide personal observations. Legacy observations with no repeat counts appear as minimums. The selected character supplies the skill snapshot. Skill snapshots older than 24 hours or missing a timestamp produce unknown eligibility. The bundled factual seed is limited to Silverleaf and Battered Chest; only Silverleaf has reviewed Forever difficulty bands. Fishing skill-up requirements are left unknown.

Fishing recording requires a recognized named tooltip, a fishing cast, game-object loot evidence, and a cleared item loot slot. Item IDs and quantities come from the cleared slots. The marker represents the player standing position. The client event order, tooltip identification and correspondence to the pool or bobber still need live-client verification. Clients without the required loot evidence do not write a fishing record.

## Local reference staging

Use three previously acquired authorized ForeverDB Gathering endpoint responses, named herbalism.json, mining.json and fishing.json. Follow the provider terms and use the existing credentialed provider and quota ledger for any new acquisition. The offline tools make no requests and do not access SavedVariables. Current provider documentation does not advertise delta tokens for these endpoints. This branch does not add a new network refresh or scheduled task.

From the checkout root, stage a generation in an existing private directory:

    python -B tools/import_foreverdb_gathering.py INPUT_DIRECTORY PRIVATE_DIRECTORY/GENERATION

A successful generation contains a normalized reference, addon Lua and an audit with content hashes and provider build. An identical rerun verifies the committed output and returns unchanged. For a different version or input fingerprint, use a new generation directory. Incomplete or rejected generations leave the previous directory intact. Review the output before publishing it locally. With WoW closed, the compiler can atomically replace GatheringReferenceData.lua in a test addon using the staged JSON as input, retaining the prior file as a hash-named backup.

    python -B tools/build_gather_reference.py PRIVATE_DIRECTORY/GENERATION/gathering-reference.json TEST_ADDON/GatheringReferenceData.lua

The public branch ships only the small reviewed seed. Keep API responses and locally generated provider data outside Git. See https://foreverdb.net/developers and https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling for source coverage.
