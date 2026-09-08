# BlindensportGraz — Architecture & Design Review (2026-09-08)

**Scope:** the iOS app (`BlindensportGraz/`, 86 Swift files / ~12.6k lines) — architecture, SwiftData +
CloudKit sync, design/UX, plus a prioritized feature backlog. Companion `RootCLI/` package touched only
where it contrasts with the app.
**Method:** source reading + `grep`/`wc` evidence against `main` @ `8852d6f`. No code changed.
**Baseline:** this supersedes `audit.md` (2026-08-19). Nearly every finding in that report was
implemented in the 2026-08-22 supergoal run (phases 1–19: service layer, `CKSchema`, split
`CloudKitSync`/models, `AppRole`/`MembershipRole`/`Sport` enums, `SyncState`/`NetworkMonitor`/
`SyncStatusBanner`, `RoleChangeLog`, `Validation`, `EventReminderService`, `AttendanceTrends` + Charts,
`.ics` export, `ExpenseReceipt`, shared `ClubSchema` package). **The app is in good shape.** This review
looks at what's worth doing *next*.

Severity: High / Medium / Low · Effort: S (hours) / M (day-ish) / L (multi-day)

---

## Executive summary — top 6

1. **`CloudKitSync.fetchAll` never pages** (`CloudKitSync.swift:132`) — `publicDB.records(matching:)` is
   called with no `resultsLimit` and the returned cursor is discarded (`let (results, _) = …`). Any
   single record type larger than one CloudKit page (~100 rows; the code's own comments cite ~200
   `ClubMember`s) is **silently truncated on every pull**. `RootCLI`'s S2S client pages correctly with a
   `continuationMarker` loop — the app side just doesn't. High / S–M.
2. **Failed pushes are still lost.** `performWithRetry` retries 4× over ~3.5s, then calls
   `SyncState.markFailed()` and drops the write. There is no durable outbox, and `BlindensportGrazApp`'s
   own store-reset comment admits it can't verify what actually synced. This is the largest remaining
   correctness gap. Medium–High / M–L.
3. **Presentation logic lives entirely in View structs.** No `@Observable` view models; 64 `@Query`
   sites directly in views; the same business rules (`myTeams` admin-bypass, `allMemberships` dedup,
   `visibleTrainings`/`visibleTournaments` team-scoping, `attendedMemberships`) are copy-pasted as
   computed vars across the Event/Training/Tournament detail + list views. These are pure, testable
   functions trapped in SwiftUI. Medium / M.
4. **Every sync is a full pull of every type**, hand-ordered across 11 stages with interleaved
   `save()` calls whose placement is load-bearing and was derived from production incidents
   (bug-221, bug-371). Adding a model type means correctly slotting it by hand. Medium / M.
5. **No design system.** Colors (`.blue`/`.yellow`/`.green`/`.purple`, `opacity(0.1)` fills), spacing,
   corner radii, and card styling are re-specified inline per view. For an accessibility-first app this
   should be one tunable place (semantic colors, contrast, Dynamic Type). Medium / M.
6. **Swift 5 language mode** (`project.yml: SWIFT_VERSION: "5.0"`) with a `@MainActor` sync singleton
   full of fire-and-forget `Task {}`s. On an iOS-26-only target, Swift 6 mode / `SWIFT_STRICT_CONCURRENCY:
   complete` would catch data-race classes at compile time. Medium / M.

---

## 1. Architecture & code organization

**1.1 (Medium, M) — View files are still large and multi-purpose.** `TrainingsViews.swift` 865,
`TournamentsViews.swift` 769, `MembersViews.swift` 630, `TeamsViews.swift` 492, `AccountView.swift`
484. Each bundles list + row + detail + `Add*View` + helper structs in one file. The service-layer
refactor stopped at persistence; everything above it is still one big view file per tab. Recommend
splitting per screen (`Trainings/TrainingsListView.swift`, `…/TrainingDetailView.swift`,
`…/TrainingRow.swift`, `…/AddTrainingView.swift`) — smaller diffs, fewer type-check-timeout hazards
(cerebrum has three of those), easier review.

**1.2 (Medium, M) — No view models; logic duplicated across views.** There is no `@Observable` type in
the presentation layer (`ServiceFailureSignal`/`SyncState`/`NetworkMonitor` are app-infra, not
per-screen). `TrainingDetailView` and `TournamentDetailView` now each carry ~10 helper methods/computed
vars (`allMemberships`, `attendedMemberships`, `collidesWithExistingEvent`, `totalPraeAmount`,
`attendance(for:)`, `setAttendance`, `setPraeAmount`, `addImage`, …) that are near-identical between the
two. Extract the roster/attendance logic into a plain testable type (`EventRosterModel` or free
functions in one file) shared by Event/Training/Tournament; keep the View thin. Same for the
`visible…`/`myTeams` filters — one `EventVisibility` helper with unit tests.

**1.3 (Medium, M) — `CloudKitSync` does all pull-side work on `@MainActor`.** `syncAll` fetches ~190+
`CKRecord`s, decodes them, and inserts into the main `ModelContext` on the main thread. Fine today;
it will visibly hitch as the club accumulates years of trainings/attendances. Move pull-side
decode+insert onto a background `ModelContext` / `@ModelActor`, hop to main only for the final merge.

**1.4 (Medium, M) — The `syncAll` pipeline is imperative and fragile.** `CloudKitSync.swift:223-251`:
11 ordered `await pullX` calls with 6 hand-placed `try? modelContext.save()` boundaries, documented
via battle scars. A declarative form — each puller declares `dependsOn: [Team.self, User.self]` and the
orchestrator topo-sorts + inserts save boundaries — would make a new model type a data change, not a
careful manual edit. At minimum add a test asserting the call order still satisfies the documented
dependency graph.

**1.5 (Low–Medium, S–M) — No delete propagation on pull.** Pushes delete via
`publicDB.deleteRecord` (`CloudKitSync.swift:99`), but `syncAll` only ever upserts. A record deleted on
another device — on a device that missed the push subscription (offline, notifications denied) —
lingers locally until the next full store wipe. Consider tombstone records or a periodic
"reconcile: local ids not in the pulled set → soft-delete".

**1.6 (Low, S) — Stringly-typed cross-component events.** `NotificationCenter.default.post(name:
"showToast" / "TrainingCreated" / "TournamentCreated" …)` with untyped `userInfo` dicts
(`BlindensportGrazApp.swift:122-163`, each `Add*View`). Replace with a small typed event type or a
direct closure — there are only a handful of posters/observers.

**1.7 (Low, S) — `BlindensportGrazApp` holds a version-gated `UserDefaults` wipe flag
(`didWipeForRoleEnumMigration_2026_08_22`).** Works, but these accumulate — each schema-shape change
adds another one-shot key with no cleanup. A tiny `StoreMigrations` helper that records a schema
version integer and runs an ordered list of one-time steps would keep this from sprawling.

**1.8 (Low, S) — `project.yml` `SWIFT_VERSION: "5.0"`.** See summary #6. Also no
`SWIFT_STRICT_CONCURRENCY` setting. Given the deliberate iOS 26 floor there's no compatibility reason
to stay on the Swift 5 language mode.

---

## 2. SwiftData & CloudKit sync

**2.1 (High, S–M) — `fetchAll` is not paginated.** See executive summary #1. `CloudKitSync.swift:129-138`:

```swift
let (results, _) = try await publicDB.records(matching: query)   // cursor discarded
```

Fix: loop on the returned cursor (`records(matching:continuingMatchFrom:)`) until it's `nil`, or drop
to `CKQueryOperation` with `resultsLimit` + `queryResultBlock`. Verify current `ClubMember` /
`TrainingAttendance` counts in the CloudKit dashboard — if either already exceeds one page, some roster
/ attendance rows are missing on freshly-synced devices right now.

**2.2 (Medium–High, M–L) — No pending-write ledger / outbox.** See summary #2. Minimal version: a local
`PendingPush(recordType, recordName, payload, attempts, lastError)` SwiftData model; `save()` enqueues,
`performWithRetry` dequeues on success, a launch/reconnect drain retries the rest. This also makes the
`ModelContainer` reset fallback honest — it could refuse to wipe while the outbox is non-empty.

**2.3 (Medium, S) — `markFailed()` has no user-facing retry.** `SyncStatusBanner` shows the failed
state, but recovery is only per-list pull-to-refresh. Add a "Erneut versuchen" button in the banner
that calls `SyncOrchestrationService.syncAll`.

**2.4 (Medium, M) — Full pull every time; no delta sync.** Every `syncAll` re-fetches every record of
every type. A `modificationDate > lastSyncedAt` predicate on each `CKQuery` (paired with 2.1's paging)
turns sync into O(changes). `SyncState` already persists `lastSyncedAt`.

**2.5 (Low–Medium, M) — 64 `@Query` sites, 2 filtered.** `DashboardView` alone opens 4 whole-table
queries (`events`/`tournaments`/`trainings`/`teams`); list views fetch full history then filter in
memory. Accepted at today's scale (documented), but the trajectory is years of trainings + attendances.
Add date-window `#Predicate`s to the list `@Query`s and a "load older" affordance before the dataset
gets large.

**2.6 (Low, S) — `fetchAll` swallows all pull errors to `[]`.** `CloudKitSync.swift:134-137` logs and
returns empty on any error — a transient network failure mid-`syncAll` looks identical to "that type is
genuinely empty", and a later `save()` won't notice. Return a `Result`/throw so `syncAll` can abort the
pass and leave the local store intact rather than partially reconciling against empties.

**2.7 (Positive) — `.changedKeys` upsert, pull ordering, and `cloudKitDatabase: .none` remain the right
calls** for this app's public-shared-data requirement; all three are well-documented in place.

---

## 3. Design & UX

**3.1 (Medium, M) — No design system / theme.** Introduce `Theme` (or `DesignTokens`): semantic colors
(`Theme.surface`, `Theme.accent`, `Theme.warning`), a spacing scale, corner radii, and a `.card()`
`ViewModifier` replacing the repeated `.padding().background(color.opacity(0.1), in:
RoundedRectangle(cornerRadius: 12))`. One place to tune contrast is worth a lot for a VoiceOver/low-vision
audience. CLAUDE.md still describes a "blue/purple gradient theme" that `DashboardView` doesn't use —
either adopt it consistently or drop the note.

**3.2 (Medium, S–M) — Dashboard is inert.** `StatCard`s aren't tappable (no `NavigationLink` to the
filtered list), rows shown under "Nächste Events / Kommende Trainings" aren't navigable, there's no
"your next training" personal callout and no first-run guidance for an empty club. Make the cards and
rows navigate; add a single prominent "Dein nächster Termin" block.

**3.3 (Medium, M) — No iPad / large-size-class layout.** Everything is `NavigationStack` (41 nav
sites, 0 `NavigationSplitView`). The admin reporting flows (PRAE / KostZ / Sammelabrechnung /
Trainingsfrequenzliste) are desktop-shaped work; `VereinView`'s hub → detail maps cleanly onto a
`NavigationSplitView` sidebar. Low effort, large payoff for whoever does the club's paperwork on an iPad.

**3.4 (Low–Medium, S) — Localization is half-wired.** `Localizable.xcstrings` has 183 keys (`de`
source, `en` target) but only 5 `String(localized:)`/`LocalizedStringKey` call sites against ~106 raw
German `Text("…")` literals — the catalog is mostly bypassed. Decide: (a) commit to it (wrap strings;
the compiler extracts them) if international tournaments/guests matter, or (b) go `de`-only and delete
the dead `en` localizations so the catalog stops implying bilingual support that isn't there.

**3.5 (Low, S) — No `#Preview`s anywhere (0).** The team's stated QA path is "Simulator with VoiceOver";
previews with `.environment(\.dynamicTypeSize, .accessibility3)` and preview-time VoiceOver make that
faster and make the big view files safer to split (§1.1).

**3.6 (Low, S) — No haptics.** `.sensoryFeedback(.success, trigger:)` on save / `.selection` on the
attendance toggles / `.impact` on role changes is cheap non-visual confirmation that suits this
audience.

**3.7 (Low, S) — `AccountView` (484 lines) mixes profile, settings, role admin, logout.** Split into
Profil / Einstellungen / (admin) Rollen — the role-admin piece already partly duplicates `VereinView`.

**3.8 (Low, S) — Edit forms don't do the progressive disclosure the new read-only views do.** The
read-only detail views now hide empty fields (good). The *edit* forms still show every section always;
collapsing "Adresse" when it equals the club default, etc., would shorten the common path.

---

## 4. Security & accounts

Mostly addressed by the 2026-08-22 run (`testAdminEmail` removed, `RoleChangeLog` added, `Validation`
for email/IBAN/SVNR, CloudKit Security-Roles docs, `clubmembersapi` rate limiter). Remaining:

**4.1 (Medium, S) — Switching into an account is unauthenticated.** `LoginView` is a plain name picker;
anyone holding the unlocked device can enter any account, including an admin/root account previously
used on it. A `LocalAuthentication` (Face ID / passcode) gate on `role == .admin || isRoot` accounts
would be proportionate.

**4.2 (Medium, S) — `LoginView` swipe-to-delete pushes a CloudKit `User` delete for everyone**
(`RootView.swift:272-276` → `UserService.delete`), with no confirmation and no role gate. Add a
destructive-action confirmation and restrict it (or make it local-only "remove from this device").

**4.3 (Low–Medium, verify) — CloudKit Production Security Roles unverified.** `audit.md` Finding 2 was
closed as "docs only"; cerebrum notes the Dashboard steps to actually apply per-type role locks in
**Production** were blocked. World read/write on the public DB means the client-side role model is still
the only real gate. Confirm before wider TestFlight.

**4.4 (Low, S) — `appleUserIdentifier` recovery path can still mint a duplicate account** in the
narrow case where Apple returns a blank credential *and* both `@AppStorage` pointers were wiped *and*
the CloudKit resync hasn't landed yet (`RootView.swift:116-119` bails to `LoginView` — good — but a
user who then taps "Neues Konto" instead of finding their synced name creates a second account). A
"we think you already have an account — check the list first" hint on `RegisterView` when
`users.isEmpty` is false would help.

---

## 5. Feature backlog (prioritized)

Priorities weigh volunteer-run maintenance cost, not just value.

### P0 — correctness follow-ups from §1–§2
- **Paginate `fetchAll`** (§2.1). Not really a "feature" but ship it first.
- **Push-write outbox with a visible "N Änderungen nicht synchronisiert" indicator + retry** (§2.2,
  §2.3). The indicator is the user-facing half; the outbox is the engine.

### P1 — high value, moderate effort
- **Attendance "roll-call" mode.** A dedicated full-screen list for one training/tournament: big rows,
  swipe present/absent, running count, coach-on-the-sideline ergonomics — instead of toggles buried in
  the detail form. Extends the existing `Attendance` model + `setAttendance`. M.
- **Recurring trainings from a `TrainingFavorite`.** One action generates a weekly series for a term
  (favorite already stores weekday + time + duration + teams). Removes the biggest repetitive data-entry
  chore. M.
- **Home-screen widget (WidgetKit).** "Dein nächstes Training / Turnier" — reads the shared store via an
  App Group + read-only `ModelContainer`. High-value, VoiceOver-friendly, 0 WidgetKit usage today. M.
- **Siri / App Shortcuts ("Wann ist mein nächstes Training?").** `AppIntents` over the existing query
  logic — strong accessibility fit for this user base. M.
- **Push on training change / cancellation.** The `CKQuerySubscription` fires on *creation* only
  (`PushNotifications.swift`); add update/delete predicates so members get "Training heute abgesagt". S–M.
- **Dark-mode / high-contrast pass** once §3.1's tokens exist. The `opacity(0.1)` fills and undeclared
  `preferredColorScheme` likely read poorly in dark mode. S–M.

### P2 — larger or nice-to-have
- **iPad split-view admin console** (§3.3). M–L.
- **`webcal` subscription feed.** A stable per-user calendar URL from `clubmembersapi` so a member
  subscribes once and every club training/tournament flows into their system calendar — extends the
  `CalendarEventExport` RFC-5545 renderer + the Vapor app. M.
- **Member self-service profile edits with an admin approval queue.** Cuts the manual roster entry that
  `MemberImportExport` exists to work around; `RoleChangeLog` is the audit/approval precedent. M–L.
- **Season dashboard.** Attendance %, trainings held, PRAE totals per season — extends `AttendanceTrends`
  + `SammelabrechnungSeason`. M.
- **Full club backup/restore (all record types).** Generalize `MemberBackup` (roster-only today) to a
  whole-store JSON export for the admin. M.

---

## How to use this

Do §2.1 (pagination) first — it's small and it's a live data-loss risk the moment any record type
crosses a CloudKit page. §2.2 (outbox) is the next-highest-leverage correctness item. Everything in
§1 and §3 is genuine improvement, not urgent — sequence it behind whatever feature work matters to the
club, and treat §1.1/§1.2 (splitting views, extracting logic) as something you do *while* touching those
files for features, not as a standalone refactor sprint.

**Totals: 8 architecture + 7 sync + 8 design/UX + 4 security findings, 14 backlog items.**
