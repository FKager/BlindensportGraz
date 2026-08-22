# Thinking: iOS best-practices review & enhancement suggestions — BlindensportGraz

## Goals

Produce a single, well-organized, evidence-backed report (Markdown, published as an Artifact) that:
1. Audits the existing SwiftUI/SwiftData/CloudKit iOS app against current best practices in four
   focus areas the user selected: SwiftData & iCloud sync, architecture/code organization,
   accessibility, and security/account admin.
2. Proposes prioritized enhancements and new features, grounded in what the app already does (not
   generic iOS boilerplate suggestions).
3. Every finding cites a real `file:line` or file name — no vague claims.
4. Produces **zero source code changes** — report only, confirmed with the user in intake.

## Constraints

- Report-only deliverable — no code edits, no `xcodegen generate`, no build attempts as "fixes."
- Do not attempt `xcodebuild`/`codesign` in this sandbox — known, documented, unfixable-here sandbox
  block (see tools.md). Any "does this build" claim must be phrased as a recommendation for the user
  to verify themselves (or via the self-hosted CI runner / `deploy` skill), not as something this run
  verified.
- User is a VoiceOver-primary user of their own phone — cannot test with VoiceOver off. Accessibility
  findings and suggestions must respect that (evaluate via code/simulator-VoiceOver reasoning, never
  suggest "disable VoiceOver to test").
- German-language UI, Austrian sport-federation (Sport Austria) paperwork/export requirements are
  central to this app's actual value — enhancement suggestions should extend that domain, not propose
  generic replacement of working, hand-verified Excel-template-patching logic.
- iOS 26.0 minimum deployment target is deliberate (SwiftData `@Model` inheritance requirement) — not
  a finding to "fix," but worth surfacing as a business-risk note (very small addressable device
  population while iOS 26 is new) since CLAUDE.md's requirements never stated a target OS version.

## Top 3 risks (of this review, not of the app)

1. **Findings without evidence read as opinion, not audit.** Mitigation: every phase spec requires
   `file:line` citations and a minimum finding count; the final Polish phase spot-checks a sample of
   citations for accuracy before publishing.
2. **Re-flagging things the codebase's own history already discusses and deliberately accepted**
   (e.g., `.changedKeys` last-write-wins, iOS 26 minimum target, PRAE/KostZ/Trainingsfrequenzliste's
   per-form formatting divergences). Mitigation: `.wolf/cerebrum.md` was read in full before phase
   work started (see applied-memories.md) and its Decision Log / Do-Not-Repeat conclusions are baked
   into each phase spec's "Notes" section so findings are framed as "known tradeoff, X residual risk"
   rather than "undiscovered bug."
3. **Feature suggestions ignoring already-rejected or already-answered asks.** Mitigation: cerebrum.md
   documents several explicit user decisions (e.g., tournaments are date-only, no time picker; PRAE
   name order Nachname-Vorname *only* in the exported form, not app UI; Trainingsfrequenzliste's Y3
   sourced from Training.location, D3 stays a hardcoded club name) — the feature-ideation phase must
   not suggest re-litigating these.

## Non-obvious dependencies

- The security/account-admin audit phase needs the architecture audit's CloudKitSync findings (public
  DB, `.changedKeys`, fire-and-forget push) as an input — depends on phase 2.
- The final report-compilation phase depends on all four audit phases + the feature-ideation phase,
  since it deduplicates/cross-references and prioritizes across all of them.
- Feature ideation (phase 5) should run after the four audits (not before) so proposed features are
  informed by real architectural constraints (e.g., don't propose a feature that assumes per-user
  private CloudKit sync when the app deliberately uses a shared public DB).

## Already-known findings surfaced by recon (to be verified/expanded by phase work, not re-discovered)

- `User.testAdminEmail` hardcoded admin-role backdoor for the user's own email, marked "remove once
  testing is done" a month ago, still live (Models.swift).
- CloudKit public database default is World-role read/write; app-side role checks (34 call sites of
  `role == "admin"` / `isRoot`) are 100% client-side — RootCLI/README.md documents "Security Roles"
  hardening as a manual, optional, not-yet-confirmed-applied step, and it only names `UserIdentity`/
  `ClubMember` record types, not Team/TeamMembership/Training/Tournament/SportEvent/EventImage/etc.
- Zero unit test coverage on the role-escalation logic (`elevateIfDesignatedRoot`, `elevateIfTestAdmin`)
  despite that logic having a documented history of bugs (bug-173 and others in cerebrum.md).
- CloudKit push is fire-and-forget (`Task { try await ...; catch { print(...) } }`) everywhere in
  CloudKitSync.swift — no retry, no offline queue, no user-visible sync-failure state; errors go to
  `print()` (stdout), not `os.Logger` — invisible in a real device Console/sysdiagnose search.
- No email format validation anywhere (RegisterView, EditAccountView); no IBAN/SVNR format validation
  despite storing these for real people (PRAE/KostZ paperwork).
- Accessibility: only 4 of 33 app source files use `accessibilityLabel`/`accessibilityHint` at all,
  despite VoiceOver being this app's primary real-world usage mode (documented user preference).
- `BlindensportGraz/CLAUDE.md` (in-app architecture doc) is stale — references removed `username`
  field, old `ClubMember` naming (now `Member`), and a 7-model list that's actually 11 models — this
  is itself a "docs drift" finding worth a line in the report.

## Best practices applied (from training-cutoff knowledge; WebSearch available if a specific claim
needs a current-API check, e.g. very recent SwiftData/iOS 26 API surface)

- Apple HIG accessibility guidance (VoiceOver labels/traits/hints, Dynamic Type, sufficient contrast).
- SwiftData/CloudKit sync best practices: conflict resolution strategy, offline-first UX (visible sync
  state, retry), schema evolution discipline.
- iOS app architecture: separation of view/business logic, testability of security-sensitive logic,
  consistent error handling/logging (os.Logger vs print), input validation at data-entry boundaries.
- OWASP Mobile Top 10 categories relevant here: M1 (improper credential usage — N/A, no passwords),
  M4 (insufficient input/output validation), M8 (security misconfiguration — CloudKit World-role
  default), M6 (inadequate privacy controls where relevant to storing SVNR/IBAN).

## Open questions already assumed (surfaced in Stage 6 for correction)

- Assume the report should be delivered as a single published Artifact (Markdown) plus a plain-text
  summary in chat, not as multiple separate files handed to the user.
- Assume "new features" should stay within the app's existing domain (Austrian blind-sports club
  administration) rather than proposing an unrelated pivot.
- Assume RootCLI/Vapor web companion is in-scope for the security audit (it shares CloudKit data and
  auth model) but out of scope for the accessibility audit (it's an admin web tool, not the iOS app).
