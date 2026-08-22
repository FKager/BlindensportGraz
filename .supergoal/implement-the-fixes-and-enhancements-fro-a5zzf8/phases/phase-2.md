SUPERGOAL_PHASE_START
Phase: 2 of 19 — Role-change audit log
Task: Add a RoleChangeLog model + CKRecord type, wire it into every role-mutation call site, and surface it in an admin-visible UI.
Type: brownfield, security, feature
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...; cd RootCLI && swift build
Acceptance criteria: 6
Evidence required: model+sync diff, new test names/output, build/test tails
Depends on phases: 1

## Why

P0 enhancement #2 in audit.md, directly following Security Findings 1 & 2 — no history of role changes
exists today (confirmed: no `AuditLog`/`RoleChangeLog` symbol anywhere). A small audit trail would have
made Phase 1's own backdoor grant visible after the fact, and generally hardens account administration.

## Work

- Check `.wolf/anatomy.md` before reading files; check `.wolf/cerebrum.md` Do-Not-Repeat before writing
  code.
- Add a new `@Model final class RoleChangeLog` with: the affected user's id, old role, new role, a
  changed-by identifier (the acting admin/root's id or "system:designatedRoot" for the bootstrap grant),
  and a timestamp. Match this app's existing `@Model` conventions (see any existing model for the
  pattern — id type, CloudKit-friendly field types).
- Add `pushRoleChangeLog`/`pullRoleChangeLog` to `CloudKitSync.swift` following the exact same pattern
  as every other model's push/pull (same file for now — Phase 6 will split it later, don't pre-split
  here).
- Wire a `RoleChangeLog` write into every role-mutation call site:
  - `UserListView`'s role-editing UI (the Menu described in audit.md's Accessibility Finding 5 as a
    model example — don't touch its accessibility treatment, just add the log write alongside the role
    change)
  - `elevateIfDesignatedRoot()` in Models.swift — log the bootstrap auto-grant too
  - RootCLI's `set-role` command path (`RootCLI/Sources/rootcli/RootCLI.swift` /
    `RootCLI/Sources/CloudKitS2SCore`) — write a `RoleChangeLog` CKRecord server-side via the same
    CloudKit Web Services mechanism `CloudKitS2SCore` already uses for other record writes
- Add a new admin-only UI surface (or extend `UserListView`) listing recent role changes, newest first —
  reuse an existing list-view pattern in this codebase rather than inventing new list-rendering code.
- Add at least 2 unit tests exercising the audit-log write path against an in-memory `ModelContainer`
  (see existing tests like `InheritanceQueryTests.swift` for the in-memory container setup pattern used
  in this project).
- Update `.wolf/anatomy.md`/`.wolf/memory.md` per the OpenWolf protocol.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] `RoleChangeLog` has all 5 documented fields, synced via the same public-DB push/pull pattern as
      every other model
- [ ] Changing a role via `UserListView` creates exactly one `RoleChangeLog` entry with correct old/new
      values and a changed-by identifier
- [ ] `elevateIfDesignatedRoot`'s auto-grant also logs an entry
- [ ] RootCLI's `set-role` command writes a `RoleChangeLog` record server-side, confirmed via `swift
      build` passing and a code-level review (a live CloudKit write isn't expected to succeed without
      real credentials in this sandbox — that's fine, verify by code review + compile success)
- [ ] A new admin-only UI surface shows the log, newest first
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions) with at least 2 new tests for the audit-log write path

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `cd RootCLI && swift build`

## Evidence required in transcript

- The new `RoleChangeLog` model + CloudKitSync push/pull diff
- New test names + pass output
- Build/test tails with exit codes

## Notes

Don't touch `TeamDetailView`'s role-editing Menu's existing accessibility labels (audit.md marks it
Positive — no fix needed) — only add the log write alongside it. Keep the RootCLI-side write
best-effort: if `CloudKitS2SCore` doesn't yet have a generic "create arbitrary record type" helper, add
one narrowly scoped rather than a broad rewrite.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
