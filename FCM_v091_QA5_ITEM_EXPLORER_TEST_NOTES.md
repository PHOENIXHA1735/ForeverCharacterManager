# FCM v0.9.1 QA5 — Item Explorer readability and acquisition sources

Build: `QA5-20261114-Readable-Item-Sources` (local test candidate; **not** an official GitHub release)

## What changed

- The right-hand panel in **Global Search** and **Item Explorer** is wider.
  Results use readable item types instead of `material / unknown` and hide
  technical inventory enums such as `INVTYPE_NON_EQUIP_IGNORE`.
- The selected item explains **How to get it**, **Crafting & uses**, **Your
  characters**, **Auction House**, **Item facts** and **About this data**.
  Cached auction times show human dates; ordinary reagents say they have no
  combat stats. Gear retains client stats and activity comparisons.
- Clam Meat, ID **5503**, has a documented **Giant Clam** container source.
  ForeverDB's public item page lists it as **Seen in Forever** (checked
  November 14, 2026); the API record alone did not include this acquisition
  information. FCM does not invent a zone, rate, route or respawn time.
- Item imports can preserve explicit container, vendor and gathering source
  kinds when the provider includes them. Dungeon item imports now match
  explicitly supplied numeric boss/NPC/encounter IDs as well as exact boss
  names. Unattributed loot is still shown at the dungeon level.

## Install without losing any player data

1. Exit WoW Forever and the FCM Windows Data Companion completely.
2. Back up the installed `Interface\AddOns\ForeverCharacterManager` folder and
   WoW's `WTF` SavedVariables before merging the update.
3. Merge the QA5 package's `ForeverCharacterManager` folder into the installed
   addon folder, replacing matching source files. **Do not first delete the
   installed folder.** Leave `ExternalData.generated.lua`,
   `AHPrices.generated.lua`, local API-key storage, cache/settings JSON, and
   account SavedVariables in place.
4. Restart WoW and check FCM > Diagnostics for the exact QA5 build above.

## Live WoW checks

1. Open `/fcm` > **Global Search**. Search `Clam Meat`. Five related item
   records should still appear, with a clear `Crafting material | Common`
   description for item #5503.
2. Click **Clam Meat #5503**. Its right-hand pane should show **How to get it
   > Giant Clam** with a **Seen in Forever** attribution, but no invented
   zone or percentage. Confirm **Boiled Clams** and **Clam Chowder** appear
   under **Crafting & uses** if present in the imported recipe library.
3. Check the **Auction House** section. It should show readable money and a
   date such as `Nov 14, 2026`, never a raw value like `1794685800`.
4. Confirm no `INVTYPE_NON_EQUIP_IGNORE` code or `Stats unavailable` warning
   for Clam Meat. Scroll the whole panel to test text wrapping and readability.
5. Search an item with no source information. It must say that the imported
   data lacks an acquisition location, rather than inventing a drop.
6. Search a **bag** and confirm the known slot count still appears. Then
   inspect a weapon or armor piece and verify its relevant combat stats remain.
7. Open **Item Explorer**, repeat the Clam Meat test, and resize FCM to its
   normal minimum window size to check that the list and right pane remain
   usable. Normal character and crafting tabs should keep their prior widths.

## Zero-network Windows companion mapping regression

From the updated **installed** `FCM-Companion` folder in PowerShell:

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-FCMDungeonSourceMapping.ps1`

Expected result:

`PASS: explicit boss ID/name loot, unknown-boss isolation, and typed container imports.`

This test creates only in-memory mock records; it does not contact ForeverDB,
use an API key, reset request counts, or touch real cache/SavedVariables.

## Known source limitations

- ForeverDB's item API documents client metadata, not the full **Where to get
  it** list shown on its web pages. FCM links to the public item page when an
  imported source is missing; it does not scrape webpages or synthesize routes.
- The prior live sync imported 47 dungeons, 39 with bosses and 27 with some
  dungeon-level loot, but **zero proven boss-linked loot records**. QA5 can
  attach explicitly identified drops if provided; it does not retroactively
  assign anonymous loot to bosses. A future live sync may still show zero.
- Price snapshots are historical and should not be taken as live AH listings.

Report the build ID, screenshots of the new Clam Meat pane (top and lower
sections), and the zero-network PowerShell test result before a release.
