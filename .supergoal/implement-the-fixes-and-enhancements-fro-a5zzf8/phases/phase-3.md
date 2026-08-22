SUPERGOAL_PHASE_START
Phase: 3 of 19 — Role tests & input validation
Task: Add unit test coverage for elevateIfDesignatedRoot, plus non-blocking email/IBAN/SVNR validation.
Type: brownfield, security, testing
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...
Acceptance criteria: 5
Evidence required: new test names/output, validation UI diff, import-path regression confirmation
Depends on phases: 1, 2

## Why

audit.md's Security Finding 3 (zero test coverage on role-escalation logic despite a documented
multi-session bug history — bug-173) and Findings 4/5 (no email format validation, no IBAN/SVNR
validation) plus Enhancement #7.

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first, including the bug-173 and surrounding
  2026-07-19/2026-08-02 entries in `.wolf/buglog.json`/cerebrum.md describing the designated-root grant
  bug history — understand exactly what broke before writing tests for it.
- Add `BlindensportGrazTests` coverage for `elevateIfDesignatedRoot()`: full first/last/email match
  grants root; missing any one of the three does not grant; case-insensitive match still grants
  (mixed-case input); whitespace-padded input still grants; already-root does not re-grant/re-log
  (guard against duplicate `RoleChangeLog` entries from Phase 2); and a regression test confirming
  `grep`-style that `elevateIfTestAdmin`/`testAdminEmail` no longer exist as symbols anywhere in
  `BlindensportGraz/*.swift` (a `Process`-based grep check from within a test, or an equivalent
  compile-time absence check — pick whichever fits this project's existing test style).
- Add email format validation to `AccountView.swift:125` and `RootView.swift:287`'s email `TextField`s —
  match whatever validation UX pattern this app's other required-field checks already use (look at how
  other forms in this codebase validate before inventing a new pattern); non-blocking or blocking should
  match the surrounding form's existing convention, not introduce an inconsistent one.
- Add soft IBAN checksum (mod-97) + Austrian SVNR pattern validation to wherever `Member.iban`/
  `Member.svnr` are entered/edited — surfaced as a warning icon/hint, never a save-blocking error. Check
  `MemberImportExport.swift` and the bulk-import path too: the validation must not reject or crash on
  already-malformed real-world data (cerebrum.md's 2026-07-30 entry documents actual malformed source
  data already encountered) — it's advisory only.
- Confirm existing import/export tests (`MemberImportExportTests.swift`, `TrainingImportExportTests.swift`) still pass unchanged with
  deliberately malformed IBAN/SVNR sample data if such fixtures exist, or add one confirming malformed
  data still imports successfully with just a warning surfaced, not a rejection.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] At least 6 new unit tests for `elevateIfDesignatedRoot` covering: full match grants, partial match
      doesn't, case-insensitive match grants, whitespace-padded match grants, already-root doesn't
      re-grant, and confirmed absence of `elevateIfTestAdmin`/`testAdminEmail`
- [ ] Email fields warn/reject on obviously malformed input without blocking viewing/editing of
      already-malformed pre-existing data
- [ ] IBAN/SVNR fields show a non-blocking warning for checksum/pattern failures, never prevent saving
- [ ] Malformed sample data (existing fixtures or a newly added one) still imports/loads successfully —
      validation is not a hard gate anywhere in the import path
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions), including all new tests

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- New test names + pass output for all 6+ role-escalation tests
- Before/after snippet of the email/IBAN/SVNR validation UI code
- Confirmation the import-path test(s) still pass with malformed sample data

## Notes

This is exactly the class of bug the audit calls out as having "a documented multi-session bug history"
— don't rush the test cases; each one should map to a real historical failure mode described in
cerebrum.md, not a generic happy-path check.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
