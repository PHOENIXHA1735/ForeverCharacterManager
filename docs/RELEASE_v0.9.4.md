# FCM v0.9.4 release qualification

v0.9.4 is the proposed successor to the already-published v0.9.3. This candidate contains the Gathering browser and detail pane, Planner presentation and readiness fixes, Dungeon evidence and eligibility changes, and the reviewed history integration. The production addon uses FCM_DB and FCM_GatherExport. No release tag or publishing workflow is activated by this change.

## Build and inspection

From the repository root, use Python 3.12 or later:

    python tools/release/build_candidate.py <new-output-directory>
    python tools/release/overlay.py <client-root> <FCM-v0.9.4.zip> <trusted-ZIP-SHA256> <reviewed-baseline.json>

The first command builds an 87-file source-derived ZIP and independent per-file and ZIP SHA-256 lists. The second only inspects and prints a JSON operation plan. For qualification, pass a disposable fixture root and independently recorded hashes. The baseline JSON has static and preserve objects keyed by slash-separated client-relative paths, with SHA-256 strings as values. Static entries are previously approved addon files, including obsolete code approved for retirement. The preserve inventory covers the two FCM save files when present, five generated files, any existing Gathering reference, companion configuration and state, and task identity evidence. Record missing optional files explicitly only when that absence is intended. Never point rehearsal at a live layout.

The archive intentionally carries the source placeholders for PublicHistory and CommunityGathering. An existing file at either target always belongs in the preservation inventory. The overlay rejects missing required generated-state evidence, unexpected top-level Lua or TOC files, changed expected hashes, linked managed paths and existing candidate destinations without prior ownership. The fixture API supports atomic per-file replacement and a journal. Activation and recovery are guarded and restricted to disposable OS temporary directories. Only dry-run is exposed through the CLI. Live activation requires a separately integrated Windows writer gate and permission and ACL qualification. Do not use the legacy companion update button or a drag-and-drop overwrite for this upgrade. The v0.9.3 updater lacks the preservation and writer rules used here.

## Read-only writer inventory

The following enabled tasks were Ready during inspection. All use the root Task Scheduler folder.

| Task | Action | Schedule observed |
|---|---|---|
| FCM Auction House Price Refresh | System32 wscript.exe, installed FCM-Companion/FCM-HiddenTask.vbs | 30 minutes, start 2026-11-12 06:58:54 Pacific |
| FCM ForeverDB Build Check | System32 wscript.exe, same installed FCM-HiddenTask.vbs | 12 hours, start 2026-11-12 06:58:54 Pacific |
| FCM-AHHistory | System32 wscript.exe, %LOCALAPPDATA%/FCMTaskBackups/FCM-AHHistory-Hidden.vbs | 30 minutes, start 2026-11-19 10:10:45 Pacific |
| FCM-Private365-Update | %LOCALAPPDATA%/FCMRuntime/Python314/pythonw.exe, %LOCALAPPDATA%/FCMPrivateHistoryUpdater/app/updater.py | 5 minutes, start 2026-11-18 09:42 Pacific, plus daily midnight |

The installed wrapper directory is C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/ForeverCharacterManager/FCM-Companion. No installed overnight or morning catalog task appeared in this inventory. Recheck all tasks by task name and action path before deployment, including these optional tasks, manual GUI/CLI companion processes, WoW and Battle.net, wrappers and children, private updater, and Public30 publication. A one-time snapshot cannot rule out a later start. Record protected action arguments and process ancestry locally. Keep credentials and raw command lines out of reports.

## Future writer gate and rollback

1. After separate approval, capture task XML, enabled and running states, triggers, principals and task settings into a timestamped private recovery directory outside AddOns. Hash the XML and record actual executable, wrapper and target paths. Verify read and write permissions on the target and backup.
2. Close WoW, Battle.net and manual companion sessions and prevent user launches for the entire maintenance window. Verify each scheduled writer is idle, then temporarily disable only the approved tasks using their exact task name and folder. Recheck their disabled state and wait for any in-flight wrapper and child job to drain. Do not kill a running history process. Abort if any job cannot drain, any writer's state cannot be read, or the operator cannot prevent manual writers. An exclusive installer lock alone does not exclude companion processes that do not honor it.
3. Record a durable maintenance state with task identities and original settings before disabling any task. During a partial failure keep the writer gate in place until verified recovery. Back up and SHA-256 verify old static files and matching SavedVariables before activation. Record protected data hashes without migrating data. Do not bulk-copy live SQLite files or alter archives, runtime pointers, quotas or credentials. On Windows qualify the actual filesystem rename semantics, ACL preservation and permissions before enabling a production mode.
4. If interrupted, check whether the journal is pending, restoring, or committed, reacquire the gate, then verify the backup before restoring. The fixture recovery restores approved static changes and matching FCM saves, keeps copies of the failed state, and refuses to rewind drifted generated, quota, config or historical records. A missing/corrupt journal or backup requires manual reconciliation before reopening any writer.
5. When original or new files are verified, re-enable only tasks previously enabled and compare their definitions after normalizing the temporary Enabled difference. Leave previously disabled tasks disabled. There should be no initially running tasks in a deployment window. Allow the original schedules to resume naturally. Verify application-level success for normal 5-minute, 30-minute, and build-check cycles and confirm schema-2 Private365 binding and Public30 caps after login. Never reset budgets or checkpoints.

The current gate used by tests simulates a complete, idle, fenced writer census. It tests fail-closed behavior without changing any scheduled task. It is not evidence that a live task suspension and restoration procedure has been run.

## Windows writer-gate rehearsal

The disposable overlay now has a Windows byte-range lock for participating writers and a durable maintenance fence. Each enrolled writer must acquire the same lease before it opens or modifies any protected file and retain the lease until all child processes finish. Maintenance takes that lease before creating the fence and retains it through backup, activation, verification and automatic rollback. A launched writer fails immediately while maintenance owns the lease. If the process disappears, the OS releases the lock while the on-disk fence continues rejecting enrolled writers. Recovery must match the recorded path and task census. The fence remains when rollback fails or verification cannot be completed.

The Windows rehearsal used actual separate processes and invented task records for the four named jobs, plus a manual companion launch. Task records, data digests and file ACLs were compared before and after rehearsal. No Windows task was disabled, created or reconfigured; the rehearsal did not exercise Task Scheduler's registration or task restoration APIs. The ACL check covers the tested layout's inherited permissions and unchanged protected files. Restoration of production-specific explicit ACLs on replaced program files requires separate qualification.

Production enrollment remains blocked. The installed scheduled wrappers, manual companion GUI and CLI, direct helper scripts and private updater do not acquire this lease. An arbitrary process running as the same Windows account can bypass the lease. For live activation, first approve exact writer enrollment or independently enforced write exclusion. Gate every approved writer before its first write and retain the lease through child exit. Dry-run is the only live-facing installer mode. Qualify scheduled task suspension and restoration against disposable task registrations, then qualify filesystem permissions using a representative Windows layout before proposing activation. Keep the live tasks and ACLs intact during this phase.

The v0.9.4 companion retains the GitHub version check. Its Install and Restore buttons and corresponding handlers cannot install or replace files. Installed prior companion versions must not be used to activate this candidate.
