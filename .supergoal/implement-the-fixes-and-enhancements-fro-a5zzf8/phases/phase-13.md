SUPERGOAL_PHASE_START
Phase: 13 of 19 — Accessibility Dynamic Type pass
Task: Check dense list rows and multi-field forms against large Dynamic Type sizes and fix confirmed clipping/truncation.
Type: brownfield, accessibility
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...
Acceptance criteria: 4
Evidence required: checked-surfaces list with results, fix diffs, build/test tails
Depends on phases: 12

## Why

audit.md's Accessibility Finding 4 — zero Dynamic Type accommodation found anywhere
(`dynamicTypeSize`/`minimumScaleFactor` usage: none). Dense list rows and multi-field forms have not
been checked against larger Dynamic Type sizes and may clip or truncate.

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first.
- Identify the dense list rows and multi-field forms audit.md names: `MemberListView`, `TeamsViews`
  roster rows, and the multi-field `Add*View` forms (AddTeamView, AddTrainingView, AddTournamentView,
  AddEventView) — plus any other view with a similarly dense `HStack`-heavy row layout found while
  reviewing.
- For each, check layout at a large Dynamic Type size using a SwiftUI preview with
  `.environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)` (or the Simulator's Text Size
  accessibility setting if previews aren't practical for a given view) — record clip/no-clip for each
  surface checked.
- Fix every confirmed clipping/truncation case: prefer allowing `HStack`s to wrap into `VStack`s at
  large sizes, tuning `.lineLimit`, or `.minimumScaleFactor` only where wrapping isn't appropriate (e.g.
  a fixed-width badge) — pick the fix that keeps the layout genuinely readable, not just non-clipping.
- Re-check each fixed surface at the DEFAULT Dynamic Type size (`.large`) afterward to confirm no
  regression to the normal-size layout.
- Update `.wolf/anatomy.md`/`.wolf/memory.md` per the OpenWolf protocol.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] Every dense list row / form named above is checked at `.accessibility3` or larger, with the result
      (clips / doesn't clip) recorded for each
- [ ] Every confirmed clipping/truncation case is fixed — no "found but not fixed" items left
- [ ] Fixes don't regress the default (`.large`) Dynamic Type layout — spot-checked for each fixed
      surface
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions) (layout-only changes must not break logic/tests)

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- The list of checked surfaces with clip/no-clip result for each
- Diffs for every surface that needed a fix
- Build/test tails with exit codes

## Notes

This is lower severity than Phase 12's VoiceOver-blocking findings per audit.md's own weighting — don't
let it balloon into a full design pass; the acceptance bar is "doesn't clip/truncate at large sizes,"
not a redesign.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
