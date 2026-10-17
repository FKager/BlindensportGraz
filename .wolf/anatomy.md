# anatomy.md

> Auto-maintained by OpenWolf. Last scanned: 2026-10-17T12:24:14.294Z
> Files: 168 tracked | Anatomy hits: 0 | Misses: 0

## ../../../../private/tmp/claude-501/-Users-franz-dev-BlindensportGraz/2984f4bf-5d7b-4788-ad30-32ad8fdc94d7/scratchpad/


## ../../../../private/tmp/claude-501/-Users-franz-dev-BlindensportGraz/9310fa5d-a462-4776-b78e-97a4d735b7da/scratchpad/


## ../../../../private/tmp/claude-501/-Users-franz-dev-BlindensportGraz/f77275b7-eb9b-48cf-a257-42428c82e0cc/scratchpad/cktool/


## ../../../../private/tmp/claude-501/-Users-franz-dev-BlindensportGraz/fb41bc4a-fcd5-49ae-960d-e0a64acb5c99/scratchpad/


## ../../../../tmp/


## ../../../Users/franz/.claude/plans/

- `frolicking-stirring-breeze.md` — Migrate Authentication & Role Management to Supabase (~4385 tok)

## ../../../Users/franz/.claude/projects/C--dev-iOS-BlindensportGraz/memory/

- `MEMORY.md` — Memory (~45 tok)
- `project_supabase-auth-migration.md` — Current State (2026-10-04) (~960 tok)

## ../../.claude/jobs/53286a7d/tmp/export_test/Sources/ExportTest/


## ../../.claude/jobs/a920fb1f/tmp/


## ../../.claude/jobs/ad96dfdd/tmp/

- `limiter-e2e.sh` — Fix 1 check: a valid non-admin login must not reset the failure window. (~163 tok)

## ../../.claude/plans/

- `melodic-cuddling-magpie.md` — Web admin → Java Quarkus + Vaadin (~2435 tok)
- `prancy-fluttering-quill.md` — Plan: Move the remaining club data from CloudKit to Supabase (~3127 tok)
- `woolly-toasting-lobster.md` — Plan: Roll out the Supabase auth & role migration (~2226 tok)

## ../../.claude/projects/-Users-franz-dev-BlindensportGraz/memory/

- `MEMORY.md` — Memory (~364 tok)
- `project_cloudkit-to-supabase-club-data.md` — Declares in (~845 tok)
- `project_supabase-auth-migration.md` (~488 tok)

## ../../.claude/projects/-Users-franz-dev-claude/memory/


## ./

- `project.yml` (~2248 tok)

## .claude/


## .claude/commands/


## .claude/rules/


## .claude/worktrees/docker-container-fixes/

- `docker-compose.yml` — Docker Compose services (~944 tok)

## .claude/worktrees/docker-container-fixes/RootCLI/

- `Dockerfile` — Docker container definition (~711 tok)

## .claude/worktrees/pr9-review-fixes/.wolf/

- `buglog.json` (~117806 tok)

## .claude/worktrees/pr9-review-fixes/RootCLI/Public/

- `admin-session.css` — Styles: 2 rules (~162 tok)
- `index.html` — Grazer VSC – Mitgliederverwaltung (~3294 tok)
- `records.html` — CloudKit – Datensatzverwaltung (generisch) (~2300 tok)

## .claude/worktrees/pr9-review-fixes/RootCLI/Sources/CloudKitS2SCore/

- `MemberBulkImport.swift` — / Loose, per-row-tolerant input shape for bulk Member import — shared by (~3531 tok)
- `MemberFillUpdate.swift` — / Non-destructive counterpart to `MemberBulkImport.run` — fills in fields (~2650 tok)
- `MemberPrivateStore.swift` — / The protected part of a roster entry — SVNR, IBAN, birth date, last (~1931 tok)

## .claude/worktrees/pr9-review-fixes/RootCLI/Sources/clubmembersapi/

- `Auth.swift` — / A signed-in club admin. Accounts, roles and permissions come from (~2919 tok)
- `Routes.swift` — `MemberRecord` is a typealias for `ClubSchema.ClubMemberRecord` (Phase 9) — (~4253 tok)

## .claude/worktrees/pr9-review-fixes/RootCLI/Sources/rootcli/

- `RootCLI.swift` — Struct: RootCLI (~5779 tok)

## .claude/worktrees/reactive-watching-lemon/.wolf/


## .claude/worktrees/reactive-watching-lemon/BlindensportGraz/


## .claude/worktrees/reactive-watching-lemon/BlindensportGrazTests/


## .claude/worktrees/web-admin-session-race/.wolf/

- `buglog.json` (~116570 tok)

## .claude/worktrees/web-admin-session-race/RootCLI/Sources/clubmembersapi/

- `Auth.swift` — / A signed-in club admin. Accounts, roles and permissions come from (~2670 tok)

## .github/workflows/

- `supabase-maintenance.yml` — Supabase maintenance for the Free-plan projects (staging + production): (~1133 tok)

## .supergoal/implement-the-fixes-and-enhancements-fro-a5zzf8/


## .supergoal/implement-the-fixes-and-enhancements-fro-a5zzf8/phases/


## .supergoal/ios-best-practices-review-vR4hEq/


## .supergoal/ios-best-practices-review-vR4hEq/phases/


## BlindensportGraz.xcodeproj/


## BlindensportGraz.xcodeproj/project.xcworkspace/


## BlindensportGraz.xcodeproj/project.xcworkspace/xcuserdata/franz.xcuserdatad/


## BlindensportGraz.xcodeproj/xcuserdata/franz.xcuserdatad/xcschemes/


## BlindensportGraz/

- `CLAUDE.md` — CLAUDE.md (~1817 tok)

## BlindensportGraz/.claude/


## BlindensportGraz/App/


## BlindensportGraz/Features/Account/

- `EditAccountView.swift` — / Edits the own name in the Supabase profile (the only client-writable (~848 tok)
- `LoginView.swift` — / Email + password or Sign in with Apple, both against Supabase Auth. (~845 tok)
- `RedeemActivationCodeView.swift` — / A pending account enters the one-time code an admin created for it (~630 tok)
- `RegisterView.swift` — / Creates a Supabase Auth account. Name goes into the sign-up metadata (the (~1536 tok)
- `ResetPasswordRequestView.swift` — / "Passwort vergessen": Supabase emails a link that opens the app (~622 tok)
- `RoleChangeLogView.swift` — / Role-change audit log from Supabase (`role_change_log`, written by a (~721 tok)
- `SetPasswordView.swift` — / Sets a new password for the signed-in Supabase account — after opening a (~775 tok)
- `UserAccountAdminMenu.swift` — / "Konto" menu on a `UserListView` row, for root (`roles.assign`), never on (~1086 tok)
- `UserApprovalControls.swift` — / Approval status and admin actions for one account in "App-Konten": (~1142 tok)
- `UserRolePicker.swift` — / App-role picker on a `UserListView` row. Shown only with `roles.assign` (~478 tok)

## BlindensportGraz/Features/Attendance/


## BlindensportGraz/Features/Backup/


## BlindensportGraz/Features/Budget/


## BlindensportGraz/Features/Dashboard/


## BlindensportGraz/Features/Events/


## BlindensportGraz/Features/Members/


## BlindensportGraz/Features/Reports/


## BlindensportGraz/Features/Reports/KostZ/


## BlindensportGraz/Features/Reports/Prae/


## BlindensportGraz/Features/Reports/Sammelabrechnung/


## BlindensportGraz/Features/Reports/Teilnehmerliste/


## BlindensportGraz/Features/Reports/Trainingsfrequenzliste/


## BlindensportGraz/Features/Schedule/


## BlindensportGraz/Features/Teams/


## BlindensportGraz/Features/Tournaments/


## BlindensportGraz/Features/Trainings/


## BlindensportGraz/Features/Welcome/


## BlindensportGraz/Models/


## BlindensportGraz/Resources/


## BlindensportGraz/Resources/Assets.xcassets/


## BlindensportGraz/Resources/Assets.xcassets/AppIcon.appiconset/


## BlindensportGraz/Services/


## BlindensportGraz/Shared/

- `AccessClaims.swift` — / Fine-grained permissions, mirroring the `app_permission` enum in (~739 tok)
- `AuthContext.swift` — / The signed-in account, its role and permissions — the one place views ask (~2375 tok)

## BlindensportGraz/Supabase/

- `AuthErrorMessage.swift` — German, user-facing text for Supabase Auth / RPC errors. (~461 tok)
- `MemberPrivateSync.swift` — Pushes local svnr/iban/birthDate/lastMedicalExamination edits to Supabase member_private (only with members.private.write and after load) (~400 tok)
- `SupabaseAccountAdminService.swift` — Root's account administration: block (lock) / unblock and delete another (~356 tok)
- `SupabaseApprovalService.swift` — Struct: SupabaseApproval (~942 tok)
- `SupabaseAuthService.swift` — Struct: Row (~1186 tok)
- `SupabaseClientSingleton.swift` — Holds the single shared SupabaseClient for the lifetime of the app. (~296 tok)
- `SupabaseConfig.swift` — Values come from the SUPABASE_URL / SUPABASE_ANON_KEY build settings (~255 tok)
- `SupabaseMemberPrivateService.swift` — Sensitive roster fields that no longer travel through the CloudKit public (~1392 tok)
- `SupabaseProfileService.swift` — Wire shape of `profiles` joined with the caller-visible role/approval. (~911 tok)
- `SupabaseRoleService.swift` — Struct: SupabaseRoleRow (~829 tok)

## BlindensportGraz/Sync/

- `PushRegistration.swift` — / Registers this device's APNs token in Supabase (`device_tokens`) so the (~840 tok)
- `SyncStatusRow.swift` — / Always-visible sync status for the account screen: "Status: Online / (~1076 tok)

## BlindensportGraz/Sync/CloudKit/


## BlindensportGraz/Sync/Supabase/

- `SupabaseRows.swift` — One row type per Supabase table (migration 20261013000001_club_data). (~5086 tok)
- `SupabaseSync.swift` — / Keeps the local SwiftData cache in sync with the club data in Supabase (~4324 tok)
- `SupabaseSync+Models.swift` — Push and pull per table. Pulls fetch rows changed since the table's cursor; (~9047 tok)

## BlindensportGrazShareExtension/


## BlindensportGrazTests/

- `AccessClaimsTests.swift` — Class: AccessClaimsTests (~917 tok)
- `SupabaseRowsTests.swift` — Class: SupabaseRowsTests (~1311 tok)

## BlindensportGrazWidgets/


## RootCLI/


## RootCLI/Public/

- `admin-session.js` — shared sign-in for the admin pages (Supabase account, session cookie, X-Requested-With header, AdminSession.request/can) (~900 tok)
- `admin-session.js` — Sign-in for the admin pages. Admins use their own Blindensport Graz (~1134 tok)

## RootCLI/Sources/CloudKitS2SCore/

- `CloudKitCopy.swift` — / Maps the CloudKit public database's club data onto the Supabase tables (~4338 tok)
- `MemberPrivateStore.swift` — MemberPrivate (svnr/iban/dates), Supabase member_private read/write, CloudKitWriteGuard (~1500 tok)
- `MemberPrivateStore.swift` — / The protected part of a roster entry — SVNR, IBAN, birth date, last (~1484 tok)
- `MemberStore.swift` — / The club roster in Supabase (v0.3.0): `members` (names, readable by every (~1906 tok)
- `SupabaseAdminClient.swift` — if canImport(FoundationNetworking) (~2382 tok)

## RootCLI/Sources/clubmembersapi/

- `Auth.swift` — / A signed-in club admin. Accounts, roles and permissions come from (~2610 tok)
- `Configure.swift` (~439 tok)
- `Routes.swift` — `MemberRecord` is a typealias for `ClubSchema.ClubMemberRecord` (Phase 9) — (~3802 tok)

## RootCLI/Sources/rootcli/

- `SupabaseMigrate.swift` — / One-off move of accounts, roles, approvals and sensitive member data from (~3504 tok)

## RootCLI/Tests/CloudKitS2SCoreTests/

- `CloudKitCopyTests.swift` — Class: CloudKitCopyTests (~1299 tok)
- `MemberPrivateTests.swift` — protected fields never in ckFields, Supabase row format, CloudKitWriteGuard (~600 tok)
- `MemberPrivateTests.swift` — Class: MemberPrivateTests (~722 tok)

## Shared/ClubSchema/


## Shared/ClubSchema/Sources/ClubSchema/


## Shared/ClubSchema/Tests/ClubSchemaTests/


## data/


## fastlane/


## supabase/

- `seed.sql` — LOCAL DEVELOPMENT ONLY (`supabase db reset`). Never pushed to the hosted (~338 tok)

## supabase/functions/delete-account/

- `index.ts` — Deletes the calling user's auth account. All rows in public.* cascade (~521 tok)

## supabase/functions/notify-schedule/

- `index.ts` — Sends the schedule pushes ("Neues Training", "Training abgesagt", …) for (~1580 tok)

## supabase/migrations/

- `20261008000001_rbac.sql` — Accounts, roles, permissions, approvals and protected member data. (~1780 tok)
- `20261008000002_auth_hook.sql` — Custom Access Token Hook: adds `user_role` (text or null) and `approved` (~722 tok)
- `20261008000003_rls.sql` — Row Level Security on every table. Clients never write user_roles, (~1167 tok)
- `20261008000004_rpcs.sql` — Write paths for roles and approvals. Every function is SECURITY DEFINER (~1909 tok)
- `20261008000005_member_private_self.sql` — Members see their own protected data (via their approval's roster entry) (~908 tok)
- `20261008000006_directory.sql` — Name-only directory of accounts for approved users (participant lists, (~222 tok)
- `20261012000001_member_private_updated_by.sql` — touch trigger keeps updated_by supplied by the service role (~200 tok)
- `20261013000001_club_data.sql` — Club data moved from the CloudKit public database (v0.3.0): roster names (~5428 tok)
- `20261013000002_storage.sql` — Files formerly stored as CKAssets: event photos and expense receipts. (~516 tok)
- `20261014000001_push.sql` — Schedule pushes (v0.3.0; replaces the CloudKit query subscriptions): (~1405 tok)
- `20261014000002_account_admin.sql` — Root account administration: block (lock) / unblock and delete another (~1386 tok)
- `20261014000003_account_admin_hardening.sql` — Hardening for root account administration (review of 20261014000002): (~2307 tok)

## supabase/tests/

- `account_admin_hardening_test.sql` — Run with: supabase test db (~2468 tok)
- `account_admin_test.sql` — Run with: supabase test db (~1370 tok)
- `BlindensportGraz/Features/Account/UserAccountAdminMenu.swift` — "Konto" menu on App-Konten rows (root): Sperren/Entsperren, Löschen with confirmations (~700 tok)
- `BlindensportGraz/Supabase/SupabaseAccountAdminService.swift` — Root RPC wrappers: setBlocked / delete / fetchBlocked (~300 tok)
- `club_data_test.sql` — Run with: supabase test db (~2474 tok)
- `member_private_test.sql` — Run with: supabase test db (~864 tok)
- `push_test.sql` — Run with: supabase test db (~1767 tok)
- `rbac_test.sql` — Run with: supabase test db (~2528 tok)
- `supabase/migrations/20261014000002_account_admin.sql` — is_blocked, set_account_blocked, delete_account, blocked_accounts; block-aware has_permission/authorize/is_approved (~1200 tok)
- `supabase/migrations/20261014000003_account_admin_hardening.sql` — account_admin_log, root targets refused, last-root guard counts unblocked roots, calendar token rotation, is_blocked in own-account RPCs, unblocked_user_ids (~2500 tok)
- `supabase/tests/account_admin_hardening_test.sql` — pgTAP 26 tests for the hardening (~2200 tok)
- `supabase/tests/account_admin_test.sql` — pgTAP 17 tests for block/unblock/delete (~1300 tok)

## webadmin/

- `pom.xml` (~1264 tok)
- `README.md` — Project documentation (~2209 tok)

## webadmin/src/main/java/it/a11y/blindensport/webadmin/accounts/

- `AccountService.java` — App accounts ("App-Konten"), as the signed-in admin sees them. Every (~2290 tok)

## webadmin/src/main/java/it/a11y/blindensport/webadmin/api/

- `ApiAuthFilter.java` — Everything under /api needs a signed-in admin, except signing in itself; (~563 tok)
- `ApiException.java` — An API error answered as {@code {"error": true, "reason": "..."}} — the shape Vapor's Abort produced (~184 tok)
- `ApiExceptionMappers.java` — Every API error as {@code {"error": true, "reason": "..."}} (admin-session.js and scripts read {@cod (~603 tok)
- `CurrentAdmin.java` — The admin {@link ApiAuthFilter} found for this request. (~226 tok)
- `MembersResource.java` — The roster REST API, unchanged contract from the Swift server: (~2435 tok)
- `SessionResource.java` — POST/GET/DELETE /api/session — sign in with a Supabase account, show the current admin, sign out. (~948 tok)

## webadmin/src/main/java/it/a11y/blindensport/webadmin/auth/

- `Access.java` — Role and permissions as the database grants them right now (tables, not (~439 tok)
- `AdminSession.java` — One signed-in admin. Holds their Supabase tokens server-side (never sent (~942 tok)
- `AdminSessions.java` — Sign-in and the in-memory session table shared by the REST API (token in (~1525 tok)
- `LoginAttemptLimiter.java` — In-memory sliding-window limiter for failed sign-ins (REST and Vaadin (~567 tok)
- `Permission.java` — {@code public.app_permission} values (supabase/migrations/20261008000001_rbac.sql). (~354 tok)
- `SessionExpiredException.java` — The admin's session ended: timed out, signed out, or Supabase no longer accepts it. (~85 tok)
- `SignInException.java` — A refused sign-in, with the HTTP status the REST API answers and a German message. (~106 tok)

## webadmin/src/main/java/it/a11y/blindensport/webadmin/calendar/

- `CalendarFeed.java` — One user's read-only webcal feed (port of RootCLI's {@code CalendarFeed}). (~712 tok)
- `CalendarFeedResource.java` — {@code GET /calendar/{token}[.ics]} — one user's webcal feed, the URL the (~1207 tok)

## webadmin/src/main/java/it/a11y/blindensport/webadmin/club/

- `ClubModels.java` — Club data rows (supabase/migrations/20261013000001_club_data.sql) and the app's value conventions. (~1042 tok)
- `ClubStore.java` — Teams, memberships, events (trainings / tournaments / events), (~3226 tok)

## webadmin/src/main/java/it/a11y/blindensport/webadmin/members/

- `ChangeRequestStore.java` — Members' proposed changes to their own roster entry (~1682 tok)
- `Dates.java` — Date conventions shared with the Swift tooling and the app. (~827 tok)
- `MemberBulkImport.java` — Bulk create-or-update of roster entries — same per-row rules as RootCLI's (~1010 tok)
- `MemberBulkInput.java` — Loose, per-row-tolerant import row — the same JSON shape as the app's (~424 tok)
- `MemberInput.java` — Body of POST/PUT /api/members (and what the Vaadin form produces): the (~1049 tok)
- `MemberPrivate.java` — The protected part of a roster entry — SVNR, IBAN, birth date, last (~513 tok)
- `MemberRecord.java` — One roster entry as the API and the UI see it — the same shape as (~984 tok)
- `MemberStore.java` — The club roster in Supabase, read and written as the signed-in admin (RLS: (~1674 tok)
- `Validation.java` — Soft checks as in the app's {@code Validation.swift}: they warn, never (~374 tok)

## webadmin/src/main/java/it/a11y/blindensport/webadmin/supabase/

- `DbErrorMessages.java` — German texts for the errors the database raises (supabase/migrations: (~600 tok)
- `GoTrue.java` — Supabase Auth (GoTrue) with the anon key: sign in, refresh, sign out. (~791 tok)
- `Postgrest.java` — PostgREST (tables + RPCs) with one identity: either a signed-in admin (~1072 tok)
- `Supabase.java` — Entry point to the club's Supabase project: auth, user-scoped and service-role PostgREST. (~427 tok)
- `SupabaseConfig.java` — {@code supabase.*} in application.properties (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_KEY) (~159 tok)
- `SupabaseException.java` — A Supabase call answered with a non-2xx status. {@link #code()} is the (~465 tok)
- `SupabaseHttp.java` — Raw HTTP to one Supabase project (GoTrue under {@code auth/v1}, PostgREST (~1214 tok)

## webadmin/src/main/java/it/a11y/blindensport/webadmin/ui/

- `AccessGuard.java` — Every navigation: no valid session → sign-in page; a view marked (~490 tok)
- `AccountDialog.java` — Everything an admin can do with one account, as plainly labelled buttons (~2575 tok)
- `AccountsView.java` — "App-Konten": approve accounts and link them to their roster entry, (~1987 tok)
- `AdminView.java` — Base of the signed-in pages: a page heading (h1 — VoiceOver users jump (~675 tok)
- `Announcer.java` — Status messages. Vaadin notifications live in an ARIA live region, so (~452 tok)
- `AppShell.java` — Class: AppShell (~110 tok)
- `AttendanceDialog.java` — Roll call for one training or tournament, like the app's (~1659 tok)
- `BudgetView.java` — Club budget ("Vereinsbudget"): income and expenses per year, with balance. (~2561 tok)
- `ChangeRequestsView.java` — Review members' proposed changes to their own entry (Annehmen / Ablehnen), like the app's Änderungsa (~2387 tok)
- `ClubFields.java` — Form fields shared by the club-data dialogs. (~749 tok)
- `EventDialog.java` — Create / edit a training, tournament or event. Trainings: start + duration (~2741 tok)
- `EventsView.java` — Trainings, tournaments and other events in one list, filterable by type; attendance per entry. (~2640 tok)
- `FavoritesView.java` — Saved recurring trainings ("Favoriten") the app offers when creating a training. (~2241 tok)
- `GermanUi.java` — German texts and formats for Vaadin's built-in components (their defaults are English). (~1197 tok)
- `LoginView.java` — Sign-in with the own Blindensport Graz account (same as in the app). Own (~1018 tok)
- `MainLayout.java` — Frame of every signed-in page: title, who is signed in, sign-out, and (~864 tok)
- `MemberDialog.java` — Create / edit one roster entry, laid out like the app's MemberDetailView. (~2864 tok)
- `MembersView.java` — The club roster: search, create, edit, delete, JSON import and export. (~2945 tok)
- `RequiresPermission.java` — A view only admins holding at least one of these permissions may open (checked by {@link AccessGuard (~118 tok)
- `RoleLogView.java` — Audit trail: role changes and block/unblock/delete of accounts (rolelog.read), like the app's RoleCh (~904 tok)
- `SessionCookieSetup.java` — Vaadin's HTTP session cookie (JSESSIONID): HttpOnly, and Secure unless (~246 tok)
- `StartView.java` — Start page: the areas this admin may open, as a plain link list. (~418 tok)
- `TeamsView.java` — Teams and who plays / coaches in them. (~3030 tok)
- `UiSession.java` — The Vaadin side of a sign-in: the {@link AdminSessions} token lives in the (~464 tok)
- `WelcomeView.java` — The welcome text the app shows at startup, also before signing in (club.manage). (~876 tok)

## webadmin/src/main/resources/

- `application.properties` — Supabase project the web admin works on. Admins act with their OWN (~401 tok)

## webadmin/src/test/java/it/a11y/blindensport/webadmin/api/

- `ApiTest.java` — The REST contract of the Swift server (session, CSRF, members CRUD, (~4269 tok)
- `SupabaseMock.java` — A WireMock stand-in for the Supabase project (GoTrue + PostgREST) during @QuarkusTest. (~213 tok)

## webadmin/src/test/java/it/a11y/blindensport/webadmin/auth/

- `LoginAttemptLimiterTest.java` — LoginAttemptLimiterTest: getZone, withZone, instant (~618 tok)

## webadmin/src/test/java/it/a11y/blindensport/webadmin/calendar/

- `CalendarFeedTest.java` — Port of RootCLI's CalendarFeedTests. (~1022 tok)

## webadmin/src/test/java/it/a11y/blindensport/webadmin/members/

- `ChangeRequestStoreTest.java` — Approve / reject of member change requests against a mocked PostgREST. (~1501 tok)
- `MemberInputTest.java` — PUT semantics of the members API, as the Swift server had them. (~890 tok)
- `MemberMappingTest.java` — Ports of RootCLI's MemberStoreTests / MemberPrivateTests (row mapping, no network). (~1474 tok)
- `ValidationTest.java` — Class: ValidationTest (~251 tok)

## webadmin/src/test/java/it/a11y/blindensport/webadmin/ui/

- `ChangeRequestDiffTest.java` — Class: ChangeRequestDiffTest (~476 tok)
