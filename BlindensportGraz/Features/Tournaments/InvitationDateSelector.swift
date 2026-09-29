import Foundation

/// Picks the tournament's own dates out of an invitation that mentions many
/// dates — the letter date ("Graz, 12. Jänner 2026"), registration and
/// payment deadlines, arrival/hotel dates, and the actual playing days.
///
/// Every date in the text becomes a candidate, scored by the words on its
/// line: "Termin", "Turnier", "Spieltag", "findet … statt" count for it;
/// "Anmeldeschluss", "Frist", "Zahlung", "Anreise", "Hotel" count against
/// it, as do the letter date and dates already in the past. Date ranges
/// ("14.–15. März", "Samstag … bis Sonntag …") get a small bonus, since
/// most tournaments span a weekend. The best-scoring candidate wins; ties
/// go to the range, then to the earlier date.
///
/// If the invitation names an arrival day ("Anreise am 13.03.2026") shortly
/// before the first playing day, the tournament starts on the arrival day
/// (user decision 2026-09-29) — see `arrivalDate(in:before:)`.
///
/// Used by the deterministic fallback directly, and to overrule the Apple
/// Intelligence result when the model picked a deadline or letter date.
nonisolated enum InvitationDateSelector {
    struct Candidate: Equatable {
        let start: Date
        let end: Date
        let score: Int
        /// On an "Anreise"/"Ankunft" line that isn't a deadline.
        let isArrival: Bool

        /// Deadline, letter date or past date — never the tournament itself.
        /// (An arrival day is a valid start, so it's never rejected.)
        var isRejected: Bool { score < 0 && !isArrival }
    }

    /// An arrival day counts only if it's at most this many days before the
    /// first playing day — "Anreise bis 1. März mitteilen" isn't one.
    private static let maxArrivalLeadDays = 7
    private static let arrivalKeywords = ["anreise", "ankunft"]
    /// Words that make an "Anreise" line a deadline rather than the arrival.
    private static let arrivalDeadlineKeywords = ["spätestens", "mitteil", "bekannt", "meld", "frist"]

    private static let positiveKeywords = [
        "turnier", "termin", "spieltag", "spielbeginn", "spielzeit", "austragung",
        "findet", "statt", "veranstaltung", "wettkampf", "zeitraum", "wann", "datum"
    ]
    private static let negativeKeywords = [
        "anmeld", "meldeschluss", "nennschluss", "nennung", "einsendeschluss", "deadline",
        "frist", "spätestens", "zahlung", "überweis", "einzahl", "rückmeld", "storn",
        "bestätig", "anreise", "ankunft", "abreise", "check-in", "hotel", "zimmer", "buchung", "unterkunft"
    ]

    /// The tournament's start and end day, or nil if the text has no usable
    /// date. Starts on the arrival day when one is given.
    static func eventDates(in text: String, now: Date = .now, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let all = candidates(in: text, now: now, calendar: calendar)
        // The playing days: arrival lines are scored down, so they only win
        // when there's nothing better.
        guard let best = all.max(by: isWorse) else { return nil }
        let arrival = arrivalDate(among: all, before: best.start, calendar: calendar)
        return (arrival ?? best.start, best.end)
    }

    /// The arrival day for a tournament whose first playing day is
    /// `eventStart`, if the text names one within `maxArrivalLeadDays` before it.
    static func arrivalDate(in text: String, before eventStart: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        arrivalDate(among: candidates(in: text, now: now, calendar: calendar), before: eventStart, calendar: calendar)
    }

    private static func arrivalDate(among candidates: [Candidate], before eventStart: Date, calendar: Calendar) -> Date? {
        let eventDay = calendar.startOfDay(for: eventStart)
        guard let earliestAllowed = calendar.date(byAdding: .day, value: -maxArrivalLeadDays, to: eventDay) else { return nil }
        return candidates
            .filter { $0.isArrival && $0.start < eventDay && $0.start >= earliestAllowed }
            .map(\.start)
            .max()
    }

    /// All dates found in the text, scored. Exposed for checking the AI result.
    static func candidates(in text: String, now: Date = .now, calendar: Calendar = .current) -> [Candidate] {
        let text = normalizedMonthNames(text)
        let today = calendar.startOfDay(for: now)
        var found: [(start: Date, end: Date, range: Range<String.Index>)] = []

        // 1. System date detection (handles month names, weekdays, ranges).
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            detector.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
                guard let match, let date = match.date, let range = Range(match.range, in: text),
                      containsDayAndMonth(text[range]) else { return }   // skip "9:00 Uhr" etc.
                let start = calendar.startOfDay(for: date)
                let end = calendar.startOfDay(for: date.addingTimeInterval(max(0, match.duration)))
                found.append((start, end, range))
            }
        }

        // 2. Numeric d.m.yyyy the detector misses without leading zeros ("5.3.2026").
        if let regex = try? NSRegularExpression(pattern: #"(?<![\d.])(\d{1,2})\.(\d{1,2})\.(\d{4})(?!\d)"#) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text),
                      !found.contains(where: { $0.range.overlaps(range) }),
                      let day = Int(text[Range(match.range(at: 1), in: text)!]),
                      let month = Int(text[Range(match.range(at: 2), in: text)!]),
                      let year = Int(text[Range(match.range(at: 3), in: text)!]),
                      let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
                found.append((date, date, range))
            }
        }

        return found.map { item in
            let line = lineContaining(item.range, in: text)
            var score = 0
            let context = line.text.lowercased()
            if positiveKeywords.contains(where: context.contains) { score += 3 }
            if negativeKeywords.contains(where: context.contains) { score -= 6 }
            if isLetterDate(line: line, dateRange: item.range, in: text) { score -= 6 }
            if item.start < today { score -= 4 }
            if item.end > item.start { score += 2 }
            let isArrival = arrivalKeywords.contains(where: context.contains)
                && !arrivalDeadlineKeywords.contains(where: context.contains)
            return Candidate(start: item.start, end: item.end, score: score, isArrival: isArrival)
        }
    }

    /// Ordering for `max(by:)`: higher score, then a range, then the earlier date.
    private static func isWorse(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.score != rhs.score { return lhs.score < rhs.score }
        let lhsRange = lhs.end > lhs.start, rhsRange = rhs.end > rhs.start
        if lhsRange != rhsRange { return !lhsRange }
        return lhs.start > rhs.start
    }

    /// A real calendar date needs a day and a month — rejects bare times and weekdays.
    private static func containsDayAndMonth(_ text: Substring) -> Bool {
        text.range(of: #"\d{1,2}\.\s*(\d{1,2}\.|[A-Za-zÄäÖöÜü]{3,})|\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
    }

    /// Austrian month names the date detector doesn't know.
    private static func normalizedMonthNames(_ text: String) -> String {
        text.replacingOccurrences(of: #"\bJänner\b"#, with: "Januar", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bJän\.\s"#, with: "Jan. ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bFeber\b"#, with: "Februar", options: [.regularExpression, .caseInsensitive])
    }

    /// The line around a match, plus the previous line when the date stands
    /// alone on its line (e.g. "Termin:" on one line, the date on the next).
    private static func lineContaining(_ range: Range<String.Index>, in text: String) -> (text: String, range: Range<String.Index>) {
        let lineRange = text.lineRange(for: range)
        var context = String(text[lineRange])
        let beforeDate = text[lineRange.lowerBound..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        if beforeDate.isEmpty, lineRange.lowerBound > text.startIndex {
            let previous = text.lineRange(for: text.index(before: lineRange.lowerBound)..<lineRange.lowerBound)
            context = String(text[previous]) + context
        }
        return (context, lineRange)
    }

    /// "Graz, 12. Januar 2026" — a place, a comma, the date, nothing after.
    private static func isLetterDate(line: (text: String, range: Range<String.Index>), dateRange: Range<String.Index>, in text: String) -> Bool {
        let before = text[line.range.lowerBound..<dateRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let after = text[dateRange.upperBound..<line.range.upperBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard after.isEmpty || after == "." else { return false }
        return before.range(of: #"^[A-ZÄÖÜ][\p{L} .\-]{1,40},$"#, options: .regularExpression) != nil
    }
}
