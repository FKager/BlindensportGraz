SUPERGOAL_PHASE_START
Phase: 14 of 19 — Local reminder notifications
Task: Add UNCalendarNotificationTrigger-based local reminders for Training/Tournament start times, rescheduled on edit and cancelled on delete.
Type: brownfield, feature
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...
Acceptance criteria: 6
Evidence required: scheduling/reschedule/cancel code, new test output, build/test tails
Depends on phases: 8

## Why

audit.md's Enhancement #5 — confirmed via `PushNotifications.swift`'s own doc comment that the existing
`CKQuerySubscription`s only fire on Training/Tournament *creation*, never on a schedule before the event
starts. This is additive to, not a replacement for, the existing creation-alert subscriptions.

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md` first. Read `PushNotifications.swift` in full to
  understand the existing registration/permission-request flow before adding to it.
- Add local notification scheduling using `UNCalendarNotificationTrigger` off `Training.startDate`/
  `Tournament.startDate`, firing at a reasonable lead time before the event (e.g. 2 hours — pick a
  sensible default, this isn't user-configurable in this phase unless trivially easy to add a fixed
  setting).
- Wire scheduling into the Phase 8 service layer's Training/Tournament save path (create → schedule;
  update with a changed start date → cancel old + schedule new; delete → cancel) rather than adding a
  new ad-hoc call site pattern outside the service layer.
- Guard against scheduling a notification for a start date already in the past (no immediate/backdated
  fire).
- Request notification permission appropriately — reuse `PushNotifications.swift`'s existing
  registration flow if it already requests `UNUserNotificationCenter` authorization, or add the request
  if it doesn't yet.
- Add tests for the scheduling logic that don't require a real device/notification to actually fire:
  assert on the computed `UNNotificationRequest`/trigger date given a known `startDate`, and assert that
  edit/delete correctly remove the prior pending request identifier before adding/not adding a new one.
- Update `.wolf/anatomy.md`/`.wolf/memory.md` per the OpenWolf protocol.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] Creating a Training/Tournament with a future start date schedules exactly one local notification
      at the chosen lead time before `startDate`
- [ ] Editing the start date reschedules the notification — no duplicate, no stale one pointing at the
      old time
- [ ] Deleting the Training/Tournament cancels its notification
- [ ] A start date already in the past does not schedule a notification
- [ ] Notification permission is requested via the existing or extended `PushNotifications.swift` flow
- [ ] Full local unit test suite passes (no NEW failures beyond the pre-flight baseline recorded in STATE.md — MemberImportExportTests/TrainingImportExportTests are known pre-existing CloudKit-entitlement crashes under unsigned test runs, not regressions), plus new tests for schedule/reschedule/cancel logic

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## Evidence required in transcript

- The scheduling/reschedule/cancel code
- New test names + pass output
- Build/test tails with exit codes

## Notes

Keep this additive only — do not modify the existing `CKQuerySubscription` creation-alert mechanism in
`PushNotifications.swift`/`CloudKitSync.swift`, this phase only adds a second, independent local
notification path.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
