# Forever Character Manager v0.9.3 — Gold Quote Freshness

Released November 16, 2026 (America/Los_Angeles), after synthetic Gold Advisor testing and GitHub verification.

## Fixed

- The Gold tab's current price now uses the **newest** timestamped observation in the selected faction/ruleset/region, including a newer personal auction scan. Previously an older provider table could override a newer personal scan.
- Personal scans do not include provider demand estimates. FCM may carry forward the provider demand estimate only when that observation is at most **seven days old**. Otherwise estimated demand remains unknown and recommendation eligibility fails closed.

## Unchanged safety rules

- Buy/Hold/Sell recommendations still require at least **14 distinct observed days**, a fresh quote, positive estimated demand and supply, and stable history. A recommendation is advisory, not an instruction to buy or a guaranteed sale.
- FCM still distinguishes Alliance from Horde and isolates regions/rulesets. Historical windows are 7, 30, 90, 180 and 365 days.
- The companion archives only personal AHledger SavedVariables by default. Third-party provider table retention still requires independent authorization and explicit opt-in.
- No private AHHistory scans, generated local history, saved characters, provider credentials, or user configuration are included in these release packages.

## Install without losing your history

1. Exit World of Warcraft and the optional companion. Back up the installed addon folder and `WTF` SavedVariables.
2. Download `FCM-v0.9.3.zip` from this release; extract it.
3. Copy the single extracted `ForeverCharacterManager` folder into `World of Warcraft\\_forever_\\Interface\\AddOns`, **merging and replacing program files only**. Do not delete the existing addon folder first.
4. Preserve the installed `ForeverCharacterManager\\AHHistory` folder, local `AHHistory.generated.lua`, any other generated data files, local companion settings and credentials, and the entire `WTF` folder.
5. Start WoW, open `/fcm` → Diagnostics and confirm version **0.9.3**. A companion refresh and subsequent login/reload are required for newly calculated Gold history to appear in game.

## Validation

- [PR #5](https://github.com/PHOENIXHA1735/ForeverCharacterManager/pull/5) passed synthetic history/Gold Advisor checks and Linux/Windows CI.
- The release verification checks version metadata, the five-window history processor, Gold Advisor rules, package contents, SHA-256 sums, and private-file exclusions.
- Windows Task Scheduler operation and in-game behavior remain installation-dependent; a successful automated test is not a substitute for the user's live client check.
