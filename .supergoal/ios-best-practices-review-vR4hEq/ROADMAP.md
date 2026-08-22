# Roadmap: iOS best-practices review & enhancement suggestions — BlindensportGraz

**Task:** Audit the BlindensportGraz SwiftUI/SwiftData/CloudKit iOS app against best practices
(SwiftData & iCloud sync, architecture, accessibility, security/account admin) and produce a
prioritized report of findings plus new-feature/enhancement suggestions. Report only — no code changes.
**Type:** brownfield, ui, review (no `bugfix`/`refactor` — explicitly report-only per user's Stage 1 answer)
**Created:** 2026-08-19
**Total phases:** 6

## Context summary

- **Stack:** SwiftUI + SwiftData (local store) + manual CloudKit public-database sync layer
  (`CloudKitSync.swift`), iOS 26.0 minimum deployment target, XcodeGen-generated project
  (`project.yml` → `BlindensportGraz.xcodeproj`, never hand-edited). Companion SPM package `RootCLI/`
  (Vapor web admin tool + `rootcli` CLI + `CloudKitS2SCore` shared library) talks to the same CloudKit
  container server-to-server.
- **Package manager:** Swift Package Manager (ZIPFoundation for the app target; NIO/Vapor/crypto deps
  for RootCLI).
- **Build / test / lint commands:** `xcodebuild build`/`xcodebuild test` (documented in
  `BlindensportGraz/CLAUDE.md`) — **not used as mandatory commands in this run**; see tools.md for why
  (sandbox `errSecInternalComponent` block, pre-existing/unfixable in this environment). This run is
  static-analysis-only.
- **Risky areas:** CloudKit public-DB security posture (client-side-only role enforcement, default
  World read/write), a live TEST-ONLY admin-role backdoor for a specific email, near-zero
  accessibility API usage despite VoiceOver being the primary real-world usage mode, zero test
  coverage on role-escalation logic.

## Assumptions

- Report delivered as one published Artifact (Markdown) plus a chat summary — not multiple handed-off
  files.
- New-feature suggestions stay within the app's existing domain (Austrian blind-sports club
  administration: Torball/Goalball/Showdown/etc., Sport Austria paperwork) rather than proposing an
  unrelated pivot.
- RootCLI/Vapor companion is in scope for the security audit (shares the CloudKit data/auth model with
  the iOS app) but out of scope for the accessibility audit (admin web tool, not the iOS app surface).
- Every already-settled decision documented in `.wolf/cerebrum.md` (Decision Log / Do-Not-Repeat) is
  treated as intentional and NOT re-flagged as a bug (e.g. `.changedKeys` last-write-wins sync
  strategy, iOS 26 minimum target, per-export-form field-sourcing divergences, tournaments being
  date-only).

## Risk top 3

1. **Findings without evidence read as opinion, not audit.** — likelihood: medium, mitigation: every
   phase requires `file:line` citations and a minimum finding count; phase 6 spot-checks a sample.
2. **Re-flagging already-accepted tradeoffs from cerebrum.md as new bugs.** — likelihood: medium,
   mitigation: THINKING.md's "already-known findings" section and each phase's Notes fold in the
   relevant Decision Log / Do-Not-Repeat context up front.
3. **Feature suggestions that re-litigate explicit past user decisions** (date-only tournaments, PRAE
   name-order scope, Trainingsfrequenzliste field-sourcing rules). — likelihood: low, mitigation: phase
   5's Notes list the specific settled decisions to respect.

## Phase map

| # | Phase | Depends on | Deliverable |
|---|-------|------------|-------------|
| 1 | Architecture & code organization audit | — | `report/01-architecture.md` |
| 2 | SwiftData & CloudKit sync audit | — | `report/02-swiftdata-cloudkit.md` |
| 3 | Security & account admin audit | 2 | `report/03-security.md` |
| 4 | Accessibility audit | — | `report/04-accessibility.md` |
| 5 | Enhancement & new-feature ideation | 1, 2, 3, 4 | `report/05-enhancements.md` |
| 6 | Report compilation & polish | 1, 2, 3, 4, 5 | Published Artifact + `report/REPORT.md` |

---

## Phase 1 — Architecture & code organization audit

**Why:** Establishes whether the app's module boundaries, state management, and code organization
support safe long-term growth — foundational context the other audits and the feature-ideation phase
build on.

**Deliverables:**
- `report/01-architecture.md`

**Acceptance criteria:**
- [ ] At least 8 concrete findings, each with a `file:line` (or file name for file-level findings)
      citation and a specific recommendation (not "consider refactoring").
- [ ] Covers: view/business-logic separation (e.g. `Views.swift` files mixing SwiftUI view code with
      CKRecord push calls directly), file size/god-object risk (Models.swift ~38KB/848 lines,
      CloudKitSync.swift ~921 lines, TrainingsViews.swift ~641 lines), the free-text `role`/`sport`
      string fields (not enums) noted in cerebrum.md as a recurring bug source, the in-app
      `BlindensportGraz/CLAUDE.md` doc-drift (stale username/ClubMember references), the RootCLI
      package's independent hand-maintained mirror structs (documented drift risk in cerebrum.md).
- [ ] Each finding tagged Severity: High/Medium/Low and Effort: S/M/L.
- [ ] Does not re-flag anything cerebrum.md's Decision Log already treats as a deliberate, accepted
      tradeoff (cite the entry when excluding something for this reason, so phase 6 can verify).

**Mandatory commands:**
- `grep -rn "CloudKitSync.shared" BlindensportGraz --include="*.swift" | wc -l` (evidence for
  view-layer-calls-sync-directly finding — surface the count in transcript)
- `wc -l BlindensportGraz/*.swift | sort -rn | head -10` (evidence for file-size finding)

**Evidence required:**
- The two command outputs above, pasted into the transcript.
- The finished `report/01-architecture.md` content (or its finding count + first 3 findings) printed
  into the transcript.

**Dependencies:** none

---

## Phase 2 — SwiftData & CloudKit sync audit

**Why:** This is the app's most architecturally unusual and highest-risk layer (manual public-DB sync
bypassing SwiftData's native CloudKit mirroring) and the user explicitly called it out as a focus area.

**Deliverables:**
- `report/02-swiftdata-cloudkit.md`

**Acceptance criteria:**
- [ ] At least 8 concrete findings with `file:line` citations.
- [ ] Explicitly covers: fire-and-forget push with `print()`-only error handling and no retry/offline
      queue (`CloudKitSync.swift` `save`/`upsert`, and every `Task { do {...} catch { print(...) } }`
      delete/push site), the `.changedKeys` last-write-wins conflict strategy (cite the existing doc
      comment around `upsert`, frame as accepted tradeoff with a residual-risk note, not a new bug),
      no user-visible sync-failure/pending-sync state anywhere in the UI, `syncAll()`'s pull ordering
      dependencies, the local `ModelContainer`'s destructive-reset-on-schema-mismatch fallback in
      `BlindensportGrazApp.swift` (data-loss risk framing), and whether `@Query` usage anywhere risks
      large in-memory fetches without pagination given the shared/public multi-club-worth-of-data model.
- [ ] Each finding tagged Severity/Effort as in phase 1.
- [ ] Distinguishes "accepted tradeoff, note residual risk" findings from "actual gap, should fix"
      findings — don't conflate them.

**Mandatory commands:**
- `grep -n "print(" BlindensportGraz/CloudKitSync.swift | wc -l` (evidence for logging finding)
- `grep -c "Task {" BlindensportGraz/CloudKitSync.swift` (evidence for fire-and-forget pattern count)

**Evidence required:**
- The two command outputs above in transcript.
- Finished `report/02-swiftdata-cloudkit.md` finding count + first 3 findings printed into transcript.

**Dependencies:** none

---

## Phase 3 — Security & account administration audit

**Why:** User account administration and role-based access are core CLAUDE.md requirements; this app
also stores real people's SVNR/IBAN (Austrian social-security/bank data), raising the stakes.

**Deliverables:**
- `report/03-security.md`

**Acceptance criteria:**
- [ ] At least 8 concrete findings with `file:line` citations.
- [ ] Explicitly covers: `User.testAdminEmail` hardcoded TEST-ONLY admin grant for a specific real
      email address still live in `Models.swift` a month past its own "remove once testing is done"
      note (High severity, cite the cerebrum.md 2026-07-19 entry as context) — this is the single
      most important finding in the whole report; make sure it lands clearly, with an explicit
      "recommend removing before any wider release / TestFlight distribution beyond the current
      tester" call-out;
      the CloudKit public-DB default World-role read/write vs. 34 client-side-only `role`/`isRoot`
      checks (cite `RootCLI/README.md`'s "Security Roles" section as the documented-but-optional
      mitigation, and note it only names `UserIdentity`/`ClubMember`, not the other 9 record types);
      zero unit test coverage on `elevateIfDesignatedRoot`/`elevateIfTestAdmin`
      (`grep` `BlindensportGrazTests` for these symbols returns nothing — confirm and cite);
      no email-format validation anywhere user email is entered; no IBAN/SVNR format validation
      despite exporting this data on official forms; whether SVNR/IBAN ever appear in `print()`
      output reachable in this codebase (check `PraeExport.swift`/`KostZExport.swift`/CloudKitSync
      push sites); `RootCLI`'s `clubmembersapi` HTTP Basic Auth over what transport (confirm TLS
      posture is the deployer's responsibility, not app-enforced, and say so).
- [ ] Each finding tagged Severity/Effort.
- [ ] Cross-references phase 2's sync findings where the security implication overlaps (e.g. link to
      the CloudKit-DB findings rather than re-deriving them) — read `report/02-swiftdata-cloudkit.md`
      first.

**Mandatory commands:**
- `grep -n "testAdminEmail" BlindensportGraz/Models.swift` (confirm the backdoor is still present, cite line)
- `grep -rln "elevateIfDesignatedRoot\|elevateIfTestAdmin" BlindensportGrazTests` (confirm zero test coverage — expect no output)

**Evidence required:**
- The two command outputs above in transcript.
- Finished `report/03-security.md` finding count + the testAdminEmail finding printed in full into
  the transcript.

**Dependencies:** phase 2 (`report/02-swiftdata-cloudkit.md` must exist and be read first)

---

## Phase 4 — Accessibility audit

**Why:** The user's own memory record confirms VoiceOver is this app's primary real-world usage mode
(the user personally relies on it), not an edge case — the user explicitly selected this as a focus
area.

**Deliverables:**
- `report/04-accessibility.md`

**Acceptance criteria:**
- [ ] At least 8 concrete findings with `file:line` citations.
- [ ] Explicitly covers: the accessibilityLabel/Hint usage gap (only 4 of 33 app source files use
      either API at all — cite the grep), Dynamic Type support (no `dynamicTypeSize`/
      `minimumScaleFactor` usage found anywhere — confirm via grep), decorative icon/badge views
      (`SportGlyph` in `SportIcons.swift`, already correctly `.accessibilityHidden(true)` per
      cerebrum.md — cite as a positive example, don't re-flag it as a gap), the documented
      nested-sheet-freezes-under-VoiceOver class of bug (cerebrum.md 2026-07-18 entries, bug-070/
      bug-072) — check whether the codebase has any OTHER nested-`.sheet`-inside-a-`.sheet` instances
      beyond the ones already fixed, since that's a recurring pattern risk; Menu-based role editors
      (`TeamDetailView`'s role Menu already has explicit accessibilityLabel/Hint per cerebrum.md —
      confirm and check whether other custom interactive controls added since lack the same
      treatment, e.g. `TrainingFavorite` chip's `.contextMenu` for delete); color-only status
      indicators (any `Color`-only state signaling with no text/icon backup, e.g. tournament
      planned/ongoing/finished status); form field labeling/hints for the PRAE/KostZ/
      Trainingsfrequenzliste screens specifically, since those are admin-heavy multi-step flows.
- [ ] Each finding tagged Severity/Effort, with Severity weighted toward "impacts VoiceOver users"
      since that is this app's primary usage mode, not a generic WCAG checklist weighting.
- [ ] Does NOT suggest testing by disabling VoiceOver, and does NOT ask the user to manually test —
      frame verification recommendations as "test with VoiceOver on in Simulator" or code-level fixes.

**Mandatory commands:**
- `grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift"` (cite the
  4-file result)
- `grep -rn "\.sheet(" BlindensportGraz --include="*.swift" | wc -l` (evidence for sheet-nesting risk
  surface size)

**Evidence required:**
- The two command outputs above in transcript.
- Finished `report/04-accessibility.md` finding count + first 3 findings printed into transcript.

**Dependencies:** none

---

## Phase 5 — Enhancement & new-feature ideation

**Why:** The user explicitly asked for "new features," not just a bug list — this phase turns the
audits' findings plus domain knowledge of the app into a prioritized, concrete feature backlog.

**Deliverables:**
- `report/05-enhancements.md`

**Acceptance criteria:**
- [ ] At least 10 distinct suggestions, each with: one-paragraph description, why it fits this app's
      real domain (Austrian blind-sports club administration), rough effort (S/M/L), and which
      existing pattern/file it would extend (not build from scratch where an obvious precedent exists).
- [ ] Read `report/01-architecture.md`, `report/02-swiftdata-cloudkit.md`, `report/03-security.md`,
      `report/04-accessibility.md` first — at least 3 of the 10+ suggestions must be direct, explicit
      follow-ons from a specific audit finding (e.g. "add a visible sync-status indicator" following
      from phase 2's fire-and-forget-push finding) — cite which finding each follow-on addresses.
- [ ] At least 4 suggestions are genuinely new capabilities (not just fixing an audit finding) —
      grounded in what CLAUDE.md's requirements + the app's actual domain implies is still missing,
      e.g.: push-notification-driven reminders for upcoming trainings/tournaments (PushNotifications.swift
      already exists as scaffolding — check its current scope first), a coach/admin dashboard view of
      attendance trends across trainings (TrainingAttendance data already exists per-record, no
      aggregate view found — confirm via grep before proposing), season/year-level reporting beyond
      the existing month/tournament-scoped KostZ and Trainingsfrequenzliste exports, offline-mode
      messaging (since sync is fire-and-forget with no visible state, per phase 2), a calendar/ICS
      export or system-Calendar integration for trainings/tournaments (check whether `EventKit` is used
      anywhere — expect not), an audit log for role changes (isRoot/role escalation currently has no
      history/log per RootView.swift — confirm), and multi-club/multi-section extensibility if that's
      plausible given the club/single-CloudKit-container architecture (frame as a bigger, longer-term
      idea, not a quick win).
- [ ] Does NOT re-propose anything cerebrum.md's Decision Log records as an explicit past user
      rejection or settled decision (date-only tournaments, PRAE name-order scope limited to exported
      forms only, Trainingsfrequenzliste Y3/D3 sourcing rules, no self-service role editing). If in
      doubt whether something is settled, grep cerebrum.md for the topic before including it.
- [ ] Each suggestion explicitly prioritized (P0/P1/P2) considering both user value and the fact this
      is a small club's volunteer-run app (effort/maintenance burden matters more than for a commercial
      product).

**Mandatory commands:**
- `grep -n "PushNotifications" BlindensportGraz/*.swift | head -20` (confirm current push-notification scope before proposing extensions)
- `grep -rn "EventKit\|EKEventStore" BlindensportGraz --include="*.swift"` (confirm no existing Calendar integration — expect no output)

**Evidence required:**
- The two command outputs above in transcript.
- Finished `report/05-enhancements.md` suggestion count + the 3 explicit audit-follow-on suggestions
  printed into transcript, each naming which prior finding it follows from.

**Dependencies:** phases 1, 2, 3, 4

---

## Phase 6 — Report compilation, polish & publish

**Why:** This is the Polish & Harden phase for a report-only deliverable — it's how "every aspect is
perfect" gets enforced when the output is a document, not code: cross-referenced, de-duplicated,
prioritized, evidence-checked, and actually handed to the user in a usable form.

**Sub-passes (each must produce evidence):**
- [ ] **Merge & de-duplicate** — combine all 5 section reports into `report/REPORT.md` with an
      executive summary (top 5 findings across all areas, ranked) at the top, then one section per
      audit area, then the enhancements backlog. Remove/merge any finding that appears in more than
      one section (e.g. a security finding also touched in the architecture pass).
- [ ] **Citation spot-check** — pick at least 6 findings at random across the merged report and
      re-verify their `file:line` citation actually shows what the finding claims (open the file,
      confirm). Report pass/fail count in the transcript. Any citation that doesn't hold up must be
      corrected or removed before publishing.
- [ ] **Consistency check** — confirm no finding contradicts another (e.g. phase 1 and phase 3 both
      touching the same file should agree on severity framing), and confirm no enhancement suggestion
      re-proposes a cerebrum.md-settled decision (re-grep to confirm phase 5's own check held).
- [ ] **Copy pass** — report reads cleanly, consistent Severity/Effort/Priority vocabulary across all
      sections, no placeholder text, no unresolved `{{...}}` template artifacts.
- [ ] **Publish** — load the `artifact-design` skill, then publish `report/REPORT.md` as a Markdown
      Artifact (favicon, title, description per that tool's requirements) and capture the resulting
      URL.
- [ ] **Total finding count sanity check** — report should have roughly 35-55 findings total across
      the 4 audit areas plus 10+ enhancement suggestions; if far outside that range, explain why in
      the transcript (e.g. codebase is smaller/larger than typical) rather than padding or truncating
      artificially.

**Mandatory commands:**
- `grep -c "^###\|^-\s*\*\*" report/REPORT.md` or an equivalent count of the merged report's finding
  entries — surface the number in transcript as the total finding count sanity check.
- `wc -l report/REPORT.md`

**Evidence required:**
- The executive summary (top 5 findings) printed into the transcript.
- The citation spot-check results (6 findings checked, pass/fail each) printed into the transcript.
- The published Artifact URL printed into the transcript.
- Final `report/REPORT.md` line count and total finding/suggestion count.
