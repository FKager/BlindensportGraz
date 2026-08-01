# anatomy.md

> Auto-maintained by OpenWolf. Last scanned: 2026-08-01T12:30:34.760Z
> Files: 83 tracked | Anatomy hits: 0 | Misses: 0

## ../../.claude/jobs/53286a7d/tmp/export_test/Sources/ExportTest/

- `main.swift` — Struct: Entry (~843 tok)

## ../../.claude/plans/

- `functional-inventing-dream.md` — Make SportEvent the base class for Training and Tournament (~3676 tok)

## ../../.claude/projects/-Users-franz-dev-claude/memory/

- `feedback_no_clarifying_questions.md` (~384 tok)
- `feedback_test_on_physical_device.md` (~402 tok)
- `MEMORY.md` — Memory (~75 tok)

## ./

- `.DS_Store` (~2186 tok)
- `.gitignore` — Git ignore rules (~41 tok)
- `.mcp.json` (~58 tok)
- `CLAUDE.md` — OpenWolf (~129 tok)
- `CLAUDE.mdes` — Requirements (~91 tok)
- `download_certificate.sh` — One-time helper: exports your local "Apple Development" signing identity (~511 tok)
- `profile.plist` (~0 tok)
- `project.yml` (~557 tok)

## .claude/

- `settings.json` (~441 tok)
- `settings.local.json` (~380 tok)

## .claude/rules/

- `openwolf.md` (~313 tok)

## .github/workflows/

- `ios-build-deploy.yml` — CI: iOS Build and Deploy (~2446 tok)
- `ios-device-deploy.yml` — CI: iOS Device Deploy (~2426 tok)

## BlindensportGraz.xcodeproj/

- `project.pbxproj` — !$*UTF8*$! (~4369 tok)

## BlindensportGraz.xcodeproj/project.xcworkspace/

- `contents.xcworkspacedata` (~36 tok)

## BlindensportGraz.xcodeproj/project.xcworkspace/xcuserdata/franz.xcuserdatad/

- `UserInterfaceState.xcuserstate` (~2439 tok)

## BlindensportGraz.xcodeproj/xcuserdata/franz.xcuserdatad/xcschemes/

- `xcschememanagement.plist` (~94 tok)

## BlindensportGraz/

- `AccountView.swift` — SwiftUI view: AccountView (~2999 tok)
- `AppleSignIn.swift` — Struct: SignInResult (~540 tok)
- `BlindensportGraz.entitlements` (~147 tok)
- `BlindensportGrazApp.swift` — Struct: BlindensportGrazApp (~1119 tok)
- `CLAUDE.md` — CLAUDE.md (~1292 tok)
- `CloudKitSync.swift` — / Shares Team/Event/Training/Tournament/Membership/Participation/ClubMember/ (~8572 tok)
- `ClubMemberImportExport.swift` — / JSON shape for one club member, shared by export and import. Field names (~4410 tok)
- `ClubMembersViews.swift` — / Admin-only management of the "Grazer VSC" club membership roster. New app (~4317 tok)
- `DashboardView.swift` — SwiftUI view: DashboardView (~1112 tok)
- `EventImagesViews.swift` — / Downscales/compresses picked photo library assets before they ever hit (~1549 tok)
- `EventsViews.swift` — SwiftUI view: AddEventView (~3506 tok)
- `Info.plist` (~414 tok)
- `KostZCalculation.swift` — / One eligible person's summed amount for the requested month — see (~982 tok)
- `KostZExport.swift` — Declares KostZExportError (~1077 tok)
- `KostZViews.swift` — / Admin-only screen (see AccountView's "KostZ-Berechnung" button) that (~1343 tok)
- `Localizable.xcstrings` (~6145 tok)
- `MemberListView.swift` — / Admin-only member list for a SportEvent, Tournament, or Training, derived (~1378 tok)
- `Models.swift` — Class: User (~5239 tok)
- `PraeCalculation.swift` — / One club member/user who has at least one coach/assistant ("Helfer") (~1516 tok)
- `PraeExport.swift` — Declares PraeExportError (~3190 tok)
- `PraeViews.swift` — / Admin-only screen (see AccountView's "PRAE-Berechnung" button) that picks (~2191 tok)
- `RootView.swift` — SwiftUI view: RootView (~3687 tok)
- `TeamsViews.swift` — SwiftUI view: TeamsListView (~2807 tok)
- `TeilnehmerlisteExport.swift` — / One row of the exported TeilnehmerInnenliste. (~2138 tok)
- `TournamentsViews.swift` — SwiftUI view: AddTournamentView (~4390 tok)
- `TrainingsfrequenzlisteCalculation.swift` — / One roster row of the Trainingsfrequenzliste: a team member plus their (~1228 tok)
- `TrainingsfrequenzlisteExport.swift` — / Exports the Sport-Austria-federation-style "Trainingsfrequenzliste" (~2546 tok)
- `TrainingsfrequenzlisteViews.swift` — / Admin-only screen (see AccountView's "Trainingsfrequenzliste" button) (~1392 tok)
- `TrainingsViews.swift` — SwiftUI view: AddTrainingView (~4371 tok)
- `XLSXCellPatch.swift` — / Shared cell-rewriting helpers for patching blank cells inside a real (~547 tok)

## BlindensportGraz/.claude/

- `settings.local.json` (~38 tok)

## BlindensportGrazTests/

- `ClubMemberImportExportTests.swift` — Class: ClubMemberImportExportTests (~2636 tok)
- `InheritanceQueryTests.swift` — Class: InheritanceQueryTests (~1626 tok)
- `KostZCalculationTests.swift` — Class: KostZCalculationTests (~2524 tok)
- `PraeCalculationTests.swift` — Class: PraeCalculationTests (~3125 tok)
- `TeilnehmerlisteExportTests.swift` — Class: TeilnehmerlisteExportTests (~1634 tok)
- `TrainingsfrequenzlisteCalculationTests.swift` — Class: TrainingsfrequenzlisteCalculationTests (~2226 tok)

## RootCLI/

- `members.example.json` (~110 tok)
- `Package.swift` — swift-tools-version:5.9 (~355 tok)
- `README.md` — Project documentation (~3314 tok)

## RootCLI/Public/

- `index.html` — Grazer VSC – Mitgliederverwaltung (~1624 tok)
- `records.html` — CloudKit – Datensatzverwaltung (generisch) (~1942 tok)

## RootCLI/Sources/CloudKitS2SCore/

- `CKFieldCoding.swift` — / Generic bridge between plain JSON/Swift values and CloudKit Web Services' (~1693 tok)
- `CKRecordDTO.swift` — Public CKRecord DTO: stringField/boolField/dateField accessors (~420 tok)
- `CloudKitS2SClient.swift` — if canImport(FoundationNetworking) (~2435 tok)
- `ClubMemberBulkImport.swift` — / Loose, per-row-tolerant input shape for bulk ClubMember import — shared by (~2974 tok)
- `ClubMemberFillUpdate.swift` — / Non-destructive counterpart to `ClubMemberBulkImport.run` — fills in fields (~1743 tok)
- `ClubMemberRecord.swift` — / Single source of truth for the `ClubMember` CKRecord field mapping, (~1320 tok)
- `Config.swift` — Public Config + CLIError, env-var based (~433 tok)

## RootCLI/Sources/clubmembersapi/

- `Auth.swift` — HTTP Basic Auth middleware, constant-time SHA256 compare, API_USERNAME/API_PASSWORD (~315 tok)
- `Configure.swift` — Vapor app config: requires API_USERNAME/PASSWORD (fails fast if missing), auth+guard+FileMiddleware(defaultFile: "index.html"), PORT/HOSTNAME (~423 tok)
- `Entrypoint.swift` — @main entrypoint — deliberately NOT named main.swift (SPM special-cases that filename, see cerebrum Do-Not-Repeat 2026-07-16); wraps startup throw in do/catch for clean exit(1) instead of fatalError (~200 tok)
- `Routes.swift` — Struct: ClubMemberInput (~2710 tok)

## RootCLI/Sources/rootcli/

- `ClubMemberImport.swift` — / File-loading half of `import-members` — the per-row decode shape and the (~240 tok)
- `RootCLI.swift` — Struct: RootCLI (~3128 tok)

## data/

- `club-members-import.json` — Merged Person-Sport.json + Person-Others.json (50 records), ready for `rootcli import-members` (~2900 tok)
- `Person-Others.json` — Source roster: 7 coach/helper records, same shape as Person-Sport.json plus defaultFunction="COACH" (~750 tok)
- `Person-Sport.json` — Source roster: 43 Grazer VSC athlete records (gender/title/firstName/lastName/birthDate/street/zip/city/phone/email/sportId/svnr/iban/lastMedicalExamination) (~2800 tok)
- `person.new.json` — Updated/extended roster, 58 records, same ClubMemberBulkInput-compatible shape as Person-Sport/Others.json; some entries overlap by name with club-members-import.json — use `rootcli update-members` (fill-blanks-only), not `import-members`, to avoid clobbering/duplicating existing data (~2900 tok)

## fastlane/

- `Appfile` — app_identifier it.a11y.BlindensportGraz, team 5Q57Y9YT8J (~30 tok)
- `Fastfile` (~493 tok)
