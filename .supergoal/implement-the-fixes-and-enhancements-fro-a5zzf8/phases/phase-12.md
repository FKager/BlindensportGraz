SUPERGOAL_PHASE_START
Phase: 12 of 19 — Accessibility labels & control equivalents
Task: Add accessibilityLabel/Hint coverage across the ~29 gap files, fix EventsViews.swift's icon-only button, add an accessibilityAction for TrainingFavorite delete, and add Picker hints where useful.
Type: brownfield, accessibility
Mandatory commands: xcodegen generate; xcodebuild build ...; grep count for accessibilityLabel/Hint files; xcodebuild test ...
Acceptance criteria: 6
Evidence required: before/after file count, EventsViews.swift + TrainingFavorite diffs, build/test tails
Depends on phases: 1

## Why

audit.md's Accessibility Finding 1 (only 4 of 33 files use any accessibility API at all, despite
VoiceOver being this app's primary real-world usage mode — the user personally relies on it) + Finding 2
(EventsViews.swift's icon-only add button has no label, unlike the identical pattern elsewhere) +
Finding 3 (TrainingFavorite delete is only reachable via long-press contextMenu, no VoiceOver equivalent)
+ Finding 9 (report Pickers could use hints where the effect isn't obvious).

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first — accessibility conventions for this app are
  documented there and in the 4 files that already do this correctly.
- Study the existing correct pattern before writing anything: `TeamsViews.swift:198-199`'s role-capsule
  Menu (`.accessibilityLabel("Rolle: ...")` + `.accessibilityHint("Doppeltippen, um die Rolle zu
  ändern")`), and the existing usage in `TournamentsViews.swift`/`MembersViews.swift`/`TrainingsViews.swift`.
  Match this app's German-language label/hint style exactly — don't introduce English strings.
- Run `grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift"` to get
  the current 4-file baseline, then work through every other file that has interactive controls
  (buttons, custom tap targets, Menus, icon-only controls) — the audit specifically names
  `EventsViews.swift`, `DashboardView.swift`, `AccountView.swift`, `PraeViews.swift`, `KostZViews.swift`
  as having zero coverage; check every other view file too, not just those five.
- Fix `EventsViews.swift:173`'s icon-only add button (`Button { showAdd = true } label: { Image(systemName:
  "plus") }`) with `.accessibilityLabel`, matching `TrainingsViews.swift:567-576`'s established
  import/export button pattern exactly (same wording style).
- Add `.accessibilityAction(named: "Löschen")` alongside `TrainingFavorite`'s existing `.contextMenu` at
  `TrainingsViews.swift:107` — additive, do not remove the contextMenu, both should trigger the same
  underlying delete call.
- Add `.accessibilityHint` to the Pickers in `PraeViews.swift:48,55,216`, `KostZViews.swift:33`,
  `TrainingsfrequenzlisteViews.swift:57,62` only where the selection's effect isn't obvious from the
  label alone (audit.md's own example: "Zeitraum" toggling between half-years) — not a blanket
  find-and-decorate pass on every Picker.
- Do NOT touch: `SportGlyph`'s existing `.accessibilityHidden(true)` (Positive Finding 6), tournament
  status's already-correct non-color-only signaling (Positive Finding 8), or `TeamDetailView`'s
  role-Menu accessibility treatment (Positive Finding 5) — these are already correct per audit.md.
- Spot-check every `.sheet(` site touched by this phase's edits (there are 22 total in the app per
  audit.md) to confirm no nested-sheet-inside-a-sheet is introduced (the documented VoiceOver freeze
  class of bug, bug-070/bug-072).
- Update `.wolf/anatomy.md`/`.wolf/memory.md` per the OpenWolf protocol.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] `grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift" | wc -l`
      rises well above 4, covering every file with interactive controls (verify against the actual file
      list, not just a bigger number)
- [ ] `EventsViews.swift`'s add button has `.accessibilityLabel` matching the established pattern
- [ ] `TrainingFavorite`'s delete is reachable via both the existing `.contextMenu` AND a new
      `.accessibilityAction`, both calling the same underlying delete function
- [ ] Already-correct examples (`SportGlyph`, `TeamDetailView`'s role Menu, tournament status coloring)
      are left untouched by this phase's diff
- [ ] No `.sheet`-inside-a-`.sheet` nesting is introduced by any change in this phase
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions) (UI-only phase, must not break compilation/tests)

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift" | wc -l`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- Before/after file-count from the grep command
- `EventsViews.swift` and `TrainingFavorite` diffs specifically
- Build/test tails with exit codes

## Notes

Verification here is code-level/Simulator-preview-based, not manual on-device VoiceOver testing by the
user — this user personally relies on VoiceOver and shouldn't need to manually verify every label; get
the pattern right by matching the app's own established correct examples closely.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
