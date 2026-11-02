import Foundation
import ZIPFoundation

/// Everything the GVSC Beitrittserklärung asks for, as plain values (so the
/// filling logic is testable without SwiftData).
nonisolated struct GVSCApplicationData {
    struct Guardian {
        var firstName = ""
        var lastName = ""
        var street = ""
        var zip = ""
        var city = ""
        var phone = ""
        var mobile = ""
        var email = ""
    }

    var membershipType = ""
    var gender = ""
    var title = ""
    var firstName = ""
    var lastName = ""
    var street = ""
    var zip = ""
    var city = ""
    var svnr = ""
    var birthDate: Date?
    var citizenship = ""
    var phone = ""
    var mobile = ""
    var email = ""
    var iban = ""
    var sports: [String] = []
    var disabilityType = ""
    var disabilityClass = ""
    var disabilityCause = ""
    var consentDataTransfer: Bool?
    var consentPhotos: Bool?
    /// Only filled for minors (or when guardian data was entered anyway).
    var guardian: Guardian?
}

nonisolated extension GVSCApplicationData {
    @MainActor
    init(member: Member) {
        self.init(membershipType: member.membershipType, gender: member.gender, title: member.title,
                  firstName: member.firstName, lastName: member.lastName, street: member.street,
                  zip: member.zip, city: member.city, svnr: member.svnr, birthDate: member.birthDate,
                  citizenship: member.citizenship, phone: member.phone, mobile: member.mobile,
                  email: member.email, iban: member.iban,
                  sports: Array(Set(member.teamMemberships.map(\.team.sport)
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty })).sorted(),
                  disabilityType: member.disabilityType, disabilityClass: member.disabilityClass,
                  disabilityCause: member.disabilityCause,
                  consentDataTransfer: member.consentDataTransfer, consentPhotos: member.consentPhotos)
        let guardian = Guardian(firstName: member.guardianFirstName, lastName: member.guardianLastName,
                                street: member.guardianStreet, zip: member.guardianZip, city: member.guardianCity,
                                phone: member.guardianPhone, mobile: member.guardianMobile,
                                email: member.guardianEmail)
        let hasGuardian = !(guardian.firstName + guardian.lastName + guardian.street + guardian.zip
                            + guardian.city + guardian.phone + guardian.mobile + guardian.email).isEmpty
        if member.isMinor() || hasGuardian { self.guardian = guardian }
    }
}

nonisolated extension GVSCApplicationData {
    /// A member's own pending proposal (MyMemberView) — what they just
    /// entered, before an admin approved it. Sports still come from the
    /// roster entry's teams.
    @MainActor
    init(request: MemberChangeRequest, member: Member) {
        self.init(member: member)
        membershipType = request.membershipType
        gender = request.gender
        title = request.title
        firstName = request.firstName
        lastName = request.lastName
        street = request.street
        zip = request.zip
        city = request.city
        svnr = request.svnr
        birthDate = request.birthDate
        citizenship = request.citizenship
        phone = request.phone
        mobile = request.mobile
        email = request.email
        iban = request.iban
        disabilityType = request.disabilityType
        disabilityClass = request.disabilityClass
        disabilityCause = request.disabilityCause
        consentDataTransfer = request.consentDataTransfer
        consentPhotos = request.consentPhotos
        let guardian = Guardian(firstName: request.guardianFirstName, lastName: request.guardianLastName,
                                street: request.guardianStreet, zip: request.guardianZip, city: request.guardianCity,
                                phone: request.guardianPhone, mobile: request.guardianMobile,
                                email: request.guardianEmail)
        let hasGuardian = !(guardian.firstName + guardian.lastName + guardian.street + guardian.zip
                            + guardian.city + guardian.phone + guardian.mobile + guardian.email).isEmpty
        self.guardian = request.isMinor() || hasGuardian ? guardian : nil
    }

    /// Form fields still empty — shown as a checklist before sending (not
    /// blocking: the club can complete the paper form).
    var missingFields: [String] {
        var missing: [String] = []
        func check(_ value: String, _ label: String) {
            if value.trimmingCharacters(in: .whitespaces).isEmpty { missing.append(label) }
        }
        check(membershipType, String(localized: "Mitgliedsart (aktiv/fördernd)"))
        check(gender, String(localized: "Geschlecht"))
        check(firstName + lastName, String(localized: "Name"))
        check(street, String(localized: "Straße"))
        check(zip + city, String(localized: "PLZ, Wohnort"))
        check(svnr, String(localized: "SVNR"))
        if birthDate == nil { missing.append(String(localized: "Geburtsdatum")) }
        check(citizenship, String(localized: "Staatsbürgerschaft"))
        check(phone + mobile, String(localized: "Telefon oder Mobilnummer"))
        check(email, String(localized: "E-Mail"))
        check(disabilityType, String(localized: "Art der Behinderung"))
        if consentDataTransfer == nil { missing.append(String(localized: "Einwilligung Datenweitergabe")) }
        if consentPhotos == nil { missing.append(String(localized: "Einwilligung Foto/Video")) }
        if let guardian, (guardian.firstName + guardian.lastName).isEmpty {
            missing.append(String(localized: "Gesetzliche:r Vertreter:in"))
        }
        return missing
    }
}

enum GVSCApplicationDocumentError: LocalizedError {
    case templateNotFound
    case invalidTemplate

    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return String(localized: "Die Vorlage der Beitrittserklärung wurde nicht gefunden.")
        case .invalidTemplate:
            return String(localized: "Die Vorlage der Beitrittserklärung konnte nicht gelesen werden.")
        }
    }
}

/// Fills the club's Word form (bundled as GVSC_Beitrittserklaerung.docx).
/// Like the .xlsx reports, the .docx is unzipped, only word/document.xml is
/// patched, and every other entry is copied through unchanged.
///
/// The form is plain paragraphs "Label: <spaces or sample text>" in a table.
/// Each field paragraph is rebuilt as label + tab (Word's default stops keep
/// long values inside the cell) + value in the label's own font, which
/// also clears the sample values the template ships with. Labels that occur
/// twice (member, then guardian) are matched in document order. JA/NEIN
/// choices are lines "O  JA" / "O  NEIN"; the chosen "O" becomes "X".
nonisolated enum GVSCApplicationDocument {
    /// Always "Blindensport" (user decision; not stored per member).
    static let section = "Blindensport"

    static func makeDocx(_ data: GVSCApplicationData) throws -> Data {
        guard let templateURL = Bundle.main.url(forResource: "GVSC_Beitrittserklaerung", withExtension: "docx") else {
            throw GVSCApplicationDocumentError.templateNotFound
        }
        let source = try Archive(url: templateURL, accessMode: .read)
        let output = try Archive(data: Data(), accessMode: .create)
        for entry in source {
            var content = Data()
            _ = try source.extract(entry) { content.append($0) }
            if entry.path == "word/document.xml" {
                guard let xml = String(data: content, encoding: .utf8) else {
                    throw GVSCApplicationDocumentError.invalidTemplate
                }
                content = Data(fill(documentXML: xml, with: data).utf8)
            }
            try output.addEntry(with: entry.path, type: entry.type, uncompressedSize: Int64(content.count),
                                compressionMethod: .deflate) { position, size in
                content.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        guard let result = output.data else { throw GVSCApplicationDocumentError.invalidTemplate }
        return result
    }

    /// Mail/preview file name, e.g. "Beitrittserklaerung_Mueller_Joerg.docx".
    static func fileName(for data: GVSCApplicationData) -> String {
        let name = asciiFileName("\(data.lastName)_\(data.firstName)")
        return "Beitrittserklaerung_\(name.isEmpty ? "Mitglied" : name).docx"
    }

    // MARK: - Filling

    private enum Step {
        /// Rebuild the next paragraph starting with `label`. An empty value
        /// leaves only the label, unless `keepBlankLine` (IBAN's write-in line).
        case field(label: String, value: String, keepBlankLine: Bool = false)
        /// Mark the next "O JA" / "O NEIN" line when `checked`.
        case choice(answer: String, checked: Bool)
    }

    static func fill(documentXML xml: String, with data: GVSCApplicationData) -> String {
        var xml = xml
        var offset = 0
        for step in steps(for: data) {
            guard let (range, paragraph) = nextParagraph(in: xml, fromOffset: offset, matching: matcher(for: step)) else {
                continue
            }
            let replacement = rebuild(paragraph, for: step)
            let start = xml.distance(from: xml.startIndex, to: range.lowerBound)
            xml.replaceSubrange(range, with: replacement)
            offset = start + replacement.count
        }
        return xml
    }

    private static func steps(for data: GVSCApplicationData) -> [Step] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let membershipType: String
        switch data.membershipType {
        case GVSCMembershipType.active: membershipType = String(localized: "aktiv")
        case GVSCMembershipType.supporting: membershipType = String(localized: "fördernd")
        default: membershipType = ""
        }
        let gender: String
        switch data.gender {
        case "f": gender = String(localized: "weiblich")
        case "m": gender = String(localized: "männlich")
        default: gender = data.gender
        }
        var steps: [Step] = [
            .field(label: "Förderndes oder aktives", value: membershipType),
            .field(label: "Weiblich oder männlich:", value: gender),
            .field(label: "Titel:", value: data.title),
            .field(label: "Vorname, Nachname:", value: joined([data.firstName, data.lastName], " ")),
            .field(label: "PLZ, Wohnort:", value: joined([data.zip, data.city], " ")),
            .field(label: "Straße, Hausnummer:", value: data.street),
            .field(label: "Sv.Nr., Geburtsdatum:",
                   value: joined([data.svnr, data.birthDate.map(dateFormatter.string(from:)) ?? ""], ", ")),
            .field(label: "Staatsbürgerschaft:", value: data.citizenship),
            .field(label: "Telefonnummer:", value: data.phone),
            .field(label: "Mobilnummer:", value: data.mobile),
            .field(label: "Mail:", value: data.email),
            .field(label: "IBAN:", value: data.iban, keepBlankLine: true),
            .field(label: "Sportart(en):", value: data.sports.joined(separator: ", ")),
            .field(label: "Sektion (falls bekannt):", value: section),
            .field(label: "Art der Behinderung:", value: data.disabilityType),
            .field(label: "Behinderungsklasse (falls bekannt):", value: data.disabilityClass),
            .field(label: "Behinderung durch (Arbeit, Freizeit):", value: data.disabilityCause),
        ]
        if let guardian = data.guardian {
            steps += [
                .field(label: "Vorname, Nachname:", value: joined([guardian.firstName, guardian.lastName], " ")),
                .field(label: "PLZ, Wohnort:", value: joined([guardian.zip, guardian.city], " ")),
                .field(label: "Straße, Hausnummer:", value: guardian.street),
                .field(label: "Telefonnummer:", value: guardian.phone),
                .field(label: "Mobilnummer:", value: guardian.mobile),
                .field(label: "Mail:", value: guardian.email),
            ]
        }
        steps += [
            .choice(answer: "JA", checked: data.consentDataTransfer == true),
            .choice(answer: "NEIN", checked: data.consentDataTransfer == false),
            .choice(answer: "JA", checked: data.consentPhotos == true),
            .choice(answer: "NEIN", checked: data.consentPhotos == false),
        ]
        return steps
    }

    private static func matcher(for step: Step) -> (String) -> Bool {
        switch step {
        case .field(let label, _, _):
            return { $0.trimmingCharacters(in: .whitespaces).hasPrefix(label) }
        case .choice(let answer, _):
            return { $0.filter { !$0.isWhitespace } == "O" + answer }
        }
    }

    private static func rebuild(_ paragraph: String, for step: Step) -> String {
        switch step {
        case .choice(_, let checked):
            guard checked, let range = paragraph.range(of: #"(<w:t(?: [^>]*)?>\s*)O"#, options: .regularExpression) else {
                return paragraph
            }
            let marked = paragraph[range].dropLast() + "X"
            return paragraph.replacingCharacters(in: range, with: marked)
        case .field(let label, let value, let keepBlankLine):
            if value.isEmpty && keepBlankLine { return paragraph }
            let open = firstMatch(#"^<w:p\b[^>]*>"#, in: paragraph) ?? "<w:p>"
            let properties = firstMatch(#"<w:pPr>.*?</w:pPr>"#, in: paragraph) ?? ""
            let runProperties = firstMatch(#"<w:r\b[^>]*>\s*(<w:rPr>.*?</w:rPr>)"#, in: paragraph, group: 1) ?? ""
            var result = open + properties
                + "<w:r>\(runProperties)<w:t xml:space=\"preserve\">\(xmlEscape(label))</w:t></w:r>"
            if !value.isEmpty {
                result += "<w:r>\(runProperties)<w:tab/><w:t xml:space=\"preserve\">\(xmlEscape(value))</w:t></w:r>"
            }
            return result + "</w:p>"
        }
    }

    /// The next top-level-looking paragraph (from `<w:p>`/`<w:p …>` to the
    /// next `</w:p>`) whose visible text satisfies `matches`. Field labels
    /// never sit in text boxes, so nested paragraphs only ever fail to match.
    private static func nextParagraph(in xml: String, fromOffset offset: Int,
                                      matching matches: (String) -> Bool) -> (Range<String.Index>, String)? {
        var cursor = xml.index(xml.startIndex, offsetBy: offset)
        while let start = xml.range(of: #"<w:p[ >]"#, options: .regularExpression, range: cursor..<xml.endIndex),
              let end = xml.range(of: "</w:p>", range: start.upperBound..<xml.endIndex) {
            let range = start.lowerBound..<end.upperBound
            let paragraph = String(xml[range])
            if matches(visibleText(of: paragraph)) { return (range, paragraph) }
            cursor = end.upperBound
        }
        return nil
    }

    private static func visibleText(of paragraph: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<w:t(?: [^>]*)?>([^<]*)</w:t>"#) else { return "" }
        let ns = paragraph as NSString
        return regex.matches(in: paragraph, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
            .joined()
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    private static func joined(_ parts: [String], _ separator: String) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: separator)
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func asciiFileName(_ value: String) -> String {
        let map: [Character: String] = ["ä": "ae", "ö": "oe", "ü": "ue", "Ä": "Ae", "Ö": "Oe", "Ü": "Ue", "ß": "ss"]
        let transliterated = value.map { map[$0] ?? String($0) }.joined()
        return transliterated
            .replacingOccurrences(of: #"[^A-Za-z0-9-]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}
