SUPERGOAL_PHASE_START
Phase: 1 of 19 — Remove test-admin backdoor & fix doc drift
Task: Grant franz.kager@gmx.net real admin via RootCLI, then delete the testAdminEmail backdoor from Models.swift and fix the in-app CLAUDE.md doc drift.
Type: brownfield, security, refactor
Mandatory commands: cd RootCLI && swift build; xcodegen generate; xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO; xcodebuild test (see Notes for destination)
Acceptance criteria: 6
Evidence required: RootCLI grant+read-back output, grep confirming zero backdoor hits, build/test tails
Depends on phases: none

## Why

audit.md's Security Finding 1 — the single most important finding in the whole report: a hardcoded
TEST-ONLY admin grant for the user's own real email, live in production code a month past its own
"remove once testing is done" note. It must be fixed before any other phase touches Models.swift or the
role-escalation logic, and the user's own admin access must not be lost in the process.

## Work

- Read `.wolf/anatomy.md` before opening any file, and `.wolf/cerebrum.md`'s Do-Not-Repeat section
  before writing code (per this repo's OpenWolf protocol — see `.claude/rules/openwolf.md`).
- Read `.wolf/buglog.json` for anything already known about `testAdminEmail`/role-escalation before
  touching this code.
- Read `RootCLI/Sources/rootcli/RootCLI.swift` to find the exact `set-role` (or equivalent) subcommand
  and its argument shape.
- Run the RootCLI command against the real CloudKit container to grant `franz.kager@gmx.net` `role =
  "admin"` (matching the app's existing role model — check `Models.swift` for the exact role string
  values in use, e.g. `"admin"`). This requires whatever CloudKit credentials/env vars RootCLI already
  expects (`CLOUDKIT_KEY_ID` etc. per `kloudkit.md`) — use what's already configured in this repo/environment.
- Verify the grant actually landed: read the record back (`rootcli list` or equivalent query) and
  confirm the role field shows the new value before touching any app code.
- Only after the grant is verified: open `Models.swift`, remove `static let testAdminEmail`, the
  `elevateIfTestAdmin()` function, and its doc comment block; find and remove all 4 call sites (login,
  registration, email-edit paths — grep for `elevateIfTestAdmin` to find them all).
- Check every call site compiles cleanly after removal — no dangling `if`/`guard` branches, no unused
  variables left behind.
- Open `BlindensportGraz/CLAUDE.md` (the in-app doc, distinct from the repo-root one) and correct the
  drift audit.md's Architecture Finding 4 describes: remove any mention of a `username` field (removed
  2026-07-19 per cerebrum.md), rename any `ClubMember` reference to `Member` (the real roster class
  name), and update the model list/count to match the real 11 `@Model` classes in `Models.swift`. Read
  `Models.swift` first to get the real list right, don't guess from memory.
- Append a `.wolf/cerebrum.md` Decision Log entry: backdoor removed on 2026-08-20, real admin granted to
  franz.kager@gmx.net via RootCLI first, so a future session doesn't reintroduce a similar shortcut.
- Update `.wolf/anatomy.md` for any file whose description changed, and append a line to
  `.wolf/memory.md` per the OpenWolf protocol.
- Log this fix to `.wolf/buglog.json` (bug entry: testAdminEmail backdoor removed, root cause: dev
  convenience left in past its removal note, fix: removed + real admin granted first).

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] RootCLI grant command run + its output shown, THEN a separate read-back command confirming
      `franz.kager@gmx.net` now has real admin/root — both printed into the transcript, grant before any
      Models.swift edit
- [ ] `grep -n "testAdminEmail\|elevateIfTestAdmin" BlindensportGraz/*.swift` returns no results
- [ ] All 4 former call sites of `elevateIfTestAdmin()` compile cleanly with no dangling references
- [ ] `BlindensportGraz/CLAUDE.md` no longer mentions `username` or `ClubMember`; lists the actual 11
      `@Model` classes and the real roster class name (`Member`)
- [ ] `.wolf/cerebrum.md` has a new Decision Log entry documenting the removal and the grant-first order
- [ ] Full local unit test suite passes (aside from the known pre-existing `MemberImportExportTests`/`TrainingImportExportTests`
      crash under unsigned test runs — not a regression, see cerebrum.md bug-202)

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `cd RootCLI && swift build`
- The RootCLI grant command itself + a read-back/list command confirming the new role
- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcrun simctl list devices available` (to pick a concrete simulator name), then
  `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<picked device>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- RootCLI grant + read-back output
- `grep` output confirming zero `testAdminEmail`/`elevateIfTestAdmin` hits
- The `BlindensportGraz/CLAUDE.md` diff
- Build + test command tails with exit codes

## Notes

If the RootCLI grant command requires CloudKit credentials not present in this environment, treat that
as a real blocker (FAILURE_PROBE, not a silent skip) — this is the one step in the whole run that must
not be faked or assumed. If genuinely blocked, escalate per PROTOCOL.md rather than deleting the
backdoor without a confirmed replacement grant. This app's role string values are plain strings today
(closed enums land in Phase 7) — use whatever exact string `Models.swift` currently uses for admin,
don't invent a new one.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
