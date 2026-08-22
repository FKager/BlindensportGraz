SUPERGOAL_PHASE_START
Phase: 10 of 19 — Sync status & offline UX
Task: Add a visible syncing/synced/failed indicator, offline detection with messaging, and harden the destructive local-store-reset fallback.
Type: brownfield, feature, reliability
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...
Acceptance criteria: 5
Evidence required: sync-state surface code, reset-fallback diff, build/test tails
Depends on phases: 6

## Why

audit.md's SwiftData & CloudKit Finding 3 (no user-visible sync/pending state anywhere) + Finding 4 (the
destructive local-store-reset fallback's safety assumption isn't actually verifiable, since pushes are
fire-and-forget) + Enhancements #3 and #4 (visible sync status indicator, offline-mode messaging) — the
same "does the user know what's happening to their data" theme.

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first. Read `BlindensportGrazApp.swift:26-51`'s
  ModelContainer-init-failure / local-store-reset fallback in full.
- Add a lightweight app-wide sync state (syncing / synced / failed, with a last-synced `Date`), driven by
  real push/pull activity from Phase 6's retry/logging infrastructure and Phase 8's service layer — not
  a static decoration. Surface it as a small banner or icon somewhere globally visible (e.g. in
  `DashboardView` or a toolbar item reused across screens).
- Add network reachability detection (e.g. `NWPathMonitor`) and show a "you're offline, changes will
  sync once reconnected" message when offline, clearing automatically when connectivity returns.
- Harden `BlindensportGrazApp.swift`'s destructive-reset fallback: before wiping the local store, check
  the new sync-state tracking for any known-pending/unconfirmed-synced writes where feasible; if a full
  pending-write check isn't practical within this phase's scope, at minimum make the reset path log via
  Phase 6's `os.Logger` exactly what it's about to discard and why, replacing the current silent
  assumption with an honest, inspectable trail.
- Do not change `syncAll()`'s pull ordering or the `.changedKeys` conflict strategy — both are unrelated,
  already-correct/accepted per audit.md.
- Update `.wolf/anatomy.md`/`.wolf/memory.md` per the OpenWolf protocol.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] A visible sync-state indicator exists and updates in response to real push/pull activity —
      confirmed via a test or a clear code trace from a push call through to the state update
- [ ] Going offline (simulated via a mockable/testable reachability abstraction) shows the offline
      message; reconnecting clears it
- [ ] The local-store-reset path no longer proceeds silently — it checks for pending unsynced writes
      first, or at minimum clearly logs what it's about to discard and why
- [ ] No regression to `syncAll()`'s pull ordering or the `.changedKeys` conflict strategy
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions)

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- The new sync-state surface's code + a description of what drives its transitions
- The hardened reset-fallback diff in `BlindensportGrazApp.swift`
- Build/test tails with exit codes

## Notes

Don't over-build this into a full offline-write-queue — audit.md frames the achievable fix as
visibility (does the user know?), not a durability guarantee (an actual offline queue is a bigger,
separate undertaking not in this audit's explicit findings).

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
