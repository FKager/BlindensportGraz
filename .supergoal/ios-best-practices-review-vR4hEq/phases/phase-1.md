SUPERGOAL_PHASE_START
Phase: 1 of 6 — Architecture & code organization audit
Task: Audit BlindensportGraz's SwiftUI/SwiftData app architecture and code organization against best practices; produce report/01-architecture.md
Type: brownfield, review
Mandatory commands: grep -rn "CloudKitSync.shared" BlindensportGraz --include="*.swift" | wc -l ; wc -l BlindensportGraz/*.swift | sort -rn | head -10
Acceptance criteria: 4
Evidence required: command outputs, report finding count + first 3 findings
Depends on phases: none

## Why

Establishes whether the app's module boundaries, state management, and code organization support
safe long-term growth — foundational context the other audits and the feature-ideation phase build on.

## Work

- Read `.wolf/anatomy.md` first for the file map (already scanned — don't re-derive it from `find`).
- Read `.wolf/cerebrum.md`'s Decision Log and Do-Not-Repeat sections (grep for `^## Decision Log` and
  `^## Do-Not-Repeat` to jump to them) so accepted tradeoffs aren't re-flagged as bugs.
- Read `BlindensportGraz/Models.swift`, `BlindensportGraz/CloudKitSync.swift`, one or two of the larger
  `*Views.swift` files (e.g. `TrainingsViews.swift`, `TournamentsViews.swift`), and
  `BlindensportGraz/CLAUDE.md` (the in-app architecture doc, distinct from the repo-root one).
- Audit and write findings for:
  - View/business-logic separation — do SwiftUI views call `CloudKitSync.shared.push*` directly
    (bypassing a service/viewmodel layer)? Use the mandatory grep count as evidence.
  - File size / god-object risk — `Models.swift` (~848 lines, 11 `@Model` classes in one file),
    `CloudKitSync.swift` (~921 lines, every push/pull/delete for every model in one class),
    `TrainingsViews.swift` (~641 lines). Use the mandatory `wc -l` output as evidence.
  - Free-text `role`/`sport` string fields (not closed enums) — cerebrum.md's 2026-08-18
    `TeamMembership.role` entry documents this as an already-hit bug source
    (`!["coach","assistant"].contains(role)` silently matching typos). Confirm whether `sport` has the
    same shape (free text everywhere per `SportIcons.swift`'s normalization comment) and whether other
    "not X" role-string checks exist beyond the one already fixed.
  - `BlindensportGraz/CLAUDE.md` doc-drift — compare its claims (7 models, `username` field,
    `ClubMember` naming) against the real `Models.swift` (11 models via SwiftData class inheritance,
    no `username`, class renamed to `Member`) and note it as a maintenance-risk finding, not a
    functional one.
  - `RootCLI`'s hand-maintained mirror structs (`ClubMemberInput`, `ClubMemberBulkInput`, etc.) that
    independently duplicate `Models.swift`'s shape with no shared code — cerebrum.md's 2026-07-18/
    2026-07-30 entries already document this drift risk being hit twice; cite those entries and assess
    current severity.
  - State management pattern — confirm/deny consistent `@Environment(\.modelContext)` + `@Query` usage
    vs. any view doing manual SwiftData fetches or holding duplicate state.
  - Error handling consistency — count `try?` (silent-failure) vs. `try`/`do-catch` usage across the
    app target; is failure ever surfaced to the user, or always silently swallowed?
- Tag each finding `Severity: High/Medium/Low` and `Effort: S/M/L`.
- Write `report/01-architecture.md` with a numbered/bulleted findings list, each finding formatted as:
  `**Finding N (Severity, Effort):** <one-line summary>` followed by a short paragraph with the
  `file:line` citation and concrete recommendation.

## Acceptance criteria (all must pass — verify each in transcript)

- At least 8 concrete findings, each with a `file:line` (or file name) citation and a specific,
  actionable recommendation — no vague "consider refactoring this" without specifics.
- Explicitly covers all six bullets under Work's "Audit and write findings for" list above.
- Every finding tagged with both Severity and Effort.
- No finding re-flags something `.wolf/cerebrum.md`'s Decision Log already treats as a deliberate,
  accepted tradeoff — if something looks worth flagging but cerebrum.md shows it was a conscious
  choice, either omit it or explicitly frame it as "accepted tradeoff, noting residual risk" and cite
  the cerebrum.md entry.

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `grep -rn "CloudKitSync.shared" BlindensportGraz --include="*.swift" | wc -l`
- `wc -l BlindensportGraz/*.swift | sort -rn | head -10`

## Evidence required in transcript

- Both command outputs above, pasted verbatim.
- `report/01-architecture.md`'s total finding count and its first 3 findings printed in full.

## Notes

This phase produces no code changes — do not edit any `.swift` file. Write only to
`report/01-architecture.md` under this run's root. If a finding seems to require re-reading a file
already summarized in `.wolf/anatomy.md` in enough detail, trust the anatomy summary rather than
re-reading the whole file, per this project's OpenWolf token-discipline convention — but for any file
this phase cites a specific `file:line` from, read enough of that actual file to confirm the line is
accurate (don't cite from memory/summary alone).
