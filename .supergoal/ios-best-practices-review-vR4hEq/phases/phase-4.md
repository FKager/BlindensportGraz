SUPERGOAL_PHASE_START
Phase: 4 of 6 — Accessibility audit
Task: Audit BlindensportGraz's accessibility (VoiceOver-first) against best practices; produce report/04-accessibility.md
Type: brownfield, review, ui
Mandatory commands: grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift" ; grep -rn "\.sheet(" BlindensportGraz --include="*.swift" | wc -l
Acceptance criteria: 5
Evidence required: command outputs, report finding count + first 3 findings
Depends on phases: none

## Why

The user personally relies on VoiceOver to operate their own phone and has explicitly said they
cannot meaningfully test with it turned off (documented in `.wolf/cerebrum.md`'s standing User
Preferences) — VoiceOver is this app's primary real-world usage mode, not an edge case, and the user
explicitly selected accessibility as a focus area in Stage 1 intake.

## Work

- Grep `.wolf/cerebrum.md`'s User Preferences and Do-Not-Repeat sections for every VoiceOver-related
  entry (there are several: bug-071, bug-070, bug-072, the nested-sheet-freeze fixes, the
  `TeamDetailView` role-Menu accessibility labels) — read them before starting so already-fixed issues
  aren't re-flagged as new, and so the pattern of what caused past freezes is understood.
- Read `BlindensportGraz/SportIcons.swift` (already has correct `.accessibilityHidden(true)` usage per
  cerebrum.md — confirm and cite as a positive example).
- Read the 4 files the mandatory grep identifies as already using `accessibilityLabel`/`accessibilityHint`
  (`TournamentsViews.swift`, `TeamsViews.swift`, `MembersViews.swift`, `TrainingsViews.swift`) to see
  what's already covered there, then spot-check 2-3 of the other ~29 app source files that have NO
  accessibility API usage at all (e.g. `EventsViews.swift`, `DashboardView.swift`, `AccountView.swift`,
  `PraeViews.swift`, `KostZViews.swift`) for interactive controls that would benefit from explicit
  labels/hints (icon-only buttons, custom Menu triggers, swipe actions with no visible label,
  color-only status indicators).
- Audit and write findings for:
  - **accessibilityLabel/Hint coverage gap** — only 4 of 33 app source files use either API at all
    (cite the mandatory grep). Identify at least 3 specific interactive elements in files with ZERO
    accessibility API usage that would read ambiguously or silently to VoiceOver (e.g. an icon-only
    toolbar button, a tappable row with no clear accessible label distinguishing it from adjacent
    rows, a status badge conveying meaning by color alone).
  - **Dynamic Type support** — confirm via grep (already done in recon: zero `dynamicTypeSize`/
    `minimumScaleFactor` usage found) whether any layout would clip or truncate at larger Dynamic Type
    sizes, particularly dense list rows (`MemberListView`, `TeamsViews` roster rows) or the multi-field
    Add*View forms.
  - **Sheet-nesting risk surface** — use the mandatory `.sheet(` count as the denominator. Grep for any
    `.sheet(` presentation that itself opens ANOTHER `.sheet` (or a `.fullScreenCover`) without routing
    through a parent's `onDismiss` — the pattern that caused the documented freeze bugs (bug-070/072).
    Check especially any `*ListView` (e.g. `MemberListView`, `ClubMembersListView`) that might be
    presented as a sheet from one place and also present its own child sheet.
  - **Custom interactive controls without labels** — `TeamDetailView`'s role-editing `Menu` already
    has explicit accessibility treatment per cerebrum.md (cite as a positive example). Check whether
    `TrainingFavorite`'s delete `.contextMenu` (a long-press gesture with no visible affordance) has
    equivalent accessibility treatment — a long-press-only action is a known VoiceOver discoverability
    problem (VoiceOver users typically don't have an easy long-press gesture equivalent without a
    custom action) — flag if `.accessibilityAction` isn't used to expose delete as a standard VoiceOver
    action alongside/instead of the context menu.
  - **Color-only status signaling** — check `TournamentsViews.swift`'s status handling
    (planned/ongoing/finished) and `SportIcons.swift`'s accent colors for any place where color alone
    (no text/icon backup) conveys state — a problem for both VoiceOver and color-blind users.
  - **Form field labeling in admin-heavy flows** — spot-check `PraeViews.swift`/`KostZViews.swift`/
    `TrainingsfrequenzlisteViews.swift` (multi-step, admin-only report-generation screens) for
    TextFields/Pickers with only a visual label and no explicit `accessibilityLabel` where the visual
    label text alone might not be read in a useful order by VoiceOver (e.g. a `Picker` embedded in a
    `Menu` trigger showing only an icon).
- Tag each finding `Severity: High/Medium/Low` (weighted toward "impacts VoiceOver users," since that
  is this app's primary usage mode — a Dynamic-Type-only issue is lower severity here than a
  VoiceOver-blocking one) and `Effort: S/M/L`.
- Write `report/04-accessibility.md` in the same format as prior phases.

## Acceptance criteria (all must pass — verify each in transcript)

- At least 8 concrete findings, each with a `file:line` citation.
- Explicitly covers all six bullets under Work's "Audit and write findings for" list above.
- Includes at least one explicitly positive finding (something already done correctly, e.g.
  `SportGlyph`'s `.accessibilityHidden(true)` or `TeamDetailView`'s role-Menu labels) — the report
  should not read as purely negative when the codebase has documented, deliberate accessibility fixes
  already in place.
- Does NOT suggest testing by disabling VoiceOver, and does NOT ask the user to manually test with
  VoiceOver themselves as if that were a neutral ask — frame verification recommendations as
  code-level fixes or "verify via Simulator with VoiceOver enabled" (which doesn't require the user's
  own device/hands).
- Every finding tagged with both Severity and Effort.

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift"`
- `grep -rn "\.sheet(" BlindensportGraz --include="*.swift" | wc -l`

## Evidence required in transcript

- Both command outputs above, pasted verbatim.
- `report/04-accessibility.md`'s total finding count and its first 3 findings printed in full.

## Notes

No code changes. This is a real accessibility need for this specific user, not a generic checklist
exercise — keep findings concrete and actionable, and keep the tone respectful of the significant
VoiceOver work already documented in cerebrum.md rather than implying the app is accessibility-naive.
