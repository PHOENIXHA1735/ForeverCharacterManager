# Forever Character Manager v0.9.4 — release notes

**Status:** Release preparation only. This document does not authorize a live installation.

This release is based on reviewed source commit `1cf3f733b8132e565b0418f318de90a84a128d50` (main after PR #8 and PR #9). The source-derived package has 89 files. The approved GitHub-built candidate archive SHA-256 is `2ddb8f081a37f227d561c5c45dd27e03f27bfa50545fcbd0e724a85468296d06`. A separately uploaded ZIP has the same extracted file hashes but a different archive hash; installers must verify the exact ZIP used and must not silently substitute one archive for another.

## Included

- Gathering resource browser and material detail pane with source/evidence visibility.
- Planner presentation, readiness, and eligibility improvements.
- Dungeon loot/source evidence and eligibility refinements.
- Reviewed AH history provider integration and additional writer coordination.
- Version 0.9.4 in both addon TOC manifests and core version metadata.

## Data and update rules

The addon uses `FCM_DB` and `FCM_GatherExport` SavedVariables. Never distribute or delete a player's `WTF` data, generated Lua reference files, personal AH history, quotas, credentials, or companion settings. Public GitHub packages contain source placeholders, **not** any player's private data. AHledger remains optional. Do not use the older companion Install/Restore buttons, and do not perform a manual drag-and-drop overwrite of a production installation.

## Prerequisites before publishing as a live release

The release maintainer must independently qualify the production Windows deployment with a representative NTFS/ACL layout, task suspension and resumption, approved writer enrollment/exclusion, unchanged saved data and generated files, and verified interrupted-update rollback. Complete the separate Windows PE/offline NTFS rehearsal documented for this candidate. Review the exact installed task identities, including AH Refresh, ForeverDB Build Check, AH History, and Private365. Preserve existing state and resume only those tasks that were enabled beforehand.

The repository's offline tests, checksum verification, and disposable-fixture success do not replace that live Windows qualification. **Do not install v0.9.4 on a live WoW account merely because a ZIP or GitHub Release exists.**

See [v0.9.4 qualification](docs/RELEASE_v0.9.4.md) for the full writer-gate and rollback requirements.
