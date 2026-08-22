SUPERGOAL_PHASE_START
Phase: 2 of 6 — SwiftData & CloudKit sync audit
Task: Audit BlindensportGraz's manual public-database CloudKit sync layer against best practices; produce report/02-swiftdata-cloudkit.md
Type: brownfield, review
Mandatory commands: grep -n "print(" BlindensportGraz/CloudKitSync.swift | wc -l ; grep -c "Task {" BlindensportGraz/CloudKitSync.swift
Acceptance criteria: 4
Evidence required: command outputs, report finding count + first 3 findings
Depends on phases: none

## Why

This is the app's most architecturally unusual and highest-risk layer (manual public-DB CloudKit sync
that deliberately bypasses SwiftData's native per-user CloudKit mirroring, since the app requires
cross-user visibility of shared data) and the user explicitly named "SwiftData & iCloud sync" as a
focus area in Stage 1 intake.

## Work

- Read `BlindensportGraz/CloudKitSync.swift` in full (it's ~921 lines / 46KB — read it, this phase's
  entire subject is this file).
- Read `BlindensportGraz/BlindensportGrazApp.swift` (ModelContainer setup + the destructive-reset
  fallback on schema-mismatch).
- Grep `.wolf/cerebrum.md` for "CloudKit" and "sync" to pick up any additional documented history
  beyond what's already in THINKING.md's "already-known findings" section.
- Audit and write findings for:
  - **Fire-and-forget push/delete** — every `Task { do { try await ... } catch { print(...) } }` site
    (push/delete for Team, Membership, User, Member, EventImage, TrainingFavorite, etc.) has no retry,
    no offline queue, and reports failure only via `print()` to stdout — invisible in a real device's
    Console.app/sysdiagnose search (should be `os.Logger`), and completely invisible to the end user
    (no UI ever reflects "this change didn't sync"). Use the mandatory command outputs as evidence for
    scale (how many print sites, how many fire-and-forget Tasks).
  - **`.changedKeys` last-write-wins conflict strategy** — cite the existing doc comment directly above
    `private func upsert(_ record: CKRecord)`. This is a **documented, deliberate** choice (frame it as
    an accepted tradeoff), but still note the residual risk: two admins editing the same record offline
    around the same time will silently have one edit clobber the other with zero user-visible warning,
    and there's no way to know it happened after the fact.
  - **No user-visible sync/pending state** — confirm via grep/reading Views whether any screen shows
    "syncing…", "sync failed", or a last-synced timestamp anywhere. Expect none; if found, note where.
  - **`BlindensportGrazApp.swift`'s destructive local-store reset** — on `ModelContainer` init failure
    (e.g. schema mismatch), the app wipes the local store and starts fresh, relying on `syncAll()` to
    fully repopulate from CloudKit. The code's own comment says this is deliberate and only loses
    "truly offline-only, never-synced" local edits — but given fire-and-forget push means the app can
    never actually confirm a push succeeded, "never-synced" is not verifiable at the point the reset
    happens. Flag this specific gap: the reset's safety assumption depends on push reliability the app
    itself doesn't guarantee.
  - **`syncAll()` pull ordering** — read how `syncAll()` sequences pulls (e.g. TrainingAttendance
    documented as "pulled last... since it depends on both memberships and trainings already being
    resolved locally"). Confirm the actual pull order in code matches this documented dependency graph
    and flag anything that looks like it could race.
  - **Query scale** — this app uses ONE shared CloudKit public database for what's currently one
    club's data. Check whether any `@Query` in the Views files fetches without a predicate/limit in a
    way that would not scale if this club's data (or a future multi-club deployment, if that's ever
    pursued — see phase 5) grew significantly larger.
  - **Schema/record-type coupling** — note that CKRecord type/field names are hand-maintained strings
    scattered across `CloudKitSync.swift` with no central schema constant file (e.g. `"clubMemberID"`
    field name deliberately kept for wire compatibility per a comment) — assess how error-prone this
    is for future field renames, referencing the multi-file "field rename checklist" pattern documented
    repeatedly in cerebrum.md's Key Learnings as evidence this has already been a recurring source of
    multi-file changes.
- Tag each finding `Severity: High/Medium/Low` and `Effort: S/M/L`. Explicitly mark tradeoff-framed
  findings as such in the Severity line, e.g. `Severity: Medium (accepted tradeoff, residual risk)`.
- Write `report/02-swiftdata-cloudkit.md` in the same format as phase 1's report.

## Acceptance criteria (all must pass — verify each in transcript)

- At least 8 concrete findings, each with a `file:line` citation.
- Explicitly covers all seven bullets under Work's "Audit and write findings for" list above.
- Distinguishes "accepted tradeoff, note residual risk" findings from "actual gap, should fix"
  findings in the Severity line — don't conflate them.
- Every finding tagged with both Severity and Effort.

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `grep -n "print(" BlindensportGraz/CloudKitSync.swift | wc -l`
- `grep -c "Task {" BlindensportGraz/CloudKitSync.swift`

## Evidence required in transcript

- Both command outputs above, pasted verbatim.
- `report/02-swiftdata-cloudkit.md`'s total finding count and its first 3 findings printed in full.

## Notes

No code changes. This phase's file (`report/02-swiftdata-cloudkit.md`) is read by phase 3 — write it
clearly enough to be referenced, not just internally consistent.
