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

## ForeverDB API key — optional, private, and per user

**No API keys, tokens, or personal character data are included in the FCM v0.9.0 GitHub source or release ZIP.** Every person who wants authenticated ForeverDB updates must obtain their **own approved key**. FCM can run without a ForeverDB key; public AHledger and TheWoWDB updates may still work.

### Steps to obtain your own key

1. Open the [ForeverDB developer portal](https://foreverdb.net/developers).
2. Log in through **Battle.net**.
3. Request API access. Describe **Forever Character Manager (FCM)** as a **local Windows companion application/plugin for a WoW Forever addon**, supply a contact email, and agree to credit ForeverDB.net.
4. After ForeverDB approves your request, return to the developers page and create your own key (up to three per approved account).
5. When describing key use, select the option for a **personal application or plugin**, if offered. A local companion is not a website; follow ForeverDB's current key restrictions.
6. On your Windows PC, launch `ForeverCharacterManager/FCM-Companion/OPEN-FCM-DATA-UPDATER.cmd`.
7. Paste **your own key locally** into **ForeverDB API key**. Optionally tick **Remember encrypted for this Windows user**, which uses Windows DPAPI to save the key for that Windows account.
8. Click **Scan and Update**. A successful connection reports **ForeverDB API connected** in the companion log.

**Do not paste keys in GitHub issues, chats, screenshots, support requests, or source files.** Do not share a key or redistribute one in an addon. The companion keeps the key out of generated Lua reference data and GitHub downloads. Credentials saved with DPAPI are for the local Windows user, not for other users to copy.

ForeverDB currently advertises a free tier of **5,000 requests/day and 30 requests/minute per account**. Quotas, pricing, approvals, and attribution requirements may change; review [ForeverDB's current documentation](https://foreverdb.net/developers). Always credit ForeverDB.net with a visible link when displaying its data.


## Verification

- 23 addon Lua modules parsed successfully using `texlua` in development QA.
- 33 deterministic offline regression checks passed in QA2 development (16 prior + 17 new).
- In-game screenshot validation: opposing-faction Itty excluded and allied Spotty considered appropriately; the error log showed zero errors after clearing and rescanning.
- Remaining limitations: live ruleset detection is not guaranteed by the upstream client API; actual mail/trade permissions and item upgrade weighting should continue to be verified. An eligible candidate does not guarantee an item can be transferred.

## Data safety

This source package deliberately excludes personal SavedVariables, account records, logs, downloaded/generated auction and reference data, credentials and tokens. Do not delete existing WoW folders or private companion data during upgrades.

## GitHub policy

Publish to the existing repository as a **new forward commit**, preserving prior v0.8.x history, tags and releases. Tag v0.9.0 only if that tag does not already exist; never force-push.
