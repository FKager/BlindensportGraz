import XCTest
@testable import BlindensportGraz

/// Cell and Word text must stay valid XML, or Excel/Word refuse the whole file.
final class XMLTextTests: XCTestCase {
    func testEscapesMarkup() {
        XCTAssertEqual(XMLText.escape("Müller & Söhne <Graz>"), "Müller &amp; Söhne &lt;Graz&gt;")
    }

    func testDropsControlCharactersXMLForbids() {
        XCTAssertEqual(XMLText.escape("Anna\u{0B}Maria\u{00}"), "AnnaMaria")
    }

    func testKeepsTabsLineBreaksAndEmoji() {
        XCTAssertEqual(XMLText.escape("a\tb\nc\r⚽️"), "a\tb\nc\r⚽️")
    }
}
