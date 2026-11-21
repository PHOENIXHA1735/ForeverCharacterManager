# Future Gear Planner — real companion-cache audit (2026-11-21)

Scope: non-executing, read-only inspection of the privately uploaded ExternalData.generated.lua, generated 2026-11-19 10:14. **Only aggregate observations** are published here; no raw item records, user characters, API credentials or complete cache were committed.

Inspected file SHA-256: 95a6db55f46f244970803f2de869753c34a8dae5be0c5361cdf50d91e868f335 (for comparing future file versions, not a source-trust claim).

## Actual coverage

| Measure | Records |
| --- | ---: |
| Items | 23,678 |
| Recipes | 2,466 |
| Dungeon/instance records | 47 |
| Items with requiredLevel | 23,416 |
| Items with recognizable equipment slotID | 12,215 |
| Such items requiring levels 26–30 | 615 |
| Such items requiring levels 26–35 | 1,158 |
| Recipes with a positive resultID | 2,283 |
| Recipes producing known equippable outputs | 1,350 |
| Unique known equippable recipe-output item IDs | 1,348 |
| Unique equippable recipe outputs requiring level 26–35 | 161 |
| Instances with loot IDs | 27 |
| Instances with boss-specific loot attribution | **0** |
| Instances with nonempty kind classification | **0** |
| Items with numeric stats in imported record | **0** |
| Items with explicit class mask | **0** |
| Items with binding metadata | **1** |
| Items source-flagged as speculative | 2,091 |
| Items source-flagged as beta event | 27 |
| Items with per-record sourceProvider / sourceEvidence | 4,696 |

These are source-coverage counts, NOT verified available drops, equippable gear, build-specific improvements or true in-game stats. Armor/weapon training, bind restrictions, factions, game build and actual equipment still need authoritative checks.

## Important source-contract discoveries

1. All 23,416 imported slotID properties are **text**, e.g. Chest, One-Hand, Main Hand, Off Hand, Two-Hand, Held In Off-hand, Back, Finger, Ranged, Non-equippable. No item in this cache has an equipLoc field or a numeric slotID. Code expecting numeric inventory type IDs or equipLoc alone misses the imported equipment without a live client cache.
2. Most items contain string requiredLevel, itemLevel, classID and text subclass. Class masks, structured numerical item stats and binding details are absent or extraordinarily sparse; missing fields must remain unknown.
3. Companion recipes use spell/recipe key plus separate resultID, skill, reagents and acquisition. Never assume the spell ID is the resulting item ID or that the recipe is learned on a compatible character.
4. All 47 imported instances have blank kind fields and no boss-specific loot rows. 27 contain dungeon-associated loot IDs. Those sources must be labeled unclassified instance / boss unknown rather than asserting dungeon versus raid or attributing drops to the listed bosses.
5. Reference availability isn't verified. In particular, 2,091 items are explicitly speculative and 27 are marked beta event. Existing item metadataSource claims are not substitutes for observed live drops or item-client evidence.

## Fixes on isolated research branch

- Normalize text slotID and avoid conflating inventory-type IDs and actual character equipment slots.
- Reject conflicting equip locations rather than guessing.
- Retain provenance and beta/speculative status and keep unsupported class/weapon eligibility as VERIFY.
- Mark blank-kind loot associations as unclassified instances rather than confirmed dungeon drops.
- Keep scoring delegated to the shared Gear:CompareItem engine; only a build-matched, fully verified profile may support a numerical upgrade claim.

## Next required work

1. Reconcile the other development chat's locally corrected weapon proficiency and equipment-snapshot protections before integration.
2. Verify actual item links and stats from the WoW Forever client; this cache has zero numerical item-stat fields.
3. Improve class restrictions, bind information and recipe-acquisition confidence from appropriately verified sources.
4. Improve actual boss-to-drop associations and dungeon-versus-raid classification without fabrication.
5. Test real client cases for Shadow Priest, Frost Mage and Affliction Warlock level 25 to 30/35, plus different factions, item-binding restrictions and stale SavedVariables; verify Lua 5.1 compatibility.

The audit parsed text and did not execute the user-supplied Lua. A basic assignment-pattern check found no API-key/password or character-SavedVariables assignments, but that does not guarantee every free-form string is non-sensitive. **Do not publish the complete user cache** to this public repository.
