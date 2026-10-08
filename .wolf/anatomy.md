# anatomy.md

> Auto-maintained by OpenWolf. Last scanned: 2026-10-08T19:00:32.920Z
> Files: 40 tracked | Anatomy hits: 0 | Misses: 0

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


## ../../.claude/plans/

- `woolly-toasting-lobster.md` — Plan: Roll out the Supabase auth & role migration (~2226 tok)

## ../../.claude/projects/-Users-franz-dev-BlindensportGraz/memory/

- `project_supabase-auth-migration.md` (~488 tok)

## ../../.claude/projects/-Users-franz-dev-claude/memory/


## ./

- `project.yml` (~2248 tok)

## .claude/


## .claude/commands/


## .claude/rules/


## .claude/worktrees/reactive-watching-lemon/.wolf/


## .claude/worktrees/reactive-watching-lemon/BlindensportGraz/


## .claude/worktrees/reactive-watching-lemon/BlindensportGrazTests/


## .github/workflows/


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
- `RegisterView.swift` — / Creates a Supabase Auth account. Name goes into the sign-up metadata (the (~1409 tok)
- `ResetPasswordRequestView.swift` — / "Passwort vergessen": Supabase emails a link that opens the app (~622 tok)
- `RoleChangeLogView.swift` — / Role-change audit log from Supabase (`role_change_log`, written by a (~721 tok)
- `SetPasswordView.swift` — / Sets a new password for the signed-in Supabase account — after opening a (~775 tok)
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
- `AuthContext.swift` — / The signed-in account, its role and permissions — the one place views ask (~1620 tok)

## BlindensportGraz/Supabase/

- `AuthErrorMessage.swift` — German, user-facing text for Supabase Auth / RPC errors. (~461 tok)
- `MemberPrivateSync.swift` — Pushes local svnr/iban/birthDate/lastMedicalExamination edits to Supabase member_private (only with members.private.write and after load) (~400 tok)
- `SupabaseApprovalService.swift` — Struct: SupabaseApproval (~942 tok)
- `SupabaseAuthService.swift` — Struct: Row (~991 tok)
- `SupabaseClientSingleton.swift` — Holds the single shared SupabaseClient for the lifetime of the app. (~296 tok)
- `SupabaseConfig.swift` — Values come from the SUPABASE_URL / SUPABASE_ANON_KEY build settings (~255 tok)
- `SupabaseMemberPrivateService.swift` — Sensitive roster fields that no longer travel through the CloudKit public (~1392 tok)
- `SupabaseProfileService.swift` — Wire shape of `profiles` joined with the caller-visible role/approval. (~911 tok)
- `SupabaseRoleService.swift` — Struct: SupabaseRoleRow (~829 tok)

## BlindensportGraz/Sync/


## BlindensportGraz/Sync/CloudKit/


## BlindensportGrazShareExtension/


## BlindensportGrazTests/

- `AccessClaimsTests.swift` — Class: AccessClaimsTests (~917 tok)

## BlindensportGrazWidgets/


## RootCLI/


## RootCLI/Public/


## RootCLI/Sources/CloudKitS2SCore/

- `SupabaseAdminClient.swift` — if canImport(FoundationNetworking) (~1795 tok)

## RootCLI/Sources/clubmembersapi/


## RootCLI/Sources/rootcli/

- `SupabaseMigrate.swift` — / One-off move of accounts, roles, approvals and sensitive member data from (~3504 tok)

## RootCLI/Tests/CloudKitS2SCoreTests/


## Shared/ClubSchema/


## Shared/ClubSchema/Sources/ClubSchema/


## Shared/ClubSchema/Tests/ClubSchemaTests/


## data/


## fastlane/


## supabase/

- `seed.sql` — LOCAL DEVELOPMENT ONLY (`supabase db reset`). Never pushed to the hosted (~338 tok)

## supabase/functions/delete-account/

- `index.ts` — Deletes the calling user's auth account. All rows in public.* cascade (~521 tok)

## supabase/migrations/

- `20261008000001_rbac.sql` — Accounts, roles, permissions, approvals and protected member data. (~1780 tok)
- `20261008000002_auth_hook.sql` — Custom Access Token Hook: adds `user_role` (text or null) and `approved` (~722 tok)
- `20261008000003_rls.sql` — Row Level Security on every table. Clients never write user_roles, (~1167 tok)
- `20261008000004_rpcs.sql` — Write paths for roles and approvals. Every function is SECURITY DEFINER (~1909 tok)
- `20261008000005_member_private_self.sql` — Members see their own protected data (via their approval's roster entry) (~908 tok)
- `20261008000006_directory.sql` — Name-only directory of accounts for approved users (participant lists, (~222 tok)

## supabase/tests/

- `member_private_test.sql` — Run with: supabase test db (~864 tok)
- `rbac_test.sql` — Run with: supabase test db (~2528 tok)
