# Roadmap: Implement audit.md fixes & enhancements — BlindensportGraz

**Task:** Implement every actionable finding from `audit.md` (BlindensportGraz Best-Practices Audit,
2026-08-19) across Architecture, SwiftData & CloudKit sync, Security & account administration, and
Accessibility, plus the enhancement/feature backlog — as real code changes, in small ordered phases,
skipping only findings marked "Positive — no fix needed" and P2 enhancement #12 (multi-club, explicitly
excluded by the user).
**Type:** brownfield, refactor, security-hardening, accessibility, feature-additions
**Created:** 2026-08-20
**Total phases:** 19

## Context summary

- **Stack:** SwiftUI + SwiftData (local store) + manual CloudKit public-database sync layer
  (`CloudKitSync.swift`), iOS 26.0 minimum deployment target, XcodeGen-generated project (`project.yml`
  → `BlindensportGraz.xcodeproj`, never hand-edited — any new/removed/renamed Swift file requires
  `xcodegen generate`). Companion SPM package `RootCLI/` (Vapor admin web tool + `rootcli` CLI +
  `CloudKitS2SCore` shared library), macOS-only, `swift build`.
- **Package manager:** SwiftPM (ZIPFoundation for the app; NIO/Vapor/crypto for RootCLI).
- **Build / test / lint commands:** `xcodegen generate`; `xcodebuild build -project
  BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination
  'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`; `xcodebuild test`
  with the same flags plus a concrete simulator destination from `xcrun simctl list devices available`
  (confirmed runnable in this sandbox — local `xcodebuild`/codesign for **device** targets is blocked,
  simulator build/test is not); `cd RootCLI && swift build`. No project lint tool configured.
- **Risky areas:** the CloudKit public-DB security posture, the admin-role escalation logic (now the
  user's own only path to admin), near-zero accessibility coverage, fire-and-forget sync writes, and
  the large mechanical refactors (file splits, enum migration, service-layer extraction) that touch
  nearly every view file.

## Assumptions

- CloudKit Dashboard "Security Roles" configuration (Security Finding 2) cannot be applied from this
  environment (no CLI/API found for it) — Phase 4 produces documentation/a checklist for the user to
  apply manually, not automated enforcement.
- New CKRecord types added by later phases (RoleChangeLog, receipt attachments) will need the same
  manual Dashboard/Production-environment attention flagged in Phase 4 — each phase that adds one notes
  this explicitly; Phase 19 compiles the full manual-follow-up list.
- `franz.kager@gmx.net` (this user) has admin only via the `testAdminEmail` backdoor being removed in
  Phase 1 — real admin is granted via RootCLI's `set-role` BEFORE the backdoor code is deleted, per the
  user's confirmed answer.
- P2 enhancement #12 (multi-club/multi-section extensibility) is excluded from this run per explicit
  user decision — not attempted, not partially scaffolded.
- The RootCLI/app shared-schema-package phase (Phase 9) creates a genuine new local SwiftPM package
  (plain Codable types + Foundation only, no CloudKit/Vapor imports) consumed by both `project.yml` and
  `RootCLI/Package.swift`, rather than a lighter documentation-only mitigation — this is the real fix
  the audit describes, scoped down to a dependency-free package to keep the build-system risk low.
- Device-level build verification (the one thing that can't be checked locally) happens once, in Phase
  19, via the existing `deploy` skill / self-hosted GitHub Actions workflow — not on every phase, to
  avoid repeatedly disturbing the user's physical iPhone.

## Risk top 3

1. **Large unsupervised refactors (file splits, enum migration, service-layer extraction) silently
   break sync or role logic.** — likelihood: medium, mitigation: each is its own small phase, each
   required to pass the full local unit test suite before advancing, enum migration is additive/back-compat
   (no destructive data migration), 3-strike failure recovery catches real breaks.
2. **Removing the `testAdminEmail` backdoor before confirming real admin access works locks the user
   out.** — likelihood: low if sequenced correctly, mitigation: Phase 1 grants + verifies real admin via
   RootCLI before touching the backdoor code, in that order, as its own gated step.
3. **New CKRecord types/schema changes can't be verified against the real CloudKit Production
   environment from this sandbox.** — likelihood: medium, mitigation: every phase adding a new record
   type documents the manual Dashboard step it needs; Phase 19 surfaces the consolidated list to the
   user as an explicit non-code follow-up, not silently assumed done.

## Phase map

| # | Phase | Depends on | Deliverable |
|---|-------|------------|-------------|
| 1 | Remove test-admin backdoor & fix doc drift | — | Backdoor gone, real admin granted, in-app CLAUDE.md corrected |
| 2 | Role-change audit log | 1 | `RoleChangeLog` model + CKRecord + UI wiring |
| 3 | Role tests & input validation | 1, 2 | Unit tests for role escalation; email/IBAN/SVNR soft validation |
| 4 | CloudKit access-control hardening & docs | — | RootCLI README Security Roles section (all 11 types), TLS note, auth rate-limiting |
| 5 | Centralize CloudKit schema constants | 1 | `CKSchema.swift` |
| 6 | Split CloudKitSync.swift & harden logging/retry | 5 | Per-model sync files, `os.Logger`, retry/backoff |
| 7 | Split Models.swift & closed role/sport enums | 6 | Per-model files, `Role`/`Sport` enums with legacy normalization |
| 8 | Extract persistence+sync service layer | 6, 7 | Per-model service helpers; views stop calling CloudKitSync/modelContext directly |
| 9 | Shared schema package (app + RootCLI) | 6 | New local SwiftPM package, both targets depend on it |
| 10 | Sync status & offline UX | 6 | Syncing/synced/failed indicator, offline messaging, safer store-reset fallback |
| 11 | Query predicates & subscription retry | 6 | Predicated `@Query`s where it matters, subscription registration retry |
| 12 | Accessibility labels & control equivalents | 1 | accessibilityLabel/Hint coverage, contextMenu accessibilityAction, Picker hints |
| 13 | Accessibility Dynamic Type pass | 12 | Dynamic Type verified/fixed across dense rows & forms |
| 14 | Local reminder notifications | 8 | `UNCalendarNotificationTrigger` reminders for Training/Tournament |
| 15 | Attendance-trends dashboard | 8 | Swift Charts view over TrainingAttendance/TournamentAttendance |
| 16 | Season/year reporting rollup | 8 | Extends `SammelabrechnungExporter` to a full-season bundle |
| 17 | Calendar/EventKit integration | 8 | Add-to-Calendar for Training/Tournament |
| 18 | Receipt/document attachments | 8 | `EventImage`-pattern attachments for KostZ/PRAE |
| 19 | Polish & Harden | 1–18 | Every aspect verified, manual-follow-up list, one real device smoke check |

---

## Phase 1 — Remove test-admin backdoor & fix doc drift

**Why:** audit.md's #1 finding — a live TEST-ONLY admin grant for the user's own real email, a month
past its own removal note. Fix this before anything else touches Models.swift.

**Deliverables:**
- `Models.swift` with `testAdminEmail`/`elevateIfTestAdmin` and all call sites removed
- `franz.kager@gmx.net` granted real admin via `rootcli set-role` beforehand (verified, not assumed)
- `BlindensportGraz/CLAUDE.md` (in-app doc) corrected: no `username` field, roster class is `Member`
  not `ClubMember`, model count matches the real 11 `@Model` classes (Architecture Finding 4)

**Acceptance criteria:**
- [ ] `rootcli set-role` (or equivalent RootCLI command) run against the real CloudKit container to
      grant `franz.kager@gmx.net` `role = "admin"` (or root, whichever the tool supports), and the
      grant is verified by reading the record back (e.g. `rootcli list` / a query showing the updated
      role) BEFORE any Models.swift edit
- [ ] `grep -n "testAdminEmail\|elevateIfTestAdmin" BlindensportGraz/*.swift` returns no results
- [ ] All former call sites of `elevateIfTestAdmin()` (login, registration, email-edit — 4 sites per
      audit.md) compile and behave correctly with the call removed (no dangling references)
- [ ] `BlindensportGraz/CLAUDE.md` no longer mentions `username` or `ClubMember`; describes the actual
      11 `@Model` classes and the real roster class name (`Member`)
- [ ] `.wolf/cerebrum.md` gets a Decision Log entry noting the backdoor's removal date and that real
      admin was granted first (so a future session doesn't reintroduce a similar shortcut)
- [ ] Full local unit test suite passes (see Mandatory commands)

**Mandatory commands:**
- `cd RootCLI && swift build`
- The RootCLI `set-role` invocation itself, with its output showing success, and a follow-up read-back
  command confirming the new role
- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<a device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (MemberImportExportTests crash is a known pre-existing issue, not a regression — see THINKING.md)

**Evidence required:**
- RootCLI grant + read-back output pasted into transcript, showing the real role before Models.swift is touched
- `grep` output confirming zero `testAdminEmail`/`elevateIfTestAdmin` hits
- Build + test command tails with exit codes

**Dependencies:** none

---

## Phase 2 — Role-change audit log

**Why:** P0 enhancement #2, directly follows Security Findings 1 & 2 — no history of role changes exists
today; a small audit trail would have made Phase 1's very finding visible after the fact.

**Deliverables:**
- New `@Model` `RoleChangeLog` (user id, old role, new role, changed-by identifier, timestamp) in
  Models.swift (or its own file if Phase 1's doc cleanup already anticipates the eventual per-model
  split — either is fine, Phase 7 will move it into the split layout regardless)
- CloudKit push/pull for the new record type in `CloudKitSync.swift`
- Every role-mutation call site writes a `RoleChangeLog` entry: `UserListView`'s role editor,
  `elevateIfDesignatedRoot`, and RootCLI's `set-role` path (server-side write via `CloudKitS2SCore`)
- A read-only admin-visible screen/section listing recent role changes (reuse an existing admin list
  pattern, e.g. alongside `UserListView`)

**Acceptance criteria:**
- [ ] `RoleChangeLog` has all 5 documented fields, synced via the same public-DB push/pull pattern as
      every other model
- [ ] Changing a role via `UserListView` creates exactly one `RoleChangeLog` entry with correct old/new
      values and a `changed-by` identifier for the acting admin/root
- [ ] `elevateIfDesignatedRoot`'s auto-grant on first-account bootstrap also logs an entry
- [ ] RootCLI's `set-role` command writes a `RoleChangeLog` record via `CloudKitS2SCore` (server-side,
      no app running) — confirmed by a `swift build` pass and a code-level check (no live CloudKit
      write from this sandbox is expected to succeed without credentials, so this criterion is verified
      by code review + successful compile, not a live write)
- [ ] A new admin-only UI surface (or extension of `UserListView`) shows the log, newest first
- [ ] Full local unit test suite still passes; add at least 2 new unit tests exercising the audit-log
      write path against an in-memory `ModelContainer`

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (same flags as Phase 1)
- `xcodebuild test ...` (same flags/destination pattern as Phase 1)
- `cd RootCLI && swift build`

**Evidence required:**
- The new `RoleChangeLog` model + CloudKitSync push/pull diff shown in transcript
- New test names + pass output
- Build/test command tails with exit codes

**Dependencies:** Phase 1

---

## Phase 3 — Role tests & input validation

**Why:** Security Finding 3 (zero test coverage on role-escalation logic, with a documented multi-session
bug history — bug-173) and Findings 4/5 (no email format validation, no IBAN/SVNR validation) plus
Enhancement #7.

**Deliverables:**
- `BlindensportGrazTests` coverage for `elevateIfDesignatedRoot`: requires all three of first/last/email
  together, case-insensitive, doesn't fire on partial match, doesn't re-fire once already root
- A regression test confirming `testAdminEmail`/`elevateIfTestAdmin` no longer exist (grep-based test or
  a compile-time check) so Phase 1's fix can't silently regress
- Email format validation on `AccountView.swift`/`RootView.swift`'s email fields (non-blocking or
  blocking per existing form conventions — match whatever the surrounding form already does for
  required-field validation)
- Soft, non-blocking IBAN checksum + Austrian SVNR pattern validation on `Member.iban`/`Member.svnr`
  entry points, surfaced as a warning (not a hard block — audit.md explicitly notes roster data is
  regularly bulk-imported from messy real-world spreadsheets)

**Acceptance criteria:**
- [ ] At least 6 new unit tests for `elevateIfDesignatedRoot` covering: full match grants root, missing
      any one of first/last/email does not grant, case-insensitive match still grants, whitespace-padded
      match still grants, already-root does not re-grant/re-log, and confirmed no `elevateIfTestAdmin`
      symbol exists anywhere in `BlindensportGraz/*.swift`
- [ ] Email fields reject/warn on obviously malformed input (no `@`, no domain) without blocking already
      malformed pre-existing data from being viewed/edited
- [ ] IBAN/SVNR fields show a non-blocking warning (e.g. a small inline hint or icon) for
      checksum/pattern failures but never prevent saving
- [ ] Existing malformed sample data (if any exists in test fixtures) still imports/loads successfully —
      validation must not become a hard gate anywhere in the import path
- [ ] Full local unit test suite passes, including the new tests

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`

**Evidence required:**
- New test names + pass output for all 6+ role-escalation tests
- Before/after snippet of the email/IBAN/SVNR validation UI code
- Confirmation the import path test(s) still pass with malformed sample data

**Dependencies:** Phase 1, Phase 2

---

## Phase 4 — CloudKit access-control hardening & docs

**Why:** Security Finding 2 — CloudKit's public DB defaults to World read/write; the app's 34+ role
checks are entirely client-side, and the existing hardening doc only names 2 of 11 record types.
Findings 8 & 9 (TLS deployment note, RootCLI auth rate limiting) are grouped here as the same
"access-control hardening" theme.

**Deliverables:**
- `RootCLI/README.md`'s "Security Roles" section rewritten to name and give guidance for **all 11**
  CKRecord types (Team, TeamMembership, SportEvent, Tournament, Training, EventImage,
  TrainingAttendance, TournamentAttendance, TrainingFavorite, UserIdentity, ClubMember/Member), for
  both Development and Production environments explicitly
- An explicit "must be deployed behind HTTPS/TLS" note added to `RootCLI/README.md` for
  `clubmembersapi`
- Basic rate limiting / lockout on repeated failed `clubmembersapi` Basic Auth attempts
  (`RootCLI/Sources/clubmembersapi/Auth.swift`/`Configure.swift`) — an in-memory sliding-window or
  fixed-window limiter is sufficient for a small club's internal tool, document the choice

**Acceptance criteria:**
- [ ] README's Security Roles section lists all 11 record types with the recommended role
      configuration for each (not just UserIdentity/ClubMember)
- [ ] README explicitly states Development and Production are configured separately in CloudKit
      Dashboard and both need the hardening applied
- [ ] A new "Deployment / TLS" note exists in the README stating `clubmembersapi` must run behind a
      TLS-terminating reverse proxy or load balancer — not equivalent to "TLS is optional"
- [ ] `clubmembersapi` returns 429 (or closes the connection) after N failed auth attempts from the
      same client within a time window, verified by a `swift build` pass and a code-level walkthrough
      (no live server needed to verify the middleware logic compiles and is wired into the request
      pipeline)
- [ ] Existing valid-credential requests are unaffected by the new limiter (no regression to normal
      auth flow)
- [ ] `swift build` passes for RootCLI with the new middleware

**Mandatory commands:**
- `cd RootCLI && swift build`

**Evidence required:**
- README diff showing all 11 record types
- The rate-limiting middleware code + a description of its window/threshold choice
- `swift build` output with exit code

**Dependencies:** none

---

## Phase 5 — Centralize CloudKit schema constants

**Why:** Architecture Finding 7 + SwiftData & CloudKit Finding 7 — every CKRecord type/field-name is a
literal string scattered through `CloudKitSync.swift`; a typo fails silently at the CloudKit layer, not
at compile time. Doing this before splitting the file (Phase 6) means the split can use the new
constants from the start instead of being redone.

**Deliverables:**
- New `CKSchema.swift` (or similarly named file) with a `CKSchema` enum/namespace of nested
  record-type and field-name constants for all 11 CKRecord types
- `CloudKitSync.swift` updated to use `CKSchema.*` constants everywhere a literal record-type or
  field-name string currently appears (the one deliberately-mismatched field — `clubMemberID` per the
  existing comment near `pushMembership` — keeps its documented mismatch, just as a named constant with
  the same explanatory comment preserved)

**Acceptance criteria:**
- [ ] `grep -c '"[A-Z][a-zA-Z]*"' BlindensportGraz/CloudKitSync.swift` (raw record-type string literals)
      drops to near-zero outside of `CKSchema.swift` itself
- [ ] Every CKRecord type used anywhere in `CloudKitSync.swift` has a corresponding `CKSchema` constant
- [ ] The documented field-name mismatch (wire-compat `clubMemberID`) is preserved with its original
      explanatory comment, now attached to the constant declaration
- [ ] No behavior change — full local unit test suite passes identically to before this phase
- [ ] `.wolf/anatomy.md` updated with the new file's entry

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`

**Evidence required:**
- `grep` before/after counts of raw string literals in CloudKitSync.swift
- Build/test tails with exit codes

**Dependencies:** Phase 1

---

## Phase 6 — Split CloudKitSync.swift & harden logging/retry

**Why:** Architecture Finding 2 (921-line single-responsibility-violating file, will keep growing) +
SwiftData & CloudKit Finding 1 (fire-and-forget writes, `print()`-only errors, no retry) — doing both in
one pass avoids touching every push/pull function twice.

**Deliverables:**
- `CloudKitSync.swift` split into per-model extension files (e.g. `CloudKitSync+Team.swift`,
  `CloudKitSync+Training.swift`, etc.) sharing one `CloudKitSync` class/actor declared in a slim base
  file, using `CKSchema` constants from Phase 5
- All `print("CloudKitSync ... failed")` sites replaced with `os.Logger` calls (a dedicated `Logger`
  instance, subsystem/category set appropriately) so failures are visible in Console.app/sysdiagnose
- Basic retry/backoff (e.g. up to 3 attempts with short exponential backoff) added to push/delete
  operations before giving up and logging failure — no infinite retry, no offline queue infrastructure
  required (that's a larger future item, not in this audit's explicit findings)

**Acceptance criteria:**
- [ ] No single file under `BlindensportGraz/` related to CloudKit sync exceeds ~300 lines (down from
      921 in one file)
- [ ] `grep -c 'print(' BlindensportGraz/CloudKitSync*.swift` returns 0 (all converted to `os.Logger`)
- [ ] At least the push and delete paths for every of the 11 record types retry up to 3 times with
      backoff before logging a final failure
- [ ] `syncAll()`'s documented pull ordering (per audit.md's positive Finding 5) is preserved exactly —
      no reordering as a side effect of the split
- [ ] `.changedKeys` last-write-wins conflict strategy and its doc comment are preserved verbatim
      (accepted tradeoff, not being changed by this phase)
- [ ] Full local unit test suite passes, including any CloudKit-touching tests (aside from the known
      pre-existing `MemberImportExportTests` crash under unsigned test runs)
- [ ] `.wolf/anatomy.md` updated for the new file layout

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`
- `grep -c 'print(' BlindensportGraz/CloudKitSync*.swift`

**Evidence required:**
- New file list + line counts
- `grep` output showing zero `print()` sites remaining
- Build/test tails with exit codes

**Dependencies:** Phase 5

---

## Phase 7 — Split Models.swift & closed role/sport enums

**Why:** Architecture Finding 2 (848-line file, 11 `@Model` classes in one file) + Finding 3 (free-text
`role`/`sport` strings caused a confirmed bug already — `TournamentsViews.swift`'s `!= "player"` typo
class of bug).

**Deliverables:**
- `Models.swift` split into one file per `@Model` class (or logically grouped where inheritance
  requires it — SportEvent/Training/Tournament share a hierarchy per cerebrum.md, keep those together)
- `TeamMembership.role` becomes a closed `Role` enum (`.player`, `.coach`, `.assistant`, etc. — derive
  the exact case set from every distinct string value currently used across the codebase, confirmed via
  grep, not guessed) with a `normalize(_ raw: String) -> Role` fallback for any legacy/unexpected stored
  value (never crash or silently drop a membership on an unrecognized string)
- `SportEvent/Training/Tournament.sport` becomes a closed `Sport` enum mirroring `SportIcons.swift`'s
  existing display-name mapping, with the same normalize-with-fallback approach for legacy data
- Every `role == "..."`/`sport == "..."` string comparison across the app updated to the enum form,
  including the exact bug audit.md cites (`TournamentsViews.swift`'s explicit `role == "player"` check)

**Acceptance criteria:**
- [ ] `Models.swift` no longer exists as an 848-line monolith; each `@Model` class lives in its own file
      (grouped only where SportEvent/Training/Tournament's inheritance requires shared context)
- [ ] `Role` and `Sport` are closed enums (`String, CaseIterable` or similar), not raw `String` fields,
      on `TeamMembership`/`SportEvent`/`Training`/`Tournament`
- [ ] `grep -rn 'role == "\|role != "\|sport == "\|sport != "' BlindensportGraz --include="*.swift"`
      returns 0 (no remaining raw-string role/sport comparisons)
- [ ] A normalization path exists so an unrecognized legacy string value (e.g. from old CloudKit data)
      maps to a defined fallback case rather than crashing or being silently dropped — covered by a unit
      test with a deliberately garbage raw value
- [ ] CloudKit push/pull for the affected fields correctly encode/decode the enum's raw value, verified
      by a round-trip unit test (push then pull, or equivalent in-memory encode/decode test)
- [ ] Full local unit test suite passes, plus at least 3 new tests for the enum normalization fallback
      behavior (one per affected model type touched)
- [ ] `.wolf/anatomy.md` updated for the new file layout, `.wolf/cerebrum.md` gets a Decision Log entry
      noting the enum migration and its legacy-value fallback behavior

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`
- `grep -rn 'role == "\|role != "\|sport == "\|sport != "' BlindensportGraz --include="*.swift"`

**Evidence required:**
- New file list for the split
- `grep` output confirming zero raw-string comparisons remain
- New fallback-normalization test names + pass output
- Build/test tails with exit codes

**Dependencies:** Phase 6

---

## Phase 8 — Extract persistence+sync service layer

**Why:** Architecture Finding 1 (60 view-layer call sites directly drive `CloudKitSync.shared`), Finding
6 (98 `try?` silent-failure sites, no consistent error policy), and Finding 8 (save-then-sync duplicated
verbatim everywhere) — closing all three together since they're the same underlying gap.

**Deliverables:**
- A small per-model service/helper layer (e.g. `TeamService`, `TrainingService`, or one generic
  `SyncedModelService<T>` if the shared pattern is truly uniform — decide based on how uniform the 11
  models' save+push patterns actually are once inspected) that wraps `modelContext.save()` +
  `CloudKitSync.shared.push*`/`delete*` behind one call per mutation
- Consistent error handling in the new layer: `os.Logger` on every failure (reusing Phase 6's logger),
  plus a user-facing failure signal (toast/alert) specifically for admin-critical actions (role changes,
  roster edits) — not necessarily every single save in the app, matching audit.md's stated priority
- All ~60 existing view-layer call sites migrated to use the new service layer instead of calling
  `modelContext.save()` + `CloudKitSync.shared.*` inline

**Acceptance criteria:**
- [ ] `grep -rn "CloudKitSync.shared" BlindensportGraz --include="*.swift" | grep -v "Service\|CloudKitSync"`
      (calls from view files, not from the new service layer or CloudKitSync itself) drops to 0
- [ ] `grep -rc 'try? modelContext.save()' BlindensportGraz --include="*.swift"` drops sharply (ideally
      to 0 outside the new service layer) — remaining raw `try?` sites, if any, are justified in a code
      comment
- [ ] Role changes (`UserListView`) and roster edits (`Member`/`MembersViews.swift`) show a visible
      failure indicator (alert/toast) if the underlying save+sync fails — verified by a unit/UI test or
      a clear code-level trace showing the failure path is wired to a `@State`/`@Published` error signal
- [ ] Every one of the 11 model types has working create/update/delete through the new service layer —
      no model silently left on the old inline pattern
- [ ] Full local unit test suite passes; add tests for the service layer's error path (simulate a save
      failure, confirm the failure signal fires and the CloudKit push is NOT attempted on an
      already-failed local save)
- [ ] `.wolf/anatomy.md`/`.wolf/cerebrum.md` updated: new service layer documented as the pattern all
      future model mutations should follow (this is exactly the kind of convention cerebrum.md's Key
      Learnings section exists for)

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`
- `grep -rn "CloudKitSync.shared" BlindensportGraz --include="*.swift" | wc -l`

**Evidence required:**
- Before/after count of direct `CloudKitSync.shared` call sites in view files
- The new service layer's file(s) + one migrated view file's diff as a representative example
- Build/test tails with exit codes

**Dependencies:** Phase 6, Phase 7

---

## Phase 9 — Shared schema package (app + RootCLI)

**Why:** Architecture Finding 5 — `RootCLI/Sources/CloudKitS2SCore/MemberRecord.swift` and
`RootCLI/Sources/clubmembersapi/Routes.swift` independently hand-maintain the `Member`/`ClubMember`
CKRecord field shape with no shared code, already causing drift twice (cerebrum.md 2026-07-18 and
2026-07-30 entries).

**Deliverables:**
- A new local SwiftPM package (e.g. `Shared/ClubSchema`, path decided during implementation) containing
  only plain Codable value types + string field-name constants for the record shapes shared between the
  app and RootCLI (starting with Member/ClubMember, extendable to others later) — Foundation-only
  dependency, no CloudKit/Vapor/UIKit imports, so it builds cleanly on both the iOS app target and
  RootCLI's macOS SPM package
- `project.yml` updated with a local `packages:` entry pointing at the new package, and the
  `BlindensportGraz` target depends on it
- `RootCLI/Package.swift` updated with the same local package dependency, and
  `CloudKitS2SCore`/`MemberRecord.swift` refactored to use the shared types instead of its own
  hand-rolled mirror

**Acceptance criteria:**
- [ ] The new package builds standalone via `swift build` with zero dependencies beyond Foundation
- [ ] `project.yml`'s `packages:` section references the new local package by path; `xcodegen generate`
      succeeds and the app target compiles using the shared types for at least the Member/ClubMember
      field shape
- [ ] `RootCLI/Package.swift` depends on the same local package; `RootCLI/Sources/CloudKitS2SCore/MemberRecord.swift`
      is refactored to use it instead of redeclaring the field shape independently
- [ ] A single field-name change in the shared package (tested by temporarily renaming one field in a
      throwaway local edit, confirming both the app target AND RootCLI fail to compile until updated,
      then reverting) demonstrates the drift the audit describes is now caught at compile time — this
      test is done and reverted within this phase, not left in the codebase
- [ ] Both `xcodebuild build` (app) and `swift build` (RootCLI) succeed with the new shared dependency
- [ ] `.wolf/cerebrum.md` gets a Decision Log entry documenting the new shared package and that future
      cross-codebase record-shape changes should go there first

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `cd RootCLI && swift build`
- `xcodebuild test ...`

**Evidence required:**
- New package's `Package.swift` + directory listing
- The compile-time-drift-catch demonstration (before/after of the temporary rename test) described in
  transcript, confirmed reverted
- Build tails (app + RootCLI) with exit codes

**Dependencies:** Phase 6

---

## Phase 10 — Sync status & offline UX

**Why:** SwiftData & CloudKit Finding 3 (no user-visible sync/pending state anywhere) + Finding 4 (the
destructive local-store-reset fallback's safety assumption isn't verifiable) + Enhancements #3 and #4
(visible sync status indicator, offline-mode messaging) — grouped since they're the same "does the user
know what's happening to their data" theme.

**Deliverables:**
- A lightweight app-wide sync state (syncing / synced / failed, with a last-synced timestamp) surfaced
  as a small banner or icon, driven by the retry/logging infrastructure from Phase 6 and the service
  layer from Phase 8
- Network reachability detection with a visible "you're offline, changes will sync once reconnected"
  message instead of silent failure
- `BlindensportGrazApp.swift`'s destructive local-store-reset fallback hardened: before wiping the local
  store, check/wait for any known-pending pushes (using the new sync-state tracking) where feasible, or
  at minimum surface a clear warning if a reset is about to discard data that was never confirmed synced

**Acceptance criteria:**
- [ ] A visible sync-state indicator exists and updates in response to real push/pull activity (not a
      static decoration) — confirmed via a UI/unit test or a clear code trace from a push call through
      to the state update
- [ ] Going offline (simulated via a reachability-check unit test or a mockable network state) shows the
      offline message; coming back online clears it and resumes normal sync-state reporting
- [ ] The local-store-reset path in `BlindensportGrazApp.swift` no longer proceeds silently — it either
      checks for pending unsynced writes first, or at minimum logs/surfaces via `os.Logger` (Phase 6's
      logger) exactly what it's about to do and why, addressing the "can't verify the safety assumption"
      gap with honesty rather than a false guarantee
- [ ] No regression to `syncAll()`'s pull ordering (audit.md's positive Finding 5) or the `.changedKeys`
      conflict strategy (accepted tradeoff, unchanged)
- [ ] Full local unit test suite passes

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`

**Evidence required:**
- The new sync-state surface's code + a description of what drives its transitions
- The hardened reset-fallback diff in `BlindensportGrazApp.swift`
- Build/test tails with exit codes

**Dependencies:** Phase 6

---

## Phase 11 — Query predicates & subscription retry

**Why:** SwiftData & CloudKit Finding 6 (most `@Query`s unfiltered, fetching the entire shared store)
and Finding 8 (no recovery path if `CKQuerySubscription` registration fails, silently killing creation
alerts for that device).

**Deliverables:**
- `#Predicate`s added to the largest/most obviously scopeable unfiltered `@Query` sites cited in
  audit.md (`TeamsViews.swift:8`, `KostZViews.swift:18`/`124`, `SammelabrechnungViews.swift:15`/`111`,
  `RootView.swift:20`/`274`) where a natural predicate exists (date range, team scope, etc.) — document
  any left unfiltered with a one-line reason (e.g. "genuinely needs the full set")
- Retry logic for `CKQuerySubscription` registration failures (reuse Phase 6's retry/backoff helper if
  shape-compatible), with a logged, retryable failure state instead of a single silent `print()`

**Acceptance criteria:**
- [ ] Every `@Query` site named in audit.md's Finding 6 either has a `#Predicate` added or a one-line
      code comment explaining why it's intentionally unfiltered
- [ ] Subscription registration failure retries at least once more with backoff before giving up, and
      logs via `os.Logger` on final failure (not a bare `print()`)
- [ ] No behavior regression: every screen previously showing the full unfiltered list still shows the
      correct data after predicates are added (verified by existing/new unit tests, not just "looks
      right")
- [ ] Full local unit test suite passes

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`

**Evidence required:**
- Before/after `@Query` diffs for each cited site
- Subscription-retry code diff
- Build/test tails with exit codes

**Dependencies:** Phase 6

---

## Phase 12 — Accessibility labels & control equivalents

**Why:** Accessibility Finding 1 (only 4 of 33 files use any accessibility API at all, despite VoiceOver
being this app's primary real-world usage mode) + Finding 2 (EventsViews.swift's icon-only add button)
+ Finding 3 (TrainingFavorite's contextMenu-only delete has no VoiceOver-equivalent action) + Finding 9
(report Pickers could use hints where the effect isn't obvious).

**Deliverables:**
- `.accessibilityLabel`/`.accessibilityHint` added across the ~29 files audit.md identifies as having
  zero accessibility API usage — following the existing, already-correct pattern in
  `TeamsViews.swift:198-199` (label + hint on a tap-to-open-menu control) and `TournamentsViews.swift`/
  `MembersViews.swift`/`TrainingsViews.swift`'s existing usage as the reference style
- `EventsViews.swift:173`'s icon-only add button gets `.accessibilityLabel`, matching
  `TrainingsViews.swift:567-576`'s established import/export button pattern exactly
- `.accessibilityAction(named: "Löschen")` added alongside `TrainingFavorite`'s existing `.contextMenu`
  delete (not replacing it)
- `.accessibilityHint` added to the Pickers in `PraeViews.swift`/`KostZViews.swift`/
  `TrainingsfrequenzlisteViews.swift` where the selection's effect isn't obvious from the label alone
  (e.g. "Zeitraum" toggling between half-years)

**Acceptance criteria:**
- [ ] `grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift" | wc -l`
      rises from 4 to cover every interactive-control-bearing file in the app (verify against the file
      list, not just a higher number)
- [ ] `EventsViews.swift`'s add button has `.accessibilityLabel` matching the established pattern
- [ ] `TrainingFavorite`'s delete is reachable via both the existing `.contextMenu` AND a VoiceOver
      `.accessibilityAction`, confirmed by code inspection (both present, same underlying delete call)
- [ ] Already-correct examples (`SportGlyph`'s `.accessibilityHidden(true)`, `TeamDetailView`'s role
      Menu, tournament status never being color-only) are left untouched — this phase adds coverage, it
      does not "fix" things audit.md already marked Positive
- [ ] No currently-nested `.sheet`-inside-a-`.sheet` is introduced by any of this phase's changes
      (spot-check any `.sheet(` site touched)
- [ ] Full local unit test suite passes (this phase is UI-only but must not break compilation/tests)

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift" | wc -l`
- `xcodebuild test ...`

**Evidence required:**
- Before/after file-count from the grep command
- `EventsViews.swift` and `TrainingFavorite` diffs specifically (the two named findings)
- Build/test tails with exit codes

**Dependencies:** Phase 1

---

## Phase 13 — Accessibility Dynamic Type pass

**Why:** Accessibility Finding 4 — zero Dynamic Type accommodation anywhere; dense list rows and
multi-field forms may clip/truncate at larger text sizes.

**Deliverables:**
- Dense list rows (`MemberListView`, `TeamsViews` roster rows) and multi-field `Add*View` forms checked
  against larger Dynamic Type sizes; `.minimumScaleFactor`/layout adjustments (e.g. switching a fixed
  `HStack` to allow wrapping, or `.lineLimit` tuning) applied wherever clipping/truncation is confirmed
- No change to layouts that already accommodate large text correctly

**Acceptance criteria:**
- [ ] Every dense list row / form identified in audit.md's Finding 4 is checked at at least the
      `.accessibility3` (or larger) Dynamic Type size — via SwiftUI preview with
      `.environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)` or equivalent — and the check
      result (clips / doesn't clip) is recorded for each
- [ ] Every confirmed clipping/truncation case is fixed (no unaddressed "found but not fixed" items)
- [ ] Fixes don't regress the default Dynamic Type size's layout (spot-check at `.large`, the default)
- [ ] Full local unit test suite passes (Dynamic Type changes are layout-only, must not break logic)

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`

**Evidence required:**
- The list of checked surfaces with clip/no-clip result for each
- Diffs for every surface that needed a fix
- Build/test tails with exit codes

**Dependencies:** Phase 12

---

## Phase 14 — Local reminder notifications

**Why:** Enhancement #5 — `PushNotifications.swift`'s existing `CKQuerySubscription`s only fire on
Training/Tournament *creation*, never on a schedule before the event starts. This is additive.

**Deliverables:**
- `UNCalendarNotificationTrigger`-based local reminders scheduled off `Training.startDate`/
  `Tournament.startDate` (e.g. "starts in 2 hours" — confirm exact lead time is reasonable, default to
  something sensible if not otherwise specified)
- Rescheduling on edit (date change) and cancellation on delete
- Uses the existing service layer from Phase 8 for the edit/delete hooks that trigger
  reschedule/cancel, rather than adding a new ad-hoc call site pattern

**Acceptance criteria:**
- [ ] Creating a Training/Tournament with a future start date schedules exactly one local notification
      at the chosen lead time before `startDate`
- [ ] Editing the start date reschedules the existing notification (no duplicate, no stale one left
      pointing at the old time)
- [ ] Deleting the Training/Tournament cancels its notification
- [ ] A start date already in the past does not schedule a notification (no immediate/backdated fire)
- [ ] Notification permission is requested appropriately (reuses `PushNotifications.swift`'s existing
      registration flow if it already requests notification permission, or adds the request if not)
- [ ] Full local unit test suite passes, plus new tests for the schedule/reschedule/cancel logic
      (testable without a real device by asserting on the `UNNotificationRequest`/trigger date computed,
      not by requiring an actual notification to fire)

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`

**Evidence required:**
- The scheduling/reschedule/cancel code + new test names and pass output
- Build/test tails with exit codes

**Dependencies:** Phase 8

---

## Phase 15 — Attendance-trends dashboard

**Why:** Enhancement #6 — `TrainingAttendance`/`TournamentAttendance` records sync correctly but are
never aggregated/visualized anywhere; no `Charts` import exists in the project at all.

**Deliverables:**
- A new admin/coach-facing view (Swift `Charts` framework) showing per-team or per-person attendance
  rate trends over time, sourced from existing `TrainingAttendance`/`TournamentAttendance` data via the
  service layer's read path

**Acceptance criteria:**
- [ ] A new SwiftUI view using `import Charts` renders at least one chart type (e.g. a line or bar chart
      of attendance rate over time) driven by real `TrainingAttendance`/`TournamentAttendance` data
- [ ] The view is reachable from an existing admin/coach navigation surface (not an orphaned screen)
- [ ] Gated to admin/coach roles, consistent with the app's existing role-check convention
- [ ] Handles the empty-data case (a team/person with no attendance records yet) without crashing or
      showing a broken chart
- [ ] Full local unit test suite passes; add at least one test for the attendance-rate aggregation logic
      itself (pure calculation, testable independent of the chart rendering)

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`

**Evidence required:**
- The new view + aggregation-logic code
- New test name(s) + pass output
- Build/test tails with exit codes

**Dependencies:** Phase 8

---

## Phase 16 — Season/year reporting rollup

**Why:** Enhancement #8 — extends the existing `SammelabrechnungExporter` pattern (which already
bundles one period's KostZ+PRAE into a zip) to a full-season rollup across all periods and tournaments,
reusing the existing orchestration-over-existing-exporters approach.

**Deliverables:**
- A season/year-level export that calls the existing KostZ/PRAE/Trainingsfrequenzliste exporters across
  every period in a season and bundles the results (same zip-bundling approach as
  `SammelabrechnungExport.swift`), reachable from the existing "Berichte" admin menu pattern

**Acceptance criteria:**
- [ ] A new season-scoped export function reuses the existing per-period exporters (no duplicated
      template-patching logic — confirmed by code review that it calls into
      `KostZExporter`/`PraeExport`/`TrainingsfrequenzlisteExport`, not reimplementing their XLSX
      patching)
- [ ] The resulting bundle contains every period's files for the selected season, correctly named
      (matching the existing `TN-Sportler`/`TN-Helfer`-style naming convention from recent commits)
- [ ] Reachable via a new entry in the existing "Berichte" toolbar menu (`TrainingsListView`'s pattern)
- [ ] A season with zero periods/data doesn't crash — produces an empty-but-valid bundle or a clear
      "nothing to export" state
- [ ] Full local unit test suite passes; add at least one test covering the season-rollup orchestration
      (can reuse `SammelabrechnungExportTests.swift`'s existing test fixtures/patterns)

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`

**Evidence required:**
- The new season-export function + its call sites into the existing exporters
- New test name(s) + pass output
- Build/test tails with exit codes

**Dependencies:** Phase 8

---

## Phase 17 — Calendar/EventKit integration

**Why:** Enhancement #9 — confirmed absent entirely (no `EventKit`/`EKEventStore` hits anywhere); lets
members add trainings/tournaments to their personal calendar.

**Deliverables:**
- An "Add to Calendar" action on Training/Tournament detail views using `EventKit` (`EKEventStore`,
  requesting calendar access appropriately) — OR a simpler `.ics` file export via `ShareLink` if that
  proves the better fit given this app's established preference for native `ShareLink` over custom
  UIKit wrappers (per cerebrum.md's 2026-07-18 VoiceOver lesson) — decide based on which gives a better
  VoiceOver experience, document the choice

**Acceptance criteria:**
- [ ] Training/Tournament detail views have a discoverable "Add to Calendar" action with a correct
      `.accessibilityLabel` (this app's primary usage mode is VoiceOver — this must be labeled from the
      start, not left for Phase 12/13 to catch)
- [ ] The exported/created calendar event has the correct title, location, and start/end time matching
      the Training/Tournament's data
- [ ] Calendar/EventKit permission is requested appropriately if using `EKEventStore`; if using `.ics` +
      `ShareLink` instead, no permission prompt is needed and that's noted as the reason for the choice
- [ ] Editing the Training/Tournament's date does NOT silently leave a stale calendar entry — either the
      feature re-adds on demand only (no persistent link to maintain) or updates the existing entry;
      document which behavior was chosen and why
- [ ] Full local unit test suite passes; add at least one test for the event-data-mapping logic
      (Training/Tournament → calendar event fields), independent of actual EventKit/file I/O

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`

**Evidence required:**
- The chosen approach (EventKit vs .ics+ShareLink) and why, plus its code
- New test name(s) + pass output
- Build/test tails with exit codes

**Dependencies:** Phase 8

---

## Phase 18 — Receipt/document attachments

**Why:** Enhancement #10 — extends the existing `EventImage` (`@Attribute(.externalStorage)` + `CKAsset`)
pattern already used for event photos, applied to expense receipts for the KostZ/PRAE accounting flows.

**Deliverables:**
- A new attachment model (e.g. `ExpenseReceipt`) following `EventImage`'s exact established pattern:
  `@Attribute(.externalStorage)` data field, CKAsset sync via temp file + `defer` cleanup, downscale/
  compress before upload if it's an image (receipts may also be PDFs — handle both or scope explicitly
  to images if PDF support is materially more work, document the scoping decision)
- Attachment UI on the KostZ/PRAE screens (upload/view/delete), matching `EventImagesViews.swift`'s
  reusable-section approach

**Acceptance criteria:**
- [ ] `ExpenseReceipt` mirrors `EventImage`'s CKAsset sync pattern exactly (temp file + `defer` cleanup,
      immutable-once-uploaded skip-if-present-locally pull behavior)
- [ ] Upload UI is reachable from the KostZ/PRAE accounting screens
- [ ] Delete is restricted to the uploader or an admin, matching `EventImage`'s existing permission model
- [ ] Uses the Phase 8 service layer for its save+sync calls, not a new inline pattern
- [ ] Full local unit test suite passes; add at least one test for the receipt model's CloudKit
      encode/decode round-trip (matching the style of existing `EventImage`-adjacent tests if any exist,
      or a new equivalent)

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...`

**Evidence required:**
- The new model + UI code, with an explicit note on the image-vs-PDF scoping decision
- New test name(s) + pass output
- Build/test tails with exit codes

**Dependencies:** Phase 8

---

## Phase 19 — Polish & Harden

**Why:** Catch what earlier phases missed because they were focused on shipping behavior, and compile
the manual (non-automatable) follow-ups — CloudKit Dashboard Security Roles application, Production
environment schema sync for every new record type added this run — into one clear list for the user.
This is how "every aspect is perfect" gets enforced for a run this large.

**Sub-passes (each must produce evidence):**

- [ ] **Full regression sweep** — run the complete local unit test suite one final time; every test
      passes except the known pre-existing `MemberImportExportTests` CloudKit-entitlement crash (confirm
      it's still the *only* failure, not a new one hiding behind it)
- [ ] **Security** — re-verify Phase 1's backdoor removal (`grep -n "testAdminEmail"` returns nothing),
      re-verify input validation from Phase 3 doesn't block legitimate malformed-but-real data, confirm
      no secret/credential was hardcoded by any later phase
- [ ] **Accessibility spot-check** — re-run `grep -rln "accessibilityLabel\|accessibilityHint"
      BlindensportGraz --include="*.swift" | wc -l` and confirm it's meaningfully higher than the
      original 4; spot-check 3 screens by reading their code for correct label/hint presence
- [ ] **A11y regression** — confirm no `.sheet`-inside-`.sheet` nesting was introduced across all 19
      phases (re-run the check from Phase 12 against the full diff, not just Phase 12's own changes)
- [ ] **Diff review** — `git diff main --stat` reviewed for stray debug `print()`/TODO/FIXME left behind
      by any phase; anything found is fixed inline in this phase (small, targeted)
- [ ] **RootCLI regression** — `cd RootCLI && swift build` still succeeds with every phase's cumulative
      changes (schema package, audit log, rate limiting)
- [ ] **One real device smoke check** — use the `deploy` skill / self-hosted GitHub Actions workflow
      once to confirm the accumulated changes actually build and launch on the user's physical iPhone
      (this is the one thing genuinely unverifiable locally all run)
- [ ] **Manual follow-ups list** — compile every manual (non-code) action still required: applying
      CloudKit Dashboard Security Roles to all 11 record types in Production (Phase 4's documentation),
      confirming any new CKRecord type introduced this run (RoleChangeLog, ExpenseReceipt) exists in the
      Production schema and has its Security Roles configured, and any other manual step surfaced by an
      earlier phase — present this as a clear, short checklist to the user, not buried in prose
- [ ] **OpenWolf housekeeping** — confirm `.wolf/anatomy.md`, `.wolf/cerebrum.md`, `.wolf/memory.md`,
      `.wolf/buglog.json` all reflect this run's cumulative changes (each phase should have updated them
      incrementally per the project's own protocol — this pass catches anything missed)

**Mandatory commands:**
- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test ...` (full suite, same flags/destination pattern as every prior phase)
- `cd RootCLI && swift build`
- `grep -n "testAdminEmail" BlindensportGraz/*.swift` (expect no output)
- `grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift" | wc -l`
- `git diff main --stat`
- The `deploy` skill's device-deploy trigger (`gh workflow run "iOS Device Deploy"` + `gh run watch
  <run-id> --exit-status`, per `build_commands.md`'s documented flow)

**Evidence required:**
- Final test summary (pass count, the one known pre-existing failure named explicitly)
- The accessibility before/after count (4 → final)
- `git diff main --stat` output
- The device-deploy workflow run URL + result
- The final manual-follow-ups checklist, printed in full
