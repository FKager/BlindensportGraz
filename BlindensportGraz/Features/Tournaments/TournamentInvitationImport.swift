import Foundation
import PDFKit
import ZIPFoundation
import UniformTypeIdentifiers
import FoundationModels

/// Prefilled values for a new `Tournament`, produced by
/// `TournamentInvitationImporter` from an uploaded invitation file — see
/// `TournamentsViews.swift`'s `TournamentInvitationImportView` ("Turnier aus
/// Einladung erstellen" button on `TournamentsListView`, user request).
/// Plain struct, not a model: only ever used to seed `AddTournamentView`'s
/// `@State` on creation — nothing here is ever saved without the user
/// reviewing/editing the normal form first, same as every other manually
/// created Tournament.
struct TournamentDraft: Identifiable {
    let id = UUID()
    var title: String = ""
    var sport: String = "Torball"
    var location: String = "Graz"
    var street: String = ""
    var zip: String = ""
    var city: String = ""
    var country: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date().addingTimeInterval(86400)
    var maxTeams: Int = 8
    var notes: String = ""
}

enum TournamentInvitationError: LocalizedError {
    case unsupportedFileType
    case couldNotReadFile
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Dieser Dateityp wird nicht unterstützt. Bitte Text, Word (.docx) oder PDF verwenden."
        case .couldNotReadFile:
            return "Die Datei konnte nicht gelesen werden."
        case .emptyDocument:
            return "In der Datei wurde kein Text gefunden."
        }
    }
}

/// Extracts a best-effort `TournamentDraft` from an uploaded invitation
/// document (.txt/.docx/.pdf). Two independent stages:
///
/// 1. **Text extraction** (`extractText`) — format-specific, always runs:
///    plain read for .txt, PDFKit for .pdf, and a minimal tag-stripping walk
///    over `word/document.xml` for .docx (via ZIPFoundation — the same
///    zip-reading dependency/pattern this codebase already uses for .xlsx
///    template patching, see KostZExport/PraeExport's `Archive(url:
///    accessMode:)` + `extract(entry:)` usage).
/// 2. **Field extraction** (`draft(fromText:)`) — tries Apple Intelligence
///    (iOS 26's on-device Foundation Models framework, `@Generable`/
///    `LanguageModelSession`) first, but ONLY when `SystemLanguageModel`
///    reports `.available` on this specific device (Apple Intelligence is
///    hardware-gated — plenty of club members' phones won't have it, or
///    won't have the toggle on). Any device without that, or any failure
///    from the model itself, falls through to a fully deterministic
///    `NSDataDetector` (dates, addresses) + keyword-matching (against
///    `Sport.knownRawValues`) heuristic — no network, works identically on
///    every iOS 26 device. Whichever path runs, the result is ALWAYS just a
///    starting point: `AddTournamentView` opens with every field still
///    editable, nothing is saved until the user reviews and taps
///    "Speichern", same as manually creating a tournament.
enum TournamentInvitationImporter {
    static let supportedContentTypes: [UTType] = [
        .plainText,
        .pdf,
        UTType(filenameExtension: "docx") ?? .data
    ]

    static func draft(fromFileAt url: URL) async throws -> TournamentDraft {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let text = try extractText(from: url)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TournamentInvitationError.emptyDocument
        }
        return await draft(fromText: text)
    }

    // MARK: - Text extraction

    static func extractText(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "txt":
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
            if let text = try? String(contentsOf: url, encoding: .isoLatin1) { return text }
            throw TournamentInvitationError.couldNotReadFile
        case "pdf":
            return try extractPDFText(from: url)
        case "docx":
            return try extractDocxText(from: url)
        default:
            throw TournamentInvitationError.unsupportedFileType
        }
    }

    private static func extractPDFText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw TournamentInvitationError.couldNotReadFile
        }
        var text = ""
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text
    }

    private static func extractDocxText(from url: URL) throws -> String {
        guard let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil),
              let entry = archive["word/document.xml"] else {
            throw TournamentInvitationError.couldNotReadFile
        }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        guard let xml = String(data: data, encoding: .utf8) else {
            throw TournamentInvitationError.couldNotReadFile
        }
        return plainText(fromDocumentXML: xml)
    }

    /// Word's `document.xml` only ever carries visible text inside `<w:t>`
    /// runs — every other element (styling, run/paragraph properties, table
    /// grid structure) holds no freeform text of its own. So: turn the XML's
    /// paragraph/line/tab markers into real whitespace first, then strip
    /// every remaining tag — what's left is exactly the document's visible
    /// text, no per-tag special-casing or a full XML parser needed. Matches
    /// this codebase's existing "minimal string-level XML handling"
    /// convention for template files (see KostZExport/PraeExport).
    private static func plainText(fromDocumentXML xml: String) -> String {
        var normalized = xml
            .replacingOccurrences(of: "</w:p>", with: "\n")
            .replacingOccurrences(of: "<w:tab/>", with: "\t")
            .replacingOccurrences(of: "<w:br/>", with: "\n")
            .replacingOccurrences(of: "<w:br />", with: "\n")

        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, range: range, withTemplate: "")
        }

        return normalized
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    // MARK: - Field extraction

    static func draft(fromText text: String) async -> TournamentDraft {
        if let aiDraft = await appleIntelligenceDraft(fromText: text) {
            return aiDraft
        }
        return heuristicDraft(fromText: text)
    }

    // MARK: Apple Intelligence path

    @Generable
    fileprivate struct InvitationExtraction {
        @Guide(description: "The tournament's name/title, without any 'Einladung zum/zur' prefix. Empty string if unclear.")
        var title: String
        @Guide(description: "The sport, e.g. Torball, Goalball, Blindenfußball, Showdown. Empty string if not mentioned — never guess.")
        var sport: String
        @Guide(description: "Venue/hall name, e.g. 'Sporthalle Eggenberg'. Empty string if not mentioned.")
        var location: String
        @Guide(description: "Street and house number of the venue's postal address. Empty string if not mentioned.")
        var street: String
        @Guide(description: "Postal code of the venue's postal address. Empty string if not mentioned.")
        var zip: String
        @Guide(description: "City of the venue's postal address. Empty string if not mentioned.")
        var city: String
        @Guide(description: "Country of the venue's postal address. Empty string if not mentioned — never guess.")
        var country: String
        @Guide(description: "Start date, ISO 8601 format YYYY-MM-DD. Empty string if not mentioned.")
        var startDate: String
        @Guide(description: "End date, ISO 8601 format YYYY-MM-DD — same as start date for a single-day tournament. Empty string if not mentioned.")
        var endDate: String
        @Guide(description: "Maximum number of participating teams, only if explicitly stated in the text, otherwise 0.")
        var maxTeams: Int
    }

    private static func appleIntelligenceDraft(fromText text: String) async -> TournamentDraft? {
        guard SystemLanguageModel.default.availability == .available else { return nil }
        let session = LanguageModelSession(instructions: """
            Extrahiere Turnier-Informationen aus dieser Einladung für ein Blindensport-Turnier. \
            Antworte nur mit den angeforderten Feldern. Erfinde keine Angaben, die im Text nicht \
            vorkommen — lasse ein Feld leer (bzw. bei maxTeams 0), wenn es unklar ist.
            """)
        do {
            let response = try await session.respond(to: text, generating: InvitationExtraction.self)
            let content = response.content
            var draft = TournamentDraft()
            if !content.title.isEmpty { draft.title = content.title }
            if !content.sport.isEmpty { draft.sport = Sport.normalize(content.sport).rawValue }
            if !content.location.isEmpty { draft.location = content.location }
            draft.street = content.street
            draft.zip = content.zip
            draft.city = content.city
            if !content.country.isEmpty { draft.country = content.country }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let start = formatter.date(from: content.startDate)
            let end = formatter.date(from: content.endDate)
            if let start {
                draft.startDate = start
                draft.endDate = end ?? start
            }
            if content.maxTeams > 0 { draft.maxTeams = content.maxTeams }
            return draft
        } catch {
            return nil
        }
    }

    // MARK: Deterministic fallback

    private static func heuristicDraft(fromText text: String) -> TournamentDraft {
        var draft = TournamentDraft()

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let invitationLine = lines.first(where: { $0.range(of: "einladung", options: .caseInsensitive) != nil }) {
            draft.title = title(fromInvitationLine: invitationLine)
        } else if let tournamentLine = lines.first(where: { $0.range(of: "turnier", options: .caseInsensitive) != nil }) {
            draft.title = tournamentLine
        } else if let first = lines.first {
            draft.title = first
        }

        if let matchedSport = Sport.knownRawValues.first(where: {
            text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }) {
            draft.sport = matchedSport
        }

        // Dates + venue address, both via NSDataDetector — deterministic, no
        // network, available on every iOS version (unlike the AI path above).
        let detectorTypes: NSTextCheckingResult.CheckingType = [.date, .address]
        if let detector = try? NSDataDetector(types: detectorTypes.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            var foundDates: [Date] = []
            detector.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else { return }
                if let date = match.date {
                    foundDates.append(date)
                    if match.duration > 0 {
                        foundDates.append(date.addingTimeInterval(match.duration))
                    }
                }
                if let components = match.addressComponents {
                    if let street = components[.street], draft.street.isEmpty { draft.street = street }
                    if let city = components[.city], draft.city.isEmpty { draft.city = city }
                    if let zip = components[.zip], draft.zip.isEmpty { draft.zip = zip }
                    if let country = components[.country], draft.country.isEmpty { draft.country = country }
                }
            }
            if let earliest = foundDates.min() {
                draft.startDate = earliest
                draft.endDate = foundDates.max() ?? earliest
            }
        }

        if let regex = try? NSRegularExpression(pattern: "(\\d{1,3})\\s*(Teams|Mannschaften|Vereinen|Vereine)", options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let numberRange = Range(match.range(at: 1), in: text),
           let number = Int(text[numberRange]) {
            draft.maxTeams = number
        }

        return draft
    }

    private static func title(fromInvitationLine line: String) -> String {
        var result = line
        for prefix in ["Einladung zum ", "Einladung zur ", "Einladung: ", "Einladung "] {
            if let range = result.range(of: prefix, options: [.caseInsensitive]) {
                result.removeSubrange(result.startIndex..<range.upperBound)
                break
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
