import Foundation
import ZIPFoundation

/// One row of the exported TeilnehmerInnenliste.
struct TeilnehmerlisteEntry {
    let name: String
    let wohnort: String
    let tage: Int
}

/// Everything needed to fill out the official Sport Austria
/// "TeilnehmerInnenliste (TN)" template for one Training or Tournament.
/// `attendedMemberships` should already be filtered down to attendance == true.
struct TeilnehmerlisteContext {
    let betrifft: String
    let ort: String
    let startDate: Date
    let endDate: Date
    let attendedMemberships: [TeamMembership]
    // Base name for the exported .xlsx (UUID + extension appended by the
    // exporter) — TournamentDetailView.swift sets "TN-Sportler"/"TN-Helfer" for
    // its two role-split exports; defaults to the old generic name for any
    // other caller (there are none currently, but this keeps existing test
    // fixtures/callers compiling without change).
    var fileNamePrefix: String = "TeilnehmerInnenliste"
}

enum TeilnehmerlisteExportError: LocalizedError {
    case templateNotFound
    case invalidTemplateEncoding

    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return "Die Formularvorlage (TN_TeilnehmerInnenliste.xlsx) wurde nicht gefunden."
        case .invalidTemplateEncoding:
            return "Die Formularvorlage konnte nicht gelesen werden."
        }
    }
}

/// Fills the official Sport Austria "TeilnehmerInnenliste (TN)" Excel template
/// (bundled as TN_TeilnehmerInnenliste.xlsx — the club's 15-row variant of the
/// form originally downloaded from sportaustria.at)
/// with a specific event's attendees. An .xlsx is just a zip of XML, so this
/// works by unzipping the bundled template, patching the known blank cell
/// coordinates in xl/worksheets/sheet1.xml with real values, and rezipping —
/// every other file in the archive (styles, images, the GDPR footer text) is
/// copied through byte-for-byte, unchanged.
enum TeilnehmerlisteExporter {
    /// The template has exactly 15 pre-numbered rows (lfd. Nr. 1–15, sheet rows
    /// 10–24) — a hard limit of the form layout, not something we can extend
    /// without breaking the row-numbering/merge layout.
    static let maxRows = 15

    static func export(context: TeilnehmerlisteContext) throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: "TN_TeilnehmerInnenliste", withExtension: "xlsx") else {
            throw TeilnehmerlisteExportError.templateNotFound
        }

        let sourceArchive = try Archive(url: templateURL, accessMode: .read)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(context.fileNamePrefix)-\(UUID().uuidString).xlsx")
        let outputArchive = try Archive(url: outputURL, accessMode: .create)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"

        let entries = self.entries(from: context)

        for entry in sourceArchive {
            var data = Data()
            _ = try sourceArchive.extract(entry) { data.append($0) }

            if entry.path == "xl/worksheets/sheet1.xml" {
                guard let xml = String(data: data, encoding: .utf8) else {
                    throw TeilnehmerlisteExportError.invalidTemplateEncoding
                }
                let patched = patch(xml: xml, context: context, entries: entries, dateFormatter: dateFormatter)
                data = Data(patched.utf8)
            }

            // .none (stored, uncompressed) rather than .deflate — a defensive
            // simplification to avoid depending on ZIPFoundation's compression
            // write path at all. (A specific theory that .deflate caused a
            // real hang here was investigated and disproven by direct testing
            // — see .wolf/cerebrum.md 2026-07-18 — but stored is just as
            // correct and simpler for a form template this small, so it stays.)
            try outputArchive.addEntry(
                with: entry.path,
                type: entry.type,
                uncompressedSize: Int64(data.count),
                compressionMethod: .none
            ) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }

        return outputURL
    }

    /// Everyone marked present at `event`, once per person (an app account
    /// or a roster entry), by last name — from the event's attendance rows,
    /// so someone who attended through a second team's membership, or was
    /// added to the event directly, is listed too. Two memberships of one
    /// person: the first attendance row by id decides (the web UI reads them
    /// in id order). Same rule as Teilnehmerliste.forTournament in the web UI.
    static func attendedMemberships(of event: SportEvent) -> [TeamMembership] {
        var seen = Set<UUID>()
        var result: [TeamMembership] = []
        let rows = event.attendances.filter(\.attended)
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        for attendance in rows {
            let membership = attendance.membership
            if seen.insert(membership.user?.id ?? membership.member?.id ?? membership.id).inserted {
                result.append(membership)
            }
        }
        return result.sortedByLastName()
    }

    /// Players go on the Sportler list: role `.player` only, NOT "not a
    /// helper". A role this app doesn't know (e.g. "Trainer" typed into an
    /// imported spreadsheet) becomes `.other`, which must stay off the
    /// Sportler list; `!isHelfer` would let it in (audit.md Architecture
    /// Finding 3).
    static func sportler(of event: SportEvent) -> [TeamMembership] {
        attendedMemberships(of: event).filter { $0.role == .player }
    }

    /// Coaches and assistants go on the Helfer list.
    static func helfer(of event: SportEvent) -> [TeamMembership] {
        attendedMemberships(of: event).filter { $0.role.isHelfer }
    }

    /// One row per attended membership. Every attendee gets the same TAGE
    /// (day count) since attendance here is a single yes/no per event, not
    /// tracked per individual day within a multi-day tournament.
    static func entries(from context: TeilnehmerlisteContext) -> [TeilnehmerlisteEntry] {
        let dayCount = self.dayCount(from: context.startDate, to: context.endDate)
        return context.attendedMemberships.map { membership in
            TeilnehmerlisteEntry(
                name: formattedName(for: membership),
                wohnort: membership.member?.city ?? "",
                tage: dayCount
            )
        }
    }

    private static func formattedName(for membership: TeamMembership) -> String {
        // Column header is "FAMILIEN- und VORNAME" (family name first) — only
        // Member has separate first/last name fields to format that way;
        // a registered User only has a single displayName.
        if let member = membership.member {
            return "\(member.lastName) \(member.firstName)"
        }
        return membership.displayName
    }

    private static func dayCount(from startDate: Date, to endDate: Date) -> Int {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, days + 1)
    }

    private static func patch(xml: String, context: TeilnehmerlisteContext, entries: [TeilnehmerlisteEntry],
                               dateFormatter: DateFormatter) -> String {
        var result = xml
        result = setText(in: result, ref: "C3", value: context.betrifft)
        result = setText(in: result, ref: "H3", value: context.ort)
        result = setText(in: result, ref: "D5", value: dateFormatter.string(from: context.startDate))
        result = setText(in: result, ref: "F5", value: dateFormatter.string(from: context.endDate))
        result = setNumber(in: result, ref: "H5", value: dayCount(from: context.startDate, to: context.endDate))
        result = setNumber(in: result, ref: "D7", value: entries.count)

        for (index, entry) in entries.prefix(maxRows).enumerated() {
            let row = 10 + index
            result = setText(in: result, ref: "B\(row)", value: entry.name)
            if !entry.wohnort.isEmpty {
                result = setText(in: result, ref: "D\(row)", value: entry.wohnort)
            }
            result = setNumber(in: result, ref: "F\(row)", value: entry.tage)
        }

        return result
    }

    /// Every target cell is a self-closing blank in the pristine template
    /// (`<c r="C3" s="65"/>`) — this rewrites it into a valued cell while
    /// preserving whatever style attributes (`s="N"`) it already carried.
    private static func replaceCell(in xml: String, ref: String, build: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<c r=\"\(ref)\"([^>]*)/>"),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let attrsRange = Range(match.range(at: 1), in: xml),
              let fullRange = Range(match.range, in: xml) else { return xml }
        let attrs = String(xml[attrsRange])
        return xml.replacingCharacters(in: fullRange, with: build(attrs))
    }

    private static func setText(in xml: String, ref: String, value: String) -> String {
        replaceCell(in: xml, ref: ref) { attrs in
            "<c r=\"\(ref)\"\(attrs) t=\"inlineStr\"><is><t>\(XMLText.escape(value))</t></is></c>"
        }
    }

    private static func setNumber(in xml: String, ref: String, value: Int) -> String {
        replaceCell(in: xml, ref: ref) { attrs in
            "<c r=\"\(ref)\"\(attrs)><v>\(value)</v></c>"
        }
    }
}
