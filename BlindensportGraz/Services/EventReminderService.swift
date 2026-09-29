import Foundation
import UserNotifications

/// Minimal surface `EventReminderService` needs from a notification center —
/// lets tests substitute a fake instead of touching the real
/// `UNUserNotificationCenter` (which the sandboxed/unsigned test host cannot
/// reliably exercise — same class of constraint that made CloudKit crash
/// under `CODE_SIGNING_ALLOWED=NO`, see cerebrum.md's bug-202 entry; this
/// sidesteps it entirely rather than risking the same failure mode).
protocol NotificationScheduling {
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?)
}

extension UNUserNotificationCenter: NotificationScheduling {}

/// Schedules/cancels local `UNCalendarNotificationTrigger` reminders for
/// Training/Tournament start times. Additive to, and entirely independent
/// of, `PushNotifications.swift`'s `CKQuerySubscription` creation-alerts —
/// those fire once, on creation, never on a schedule before the event
/// actually starts (see that file's doc comment); this is the second,
/// local-only path audit.md's Enhancement #5 asked for. Reuses the
/// `UNUserNotificationCenter` authorization `PushNotifications
/// .requestAuthorizationIfNeeded()` already requests — local and remote
/// notifications share one authorization on iOS, so no separate permission
/// request is needed here.
enum EventReminderService {
    /// Lead time before `startDate` that the reminder fires. Not
    /// user-configurable in this phase (phase-14 spec) — 2 hours is a
    /// reasonable default for both trainings and tournaments.
    static let leadTime: TimeInterval = 2 * 60 * 60

    /// Deterministic per-event identifier so reschedule/cancel always target
    /// exactly one pending request — never a duplicate, never an orphan.
    static func identifier(for eventID: UUID) -> String {
        "event-reminder-\(eventID.uuidString)"
    }

    /// The reminder's fire date, or `nil` if `startDate - leadTime` has
    /// already passed — guards against scheduling an immediate/backdated
    /// notification for an event whose reminder window is already over.
    static func fireDate(for startDate: Date, now: Date = .now) -> Date? {
        let fire = startDate.addingTimeInterval(-leadTime)
        return fire > now ? fire : nil
    }

    /// Builds the notification request for a given event, or `nil` when
    /// `fireDate` returns `nil`. Pure/side-effect-free — this is the seam
    /// tests assert the computed trigger date against.
    static func buildRequest(eventID: UUID, title: String, sportLabel: String,
                              startDate: Date, now: Date = .now) -> UNNotificationRequest? {
        guard let fireDate = fireDate(for: startDate, now: now) else { return nil }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "\(sportLabel) beginnt in 2 Stunden."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier(for: eventID), content: content, trigger: trigger)
    }

    /// Cancels any existing reminder for this event, then schedules a new
    /// one if `startDate` still leaves a future fire date. Call this on
    /// every create AND every update — cancel-then-reschedule is idempotent
    /// and correct for both without needing to know whether the start date
    /// actually changed.
    static func reschedule(eventID: UUID, title: String, sportLabel: String, startDate: Date,
                            now: Date = .now, center: NotificationScheduling = UNUserNotificationCenter.current()) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: eventID)])
        if let request = buildRequest(eventID: eventID, title: title, sportLabel: sportLabel,
                                       startDate: startDate, now: now) {
            center.add(request, withCompletionHandler: nil)
        }
    }

    /// Cancels the reminder for this event, if any. Call on delete.
    static func cancel(eventID: UUID, center: NotificationScheduling = UNUserNotificationCenter.current()) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: eventID)])
    }
}
