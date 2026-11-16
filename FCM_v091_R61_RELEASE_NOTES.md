# Forever Character Manager v0.9.1 — R6.1 Tested Update

This update brings the approved R6 crafting and cross-faction QA work to the
public repository and adds the R6.1 inventory/vendor cleanup.

## Included

- Unassigned cross-character crafting request board with All, For Me, Can
  Craft, and Needs Materials views. Requests are gated by learned recipes,
  confirmed faction, ruleset, region, and bind-on-pickup output rules.
- Manual partial craft progress, manual delivery/archive, and preserved old
  requests through the board migration.
- Binding-aware per-stack bag/bank planning. Soulbound and unknown-binding
  stock never counts as a cross-character transfer; no mailing or crafting
  is automated.
- Tab-local search. Inventory no-match guidance explicitly refers to saved
  bag/bank snapshots; Item Explorer searches the reference catalogue.
- Shopping, Request details, and Item Explorer vendor/source reference hints,
  including sourced Fine Thread vendor examples marked unverified for current
  availability and price.
- Faction-safe profession search, character scan persistence, readable detail
  panels, gearing safeguards, and account-wide stored progress.
- One-word installer: on a confirmed WoW Forever installation, extract the
  archive, run `INSTALL-FCM-R61-Cleanup.cmd`, and type `INSTALL`. It checks
  `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`,
  remembers the last successful location, and prompts only if necessary.

## Safety

- Windows installer backs up replaced addon files to `%LOCALAPPDATA%\FCM-Backups`.
- Existing `*.generated.lua` imports and character SavedVariables are preserved.
- Local companion scripts, catalog refresh schedules, and user-owned reference
  data are not changed by this release.
- Vendor locations, AH prices, stock, and offline character inventories are
  historical references, not guaranteed current state.

## QA

- All 27 offline regression scripts passed against R6.1, including new R6
  request-board and R6.1 source-guidance checks.
- All 29 addon Lua files compiled under Lua 5.1 syntax checking.
- User confirmed R6.1's in-game workflow on their WoW Forever installation.
- Specific live soulbound-reagent transfer behavior remains a conservative
  safeguard covered by offline tests; no fabricated in-game test is claimed.

## Installer use

Completely exit WoW before running the installer. If it reports more than one
valid installation, choose the intended folder. Type `INSTALL` to back up and
merge. Restore the timestamped backup to roll back addon code; do not delete
SavedVariables.
