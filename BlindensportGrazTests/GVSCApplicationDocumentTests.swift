import XCTest
import ZIPFoundation
@testable import BlindensportGraz

/// Fills the real bundled GVSC_Beitrittserklaerung.docx and checks the
/// resulting word/document.xml: well-formed, values present in the right
/// places, template sample values gone, JA/NEIN marked.
final class GVSCApplicationDocumentTests: XCTestCase {

    private func adult() -> GVSCApplicationData {
        var data = GVSCApplicationData()
        data.membershipType = GVSCMembershipType.active
        data.gender = "m"
        data.title = "Mag."
        data.firstName = "Jörg"
        data.lastName = "Müller & Söhne"
        data.street = "Hauptstraße 12"
        data.zip = "8010"
        data.city = "Graz"
        data.svnr = "1234 010190"
        data.birthDate = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1))
        data.citizenship = "Österreich"
        data.phone = "0316 123456"
        data.mobile = "0664 1234567"
        data.email = "joerg@example.at"
        data.iban = "AT61 1904 3002 3457 3201"
        data.sports = ["Showdown", "Torball"]
        data.disabilityType = "vollblind"
        data.disabilityClass = "B1"
        data.disabilityCause = "Geburt"
        data.consentDataTransfer = true
        data.consentPhotos = false
        return data
    }

    private func documentXML(_ data: GVSCApplicationData) throws -> String {
        let docx = try GVSCApplicationDocument.makeDocx(data)
        let archive = try Archive(data: docx, accessMode: .read)
        let entry = try XCTUnwrap(archive["word/document.xml"])
        var xml = Data()
        _ = try archive.extract(entry) { xml.append($0) }
        return try XCTUnwrap(String(data: xml, encoding: .utf8))
    }

    /// Visible text per paragraph, in order.
    private func paragraphs(_ xml: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: #"<w:p[ >].*?</w:p>"#, options: .dotMatchesLineSeparators)
        let text = try NSRegularExpression(pattern: #"<w:t(?: [^>]*)?>([^<]*)</w:t>"#)
        let ns = xml as NSString
        return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).map { match in
            let paragraph = ns.substring(with: match.range) as NSString
            return text.matches(in: paragraph as String, range: NSRange(location: 0, length: paragraph.length))
                .map { paragraph.substring(with: $0.range(at: 1)) }
                .joined()
                .replacingOccurrences(of: "&amp;", with: "&")
        }
    }

    private func paragraph(startingWith label: String, in paragraphs: [String], occurrence: Int = 0) -> String? {
        let matches = paragraphs.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix(label) }
        return matches.count > occurrence ? matches[occurrence] : nil
    }

    func testFilledDocumentIsWellFormedXML() throws {
        let xml = try documentXML(adult())
        let parser = XMLParser(data: Data(xml.utf8))
        XCTAssertTrue(parser.parse(), "document.xml must stay well-formed: \(String(describing: parser.parserError))")
    }

    func testMemberFieldsAreFilledAndSamplesCleared() throws {
        let paras = try paragraphs(try documentXML(adult()))
        XCTAssertEqual(paragraph(startingWith: "Förderndes oder aktives", in: paras), "Förderndes oder aktivesaktiv")
        XCTAssertEqual(paragraph(startingWith: "Weiblich oder männlich:", in: paras), "Weiblich oder männlich:männlich")
        XCTAssertEqual(paragraph(startingWith: "Vorname, Nachname:", in: paras), "Vorname, Nachname:Jörg Müller & Söhne")
        XCTAssertEqual(paragraph(startingWith: "PLZ, Wohnort:", in: paras), "PLZ, Wohnort:8010 Graz")
        XCTAssertEqual(paragraph(startingWith: "Sv.Nr., Geburtsdatum:", in: paras), "Sv.Nr., Geburtsdatum:1234 010190, 01.01.1990")
        XCTAssertEqual(paragraph(startingWith: "IBAN:", in: paras), "IBAN:AT61 1904 3002 3457 3201")
        XCTAssertEqual(paragraph(startingWith: "Sportart(en):", in: paras), "Sportart(en):Showdown, Torball")
        XCTAssertEqual(paragraph(startingWith: "Sektion (falls bekannt):", in: paras), "Sektion (falls bekannt):Blindensport")
        XCTAssertEqual(paragraph(startingWith: "Art der Behinderung:", in: paras), "Art der Behinderung:vollblind")
        XCTAssertEqual(paragraph(startingWith: "Behinderung durch (Arbeit, Freizeit):", in: paras),
                       "Behinderung durch (Arbeit, Freizeit):Geburt")
        let all = paras.joined(separator: "\n")
        for sample in ["Schifahren", "Schisport Amp.", "US-Amputiert", "Freizeitunfall"] {
            XCTAssertFalse(all.contains(sample), "template sample \(sample) must be cleared")
        }
    }

    func testConsentsMarkTheChosenAnswer() throws {
        let choices = try paragraphs(try documentXML(adult()))
            .map { $0.filter { !$0.isWhitespace } }
            .filter { ["OJA", "ONEIN", "XJA", "XNEIN"].contains($0) }
        // Datenweitergabe: JA; Foto/Video: NEIN.
        XCTAssertEqual(choices, ["XJA", "ONEIN", "OJA", "XNEIN"])
    }

    func testAdultLeavesGuardianSectionAndSignatureEmpty() throws {
        let paras = try paragraphs(try documentXML(adult()))
        XCTAssertEqual(paragraph(startingWith: "Vorname, Nachname:", in: paras, occurrence: 1), "Vorname, Nachname:")
        XCTAssertEqual(paragraph(startingWith: "Mail:", in: paras, occurrence: 1), "Mail:")
        XCTAssertTrue(paragraph(startingWith: "Unterschrift:", in: paras)?.contains("____") ?? false)
        XCTAssertTrue(paragraph(startingWith: "Ort, Datum", in: paras)?.contains("____") ?? false)
    }

    func testMinorFillsGuardian() throws {
        var data = adult()
        data.guardian = .init(firstName: "Eva", lastName: "Müller", street: "Hauptstraße 12", zip: "8010",
                              city: "Graz", phone: "", mobile: "0664 7654321", email: "eva@example.at")
        let paras = try paragraphs(try documentXML(data))
        XCTAssertEqual(paragraph(startingWith: "Vorname, Nachname:", in: paras, occurrence: 1), "Vorname, Nachname:Eva Müller")
        XCTAssertEqual(paragraph(startingWith: "Mobilnummer:", in: paras, occurrence: 1), "Mobilnummer:0664 7654321")
        XCTAssertEqual(paragraph(startingWith: "Telefonnummer:", in: paras, occurrence: 1), "Telefonnummer:")
        XCTAssertEqual(paragraph(startingWith: "Mail:", in: paras, occurrence: 1), "Mail:eva@example.at")
    }

    func testEmptyIBANKeepsTheWriteInLine() throws {
        var data = adult()
        data.iban = ""
        let paras = try paragraphs(try documentXML(data))
        XCTAssertTrue(paragraph(startingWith: "IBAN:", in: paras)?.contains("_____") ?? false)
    }

    func testMissingFields() {
        XCTAssertEqual(adult().missingFields, [])
        var data = GVSCApplicationData()
        data.firstName = "Anna"
        data.guardian = .init()
        let missing = data.missingFields
        XCTAssertTrue(missing.contains("Mitgliedsart (aktiv/fördernd)"))
        XCTAssertTrue(missing.contains("Einwilligung Foto/Video"))
        XCTAssertTrue(missing.contains("Gesetzliche:r Vertreter:in"))
        XCTAssertFalse(missing.contains("Name"))
    }

    func testFileNameIsASCII() {
        XCTAssertEqual(GVSCApplicationDocument.fileName(for: adult()), "Beitrittserklaerung_Mueller_Soehne_Joerg.docx")
    }
}
