# FCM Gold Finder — game QA checklist

Status: code-complete candidate; **not yet verified in the WoW Forever client**.

## What the feature shows

- New **Gold Finder** tab, beside Gathering. Filter between **All**, **Bags**, **Farm**, **Fish**, and **Cook**.
- **My bags: estimated sale value**: confirmed-unbound items valued at AHledger's median and lowest available buyout, each after an estimated 5% faction-AH fee. Unknown item binding is reported separately; soulbound items are excluded. Deposits and failed auctions are not included.
- Item rows show stack counts, per-item market prices, and expected sale value. The bag summary updates after normal bag changes, when visiting Gold Finder, and when clicking **Recheck loaded prices**.
- **Farm/Fish**: source-specific level/skill checks when reference data supplies them, sale value per unit and per 20 units, market demand as context. It does **not** invent catch rates, hourly yields, or gold/hour.
- **Cook**: only actually learned/scanned recipes with priced ingredients and a positive projected margin; materials are charged at AH median, or a verified regular vendor baseline for three common spices. Output is valued at AH median less 5% fee.
- **Item hover / merchant flip**: bag tooltips compare conservative net AH proceeds to the vendor sell value; merchant stock tooltips compare net AH proceeds with the actual merchant purchase cost (including per-bundle quantity). The default minimum projected return is **30%**, adjustable with the **Flip minimum** selector in Settings or `/fcm flipmargin 35`. No buying/posting automation.

## AHledger boundaries

1. Run the companion's **AHledger Sync** on Windows and verify it is downloading current, correct Alliance/Horde/ruleset/region tables. Its 30-minute schedule is independent of this tab; FCM itself cannot fetch prices via HTTP.
2. AHledger's in-game scanner requires the **Auction House to be open**. Before posting, open AH, run `/ahl scan`, and examine the actual cheapest/current listing. An updated AHledger data file may require `/reload` or a fresh login before FCM can see it.
3. **Recheck loaded prices** only rereads prices already exposed to FCM by AHledger. It is **not** an AH scan or companion refresh button.
4. Prices with numeric provider observations more than three hours old are excluded; bundled snapshot estimates are excluded. Missing quotes are visibly **unpriced**, not guessed.
5. The median and lowest buyout represent **listing information, not guaranteed sales**. The market-wide sold/day estimate cannot predict one person's sales.

## In-game verification

- [ ] Log in on an Alliance character, load FCM, ensure Gold Finder appears and its filters switch views without UI errors.
- [ ] Check **Bags**: put known unbound, soulbound, and uncertain-binding items into bags; verify only confirmed-unbound value is counted in the primary total. Add and remove stacks, confirm the estimates change. Verify no bound-only row suggests an auction sale.
- [ ] Compare one priced item to the same faction/ruleset AHledger market. Confirm estimated net reflects item count and 5% cut.
- [ ] Recheck after a successful AH scan and newly downloaded price table; `/reload` if necessary; confirm the displayed scan date changes only when source data does.
- [ ] Test Fishing on a low-skill character and a higher-skill character; verify Feralas fish do not appear at low Fishing skill/level. Ensure the guide never reports a fabricated catch rate.
- [ ] Open Cooking, scan known recipes. Check one profitable recipe, one ingredient with no quote, and one unlearned recipe; only the valid positive-margin result should appear.
- [ ] Switch to a Horde character (or select a saved Horde character while logged in on Alliance). Confirm an unavailable Horde quote yields **no** false Alliance price.
- [ ] Disable AHledger or block its data update: FCM must show missing/unpriced info without crashing. SavedVariables must contain no downloaded AH tables, tokens or external personal uploads.
- [ ] Hover a normal merchant stock button and confirm the item's item ID, the merchant's actual gold price (including reputation discounts and bundles), AH lowest buyout, after-cut proceeds, and net percentage. Test a poor flip and a strong flip. Move the cursor from merchant stock into your bag with the merchant still open: bag price must not use the merchant purchase cost.
- [ ] Change Settings > Flip minimum from 30% to 50%, and try `/fcm flipmargin 35`. Confirm the same tooltip changes verdict without affecting the AH quote or buying anything.
- [ ] Check buyback, unavailable stock, items requiring alternate currency, and bind-on-pickup stock: no positive flip recommendation. Check an unbound bag stack, a soulbound bag stack, and an item whose binding state is unknown.
- [ ] Check a bundled AHledger price snapshot and a numeric scan timestamp older than 3 hours. Tooltips must say unverified/stale, not encourage spending gold.

## Local developer tests

From the repository root with a Lua interpreter exposing `loadfile`:

```
texlua tests/parse.lua
texlua tests/qa_gold_finder_v091.lua
texlua tests/qa_merchant_flip_v091.lua
texlua tests/qa_r61_cleanup.lua
```

Do not replace the installed addon's directory or publish a release until the in-game checklist is verified.
