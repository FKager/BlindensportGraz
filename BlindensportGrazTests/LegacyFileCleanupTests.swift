import XCTest
@testable import BlindensportGraz

/// Old roster snapshots (SVNR, IBAN, birth dates) must disappear from the
/// device; nothing else in Documents may be touched.
final class LegacyFileCleanupTests: XCTestCase {
    private var documents: URL!

    override func setUpWithError() throws {
        documents = FileManager.default.temporaryDirectory
            .appending(path: "LegacyFileCleanupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: documents)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func testRemovesTheMemberBackupsFolderAndOnlyThat() throws {
        let backups = documents.appending(path: LegacyFileCleanup.memberBackupsFolder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try Data(#"[{"svnr":"1234010180"}]"#.utf8).write(to: backups.appending(path: "mitglieder-2026-11-01.json"))
        let other = documents.appending(path: "keep.txt")
        try Data("bleibt".utf8).write(to: other)

        LegacyFileCleanup.removeMemberBackups(documents: documents)

        XCTAssertFalse(exists(backups))
        XCTAssertTrue(exists(other))
    }

    func testDoesNothingWhenThereAreNoBackups() {
        LegacyFileCleanup.removeMemberBackups(documents: documents)

        XCTAssertTrue(exists(documents))
    }
}
