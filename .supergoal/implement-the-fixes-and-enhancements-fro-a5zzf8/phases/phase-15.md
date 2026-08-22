SUPERGOAL_PHASE_START
Phase: 15 of 19 — Attendance-trends dashboard
Task: Add a Swift Charts view showing per-team/per-person attendance-rate trends from existing TrainingAttendance/TournamentAttendance data.
Type: brownfield, feature
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...
Acceptance criteria: 5
Evidence required: new view + aggregation code, new test output, build/test tails
Depends on phases: 8

## Why

audit.md's Enhancement #6 — `TrainingAttendance`/`TournamentAttendance` records exist and sync
correctly, but are referenced only inside `CloudKitSync.swift`'s push/pull; zero aggregate/trend view
exists anywhere, and no `Charts` import exists in the project at all.

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first. Read the `TrainingAttendance`/`TournamentAttendance`
  model definitions (now in their own file per Phase 7) to know exactly what fields are available to
  aggregate on.
- Write a pure aggregation function (no UI/Charts dependency) that computes attendance rate over time,
  scoped by team or by person, from the raw attendance records — this is the part that should be unit
  tested independent of chart rendering.
- Build a new SwiftUI view using `import Charts` (a line or bar chart of attendance rate over time) fed
  by the aggregation function, reading data via the Phase 8 service layer's read path.
- Add it to an existing admin/coach navigation surface (not an orphaned screen) — find the natural home,
  e.g. alongside `TeamDetailView` or the "Berichte" menu pattern used elsewhere in this app.
- Gate visibility to admin/coach roles, matching this app's existing role-check convention (use the
  `Role` enum from Phase 7, not a raw string comparison).
- Handle the empty-data case (a team/person with zero attendance records) without crashing or rendering
  a broken/empty chart — show a clear "no data yet" state instead.
- Add a unit test for the aggregation logic itself using a small in-memory fixture of attendance records
  with a known expected rate.
- Update `.wolf/anatomy.md`/`.wolf/memory.md` per the OpenWolf protocol.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] A new SwiftUI view using `import Charts` renders at least one chart type driven by real
      `TrainingAttendance`/`TournamentAttendance` data
- [ ] The view is reachable from an existing admin/coach navigation surface
- [ ] Gated to admin/coach roles via the `Role` enum, not a raw string comparison
- [ ] The empty-data case is handled without crashing or showing a broken chart
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions), plus at least one new test for the attendance-rate aggregation
      logic

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- The new view + aggregation-logic code
- New test name(s) + pass output
- Build/test tails with exit codes

## Notes

Give the chart's interactive elements accessibility labels from the start (this app's primary usage mode
is VoiceOver) — a Swift Charts view needs `.accessibilityChartDescriptor` or per-data-point labels to be
usable under VoiceOver at all; don't ship a chart that's silent to VoiceOver.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
