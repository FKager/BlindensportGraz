SUPERGOAL_PHASE_START
Phase: 7 of 19 — Split Models.swift & closed role/sport enums
Task: Split Models.swift into per-model files and convert role/sport free-text fields to closed enums with legacy-value normalization.
Type: brownfield, refactor
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...; grep -rn role/sport comparisons
Acceptance criteria: 7
Evidence required: new file list, grep zero raw-comparison confirmation, new fallback test output, build/test tails
Depends on phases: 6

## Why

audit.md's Architecture Finding 2 (848-line file, 11 `@Model` classes in one file) + Finding 3
(free-text `role`/`sport` strings already caused a confirmed bug — a `!["coach","assistant"].contains(role)`
typo-prone check in TournamentsViews.swift, fixed narrowly at one call site but the underlying free-text
field left able to recur elsewhere).

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first. Re-read `Models.swift` in full (848 lines) to plan
  both the split and the enum extraction together, since they touch the same file.
- Split `Models.swift` into one file per `@Model` class, grouping only where the SportEvent/Training/
  Tournament class-inheritance hierarchy requires shared context (check cerebrum.md's Decision Log for
  why that hierarchy exists before splitting it apart).
- Grep the entire codebase for every distinct literal value ever compared against `.role` (e.g.
  `"player"`, `"coach"`, `"assistant"`) and against `.sport` (cross-check against `SportIcons.swift`'s
  existing display-name mapping, which already has a canonical list) — derive the enum case sets from
  real usage, not guesses.
- Introduce a closed `Role` enum (`RawRepresentable, String`) on `TeamMembership.role` and a closed
  `Sport` enum on `SportEvent/Training/Tournament.sport`, each with a `static func normalize(_ raw:
  String) -> Self` that maps every known legacy string to its case AND provides a defined fallback case
  (e.g. `.other(String)` or a dedicated `.unknown` case that retains the original string) for anything
  unrecognized — never crash or silently drop data on an unexpected stored value.
- Update every `role == "..."`/`role != "..."`/`sport == "..."`/`sport != "..."` comparison across the
  app (including the exact bug audit.md cites: `TournamentsViews.swift`'s `role == "player"` check at
  the line the audit names) to use the enum form instead.
- Update `CloudKitSync`'s push/pull for `TeamMembership`/`SportEvent`/`Training`/`Tournament` to
  correctly encode the enum's raw value on push and decode+normalize on pull.
- Add unit tests: at least one per affected model type (TeamMembership/SportEvent/Training/Tournament)
  feeding a deliberately garbage raw string through the normalize path and confirming it lands in the
  defined fallback case rather than crashing, plus a push→pull round-trip test for at least one enum
  field.
- Update `.wolf/anatomy.md` for the new file layout; add a `.wolf/cerebrum.md` Decision Log entry
  documenting the enum migration and its legacy-value fallback behavior.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] `Models.swift` no longer exists as a single 848-line file; each `@Model` class lives in its own
      file (SportEvent/Training/Tournament grouped only if their inheritance genuinely requires it)
- [ ] `Role` and `Sport` are closed enums, not raw `String` fields
- [ ] `grep -rn 'role == "\|role != "\|sport == "\|sport != "' BlindensportGraz --include="*.swift"`
      returns 0
- [ ] A normalization fallback exists for unrecognized legacy string values, covered by a unit test with
      a deliberately garbage raw value that does NOT crash and does NOT silently drop the membership/event
- [ ] CloudKit push/pull round-trip for the affected enum fields is covered by a passing unit test
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions), plus at least 3 new fallback-normalization tests (one per
      affected model type)
- [ ] `.wolf/anatomy.md` and `.wolf/cerebrum.md` updated

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `grep -rn 'role == "\|role != "\|sport == "\|sport != "' BlindensportGraz --include="*.swift"`

## Evidence required in transcript

- New file list for the split
- `grep` output confirming zero raw-string comparisons remain
- New fallback/round-trip test names + pass output
- Build/test tails with exit codes

## Notes

This is the highest-risk mechanical phase in the whole run — an enum migration that mishandles one
legacy stored value could silently hide a membership or event from its team. Be conservative: when in
doubt about whether a raw value is truly obsolete, keep a fallback case for it rather than assuming it's
safe to drop.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
