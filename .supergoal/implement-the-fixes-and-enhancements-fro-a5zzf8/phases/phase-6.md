SUPERGOAL_PHASE_START
Phase: 6 of 19 — Split CloudKitSync.swift & harden logging/retry
Task: Split CloudKitSync.swift into per-model files, replace print() with os.Logger, and add retry/backoff to writes.
Type: brownfield, refactor, reliability
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...; grep -c 'print(' BlindensportGraz/CloudKitSync*.swift
Acceptance criteria: 7
Evidence required: new file list+line counts, grep zero-print confirmation, build/test tails
Depends on phases: 5

## Why

audit.md's Architecture Finding 2 (921-line single-responsibility-violating file, will keep growing
linearly with every new model) + SwiftData & CloudKit Finding 1 (every write is fire-and-forget,
`print()`-only error handling invisible on a real device, no retry) — doing both together avoids
touching every push/pull function twice.

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first. Re-read `CloudKitSync.swift` (now using
  `CKSchema` constants from Phase 5) to plan the split.
- Split into per-model extension files, e.g. `CloudKitSync+Team.swift`, `CloudKitSync+TeamMembership.swift`,
  `CloudKitSync+Event.swift` (SportEvent/Training/Tournament may share one file given their inheritance
  relationship — check how the class hierarchy is structured before deciding), `CloudKitSync+EventImage.swift`,
  `CloudKitSync+Attendance.swift` (Training+Tournament attendance), `CloudKitSync+TrainingFavorite.swift`,
  `CloudKitSync+UserIdentity.swift`, `CloudKitSync+Member.swift`, `CloudKitSync+RoleChangeLog.swift`
  (from Phase 2) — one slim base file declares the `CloudKitSync` class/actor itself plus `syncAll()`
  and shared helpers (`upsert`, the retry helper added below).
- Replace every `print("CloudKitSync ... failed")` site (11 per audit.md, now possibly relocated by the
  split) with a dedicated `os.Logger` instance (e.g. `Logger(subsystem: "it.a11y.BlindensportGraz",
  category: "CloudKitSync")`), preserving the original message content.
- Add retry/backoff to push/delete operations: up to 3 attempts with short exponential backoff (e.g.
  0.5s/1s/2s) before giving up and logging a final failure via the new logger. No offline queue, no
  infinite retry — that's explicitly out of scope per audit.md's own framing of this as the achievable
  fix.
- Preserve `syncAll()`'s documented pull ordering exactly (pullUserIdentities → pullMembers → pullTeams
  → pullMemberships → pullEvents → pullTrainings → pullTournaments → pullEventImages →
  pullParticipations → pullAttendances → pullTrainingFavorites) — audit.md marks this correct
  (Positive Finding 5), don't touch it, just don't break it moving code between files.
- Preserve the `.changedKeys` last-write-wins conflict strategy and its doc comment on `upsert(...)`
  verbatim — an accepted, documented tradeoff, not something this phase changes.
- Update `.wolf/anatomy.md` for the new file layout.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] No CloudKit-sync-related file exceeds ~300 lines (down from 921 in one file)
- [ ] `grep -c 'print(' BlindensportGraz/CloudKitSync*.swift` returns 0
- [ ] Push and delete paths for every one of the 11 record types (12 counting RoleChangeLog if Phase 2
      landed it in CloudKitSync.swift) retry up to 3 times with backoff before logging final failure
- [ ] `syncAll()`'s pull ordering is byte-for-byte unchanged
- [ ] The `.changedKeys` conflict-strategy doc comment is preserved verbatim
- [ ] Full local unit test suite passes (aside from the known pre-existing `MemberImportExportTests`/`TrainingImportExportTests`
      crash)
- [ ] `.wolf/anatomy.md` reflects the new file layout

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `grep -c 'print(' BlindensportGraz/CloudKitSync*.swift`

## Evidence required in transcript

- New file list + `wc -l` per file
- `grep` output showing zero `print()` sites remain
- Build/test tails with exit codes

## Notes

If the SportEvent/Training/Tournament class-hierarchy push/pull functions are too intertwined to split
cleanly into separate files without duplicating shared logic, keep them together in one
`CloudKitSync+Events.swift` file rather than forcing an artificial 3-way split — the acceptance
criterion is "no single file over ~300 lines," not "exactly one file per model."

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
