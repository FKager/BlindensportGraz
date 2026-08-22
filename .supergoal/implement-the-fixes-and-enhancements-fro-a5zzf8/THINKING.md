# Thinking: Implement audit.md fixes & enhancements — BlindensportGraz

## Goals

Turn every actionable finding in `audit.md` (36 findings across Architecture, SwiftData & CloudKit,
Security, Accessibility, minus the 9 findings explicitly marked "Positive — no fix needed") plus the
enhancement backlog (12 items, minus P2 #12 "multi-club/multi-section extensibility" which the user
explicitly excluded from this run) into shipped code, in small ordered phases, each independently
verifiable.

## Constraints

- Local `xcodebuild`/codesign hits a sandbox-level `errSecInternalComponent` block (cerebrum.md
  bug-008) — device build/deploy is NOT locally runnable; use `xcodebuild build -sdk iphonesimulator
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` for build verification and `xcodebuild test` with
  the same flags (plus a concrete simulator destination discovered via `xcrun simctl list devices
  available`) for test verification — both confirmed working locally per cerebrum.md's 2026-08-05
  entry. `MemberImportExportTests` AND `TrainingImportExportTests` are known pre-existing crashes
  under unsigned test runs (16 tests total: 10 + 6 — CloudKit-entitlement related, bug-202's root cause,
  confirmed broader than originally documented by this run's actual pre-flight check, see STATE.md's
  Notable events) — not a regression signal, do not chase it. Any OTHER test failure is real.
- Any new/removed/renamed Swift file requires `xcodegen generate` (project.yml uses folder-based
  `sources:`, so the `.xcodeproj` must be regenerated to pick up file adds/removes).
- RootCLI is a separate SPM package (`swift build` / no test target currently exists), macOS-only
  platform, no local codesigning issues.
- CloudKit Dashboard "Security Roles" configuration (Security Finding 2) is NOT automatable from this
  environment — no API/CLI for it was found in prior sessions (`cktool` has schema import/export but no
  Security Roles subcommand, per cerebrum.md 2026-07-16 entry). Phases addressing this produce
  documentation/a checklist for the user to apply manually in the Dashboard, not code that flips it.
- The user has ONLY the `testAdminEmail` backdoor for admin access today (real root is the club's own
  `blindensport.gvsc@gmail.com`) — confirmed via user AskUserQuestion answer: grant real admin via
  RootCLI's `set-role` BEFORE deleting the backdoor code, in Phase 1, so access isn't lost mid-run.
- User explicitly excluded P2 enhancement #12 (multi-club/multi-section extensibility) from this run's
  scope — do not implement or partially implement it.
- OpenWolf protocol applies throughout: check `.wolf/anatomy.md` before reading files, `.wolf/cerebrum.md`
  Do-Not-Repeat before generating code, append `.wolf/memory.md`/update `.wolf/anatomy.md` after edits,
  log to `.wolf/buglog.json` per its trigger list. Each phase spec reminds the executor of this.

## Risks (top 3)

1. **A large, unsupervised refactor (splitting CloudKitSync.swift/Models.swift, introducing closed
   enums, a service layer) silently breaks sync or role logic with no human watching in real time.**
   Likelihood: medium. Mitigation: sequence the risky architecture phases early but each individually
   scoped and each required to pass the full local unit test suite before advancing; the closed-enum
   migration explicitly requires back-compat normalization for existing free-text CloudKit data (no
   destructive migration); the 3-strike failure-recovery protocol catches genuine breaks.
2. **Removing the `testAdminEmail` backdoor before the user has confirmed real admin access works
   locks the user out of their own app.** Likelihood: low if sequenced correctly. Mitigation: Phase 1
   explicitly grants real admin via RootCLI `set-role` FIRST, verifies the grant (query the record back)
   BEFORE touching Models.swift, and only then removes the backdoor code.
3. **CloudKit schema changes (new record types: RoleChangeLog, receipt attachments, etc.) get pushed
   against Development but the app also needs them in Production, and Security Roles hardening can't be
   verified from this sandbox at all.** Likelihood: medium. Mitigation: every phase that adds a new
   CKRecord type documents the manual Dashboard step required (adding the record type/indexes/roles in
   Production) in its own PR-note-equivalent (a short doc comment + a line in `RootCLI/README.md`'s
   Security Roles section, kept current per Security Finding 2's original gap). The final Polish &
   Harden phase compiles a single "manual follow-ups required" list surfaced to the user.

## Non-obvious dependencies

- Enum migration (role/sport) must happen AFTER the schema-constants centralization (so it can reuse
  the same field-name constants) but BEFORE the enhancement phases that create new records referencing
  role/sport, so new code is written against the final enum types, not the old free-text convention.
- The service-layer extraction (Architecture F1/F6/F8) should land before the 5 enhancement phases so
  their new sync call sites follow the new pattern instead of adding 5 more copies of the old
  `try? modelContext.save(); CloudKitSync.shared.push...()` boilerplate the audit flags.
- Accessibility phases are independent of the architecture phases (different files/concerns mostly) —
  sequenced after Security/Architecture only to keep the run's phase count manageable and because
  Security was the user's explicit top priority.

## Memory hits applied

None — no prior memory exists for this project (`MEMORY.md` absent, empty memory dir). This run's
context comes entirely from `.wolf/cerebrum.md`/`.wolf/buglog.json`, read directly by each phase.

## Tools / skills relied on

- `xcodegen generate` for project regen after file adds/removes.
- `xcodebuild build`/`test` locally with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` for
  simulator-target verification (confirmed working in this sandbox).
- `swift build` for RootCLI (separate SPM package, no signing concerns).
- `deploy` project skill (self-hosted GitHub Actions) reserved for the final Polish & Harden phase's
  one real device-level smoke check, not run per-phase (avoids repeatedly disturbing the user's phone).
- WebSearch available if a phase needs to double check a current SwiftData/EventKit/Charts/
  UserNotifications API detail against training-cutoff knowledge.

## Best practices applied

- Closed enums with legacy-value normalization instead of a destructive migration (existing free-text
  CloudKit data must keep working).
- `os.Logger` (not `print()`) for anything that needs to survive into Console.app/sysdiagnose.
- Native `ShareLink`/Apple-maintained presentation APIs preferred over custom `UIViewControllerRepresentable`
  wrappers for any new export/share flow, per cerebrum.md's 2026-07-18 VoiceOver lesson.
- New CKAsset-backed features (receipt attachments) follow the existing `EventImage` pattern
  (downscale/compress before upload, CKAsset via temp file + `defer` cleanup) rather than inventing a
  new one.
- Local notifications (`UNCalendarNotificationTrigger`) are additive to the existing creation-alert
  `CKQuerySubscription`s, not a replacement.
