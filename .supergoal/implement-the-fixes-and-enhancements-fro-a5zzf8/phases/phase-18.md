SUPERGOAL_PHASE_START
Phase: 18 of 19 — Receipt/document attachments
Task: Add an EventImage-pattern attachment model + UI for KostZ/PRAE expense receipts.
Type: brownfield, feature
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...
Acceptance criteria: 5
Evidence required: new model+UI code, scoping-decision note, new test output, build/test tails
Depends on phases: 8

## Why

audit.md's Enhancement #10 — extends the existing `EventImage` (`@Attribute(.externalStorage)` +
`CKAsset`) pattern already used for event photos, applied instead to expense receipts, a natural fit for
the accounting flows and reuses a proven CloudKit-asset-sync mechanism rather than inventing a new one.

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first. Read `EventImagesViews.swift` and the `EventImage`
  model (now in its own file per Phase 7) plus its `CloudKitSync` push/pull (now in its own file per
  Phase 6) in full — this phase's job is to mirror this exact pattern, not invent a new one.
- Add a new `@Model final class ExpenseReceipt` (or similar name) with `@Attribute(.externalStorage)`
  data storage, following `EventImage`'s field shape and immutable-once-uploaded convention.
- Add CloudKit sync for it via the same CKAsset-via-temp-file-plus-`defer`-cleanup pattern `EventImage`
  uses — reuse the Phase 8 service layer for its save+sync call, not a new inline pattern.
- Decide and document the image-vs-PDF scoping: if handling both images and PDFs is materially more work
  than images alone, scope this phase to images only (matching most real-world receipt-photo use) and
  note PDF support as a documented follow-up, rather than half-implementing PDF handling.
- If image: downscale/compress before upload, matching `EventImage`'s existing `ImageProcessing`
  approach.
- Add upload/view/delete UI on the KostZ/PRAE screens, reusing `EventImagesViews.swift`'s reusable-section
  approach rather than writing new list-rendering code from scratch.
- Restrict delete to the uploader or an admin, matching `EventImage`'s existing permission model exactly.
- Add a unit test for the receipt model's CloudKit encode/decode round-trip.
- Update `.wolf/anatomy.md`/`.wolf/memory.md` per the OpenWolf protocol.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] `ExpenseReceipt` mirrors `EventImage`'s CKAsset sync pattern exactly (temp file + `defer` cleanup,
      immutable-once-uploaded, skip-if-present-locally pull behavior)
- [ ] Upload UI is reachable from the KostZ/PRAE accounting screens
- [ ] Delete is restricted to the uploader or an admin
- [ ] Uses the Phase 8 service layer for its save+sync calls, not a new inline pattern
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions), plus at least one new test for the receipt model's CloudKit
      round-trip

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- The new model + UI code, with an explicit note on the image-vs-PDF scoping decision
- New test name(s) + pass output
- Build/test tails with exit codes

## Notes

This is the last feature-addition phase before Polish & Harden — if anything about the Phase 8 service
layer's call shape has proven awkward across Phases 14-17, this is a reasonable last chance to note it
(not fix it — scope creep into re-opening Phase 8 is out of bounds) for Phase 19's manual-follow-ups list.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
