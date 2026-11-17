# FCM v0.9.2 — Gold toolbar layout hotfix

Released after in-game confirmation of the Gold tab layout correction on November 16, 2026 (America/Los_Angeles).

## Fixed

- The `Gold: AH fee assumptions` and `Gold: measured farm rate` controls now sit in a second row beneath the shared character/activity/role/Scan filters instead of overlapping them.
- The Gold item list and detail pane both reserve space for those controls.
- The report's visible layout was confirmed fixed by the tester after installing the patched `UI.lua` from `main`.

## Not changed

- Price-history ingestion, 365-day retention policy, AH fee/farm assumptions, sample-coverage thresholds, and conservative Buy/Hold/Sell ranking are unchanged. At least 14 observed dates, fresh prices, supply, estimated demand, and sufficiently stable history are required for ordinary eligible recommendations; these remain estimates, not actual completed-sale records.
- No personal AHledger files, private local history, credentials, or saved-character data are bundled with the source.

## Install

1. Exit WoW and the optional FCM companion, and back up the currently installed addon files plus your WTF SavedVariables.
2. Download the v0.9.2 release source ZIP from GitHub Releases.
3. Extract it and copy the inner `ForeverCharacterManager` addon folder (containing `ForeverCharacterManager.toc`) to `World of Warcraft\\_forever_\\Interface\\AddOns`, replacing program files.
4. Preserve your existing private AHHistory folder, local companion configuration, generated private price data, and WTF SavedVariables.
5. Start WoW; open `/fcm` → Gold to confirm the toolbar sits in its own row. The version should now display 0.9.2.

## Validation

- Gold spacing patch merged via [PR #3](https://github.com/PHOENIXHA1735/ForeverCharacterManager/pull/3).
- GitHub CI for the patch passed Lua 5.1 syntax/regression, synthetic AH-history/Gold Advisor tests, Windows companion safeguards, and source/privacy checks.
- This version bump/release metadata is additionally validated by the release PR CI. Some in-game paths and cross-faction screens still require continued live QA.
