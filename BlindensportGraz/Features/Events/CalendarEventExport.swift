import Foundation

/// Maps a Training/Tournament (any `SportEvent`) to calendar-event fields
/// and renders them as an RFC 5545 `.ics` file — audit.md Enhancement #9.
///
/// **Approach: `.ics` file + `ShareLink`, not `EKEventStore`.** This app's
/// primary usage mode is VoiceOver (see cerebrum.md's standing User
/// Preferences entry), and its own history has repeatedly hit VoiceOver
/// freezes from custom `UIViewControllerRepresentable` modal wrappers (see
/// the 2026-07-18 entries — `MemberListView`'s export flow was rewritten
/// from a hand-rolled `UIActivityViewController` wrapper to native
/// `ShareLink` specifically to fix that). `EKEventStore`'s "Add to Calendar"
/// flow needs its own permission-prompt + a `EKEventEditViewController`
/// (another `UIViewControllerRepresentable` wrapper) with no track record in
/// this app — `.ics`+`ShareLink` reuses the exact mechanism already proven
/// to work under VoiceOver here (`ShareLink(item: url)`, eagerly generated
/// via `.task`, same as every other export screen), needs no permission
/// prompt at all, and lets the OS's own Calendar app (or any other calendar
/// app installed) handle the actual import UI — which is itself a
/// first-party, accessibility-audited flow this app doesn't have to get
/// right itself.
///
/// **Stale-entry-on-edit: add-on-demand-only, by design, not update-existing.**
/// Sharing the `.ics` file hands a snapshot to whatever calendar app the
/// user chooses; this app has no way to reach into that calendar app's
/// store afterward (no `EKEventStore` link is ever created), so it cannot
/// update or delete that copy if the Training/Tournament is later edited or
/// deleted — same as any calendar invite from any app. This is the
/// simplest, safest default (no persistent identifier to track, no
/// silent-failure surface if a later push fails) and matches this app's
/// existing "don't invent a delete/update path that isn't there" scoping
/// (see SportEventService.swift's doc comment for the same reasoning
/// applied to CloudKit). If a user reschedules a Training/Tournament after
/// already adding it to their calendar, they re-tap "Zum Kalender
/// hinzufügen" and get an updated `.ics` to re-import — no different from
/// re-sharing any other export in this app.
enum CalendarEventExport {
    struct EventFields: Equatable {
        let title: String
        let location: String
        let startDate: Date
        let endDate: Date
    }

    /// Pure mapping, no file I/O — this is the seam tests assert against
    /// independent of `.ics` rendering (phase-17 spec).
    static func fields(for event: SportEvent) -> EventFields {
        EventFields(title: event.title, location: fullLocation(for: event),
                    startDate: event.startDate, endDate: event.endDate)
    }

    /// Venue name (`event.location`) plus street/zip+city/country, comma
    /// separated, skipping any empty part — same address fields
    /// AddEventView/AddTrainingView/AddTournamentView already collect.
    private static func fullLocation(for event: SportEvent) -> String {
        let cityLine = [event.zip, event.city].filter { !$0.isEmpty }.joined(separator: " ")
        return [event.location, event.street, cityLine, event.country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Renders one `VEVENT` `.ics` file for the given fields. `DTSTART`/
    /// `DTEND`/`DTSTAMP` are UTC (`Z` suffix) — the app stores `Date`
    /// (already timezone-agnostic instants), so this avoids embedding a
    /// `VTIMEZONE` block just to express a single fixed instant.
    static func icsFile(for fields: EventFields, uid: String = UUID().uuidString) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let ics = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        PRODID:-//BlindensportGraz//DE\r
        BEGIN:VEVENT\r
        UID:\(uid)\r
        DTSTAMP:\(formatter.string(from: .now))\r
        DTSTART:\(formatter.string(from: fields.startDate))\r
        DTEND:\(formatter.string(from: fields.endDate))\r
        SUMMARY:\(escape(fields.title))\r
        LOCATION:\(escape(fields.location))\r
        END:VEVENT\r
        END:VCALENDAR\r
        """

        let safeName = fields.title.isEmpty ? "Termin" : fields.title
            .replacingOccurrences(of: "/", with: "-")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-\(uid).ics")
        try ics.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    /// RFC 5545 §3.3.11 text escaping — backslash, comma, semicolon, and
    /// newline are structurally significant in .ics text values.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
