SUPERGOAL_PHASE_START
Phase: 9 of 19 — Shared schema package (app + RootCLI)
Task: Create a new local, dependency-free SwiftPM package for shared record-shape types, consumed by both the iOS app target and RootCLI.
Type: brownfield, refactor
Mandatory commands: xcodegen generate; xcodebuild build ...; cd RootCLI && swift build; xcodebuild test ...
Acceptance criteria: 6
Evidence required: new package listing, compile-time-drift demonstration, build tails
Depends on phases: 6

## Why

audit.md's Architecture Finding 5 — `RootCLI/Sources/CloudKitS2SCore/MemberRecord.swift` and
`RootCLI/Sources/clubmembersapi/Routes.swift` each independently hand-maintain the `Member`/`ClubMember`
CKRecord field shape with no shared code, already causing drift twice (cerebrum.md's 2026-07-18 and
2026-07-30 entries: a field split requiring lockstep updates across both codebases, caught only by
manual checklist discipline).

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first, specifically the 2026-07-18 and 2026-07-30 entries
  about this exact drift, to understand precisely what shape mismatch happened before.
- Read `RootCLI/Sources/CloudKitS2SCore/MemberRecord.swift`, `RootCLI/Sources/clubmembersapi/Routes.swift`,
  and the app's `Member`/`ClubMember` model (now in its own file per Phase 7) to determine the exact
  shared field shape.
- Create a new local SwiftPM package (e.g. `Shared/ClubSchema/Package.swift`) containing only plain
  `Codable` value types + string field-name constants for the Member/ClubMember record shape — Foundation
  only, no CloudKit/Vapor/UIKit/SwiftData imports, so it builds cleanly as a dependency of both an iOS
  app target and a macOS SPM executable.
- Add a `packages:` entry to `project.yml` pointing at the new local package by relative path; add it as
  a dependency of the `BlindensportGraz` target.
- Add the same local package as a dependency in `RootCLI/Package.swift`; refactor
  `RootCLI/Sources/CloudKitS2SCore/MemberRecord.swift` to use the shared types instead of its own
  independent field-shape declaration.
- Refactor the app-side `Member`/`ClubMember` CKRecord field mapping (in `CloudKitSync+Member.swift` per
  Phase 6's split) to also use the shared package's constants where they overlap with `CKSchema.swift`
  from Phase 5 — reconcile rather than duplicate; `CKSchema.swift` can re-export or wrap the shared
  package's constants for the Member type specifically.
- Demonstrate the drift-prevention this buys: temporarily rename one field in the shared package,
  confirm BOTH `xcodebuild build` (app) and `swift build` (RootCLI) fail to compile until the rename is
  propagated everywhere, then revert the temporary rename before finishing the phase (don't leave the
  test rename in the final diff).
- Update `.wolf/anatomy.md` for the new package; add a `.wolf/cerebrum.md` Decision Log entry documenting
  the new shared package as where future cross-codebase record-shape changes should go first.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] The new package builds standalone via `swift build` inside its own directory, with zero
      dependencies beyond Foundation
- [ ] `project.yml`'s `packages:` section references it by local path; `xcodegen generate` succeeds and
      the app target compiles using the shared types for the Member/ClubMember field shape
- [ ] `RootCLI/Package.swift` depends on the same local package;
      `RootCLI/Sources/CloudKitS2SCore/MemberRecord.swift` uses it instead of its own independent
      declaration
- [ ] The temporary-rename drift-catch demonstration is described in the transcript (before/after build
      failure, then confirmed reverted — the rename does NOT appear in the final code)
- [ ] Both `xcodebuild build` (app) and `swift build` (RootCLI) succeed with the new shared dependency in
      its final, non-renamed state
- [ ] `.wolf/cerebrum.md` documents the new shared package as the future home for cross-codebase
      record-shape changes

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `cd RootCLI && swift build`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- New package's `Package.swift` + directory listing
- The compile-time drift-catch demonstration, explicitly confirmed reverted
- Build tails (app + RootCLI) with exit codes

## Notes

Scope this to the Member/ClubMember shape specifically, matching what audit.md's Finding 5 actually
cites — don't try to migrate all 11 record types into the shared package in this phase; that's a much
larger undertaking than the audit describes and isn't required to close this specific finding. If
`xcodegen generate` + a local SPM package path reference proves genuinely broken in this XcodeGen
version, that's a real FAILURE_PROBE, not something to route around silently.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
