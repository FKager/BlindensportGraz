SUPERGOAL_PHASE_START
Phase: 16 of 19 — Season/year reporting rollup
Task: Extend SammelabrechnungExporter to a full-season rollup across all periods and tournaments, reusing the existing per-period exporters.
Type: brownfield, feature
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...
Acceptance criteria: 5
Evidence required: new export function code, new test output, build/test tails
Depends on phases: 8

## Why

audit.md's Enhancement #8 — extends the existing `SammelabrechnungExporter` pattern (which already
bundles one period's KostZ+PRAE into a zip) to a full-season rollup, same orchestration-over-existing-
exporters approach, no new template-patching logic needed.

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first. Read `SammelabrechnungExport.swift` and
  `SammelabrechnungExportTests.swift` in full to understand the exact existing bundling pattern before
  extending it.
- Add a season-scoped export function that iterates every period in a selected season and calls the
  existing `KostZExporter`/`PraeExport`/`TrainingsfrequenzlisteExport` functions per period, bundling all
  resulting files into one zip using the same approach `SammelabrechnungExport.swift` already uses — do
  not reimplement any XLSX-patching logic, only orchestrate the existing exporters.
- Match the existing file-naming convention from recent commits (`TN-Sportler`/`TN-Helfer`-style naming)
  for whatever this rollup's files are named within the bundle.
- Add a new entry to the existing "Berichte" toolbar menu pattern (`TrainingsListView`'s menu) to reach
  this new season export.
- Handle a season with zero periods/data gracefully — an empty-but-valid bundle or a clear "nothing to
  export" state, not a crash.
- Add at least one test covering the season-rollup orchestration, reusing
  `SammelabrechnungExportTests.swift`'s existing fixtures/patterns where possible.
- Update `.wolf/anatomy.md`/`.wolf/memory.md` per the OpenWolf protocol.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] The new season export function calls into the existing
      `KostZExporter`/`PraeExport`/`TrainingsfrequenzlisteExport` — confirmed by code review, no
      duplicated template-patching logic
- [ ] The resulting bundle contains every period's files for the selected season, correctly named
- [ ] Reachable via a new entry in the existing "Berichte" toolbar menu
- [ ] A season with zero periods/data doesn't crash — produces an empty-but-valid bundle or a clear
      "nothing to export" state
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions), plus at least one new test for the season-rollup orchestration

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- The new season-export function + its call sites into the existing exporters
- New test name(s) + pass output
- Build/test tails with exit codes

## Notes

Respect cerebrum.md's already-settled decisions on PRAE name-order scope and Trainingsfrequenzliste's
Y3/D3 field-sourcing rules — this phase orchestrates the existing exporters, it does not change their
internal field-sourcing behavior.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
