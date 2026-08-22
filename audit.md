# BlindensportGraz — Best-Practices Audit & Enhancement Backlog

**Date:** 2026-08-19
**Scope:** SwiftUI/SwiftData/CloudKit iOS app (`BlindensportGraz/`) + companion SPM package (`RootCLI/`,
a Vapor admin web tool + `rootcli` CLI + shared `CloudKitS2SCore` library that talks to the same
CloudKit container). Focus areas per request: SwiftData & iCloud sync, architecture & code
organization, accessibility, security & account administration — plus new-feature/enhancement
suggestions.
**Method:** Static analysis (source reading + targeted `grep`/`wc` evidence gathering) against the
current `main` branch (`06dc804`). **No code changes were made.** No build was attempted — `xcodebuild`/
`codesign` are known to hit a sandbox-level block (`errSecInternalComponent`) in this environment,
documented in `.wolf/cerebrum.md`'s Do-Not-Repeat list; that's an environment constraint, not a code
issue, so it isn't treated as a finding.
**Cross-checked against:** `.wolf/cerebrum.md` (full Decision Log / Do-Not-Repeat history) — findings
below deliberately do not re-flag anything already documented there as a conscious, accepted tradeoff;
where relevant, that context is cited inline.

---

## Executive summary — top 5

1. **A hardcoded admin-role backdoor for one real email address is still live in production code**,
   a month past its own "remove once testing is done" note (`Models.swift:99`). See Security §1.
2. **CloudKit's public database defaults to World-role read/write; all 34 role checks are client-side
   only**, and the one place this is documented as needing hardening only names 2 of 11 record types.
   See Security §2.
3. **All CloudKit writes are fire-and-forget** — no retry, no offline queue, errors only reach
   `print()` (invisible in a real device's Console), and nothing in the UI ever tells the user a save
   didn't sync. See SwiftData & CloudKit §1.
4. **Zero unit test coverage on the role-escalation logic**, despite it having a documented
   multi-session bug history (bug-173 and related cerebrum.md entries). See Security §3.
5. **Only 4 of 33 app source files use any accessibility API**, despite VoiceOver being this app's
   primary real-world usage mode (the user personally relies on it to operate their phone). See
   Accessibility §1.

---

## 1. Architecture & code organization

**Finding 1 (Severity: Medium, Effort: M) — Views call CloudKitSync directly, no service layer.**
60 call sites of `CloudKitSync.shared.*` are scattered directly inside SwiftUI view files
(`grep -rn "CloudKitSync.shared" BlindensportGraz --include="*.swift" | wc -l` → 60). There's no
intermediate service/viewmodel layer — every `AddXView`/`XDetailView` both drives UI state and
triggers persistence side effects. Works fine at current size but makes it hard to test persistence
logic independent of SwiftUI, and couples every view to CloudKit's exact API shape.

**Finding 2 (Severity: Medium, Effort: L) — Large, single-responsibility-violating files.**
`wc -l BlindensportGraz/*.swift | sort -rn | head -10` shows `CloudKitSync.swift` at 921 lines (every
push/pull/delete for all 11 model types in one class), `Models.swift` at 848 lines (11 `@Model`
classes in one file), `TrainingsViews.swift` at 641 lines, `TournamentsViews.swift` at 541. None of
these are unmanageable yet, but `CloudKitSync.swift` in particular will keep growing linearly with
every new model added — worth splitting into per-model extensions in separate files before the next
major feature lands.

**Finding 3 (Severity: Medium, Effort: M) — `role`/`sport` are free-text strings, not closed enums.**
`TeamMembership.role`, `SportEvent/Training/Tournament.sport` are plain `String` fields, editable via
raw `TextField`s (`TeamsViews.swift:168`, `TournamentsViews.swift:275`, `TrainingsViews.swift:345` for
`sport`). This has already caused one confirmed bug: a `!["coach","assistant"].contains(role)` check
in `TournamentsViews.swift` silently matched typos/unexpected values instead of just "player" —
fixed at `TournamentsViews.swift:266` with an explicit `role == "player"` check (see the code comment
at lines 259–264 explaining why). The underlying free-text field is unchanged, so the same class of
bug can recur anywhere else a "not Helfer" check gets written. A closed `enum` (or at minimum a
validated set of allowed values with normalization, mirroring what `SportIcons.swift` already does for
`sport` display) would close this permanently.

**Finding 4 (Severity: Low, Effort: S) — In-app architecture doc has drifted from the real codebase.**
`BlindensportGraz/CLAUDE.md` (the in-app doc, distinct from the repo-root one) still describes 7 core
models including a `username` field and `ClubMember` naming — the real `Models.swift` has 11 `@Model`
classes via SwiftData class inheritance, no `username` field (removed 2026-07-19 per cerebrum.md), and
the roster class was renamed to `Member`. Low functional risk, but a stale architecture doc actively
misleads whoever (human or AI) reads it next.

**Finding 5 (Severity: Medium, Effort: L) — RootCLI hand-maintains independent mirror structs.**
`RootCLI/Sources/CloudKitS2SCore/MemberRecord.swift` and `RootCLI/Sources/clubmembersapi/Routes.swift`
each independently redeclare the `Member`/`ClubMember` CKRecord field shape with no shared code
between the app target and RootCLI. `.wolf/cerebrum.md`'s 2026-07-18 and 2026-07-30 entries document
this drift being hit twice already (a field split requiring updates across both codebases in lockstep,
caught only by manual checklist discipline, not the compiler). A shared Swift package for the record
schema would eliminate this whole class of bug, though it's a real, non-trivial restructuring.

**Finding 6 (Severity: Medium, Effort: M) — Silent-failure error handling is the dominant pattern.**
98 `try?` sites vs. 45 `try`/`do-catch` sites app-wide (`grep -rn 'try?' BlindensportGraz --include="*.swift" | wc -l`).
Most SwiftData saves use `try? modelContext.save()` with no failure path — if a save fails (disk full,
corrupt store), the user sees nothing and the in-memory UI simply diverges from what's actually
persisted. Not urgent (SwiftData saves rarely fail in practice) but worth a consistent policy — at
minimum log via `os.Logger`, ideally surface a toast on failure for admin-critical actions (role
changes, roster edits).

**Finding 7 (Severity: Low-Medium, Effort: M) — CloudKit record-type/field-name strings aren't
centralized.** Every CKRecord type and field name (`"Team"`, `"clubMemberID"`, etc.) is a literal
string scattered through `CloudKitSync.swift`. One field name is deliberately kept mismatched from its
current model-layer name for wire compatibility (see the comment near `pushMembership`'s
`record["clubMemberID"]` in `CloudKitSync.swift`) — a reasonable one-off decision, but with no central
schema file, a future typo in any of these literal strings fails silently (CloudKit just won't find
the field) rather than at compile time.

**Finding 8 (Severity: Low, Effort: S) — Save-then-sync is duplicated inline everywhere rather than
a shared helper.** The `modelContext.save()` + `CloudKitSync.shared.push*(...)` pairing (Finding 1)
is repeated verbatim at each of the 60 call sites rather than factored into one helper — makes the
"every mutation should sync" invariant harder to enforce/verify by inspection as the app grows.

**Finding 9 (Severity: Low — business/product note, not a code defect) — iOS 26.0 minimum deployment
target is not documented as a deliberate product decision anywhere user-facing.** `project.yml` pins
`deploymentTarget: iOS: "26.0"` app-wide. `.wolf/cerebrum.md` confirms this is deliberate (SwiftData
`@Model` class inheritance requires it), but CLAUDE.md's original requirements never named a target OS
— worth the club being aware this currently excludes any device that can't run iOS 26, which given how
recently that OS shipped is a meaningfully large chunk of the potential user base for a while yet.

---

## 2. SwiftData & CloudKit sync

**Finding 1 (Severity: High, Effort: M) — Every CloudKit write is fire-and-forget with `print()`-only
error handling.** `CloudKitSync.swift` has 11 `print("CloudKitSync ... failed")` sites (lines 65, 77,
187, 224, 243, 253, 263, 292, 306, 403, 478) and 8 separate `Task { do {...} catch {...} }` blocks with
no retry, no backoff, no offline queue. `print()` output goes to stdout, not `os.Logger` — it will not
show up in a real device's Console.app or a sysdiagnose search, which matters for debugging a
"my change didn't show up on my teammate's phone" report after the fact. Nothing in the UI ever
reflects a failed push.

**Finding 2 (Severity: Medium — accepted tradeoff, residual risk noted, Effort: L to fully fix) —
`.changedKeys` last-write-wins conflict strategy.** The doc comment directly above
`private func upsert(_ record: CKRecord)` explains this is deliberate: building a fresh `CKRecord`
per push (no `recordChangeTag`) means the default `.ifServerRecordUnchanged` save policy would reject
every update after the first, so `.changedKeys` is used instead for true insert-or-update semantics.
This is a reasonable, documented choice — but the residual risk is real: two admins editing the same
`Member` or `Training` around the same time will have one edit silently overwrite fields the other
just changed, with zero warning to either party, and no way to discover it happened after the fact.

**Finding 3 (Severity: Medium, Effort: M) — No user-visible sync/pending state anywhere.** No screen
shows "syncing…", a last-synced timestamp, or a sync-failure indicator (confirmed via
`grep -rni "syncing\|lastSynced\|isSyncing" BlindensportGraz` — the only hit is an internal code
comment at `CloudKitSync.swift:841`, not UI). Combined with Finding 1, a user has no way to know
whether their edit actually reached other devices.

**Finding 4 (Severity: Medium, Effort: M) — The destructive local-store-reset fallback's safety
assumption isn't actually verifiable.** `BlindensportGrazApp.swift:26-48`: if `ModelContainer` init
fails (e.g. schema mismatch after a model change), the app wipes the local SQLite store
(`deleteLocalStore`, line 51) and relies on `syncAll()` to fully repopulate from CloudKit. The code's
own comment says this only loses "truly offline-only, never-synced" local edits — but because pushes
are fire-and-forget (Finding 1), the app itself has no reliable way to know whether a given local edit
actually made it to CloudKit before the reset fires. The safety net's core assumption depends on a
guarantee the app doesn't provide.

**Finding 5 (Positive — no fix needed) — `syncAll()`'s pull ordering correctly matches its documented
dependency graph.** `CloudKitSync.swift:457-468`: `pullUserIdentities → pullMembers → pullTeams →
pullMemberships → pullEvents → pullTrainings → pullTournaments → pullEventImages →
pullParticipations → pullAttendances → pullTrainingFavorites`. This matches the documented rationale
(e.g. attendances need memberships+trainings already resolved) — checked and confirmed correct, no
race found.

**Finding 6 (Severity: Low today / Medium if data grows, Effort: M) — Most `@Query`s are unfiltered.**
42 `@Query` sites app-wide (`grep -rn '@Query' BlindensportGraz --include="*.swift" | wc -l`), the
large majority with no `#Predicate` (e.g. `TeamsViews.swift:8`, `KostZViews.swift:18`/`124`,
`SammelabrechnungViews.swift:15`/`111`, `RootView.swift:20`/`274`) — every one of these fetches the
entire shared, public-DB-backed local store into memory. Fine at this club's current single-club
scale; would need predicates/pagination before any materially larger dataset (see the multi-club
enhancement idea below).

**Finding 7 (Severity: Low-Medium, Effort: M) — Same schema-string-literal issue as Architecture
Finding 7,** repeated here because it's specifically a sync-correctness risk: a typo'd field-name
literal in a push doesn't fail at compile time, it just silently fails to write that field.

**Finding 8 (Severity: Low, Effort: S-M) — No visible recovery path if a `CKQuerySubscription`
registration fails.** `CloudKitSync.swift:403`'s subscription-save failure is a single `print()` with
no retry — since these subscriptions are what deliver Training/Tournament creation alerts even to a
fully-terminated app (per `PushNotifications.swift`'s own doc comment), a silently-failed subscription
registration means that device permanently stops getting creation alerts with no indication why.

**Finding 9 (Positive — no fix needed) — The `cloudKitDatabase: .none` SwiftData config is the
correct choice for this app's requirements.** `BlindensportGrazApp.swift:25`: deliberately opts out of
SwiftData's built-in CloudKit mirroring (which only supports private, per-user sync) in favor of the
manual public-database layer, since the app's core requirement is cross-user visibility of shared
club data. This is architecturally correct, not a gap.

---

## 3. Security & account administration

**Finding 1 (Severity: High, Effort: S — but do this first) — Live TEST-ONLY admin backdoor for one
real email address.** `Models.swift:99`: `static let testAdminEmail = "franz.kager@gmx.net"`, wired
into `elevateIfTestAdmin()` at line 104 (`guard normalized == User.testAdminEmail, role != "admin" ...`),
which automatically grants `role = "admin"` on login/registration/email-edit for that one account —
no Apple-verification gate, unlike the designated-root grant. The declaration comment reads: *"Requested
2026-07-19 — remove this whole block, and its call sites, once testing is done."* This review runs
2026-08-19, a full month later, and the block is still present and wired into 4 call sites. **This is
the single most important finding in this report.** Recommendation: remove the block entirely (or, at
minimum, wrap it in `#if DEBUG` so it structurally cannot ship in a Release/TestFlight build) before
any distribution beyond the current single tester.

**Finding 2 (Severity: High, Effort: M — Dashboard configuration + verification, not code) — CloudKit
public-DB access control doesn't match the app's client-side role model.** CloudKit's default "World"
role is read/write for any authenticated iCloud user. All 34 role/permission checks in the app
(`role == "admin"`, `isRoot`, etc. — sample citations: `TournamentsViews.swift:31,218,225,489,493`,
`TeamsViews.swift:19,161`, `EventsViews.swift:30,140,144,233,240`, `RootView.swift:208`,
`AccountView.swift:220`) are enforced entirely client-side. `RootCLI/README.md:66-93` documents
CloudKit "Security Roles" hardening as a **recommended, manual, optional** step — and even that only
names 2 of the app's 11 CKRecord types (`UserIdentity`, `ClubMember`) as worth locking down, leaving
Team, TeamMembership, SportEvent, Tournament, Training, EventImage, TrainingAttendance,
TournamentAttendance, and TrainingFavorite all on the World-read/write default. Without confirming
this was actually applied in the **Production** CloudKit environment (not just Development — the doc
explicitly notes they're configured separately) for **all** record types, any iCloud user could in
principle write a forged `UserIdentity` record setting their own role, or directly tamper with any
other record type, bypassing every app-level check entirely. Recommend the user confirm and expand
Security Roles coverage in Production before wider release.

**Finding 3 (Severity: Medium, Effort: S) — Zero unit test coverage on the role-escalation logic.**
`grep -rln "elevateIfDesignatedRoot\|elevateIfTestAdmin" BlindensportGrazTests` returns no results.
This exact logic has a documented multi-session bug history — bug-173 and the surrounding
2026-07-19/2026-08-02 cerebrum.md entries describe the designated-root grant being broken (wrong gate
condition) across at least two separate sessions before being fixed. Recommend explicit unit tests:
designated-root requires all three of first/last/email together; test-admin requires only email;
neither grant fires on a partial match; both are case-insensitive on the name/email comparison.

**Finding 4 (Severity: Low-Medium, Effort: S) — No email-format validation.** `AccountView.swift:125`
and `RootView.swift:287` both bind a plain `TextField("E-Mail", ...)` directly to the stored email
field with no format check. Low risk for the designated-root match (which requires exact match on
all three fields anyway) but means garbage/malformed data can freely enter the CloudKit-synced
`UserIdentity` record.

**Finding 5 (Severity: Medium, Effort: S) — No IBAN/SVNR format validation.** `Member.iban`/
`Member.svnr` (`Models.swift`) are free-form strings with no validation anywhere, despite being
exported directly onto official PRAE/KostZ Sport-Austria paperwork (`PraeExport.swift`,
`KostZExport.swift`). Recommend a soft, non-blocking format check (IBAN checksum, SVNR's known
Austrian digit pattern) surfaced as a warning, not a hard block — this app's roster data is regularly
bulk-imported from messy real-world spreadsheets (cerebrum.md's 2026-07-30 entry documents actual
malformed source data already encountered), so validation must tolerate imperfect input.

**Finding 6 (Positive — no fix needed) — No sensitive data found leaking into logs.** Checked
`print()` sites in `PraeExport.swift`, `KostZExport.swift`, and `MemberImportExport.swift` for any
that interpolate a full `Member`/`User` object (which would leak SVNR/IBAN/email into stdout) — none
found; the few `print()`s that exist reference only ids or record types.

**Finding 7 (Positive with a caveat, Severity: Low, Effort: N/A — documented intentional tradeoff) —
RootCLI's Basic Auth is correctly constant-time, but has no per-operator attribution.**
`RootCLI/Sources/clubmembersapi/Auth.swift:23-27` hashes both sides with SHA-256 before comparing —
correctly avoids the classic early-exit timing leak. However, the doc comment at lines 6-9 confirms
this is a single shared username/password for all operators by design ("not per-user accounts") — so
any RootCLI/`clubmembersapi`-driven change (including `set-role`) carries no attribution to which
human actually ran it. Reasonable for a small club's admin tooling, but worth pairing with the
role-change audit log suggested below if more than one person ever operates it.

**Finding 8 (Severity: Low-Medium, Effort: S — docs only) — TLS is a deployment responsibility the
docs don't explicitly call out.** `clubmembersapi`'s Basic Auth security depends entirely on the
deployer terminating TLS in front of it — nothing in the app code enforces this, and
`RootCLI/README.md` doesn't currently carry an explicit "must be deployed behind HTTPS" note.
Recommend adding one.

**Finding 9 (Severity: Low, Effort: M) — No rate limiting/lockout on repeated failed `clubmembersapi`
auth attempts.** Checked `Auth.swift`/`Configure.swift` — no throttling mechanism found. Low risk for
a small-club internal tool not expected to be internet-facing at scale, but worth noting if it's ever
deployed somewhere broadly reachable.

---

## 4. Accessibility

*(This user personally relies on VoiceOver to operate their own phone and cannot meaningfully test
with it disabled — findings below are weighted toward VoiceOver impact specifically, and none of the
recommendations ask for manual on-device testing by the user; verification should happen via
Simulator with VoiceOver enabled or code-level review.)*

**Finding 1 (Severity: Medium-High, Effort: M app-wide) — Only 4 of 33 app source files use any
accessibility API at all.** `grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift"`
returns exactly `TournamentsViews.swift`, `TeamsViews.swift`, `MembersViews.swift`,
`TrainingsViews.swift`. The other 29 files — including `EventsViews.swift`, `DashboardView.swift`,
`AccountView.swift`, `PraeViews.swift`, `KostZViews.swift` — have zero explicit accessibility
labeling. The good news: the labeling *pattern* already exists and is well-executed where it's used
(see Finding 5) — this is a coverage gap, not a missing convention.

**Finding 2 (Severity: Medium, Effort: S) — `EventsViews.swift`'s icon-only add button has no
accessibility label, unlike the equivalent pattern elsewhere.** `EventsViews.swift:173`:
`Button { showAdd = true } label: { Image(systemName: "plus") }` — no `.accessibilityLabel`. Contrast
with the *identical* icon-only-button pattern in `TrainingsViews.swift:567-576`, which correctly adds
`.accessibilityLabel("Trainings importieren")` / `"Trainings exportieren"` right next to a matching
`Image(systemName:)`. The fix pattern is already established in this exact codebase; it just wasn't
applied consistently to `EventsViews.swift`.

**Finding 3 (Severity: Medium, Effort: S) — `TrainingFavorite` delete is only reachable via a
long-press `.contextMenu`, with no VoiceOver-equivalent action.** `TrainingsViews.swift:107`:
`.contextMenu { ... }` on the favorite chip, with no `.accessibilityAction` found alongside it. A
long-press gesture is a known VoiceOver discoverability problem — VoiceOver users typically don't have
an easy equivalent gesture without an explicit accessibility action exposing the same operation.
Recommend adding an `.accessibilityAction(named: "Löschen") { ... }` alongside the existing context
menu, not replacing it.

**Finding 4 (Severity: Low-Medium, Effort: M) — No Dynamic Type accommodation anywhere.** Zero
`dynamicTypeSize`/`minimumScaleFactor` usage found app-wide. Dense list rows (`MemberListView`,
`TeamsViews` roster rows) and the multi-field `Add*View` forms have not been checked against larger
Dynamic Type sizes and may clip or truncate. Lower severity than the VoiceOver-specific findings above
since it doesn't block usage the way a missing label does, but still worth a pass.

**Finding 5 (Positive — no fix needed) — `TeamDetailView`'s role-editing Menu is a model example of
correct accessibility treatment.** `TeamsViews.swift:198-199`: the role-capsule `Menu` has both
`.accessibilityLabel("Rolle: \(roleLabel(m.role))")` and
`.accessibilityHint("Doppeltippen, um die Rolle zu ändern")` — exactly right, since a plain capsule
turned into a tap-to-open-menu control would otherwise announce ambiguously. This is the pattern
Finding 1's other 29 files should follow.

**Finding 6 (Positive — no fix needed) — `SportGlyph` decorative badges are correctly hidden from
VoiceOver.** `SportIcons.swift:94`: `.accessibilityHidden(true)` on the sport-icon badge, which is
always paired with a text label that already announces the sport name — exactly the right call,
avoiding a redundant/meaningless shape description.

**Finding 7 (Positive, with a "keep watching this" note — Severity: N/A, Effort: N/A) — No currently-
nested `.sheet`-inside-a-`.sheet` found among the app's 22 `.sheet(` presentation sites.** This
pattern previously caused a permanent main-thread freeze specifically under VoiceOver (bug-070/072,
fixed 2026-07-18 by routing the second presentation through the parent's `onDismiss` instead of
nesting). Spot-checked all 22 current `.sheet(` sites (`TournamentsViews.swift` ×6,
`TrainingsViews.swift` ×5, `EventsViews.swift` ×2, `TeamsViews.swift` ×2, `AccountView.swift` ×2,
`RootView.swift`, `EventImagesViews.swift`, `MembersViews.swift` ×2) — none currently double-nest.
Worth keeping in mind as a standing constraint for any future feature that presents a share sheet,
picker, or secondary modal from inside an already-presented sheet.

**Finding 8 (Positive — no fix needed) — Tournament status is never color-only.** Checked
`TournamentsViews.swift:162-184`: `statusColor` drives the background/foreground tint of the status
badge, but `Text(tournament.status)` (line 179) always renders the literal status text alongside it —
correctly avoids a color-only signal, which would fail both VoiceOver and color-blind users.

**Finding 9 (Severity: Low, Effort: S) — Report-generation `Picker`s carry a reasonable default label
but no additional context.** `PraeViews.swift:48,55,216`, `KostZViews.swift:33`,
`TrainingsfrequenzlisteViews.swift:57,62` all use `Picker("Person"/"Monat"/"Sportart"/"Zeitraum", ...)`
— the string argument does give VoiceOver a sensible default accessible name, so this is a minor
finding, not a real gap: consider an `.accessibilityHint` only where the effect of changing the
selection isn't obvious from the label alone (e.g. `"Zeitraum"` toggling between half-years).

---

## 5. Enhancement & new-feature backlog

At least 3 of these are direct follow-ons from findings above (cited); the rest are new capabilities,
each checked against the existing codebase before being proposed so nothing here duplicates something
that already exists. None of these re-propose a decision `.wolf/cerebrum.md` already records as
settled (date-only tournaments; PRAE name-order scoped to exported forms only; Trainingsfrequenzliste's
Y3/D3 sourcing split; no self-service role editing).

### P0 — do soon

1. **Remove or `#if DEBUG`-guard the `testAdminEmail` backdoor.** *Follows Security Finding 1.*
   Effort: S.
2. **Role-change audit log.** *Follows Security Findings 1 & 2* — a small SwiftData model + CKRecord
   type logging `(user id, old role, new role, changed-by, timestamp)` would have made Finding 1's
   grant visible after the fact, and generally hardens account administration. No history of role
   changes exists today (confirmed: no `AuditLog`/`RoleChangeLog` symbol anywhere in the codebase).
   Effort: S-M.

### P1 — valuable, not urgent

3. **Visible sync status indicator.** *Follows SwiftData & CloudKit Finding 1 & 3.* A lightweight
   syncing/synced/failed state, surfaced as a small banner or icon, would close the real trust gap
   created by fire-and-forget pushes with no UI feedback. Effort: M.
4. **Offline-mode messaging.** Pairs naturally with #3 — detect reachability and tell the user
   "you're offline, changes will sync once reconnected" instead of silent failure. Effort: S-M.
5. **Training/tournament reminder notifications.** Genuinely new capability — confirmed via
   `PushNotifications.swift` that the existing `CKQuerySubscription`s only fire on *creation* of a
   Training/Tournament (per that file's own doc comment), not on any schedule before the event starts.
   Locally-scheduled `UNCalendarNotificationTrigger`s off `Training.startDate`/`Tournament.startDate`
   (rescheduled on edit/delete) would add real "starts in 2 hours" reminders — this is additive to,
   not a replacement for, the existing creation-alert subscriptions. Effort: M.
6. **Attendance-trends dashboard for coaches/admins.** Confirmed: `TrainingAttendance`/
   `TournamentAttendance` records exist and sync correctly, but are referenced only inside
   `CloudKitSync.swift`'s push/pull — zero aggregate/trend view anywhere, and no `Charts` import found
   in the project at all. A per-team/per-person attendance-rate view (Swift Charts) would surface data
   that's already being collected but never visualized. Effort: M.
7. **IBAN/SVNR format validation with a soft warning.** *Follows Security Finding 5.* Effort: S.
8. **Season/year-level reporting.** Extends the existing `SammelabrechnungExporter` pattern (which
   already bundles one period's KostZ+PRAE into a zip) to a full-season rollup across all periods and
   tournaments — same orchestration-over-existing-exporters approach, no new template-patching logic
   needed. Effort: M-L.
9. **Calendar/.ics export or system-Calendar (EventKit) integration.** Confirmed absent entirely
   (`grep -rn "EventKit\|EKEventStore" BlindensportGraz` → no hits). Would let members add
   trainings/tournaments to their personal calendar. Effort: M.
10. **Receipt/document attachments for KostZ/PRAE.** Extends the existing `EventImage`
    (`@Attribute(.externalStorage)` + `CKAsset`) pattern already used for event photos, applied
    instead to expense receipts — a natural fit for the accounting flows and reuses a proven CloudKit-
    asset-sync mechanism rather than inventing a new one. Effort: M.

### P2 — longer-term

11. **Central CloudKit schema/record-type constants file.** *Follows Architecture Finding 7 and
    SwiftData & CloudKit Finding 7.* More of a refactor than a feature, but directly reduces the cost
    of every future feature touching synced data — cerebrum.md documents the current
    hand-maintained-string pattern causing multi-file drift at least twice already. Effort: M.
12. **Multi-club/multi-section extensibility.** Plausible given the domain, but a genuinely large
    undertaking given the current single-CloudKit-container, hand-maintained-schema-string
    architecture (Architecture Finding 5, SwiftData & CloudKit Finding 6 on unfiltered `@Query`s both
    bear directly on how much work this would be). Flagging as a real long-term idea worth discussing,
    not a quick win — don't underestimate the effort here. Effort: L (architecture-level).

---

## How to use this report

Triage P0/High-severity items first — in particular, **the `testAdminEmail` backdoor (Security
Finding 1) should be addressed before this app goes to any wider TestFlight distribution or beyond
the current single tester**, since it grants full admin access to one specific email address with no
compile-time guard against shipping it. The CloudKit Security Roles gap (Security Finding 2) is the
next highest-leverage fix, since it's the one item where the app's entire client-side permission model
could otherwise be bypassed entirely. Everything else is genuinely valuable but not urgent — this is a
well-built app for a small volunteer-run club, and effort/maintenance burden should weigh at least as
heavily as raw feature value when prioritizing beyond the P0 items.

**Total: 36 audit findings (9 per area × 4 areas) + 12 enhancement/feature suggestions.**
