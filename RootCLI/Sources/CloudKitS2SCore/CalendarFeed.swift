import Foundation

/// Server-side generation of one user's read-only calendar feed —
/// architecture-review.md §5 P2 ("webcal subscription feed"). Pure Foundation
/// (no Vapor/CloudKit types) so it's unit-testable independent of the HTTP
/// layer and CloudKit querying; `clubmembersapi`'s `CalendarFeedRoutes.swift`
/// is the only caller — it does the CloudKit fetch and hands this plain data.
///
/// The feed only ever exposes training/tournament schedule data (title,
/// time, venue) the same user could already see in the app — never PII.
/// That's also why the route this feeds is deliberately NOT behind
/// clubmembersapi's Basic Auth: a webcal subscription can't present a
/// username/password prompt in most calendar clients, so each URL's own
/// opaque, unguessable, regenerable token (stored on the UserIdentity
/// CKRecord) is the credential instead — see `Auth.swift`'s
/// `RequireAPIUserExceptCalendarFeed`.
public enum CalendarFeed {
    public struct EventFields {
        public let uid: String
        public let title: String
        public let location: String
        public let startDate: Date
        public let endDate: Date
        /// The event's own `teamIDs` STRING_LIST field — empty means
        /// visible to everyone, matching the app's `SportEvent.teams`
        /// convention exactly.
        public let teamIDs: [String]

        public init(uid: String, title: String, location: String, startDate: Date, endDate: Date, teamIDs: [String]) {
            self.uid = uid
            self.title = title
            self.location = location
            self.startDate = startDate
            self.endDate = endDate
            self.teamIDs = teamIDs
        }
    }

    /// Which of `allEvents` a user may see — mirrors the iOS app's
    /// `NextEventLookup.isVisible`/`TrainingsListView.visibleTrainings`
    /// exactly: an admin sees everything; anyone else sees events with no
    /// team scoping, or scoped to at least one of their own teams.
    public static func visibleEvents(_ allEvents: [EventFields], role: String, userTeamIDs: Set<String>) -> [EventFields] {
        guard role != "admin" else { return allEvents }
        return allEvents.filter { event in
            event.teamIDs.isEmpty || !userTeamIDs.isDisjoint(with: event.teamIDs)
        }
    }

    /// Renders every event as one RFC 5545 `.ics` VCALENDAR, one VEVENT per
    /// event, sorted by start date. Same escaping/UTC-instant convention as
    /// the iOS app's `CalendarEventExport.icsFile` (duplicated here rather
    /// than shared — this SPM target can't import the iOS app target, and
    /// it's a small, stable RFC).
    public static func render(_ events: [EventFields], now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: now)

        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//BlindensportGraz//DE",
            "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:Blindensport Graz",
        ]
        for event in events.sorted(by: { $0.startDate < $1.startDate }) {
            lines += [
                "BEGIN:VEVENT",
                "UID:\(event.uid)",
                "DTSTAMP:\(stamp)",
                "DTSTART:\(formatter.string(from: event.startDate))",
                "DTEND:\(formatter.string(from: event.endDate))",
                "SUMMARY:\(escape(event.title))",
                "LOCATION:\(escape(event.location))",
                "END:VEVENT",
            ]
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 5545 §3.3.11 text escaping — same four characters as
    /// `CalendarEventExport.escape`.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
