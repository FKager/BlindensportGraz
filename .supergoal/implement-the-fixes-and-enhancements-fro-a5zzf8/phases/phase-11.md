SUPERGOAL_PHASE_START
Phase: 11 of 19 — Query predicates & subscription retry
Task: Add #Predicates to the largest unfiltered @Query sites and add retry to CKQuerySubscription registration failures.
Type: brownfield, performance, reliability
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...
Acceptance criteria: 4
Evidence required: query diffs, subscription-retry diff, build/test tails
Depends on phases: 6

## Why

audit.md's SwiftData & CloudKit Finding 6 (most `@Query`s unfiltered, fetching the entire shared/public
store into memory) and Finding 8 (no recovery path if `CKQuerySubscription` registration fails, silently
and permanently killing creation alerts for that device).

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first.
- Add `#Predicate`s to the `@Query` sites audit.md names: `TeamsViews.swift:8`, `KostZViews.swift:18`/`124`,
  `SammelabrechnungViews.swift:15`/`111`, `RootView.swift:20`/`274` — for each, determine a natural scope
  (date range, team, selected period) from the surrounding view's own state/parameters. Where no natural
  predicate exists (a screen genuinely needs the full set), leave it unfiltered but add a one-line code
  comment explaining why.
- Add retry to `CKQuerySubscription` registration failure (currently a single `print()` at
  `CloudKitSync.swift:403`, now relocated by Phase 6's split) — reuse Phase 6's retry/backoff helper if
  its shape fits a one-shot registration call; log final failure via `os.Logger`, not a bare `print()`.
- Confirm no screen's visible data changes as a result of adding predicates — every predicate must be
  provably equivalent to "the subset this screen actually needs," not an accidental narrowing.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] Every `@Query` site audit.md names either has a `#Predicate` added or a one-line comment
      explaining why it's intentionally unfiltered
- [ ] Subscription registration retries at least once more with backoff before giving up, logging via
      `os.Logger` on final failure
- [ ] No behavior regression — every screen previously showing the full unfiltered list still shows
      correct data after predicates are added, verified by existing/new unit tests
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions)

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- Before/after `@Query` diffs for each cited site
- Subscription-retry code diff
- Build/test tails with exit codes

## Notes

This app is single-club scale today (audit.md notes this is "fine at current scale"), so predicates here
are about correctness-of-intent and future-proofing, not fixing an active performance problem — don't
over-engineer pagination infrastructure that isn't asked for.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
