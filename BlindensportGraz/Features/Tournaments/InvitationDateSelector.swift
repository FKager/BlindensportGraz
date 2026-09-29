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
        let fullRange = NSRange(text.startIndex..., in: text)
        // Year for dates written without one ("Sa, 14.3."): the year most
        // other dates in the invitation use.
        let documentYear = mostCommonYear(in: text)
        var found: [(start: Date, end: Date, range: Range<String.Index>)] = []

        // 1. System date detection (month names, weekdays, many formats,
        //    ranges). Every result is checked against the text it came from:
        //    its day and month must actually be written there. That drops
        //    times ("9:00 Uhr" comes back as today) and misreadings
        //    ("14. bis Sonntag, 15. März" comes back as 14 November).
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            detector.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match, let date = match.date, let range = Range(match.range, in: text) else { return }
                let written = text[range]
                let start = withDocumentYear(calendar.startOfDay(for: date), written: written, year: documentYear, calendar: calendar)
                let end = withDocumentYear(calendar.startOfDay(for: date.addingTimeInterval(max(0, match.duration))),
                                           written: written, year: documentYear, calendar: calendar)
                let startOK = mentions(start, in: written, calendar: calendar)
                let endOK = end > start && mentions(end, in: written, calendar: calendar)
                switch (startOK, endOK) {
                case (true, true): found.append((start, end, range))
                case (true, false): found.append((start, start, range))
                case (false, true): found.append((end, end, range))
                case (false, false): break
                }
            }
        }

        func addUnlessCovered(_ start: Date, _ end: Date, _ range: Range<String.Index>, replacing: Bool = false) {
            if replacing {
                found.removeAll { $0.range.overlaps(range) }
            } else if found.contains(where: { $0.range.overlaps(range) }) {
                return
            }
            found.append((start, end, range))
        }

        // 2. Day ranges the detector misreads or misses: "14. bis Sonntag,
        //    15. März 2026", "14 und 15 März 2026", "14.–15. Mrz.".
        let rangePattern = #"(?<!\d)(\d{1,2})\.?\s*(?:–|-|bis|und)\s*(?:\p{L}+\.?,?\s*)?(\d{1,2})\.?\s*("#
            + monthNamePattern + #")\.?\s*(\d{4})?"#
        if let regex = try? NSRegularExpression(pattern: rangePattern, options: [.caseInsensitive]) {
            for match in regex.matches(in: text, range: fullRange) {
                guard let range = Range(match.range, in: text),
                      let firstDay = intGroup(match, 1, in: text), let lastDay = intGroup(match, 2, in: text),
                      let monthRange = Range(match.range(at: 3), in: text),
                      let month = monthNumber(text[monthRange]) else { continue }
                let year = intGroup(match, 4, in: text) ?? documentYear ?? calendar.component(.year, from: now)
                guard let start = calendar.date(from: DateComponents(year: year, month: month, day: firstDay)),
                      let end = calendar.date(from: DateComponents(year: year, month: month, day: lastDay)),
                      end >= start else { continue }
                addUnlessCovered(start, end, range, replacing: true)
            }
        }

        // 3. Numeric d.m.yyyy the detector misses without leading zeros ("5.3.2026").
        if let regex = try? NSRegularExpression(pattern: #"(?<![\d.])(\d{1,2})\.(\d{1,2})\.(\d{4})(?!\d)"#) {
            for match in regex.matches(in: text, range: fullRange) {
                guard let range = Range(match.range, in: text),
                      let day = intGroup(match, 1, in: text), let month = intGroup(match, 2, in: text),
                      let year = intGroup(match, 3, in: text),
                      let date = validDate(year: year, month: month, day: day, calendar: calendar) else { continue }
                addUnlessCovered(date, date, range)
            }
        }

        // 4. Year-less d.m. ("Sa, 14.3.") — only next to a weekday or a date
        //    keyword, so section numbers like "3.1." aren't mistaken for dates.
        if let regex = try? NSRegularExpression(pattern: #"(?<![\d.])(\d{1,2})\.(\d{1,2})\.(?!\d)"#) {
            for match in regex.matches(in: text, range: fullRange) {
                guard let range = Range(match.range, in: text),
                      let day = intGroup(match, 1, in: text), let month = intGroup(match, 2, in: text) else { continue }
                let context = lineContaining(range, in: text).text.lowercased()
                guard weekdayNames.contains(where: context.contains)
                        || (positiveKeywords + negativeKeywords).contains(where: context.contains),
                      let date = validDate(year: documentYear ?? calendar.component(.year, from: now),
                                           month: month, day: day, calendar: calendar) else { continue }
                addUnlessCovered(date, date, range)
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

    // MARK: - Date text helpers

    private static let monthAliases: [(month: Int, names: [String])] = [
        (1, ["januar", "jänner", "jan", "january"]), (2, ["februar", "feber", "feb", "february"]),
        (3, ["märz", "mär", "mrz", "march", "mar"]), (4, ["april", "apr"]), (5, ["mai", "may"]),
        (6, ["juni", "jun", "june"]), (7, ["juli", "jul", "july"]), (8, ["august", "aug"]),
        (9, ["september", "sept", "sep"]), (10, ["oktober", "okt", "october", "oct"]),
        (11, ["november", "nov"]), (12, ["dezember", "dez", "december", "dec"])
    ]
    private static let monthNamePattern = monthAliases.flatMap(\.names)
        .sorted { $0.count > $1.count }.joined(separator: "|")
    private static let weekdayNames = [
        "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag",
        "mo.", "di.", "mi.", "do.", "fr.", "sa.", "so.", "mo,", "di,", "mi,", "do,", "fr,", "sa,", "so,"
    ]

    private static func monthNumber(_ name: Substring) -> Int? {
        let lower = name.lowercased()
        return monthAliases.first { $0.names.contains(lower) }?.month
    }

    /// Whether `date`'s day and month are actually written in `text` — the
    /// day as a number, the month as a number after "." / "/" or as a name.
    private static func mentions(_ date: Date, in text: Substring, calendar: Calendar) -> Bool {
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let lower = text.lowercased()
        guard lower.range(of: "(?<!\\d)0?\(day)(?!\\d)", options: .regularExpression) != nil else { return false }
        if lower.range(of: "[./-]\\s*0?\(month)(?!\\d)", options: .regularExpression) != nil { return true }
        let names = monthAliases.first { $0.month == month }?.names ?? []
        return names.contains { lower.range(of: "\\b\($0)", options: .regularExpression) != nil }
    }

    /// Dates written without a year get the invitation's usual year instead
    /// of the detector's guess (the next occurrence after today).
    private static func withDocumentYear(_ date: Date, written: Substring, year: Int?, calendar: Calendar) -> Date {
        guard let year, written.range(of: #"\d{4}|\d{1,2}\.\d{1,2}\.\d{2}(?!\d)"#, options: .regularExpression) == nil else { return date }
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.year = year
        return calendar.date(from: components) ?? date
    }

    /// The four-digit year (20xx) written most often in the text.
    private static func mostCommonYear(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(20\d{2})(?!\d)"#) else { return nil }
        var counts: [Int: Int] = [:]
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let year = intGroup(match, 1, in: text) { counts[year, default: 0] += 1 }
        }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }

    private static func intGroup(_ match: NSTextCheckingResult, _ group: Int, in text: String) -> Int? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }

    /// A date only if day and month are in range (no rolling 31.2. into March).
    private static func validDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: date) == day else { return nil }
        return date
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
