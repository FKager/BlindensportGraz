# State: Implement audit.md fixes & enhancements — BlindensportGraz

**Status:** PHASES_COMPLETE_AUDIT_PENDING
**Current phase:** 19 (complete)
**Started:** 2026-08-20
**Last update:** 2026-08-22
**Run root:** .supergoal/implement-the-fixes-and-enhancements-fro-a5zzf8
**Baseline ref:** 06dc8047d7c00b09ab84f4b730f9cd782b6028dc

## Phase progress

| # | Phase | Status | Started | Completed | Notes |
|---|-------|--------|---------|-----------|-------|
| 1 | Remove test-admin backdoor & fix doc drift | done | 2026-08-20 | 2026-08-22 | Real admin granted (CloudKit dev env) before removal; CLAUDE.md doc drift fixed |
| 2 | Role-change audit log | done | 2026-08-22 | 2026-08-22 | RoleChangeLog model+sync+UI+RootCLI+tests |
| 3 | Role tests & input validation | done | 2026-08-22 | 2026-08-22 | 8 designated-root tests, Validation.swift (email/IBAN/SVNR advisory checks) |
| 4 | CloudKit access-control hardening & docs | done | 2026-08-22 | 2026-08-22 | README rewrite (13 types, 2-tier), TLS note, clubmembersapi rate limiter |
| 5 | Centralize CloudKit schema constants | done | 2026-08-22 | 2026-08-22 | CKSchema.swift, all literals in CloudKitSync.swift replaced |
| 6 | Split CloudKitSync.swift & harden logging/retry | done | 2026-08-22 | 2026-08-22 | 12 files (max 206 lines), os.Logger, 4-attempt retry/backoff |
| 7 | Split Models.swift & closed role/sport enums | done | 2026-08-22 | 2026-08-22 | 12 model files, AppRole+MembershipRole enums, Sport utility (deviation documented) |
| 8 | Extract persistence+sync service layer | done | 2026-08-22 | 2026-08-22 | 15 service files, 64 call sites migrated, ServiceFailureSignal alerts on 2 admin screens |
| 9 | Shared schema package (app + RootCLI) | done | 2026-08-22 | 2026-08-22 | Shared/ClubSchema package, drift-catch demonstrated+reverted |
| 10 | Sync status & offline UX | done | 2026-08-22 | 2026-08-22 | SyncState+NetworkMonitor+SyncStatusBanner, hardened reset-fallback logging |
| 11 | Query predicates & subscription retry | done | 2026-08-22 | 2026-08-22 | 7 @Query sites documented, subscription retry added; caught+fixed a #Predicate runtime crash |
| 12 | Accessibility labels & control equivalents | done | 2026-08-22 | 2026-08-22 | Work was already complete from a prior interrupted session (STATE.md was stale); this run re-verified all 6 acceptance criteria fresh: 7 files with accessibilityLabel/Hint (up from 4), EventsViews add button labeled, TrainingFavorite has both contextMenu+accessibilityAction, SportGlyph/TeamDetailView role Menu/tournament status untouched, no new sheet nesting, build+test clean (16 known pre-existing failures only) |
| 13 | Accessibility Dynamic Type pass | done | 2026-08-22 | 2026-08-22 | Audited MemberListView/TeamsViews roster row/4 Add*Views/TrainingRow/TournamentRow/MemberRow (all wrap safely); found+fixed 4 real fixed-width clip risks (TeamRow avatar initial, EventRow date badge, PRAE TextFields in Training+Tournament detail) via minimumScaleFactor; build+test clean |
| 14 | Local reminder notifications | done | 2026-08-22 | 2026-08-22 | EventReminderService (UNCalendarNotificationTrigger, 2h lead, injectable NotificationScheduling for tests); wired into Training/TournamentService save (reschedule) + new delete methods (cancel); 9 new tests, 123 pass/16 known-baseline fail |
| 15 | Attendance-trends dashboard | done | 2026-08-22 | 2026-08-22 | AttendanceTrends (pure aggregation) + AttendanceTrendsView (Charts, AXChartDescriptorRepresentable), reachable via TrainingsListView toolbar gated by canManageEvents (admin/coach AppRole); 4 new tests, 127 pass/16 baseline fail |
| 16 | Season/year reporting rollup | done | 2026-08-22 | 2026-08-22 | SammelabrechnungExporter.exportSeason orchestrates existing KostZ/PRAE/Trainingsfrequenzliste exporters per month/tournament/sport-halfyear (skips empty periods); SammelabrechnungSeasonView wired into Berichte menu; 3 new tests, 130 pass/16 baseline fail |
| 17 | Calendar/EventKit integration | done | 2026-08-22 | 2026-08-22 | .ics+ShareLink chosen over EKEventStore (documented rationale, VoiceOver track record); CalendarEventExport (fields mapping + RFC5545 render); wired on Training/TournamentDetailView toolbars; add-on-demand-only stale-entry behavior documented; 6 new tests, 136 pass/16 baseline fail |
| 18 | Receipt/document attachments | done | 2026-08-22 | 2026-08-22 | ExpenseReceipt (images-only, PDF documented as follow-up) mirrors EventImage's CKAsset pattern exactly; ExpenseReceiptsSection (no nested sheet — inline expand) on KostZ month+tournament screens; uploader-or-admin delete; 3 new CKRecord-level round-trip tests, 139 pass/16 baseline fail |
| 19 | Polish & Harden | done | 2026-08-22 | 2026-08-22 | Final regression clean (139/16 baseline), RootCLI builds, no secrets, no sheet-nesting, a11y 4→9 files, committed (9c4cda7)+pushed+real-device smoke deploy succeeded; manual follow-ups checklist printed |

## Engineering check status

- Build: —
- Typecheck: —
- Lint: —
- Tests: —

## Notable events

- 2026-08-20 — Plan created, 19 phases. Scope: every actionable audit.md finding + enhancement backlog
  except items marked "Positive — no fix needed" and P2 enhancement #12 (multi-club, excluded by user).
  User confirmed: remove testAdminEmail entirely (grant real admin via RootCLI first); exclude
  multi-club extensibility from this run.
- 2026-08-20 — Pre-flight: `cd RootCLI && swift build` clean; `xcodegen generate` clean; `xcodebuild
  build -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` → BUILD SUCCEEDED;
  `xcodebuild test` (same flags, destination `platform=iOS Simulator,id=9BE30824-E947-475E-9A22-777FD4309637`
  / "iPhone 17") → 16 pre-existing failures, ALL in `MemberImportExportTests` (10) and
  `TrainingImportExportTests` (6) — same root cause as cerebrum.md's documented bug-202
  (`CloudKitSync.shared.push*` touches a real `CKContainer`, which hard-crashes without the iCloud
  entitlement that `CODE_SIGNING_ALLOWED=NO` strips). Every other suite passed. This is a real,
  pre-existing environment limitation, not a regression — but it was broader than THINKING.md/ROADMAP.md
  originally documented (only `MemberImportExportTests` was named). All 19 phase specs corrected in
  place to except both test classes from their "full suite passes" criteria before dispatch, so no phase
  wastes retries chasing an unfixable sandbox limitation. Baseline test-failure set for the run: exactly
  these 16 tests, in these 2 classes — any OTHER failure at any phase is a real regression.

## Failure log

- Phase 1 (Remove test-admin backdoor & fix doc drift): `rootcli set-role "franz kager" admin` failed
  with "Missing required environment variable CLOUDKIT_KEY_ID" — not a bug, a genuine missing
  precondition. CLOUDKIT_KEY_ID has no CLI/API source; it's Dashboard-web-UI-only (sign-in required),
  confirmed unobtainable from this sandboxed session across multiple prior sessions (cerebrum.md
  2026-07-30/2026-08-01). Private key file exists locally; the Key ID does not. Paused for user input
  rather than burning retries on a deterministic failure or deleting the backdoor without a confirmed
  replacement grant (phase spec explicitly forbids that). Status set to BLOCKED pending user action.
- 2026-08-22 — User supplied CLOUDKIT_KEY_ID + confirmed CLOUDKIT_PRIVATE_KEY_PATH
  (`~/.config/rootcli/rootcli_private_key_pkcs8.pem`, file confirmed present). Two NEW blockers found
  running `rootcli list`: (1) `CLOUDKIT_ENVIRONMENT=production` → HTTP 401 Authentication failed — key
  appears registered only under CloudKit Dashboard's Development environment key list, not Production's;
  (2) `CLOUDKIT_ENVIRONMENT=development` → auth succeeds but HTTP 400 "Field 'recordName' is not marked
  queryable" — same unresolved root cause as buglog bug-174, now confirmed to affect `UserIdentity` too.
  Both require CloudKit Dashboard (web UI, Apple ID sign-in) fixes the agent cannot perform. User chose
  to fix Dashboard (register key under Production + add Queryable index on UserIdentity.recordName) and
  have the agent retry after. Still BLOCKED pending that. Full diagnosis + the `!`-export-doesn't-persist
  gotcha logged in cerebrum.md 2026-08-22 Do-Not-Repeat.
- Phase 19 (Polish & Harden), device-deploy smoke check step: invoked the `deploy` skill per the phase
  spec's mandatory-commands list. Its own step 1 is `git status` — if uncommitted changes exist, STOP
  and tell the user to commit first, do NOT auto-commit. `git status --porcelain` shows 114 changed
  files (the cumulative uncommitted work of all 18 prior phases, never committed mid-run since no phase
  spec asked for a commit). This is a genuine, deliberate safety guardrail in the deploy skill, not a
  bug — committing 114 files including Phase 1's admin-role removal and Phase 18's new CloudKit record
  type to `main` and pushing is exactly the "hard to reverse, outward-facing" class of action that needs
  explicit user sign-off, not silent auto-commit. Paused (not retried — retrying without a commit would
  deterministically hit the same stop every time, same reasoning as the Phase 1 CLOUDKIT_KEY_ID
  blocker) and surfaced to the user via AskUserQuestion rather than routing around the skill's own
  guardrail or committing unasked.
