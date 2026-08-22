SUPERGOAL_PHASE_START
Phase: 5 of 19 — Centralize CloudKit schema constants
Task: Create CKSchema.swift with named constants for every CKRecord type/field name, and use it throughout CloudKitSync.swift.
Type: brownfield, refactor
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...
Acceptance criteria: 5
Evidence required: grep before/after counts, build/test tails
Depends on phases: 1

## Why

audit.md's Architecture Finding 7 + SwiftData & CloudKit Finding 7 — every CKRecord type/field-name is a
literal string scattered through `CloudKitSync.swift`; a typo'd literal fails silently at the CloudKit
layer instead of at compile time. Doing this before Phase 6 splits the file means the split reuses these
constants from the start instead of needing a second pass.

## Work

- Check `.wolf/anatomy.md` for `CloudKitSync.swift`'s current summary before reading it in full — it's
  ~921 lines, read it once carefully since this phase and Phase 6 both depend on understanding it fully.
- Create `BlindensportGraz/CKSchema.swift` with a `CKSchema` enum/namespace containing nested constants
  for all 11 CKRecord types' record-type names and every field name used on each, grouped clearly (e.g.
  `CKSchema.Team.recordType`, `CKSchema.Team.name`, `CKSchema.Team.members`, ...).
- Find the documented field-name mismatch (wire-compat `clubMemberID` near `pushMembership` — search for
  the exact comment) and preserve it exactly: the constant's name/value keeps the deliberate mismatch,
  and the original explanatory comment moves with it to the constant declaration, not lost.
- Replace every literal record-type/field-name string in `CloudKitSync.swift` with the corresponding
  `CKSchema.*` constant. Do this mechanically and completely — don't leave a mix of literals and
  constants.
- Do not change any logic, push/pull ordering, retry behavior, or error handling in this phase — this is
  a pure rename/extract, verified by the full test suite passing identically to before.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] `CKSchema.swift` exists with constants for all 11 CKRecord types and their fields
- [ ] Raw record-type/field-name string literals in `CloudKitSync.swift` (outside of `CKSchema.swift`
      itself) are eliminated or reduced to near-zero — verify via grep
- [ ] The documented `clubMemberID` field-name mismatch is preserved with its original explanatory
      comment, now attached to the constant
- [ ] No behavior change: full local unit test suite passes identically to its pre-phase state (same
      pass/fail set, modulo the known pre-existing `MemberImportExportTests`/`TrainingImportExportTests` crashes)
- [ ] `.wolf/anatomy.md` updated with the new file's entry

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- `grep -c '"[A-Z][a-zA-Z]*"' BlindensportGraz/CloudKitSync.swift` before/after counts
- Build/test tails with exit codes

## Notes

Pure refactor phase — resist the urge to also fix anything else you notice in CloudKitSync.swift while
you're in there (logging, retry, splitting) — those are Phase 6's explicit job, done right after this
one so nothing gets touched twice unnecessarily, but scope creep here just makes this phase's own
acceptance criteria harder to verify cleanly.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
