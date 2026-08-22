SUPERGOAL_PHASE_START
Phase: 8 of 19 — Extract persistence+sync service layer
Task: Wrap modelContext.save() + CloudKitSync.shared push/delete calls in a per-model service layer with consistent error handling, and migrate all view-layer call sites to it.
Type: brownfield, refactor
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...; grep count for direct CloudKitSync.shared calls in views
Acceptance criteria: 6
Evidence required: before/after call-site counts, service layer diff, one migrated view diff, build/test tails
Depends on phases: 6, 7

## Why

audit.md's Architecture Finding 1 (60 view-layer call sites directly drive `CloudKitSync.shared`, no
service/viewmodel layer), Finding 6 (98 `try?` silent-failure sites, no consistent error policy), and
Finding 8 (save-then-sync duplicated verbatim everywhere) — the same underlying gap, closed together.

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first. Grep `CloudKitSync.shared` across all view files
  to get the real current call-site count and inventory which model each site touches.
- Inspect how uniform the 11 (12 with RoleChangeLog) models' save+push/delete patterns actually are.
  Build either one generic `SyncedModelService<T>` if the pattern is truly uniform enough, or one
  service per model (`TeamService`, `TrainingService`, etc.) if the models' mutation shapes differ
  meaningfully — decide based on what's actually in the code, not an assumption.
- Each service call wraps: `modelContext.save()` (do/catch, not `try?`) → on success, call the
  corresponding `CloudKitSync.shared.push*`/`delete*` (which now itself retries/logs per Phase 6) → on
  local save failure, log via Phase 6's `os.Logger` and surface a user-facing failure signal WITHOUT
  attempting the CloudKit push (a local save failure means there's nothing valid to push yet).
- Add a lightweight failure-signal mechanism (e.g. an `@Observable`/`@Published` error state consumed by
  an alert/toast at the app or screen level) wired specifically into admin-critical actions: role changes
  (`UserListView`) and roster edits (`Member`/`MembersViews.swift`) — audit.md's stated priority, not
  necessarily every single save in the app.
- Migrate all ~60 existing view-layer call sites from the old `modelContext.save()` +
  `CloudKitSync.shared.push*` inline pattern to the new service layer, one model type at a time so the
  test suite can catch regressions incrementally rather than in one giant diff.
- Add tests for the service layer's failure path: simulate a save failure (e.g. an invalid in-memory
  container state) and confirm the failure signal fires AND the CloudKit push is never attempted.
- Update `.wolf/anatomy.md` for the new service files; add a `.wolf/cerebrum.md` Key Learnings entry
  documenting the new service layer as the pattern all future model mutations should follow (this is
  exactly what that section exists for).

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] `grep -rn "CloudKitSync.shared" BlindensportGraz --include="*.swift"` shows remaining hits
      confined to the new service layer and `CloudKitSync*.swift` itself — zero direct calls left in
      view files
- [ ] `grep -rc 'try? modelContext.save()' BlindensportGraz --include="*.swift"` drops sharply; any
      remaining raw `try?` site outside the service layer has a code comment justifying why
- [ ] Role changes and roster edits show a visible failure indicator if the underlying save+sync fails
      — verified by a test or a clear code-level trace from failure to UI signal
- [ ] All 11 (12 with RoleChangeLog) model types have working create/update/delete through the new
      service layer — none left on the old inline pattern
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions), plus new tests for the service layer's failure path
- [ ] `.wolf/anatomy.md`/`.wolf/cerebrum.md` updated documenting the new pattern

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `grep -rn "CloudKitSync.shared" BlindensportGraz --include="*.swift" | wc -l`

## Evidence required in transcript

- Before/after count of direct `CloudKitSync.shared` call sites in view files
- The new service layer's file(s) + one migrated view file's diff as a representative example
- Build/test tails with exit codes

## Notes

This is the phase every later enhancement phase (14-18) depends on — take the time to make the service
layer's call shape genuinely pleasant to extend (e.g. `TrainingService.save(_:)`/`.delete(_:)` style),
since Phases 14-18 will each add new mutation call sites through it.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
