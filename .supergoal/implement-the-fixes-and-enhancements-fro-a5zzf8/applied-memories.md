# Applied memories

No memory files exist yet at `/Users/franz/.claude/projects/-Users-franz-dev-BlindensportGraz/memory/`
(directory present but empty — `MEMORY.md` absent). Nothing to inherit from prior-session memory.

All project conventions/history for this run instead come from `.wolf/cerebrum.md` (Decision Log,
Do-Not-Repeat, Key Learnings) and `.wolf/buglog.json`, per this repo's OpenWolf protocol — these are
read directly by each phase, not duplicated here.

Key facts already surfaced this session (from cerebrum.md, not memory):
- Local `xcodebuild`/codesign hits a sandbox-level `errSecInternalComponent` block in this coding
  session (bug-008) — device build/deploy only runs via the self-hosted GitHub Actions runner
  (`gh workflow run "iOS Device Deploy"`). `xcodebuild test -sdk iphonesimulator
  CODE_SIGNING_ALLOWED=NO` DOES work locally for unit tests, with one known pre-existing crash
  (`MemberImportExportTests`, CloudKit-entitlement-related, not a regression signal — bug-202).
- `franz.kager@gmx.net` (this user) currently has admin ONLY via the `testAdminEmail` backdoor
  (Models.swift:99) being removed in this run — real root is the club's own account
  (`blindensport.gvsc@gmail.com`, `User.designatedRootEmail`). User confirmed: grant real admin via
  RootCLI's `set-role` before removing the backdoor, so access isn't lost.
- User explicitly excluded audit.md's P2 enhancement #12 (multi-club/multi-section extensibility)
  from this run's scope.
