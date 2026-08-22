SUPERGOAL_PHASE_START
Phase: 5 of 6 — Enhancement & new-feature ideation
Task: Produce a prioritized backlog of enhancements and new features for BlindensportGraz, grounded in the audit findings and the app's real domain; produce report/05-enhancements.md
Type: brownfield, feature
Mandatory commands: grep -n "PushNotifications" BlindensportGraz/*.swift | head -20 ; grep -rn "EventKit\|EKEventStore" BlindensportGraz --include="*.swift"
Acceptance criteria: 6
Evidence required: command outputs, suggestion count, 3 audit-follow-on suggestions with cited findings
Depends on phases: 1, 2, 3, 4 (read all four report files first)

## Why

The user explicitly asked for enhancement and new-feature suggestions, not just a bug list. This phase
turns the four audits' findings plus real domain knowledge of the app (Austrian blind-sports club
administration, Sport Austria paperwork) into a concrete, prioritized backlog — not generic iOS
boilerplate ideas that could apply to any app.

## Work

- Read `report/01-architecture.md`, `report/02-swiftdata-cloudkit.md`, `report/03-security.md`, and
  `report/04-accessibility.md` in full before writing anything.
- Grep `.wolf/cerebrum.md`'s Decision Log for topics that are already settled so nothing here
  re-litigates them. At minimum check for and respect: tournaments are date-only (no time picker,
  2026-08-18 preference — don't suggest adding time back); PRAE Nachname-Vorname name order is scoped
  to the exported form only, not app UI (2026-08-18 — don't suggest changing in-app pickers); the
  Trainingsfrequenzliste's Y3 (Sportstätte) sources from `Training.location` while D3 (Verein/LV) stays
  a hardcoded club-name string, deliberately NOT derived per-training (2026-08-18 — don't suggest
  making D3 dynamic); no self-service role editing exists by design (only root can change roles,
  2026-07-16 — don't suggest letting coaches self-promote).
- For each of the four audit reports, pick at least one finding whose natural fix is better framed as
  a feature than a bug fix, and write it up as an explicit follow-on suggestion, citing which report
  and finding it addresses (e.g. "Follows from report/02-swiftdata-cloudkit.md Finding 3 (fire-and-
  forget push, no visible sync state): add a lightweight sync-status indicator...").
- Check current scope of existing scaffolding before proposing extensions to it:
  - `PushNotifications.swift` — read it (it's short, ~488 tokens per anatomy.md) and the mandatory
    grep results to see exactly what push notifications currently do (per `BlindensportGrazApp.swift`'s
    `handleEventCreated`/`handleTournamentCreated`/`handleTrainingCreated`, these look like "new item
    created" toasts only) before proposing reminder-style notifications as a new capability.
  - `TrainingAttendance`/`TournamentAttendance` (Models.swift) — confirm these are per-record only
    with no aggregate/trend view anywhere (grep Views files for any chart/aggregate over attendance)
    before proposing a coach/admin attendance-trends dashboard.
  - `EventKit`/calendar integration — confirm absent (mandatory grep) before proposing a
    Calendar/.ics export for trainings/tournaments.
  - Role-change history — confirm `RootView.swift`/`Models.swift` have no audit log of `role`/`isRoot`
    changes (grep for anything like `RoleChangeLog`/`AuditLog` — expect none) before proposing one,
    which would also directly harden the `testAdminEmail` finding from phase 3 (a real audit log would
    have surfaced that grant being used).
- Write at least 10 distinct suggestions, each with: one-paragraph description, why it fits this app's
  real domain (not "any app could use this"), rough effort (S/M/L), which existing pattern/file it
  would extend where an obvious precedent exists (e.g. "mirrors TrainingFavorite's shared/team-wide
  scope pattern" or "extends the existing Berichte menu alongside PRAE/KostZ/Trainingsfrequenzliste"),
  and a priority tag P0 (do soon)/P1 (valuable, not urgent)/P2 (nice-to-have/longer-term). At least 3
  must be explicit audit-follow-ons (cited above) and at least 4 must be genuinely new capabilities not
  tied to fixing an existing finding — candidates to develop (verify each against the confirm-scope
  checks above before writing):
  - Visible sync status indicator (follows report/02 finding on fire-and-forget push).
  - Training/tournament reminder notifications (extends `PushNotifications.swift`'s existing
    infrastructure, if scope confirms it's currently creation-toasts-only).
  - Attendance-trends view for coaches/admins (aggregates existing `TrainingAttendance` records — no
    new data model needed if the aggregation can be computed client-side).
  - Season/year-level reporting beyond the existing month/tournament-scoped KostZ and
    Trainingsfrequenzliste exports (extends the existing `Sammelabrechnung`-style bundling pattern).
  - Role-change audit log (small, high-value, directly relevant to phase 3's security findings).
  - Calendar/.ics export or system-Calendar integration for trainings/tournaments (only if EventKit
    confirmed absent).
  - IBAN/SVNR format validation with non-blocking warnings (follows report/03's validation finding —
    can double as a security-audit-follow-on AND a UX enhancement).
  - Multi-club/multi-section extensibility — frame explicitly as a bigger, longer-term P2 idea given
    the current single-CloudKit-container architecture (report/02's findings on hand-maintained schema
    strings are directly relevant to how much work this would be) — do not undersell the effort here.
  - Any additional domain-grounded idea that emerges naturally from the read-through (e.g. something
    tied to the Sport Austria paperwork workflow, team roster management, or the RootCLI admin tooling)
    — don't pad with generic ideas just to hit the count; if fewer than 10 genuinely good ideas emerge,
    say so explicitly rather than padding, but 10 is realistic given the app's scope.
- Write `report/05-enhancements.md` in a consistent format: `**Suggestion N (Priority, Effort):**
  <title>` followed by the description, domain-fit rationale, and (if applicable) the audit finding it
  follows from.

## Acceptance criteria (all must pass — verify each in transcript)

- At least 10 distinct suggestions, each with description, domain-fit rationale, effort, and priority.
- At least 3 suggestions are explicit, cited follow-ons from a specific finding in reports 1-4.
- At least 4 suggestions are genuinely new capabilities, each verified against existing scope via the
  confirm-scope greps/reads listed in Work (not proposed blind).
- No suggestion re-proposes anything `.wolf/cerebrum.md`'s Decision Log records as an explicit past
  user decision or rejection (the four examples listed in Work at minimum must be respected).
- Each suggestion has an explicit P0/P1/P2 priority.

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `grep -n "PushNotifications" BlindensportGraz/*.swift | head -20`
- `grep -rn "EventKit\|EKEventStore" BlindensportGraz --include="*.swift"`

## Evidence required in transcript

- Both command outputs above, pasted verbatim.
- `report/05-enhancements.md`'s total suggestion count.
- The 3+ explicit audit-follow-on suggestions printed in full, each naming which report/finding it
  follows from.

## Notes

No code changes. This phase is the one place in the run where genuine creative/product judgment
matters most — ground every idea in what actually exists in this codebase and this club's real needs
(Sport Austria federation paperwork, VoiceOver-primary users, volunteer-run small club — effort/
maintenance burden matters as much as raw user value here).
