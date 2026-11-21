# Gathering resource browser

The browser groups confirmed fishing catches by item ID across source pools. Other resources are grouped by name and profession. Reference zones and associated items remain separate from account-wide personal observations. Legacy observations with no repeat counts appear as minimums. The selected character supplies the skill snapshot. Skill snapshots older than 24 hours or missing a timestamp produce unknown eligibility. The ten-record seed contains nine resources with reviewed Forever difficulty bands and Battered Chest. Fishing skill-up requirements are left unknown.

A named pool observation requires a fishing cast followed by a recent recognized tooltip, game-object loot evidence, and a cleared item loot slot. If only a recent pre-cast tooltip was observed and the client independently marks the loot as fishing through IsFishingLoot, FCM retains the cleared item as an unattributed catch. It does not assign a pool or map location. If that signal is absent, use the fishing diagnostics to check why a catch was skipped. Item IDs and quantities come from the cleared slots. The marker represents the player standing position. The client event order, tooltip identification and correspondence to the pool or bobber still need live-client verification. Clients without the required loot evidence do not write a fishing record.

## Local reference staging

Use three previously acquired authorized ForeverDB Gathering endpoint responses, named herbalism.json, mining.json and fishing.json. Follow the provider terms and use the existing credentialed provider and quota ledger for any new acquisition. The offline tools make no requests and do not access SavedVariables. In the companion, close WoW and choose **Refresh ForeverDB Gathering**. The manual action uses the existing API key, UTC request ledger and backoff. Configure Python through the existing absolute interpreter-path file or an accessible Python on PATH. A matching build, verified published digest, and checkpoint younger than 24 hours skip the three gathering payloads. The meta request still counts. A changed build, old checkpoint, or file mismatch triggers a complete refresh. The provider does not advertise delta tokens here. Existing scheduled tasks are unchanged.

A malformed response, missing page or request failure aborts before publication. The Lua file is activated atomically and the receipt written afterward. If interruption occurs between those writes, the next run sees the receipt/hash mismatch and refreshes again.

From the checkout root, stage a generation in an existing private directory:

    python -B ForeverCharacterManager/FCM-Companion/import_foreverdb_gathering.py INPUT_DIRECTORY PRIVATE_DIRECTORY/GENERATION

A successful generation contains a normalized reference, addon Lua and an audit with content hashes and provider build. An identical rerun verifies the committed output and returns unchanged. For a different version or input fingerprint, use a new generation directory. Incomplete or rejected generations leave the previous directory intact. Review the output before publishing it locally. With WoW closed, the compiler can atomically replace GatheringReferenceData.lua in a test addon using the staged JSON as input, retaining the prior file as a hash-named backup.

    python -B ForeverCharacterManager/FCM-Companion/build_gather_reference.py PRIVATE_DIRECTORY/GENERATION/gathering-reference.json TEST_ADDON/GatheringReferenceData.lua

The public branch ships only the small reviewed seed. Keep API responses and locally generated provider data outside Git. See https://foreverdb.net/developers and https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling for source coverage.
