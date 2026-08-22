SUPERGOAL_PHASE_START
Phase: 17 of 19 — Calendar/EventKit integration
Task: Add an "Add to Calendar" action for Training/Tournament detail views (EventKit or .ics+ShareLink, whichever is the better VoiceOver fit).
Type: brownfield, feature
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...
Acceptance criteria: 5
Evidence required: chosen-approach rationale, event-mapping code, new test output, build/test tails
Depends on phases: 8

## Why

audit.md's Enhancement #9 — confirmed absent entirely (`grep -rn "EventKit\|EKEventStore"
BlindensportGraz` → no hits). Would let members add trainings/tournaments to their personal calendar.

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first, specifically the 2026-07-18 VoiceOver lesson about
  preferring native `ShareLink` over custom `UIViewControllerRepresentable` wrappers for sharing/export
  features in this app.
- Decide between `EKEventStore` (native "Add to Calendar" with a permission prompt) and a generated
  `.ics` file offered via `ShareLink` (no permission prompt, reuses the pattern already proven to work
  well under VoiceOver for this app per the cited cerebrum.md lesson) — pick whichever gives the better
  VoiceOver experience and document the choice in a code comment and in this phase's evidence.
- Implement the chosen approach on Training/Tournament detail views: a discoverable action mapping the
  Training/Tournament's title, location, and start/end time to a calendar event.
- Give the action a correct `.accessibilityLabel` from the start — this app's primary usage mode is
  VoiceOver, this must not wait for a later accessibility phase.
- Decide and document what happens when the Training/Tournament's date is edited after the calendar
  event was created: either the feature is add-on-demand-only (no persistent link to maintain, simplest
  and safest default) or it updates the existing entry — pick one, document why, don't leave it
  ambiguous.
- Add a unit test for the event-data-mapping logic (Training/Tournament → calendar event fields:
  title/location/start/end) independent of actual EventKit/file I/O.
- Update `.wolf/anatomy.md`/`.wolf/memory.md` per the OpenWolf protocol.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] Training/Tournament detail views have a discoverable "Add to Calendar" action with a correct,
      German-language `.accessibilityLabel`
- [ ] The created/exported calendar event has the correct title, location, and start/end time
- [ ] Permission handling matches the chosen approach (EventKit authorization request, or no prompt
      needed if `.ics`+`ShareLink` — the choice and its reasoning are documented)
- [ ] The stale-entry-on-edit behavior is explicitly decided and documented (add-on-demand-only, or
      update-existing — not left unhandled/ambiguous)
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions), plus at least one new test for the event-data-mapping logic

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- The chosen approach and why, plus its code
- New test name(s) + pass output
- Build/test tails with exit codes

## Notes

Given this app's documented VoiceOver history with custom UIKit wrappers, the `.ics`+`ShareLink`
approach is the safer default unless EventKit's native flow proves clearly better in testing — don't
default to EventKit just because it's the more "native-feeling" option without weighing the VoiceOver
track record.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
