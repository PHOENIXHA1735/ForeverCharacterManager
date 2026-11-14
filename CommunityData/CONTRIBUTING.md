# Contribute FCM Gathering Locations

FCM stores personal discoveries locally. The companion's **Export Gathering Contribution** button writes a local `fcm-gathering-contribution.json` file after WoW is closed.

1. Inspect the file. It contains only `kind`, `mapID`, normalized `x`/`y` coordinates, and `name`. It must not contain SavedVariables, character names, account data, private inventory or GatherMate2 data.
2. Create a GitHub issue in this repository and attach the reviewed JSON, or submit a pull request updating the relevant category JSON.
3. Maintainers review coordinates, names, and duplicates before merging independently observed points into `herbalism.json`, `mining.json`, `fishing.json`, or `treasure.json`.
4. Increment `manifest.json` `version` when publishing new data. Companion users can then select **Sync Gathering (GitHub)** without installing a new FCM code version.

Public snapshots are a list of observed **possible** spawns, not live spawn guarantees. Do not submit locations imported from addons with incompatible redistribution terms, or fabricate / extrapolate coordinates.

The initial v1 dataset is intentionally empty. FCM does not automatically send data anywhere.
