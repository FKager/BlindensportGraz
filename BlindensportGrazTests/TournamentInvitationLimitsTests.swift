import XCTest
import ZIPFoundation
@testable import BlindensportGraz

/// Invitations come from outside (mail from other clubs). A .docx is a zip,
/// so a small crafted one could unpack to gigabytes: its text is read only up
/// to a limit. And the new-tournament form says why an invitation won't be
/// kept as a document, instead of dropping it silently.
final class TournamentInvitationLimitsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A .docx holding only `word/document.xml` with one paragraph of `text`.
    private func docx(_ text: String) throws -> URL {
        let url = folder.appendingPathComponent("Einladung.docx")
        let xml = Data("<w:document><w:body><w:p><w:r><w:t>\(text)</w:t></w:r></w:p></w:body></w:document>".utf8)
        let archive = try Archive(url: url, accessMode: .create)
        try archive.addEntry(with: "word/document.xml", type: .file, uncompressedSize: Int64(xml.count),
                             compressionMethod: .deflate) { position, size in
            xml.subdata(in: Int(position)..<Int(position) + size)
        }
        return url
    }

    func testADocumentWithinTheLimitIsRead() throws {
        let url = try docx("Torball-Turnier in Graz")

        let text = try TournamentInvitationImporter.extractText(from: url, maxDocumentXMLBytes: 1_000)

        XCTAssertTrue(text.contains("Torball-Turnier in Graz"))
    }

    func testADocumentThatUnpacksBeyondTheLimitIsRefused() throws {
        // Repetitive text compresses to almost nothing, like a zip bomb.
        let url = try docx(String(repeating: "A", count: 50_000))

        XCTAssertThrowsError(try TournamentInvitationImporter.extractText(from: url, maxDocumentXMLBytes: 10_000)) { error in
            guard case TournamentInvitationError.fileTooLarge = error else {
                return XCTFail("expected fileTooLarge, got \(error)")
            }
        }
    }

    func testTheLimitsStayGenerous() {
        XCTAssertGreaterThanOrEqual(TournamentInvitationImporter.maxDocumentXMLBytes, 10 * 1024 * 1024)
        XCTAssertGreaterThanOrEqual(TournamentInvitationImporter.maxFileBytes, TournamentInvitation.maxFileSize)
    }

    // MARK: - Keeping the invitation as a document

    func testAttachmentProblems() {
        XCTAssertNil(TournamentInvitation.attachmentProblem(fileName: "Einladung.pdf", size: 1_000))
        XCTAssertEqual(TournamentInvitation.attachmentProblem(fileName: "Einladung.pdf",
                                                              size: TournamentInvitation.maxFileSize + 1),
                       "größer als 15 MB.")
        XCTAssertEqual(TournamentInvitation.attachmentProblem(fileName: "Einladung.pages", size: 1_000),
                       "Dateityp wird nicht unterstützt.")
    }
}
