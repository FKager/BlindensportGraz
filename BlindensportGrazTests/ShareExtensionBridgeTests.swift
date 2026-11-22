import XCTest
@testable import BlindensportGraz

/// The import link's file name comes from a URL anyone can open; only the
/// names the share extension creates may reach the inbox lookup and clean-up.
final class ShareExtensionBridgeTests: XCTestCase {
    private let id = "9E3AC32B-E4C1-4FE7-93FB-0CA5BC63A27D"

    func testNamesTheShareExtensionCreatesAreAccepted() {
        XCTAssertTrue(ShareExtensionBridge.isInboxFileName("\(id).pdf"))
        XCTAssertTrue(ShareExtensionBridge.isInboxFileName("\(id).docx"))
        XCTAssertTrue(ShareExtensionBridge.isInboxFileName("\(id)."), "a shared file without extension")
    }

    func testPathsAndOtherNamesAreRefused() {
        for name in ["../\(id).pdf", "../../Library/Preferences/x.plist", "\(id).pdf/../../x", "/etc/passwd",
                     "\(id)/x.pdf", "\(id).tar.gz", "Einladung.pdf", "\(id)", "\(id).p d f", "\(id).pdf\u{0}",
                     "", "..", "\(id).\u{00FC}ber"] {
            XCTAssertFalse(ShareExtensionBridge.isInboxFileName(name), name)
        }
    }

    func testCleanUpOnlyTouchesFilesDirectlyInTheInbox() {
        let inbox = URL(fileURLWithPath: "/tmp/group/SharedInvitations", isDirectory: true)

        XCTAssertTrue(ShareExtensionBridge.isInInbox(inbox.appendingPathComponent("\(id).pdf"), inbox: inbox))
        XCTAssertFalse(ShareExtensionBridge.isInInbox(inbox.appendingPathComponent("../widget.json"), inbox: inbox))
        XCTAssertFalse(ShareExtensionBridge.isInInbox(inbox.appendingPathComponent("sub/\(id).pdf"), inbox: inbox))
        XCTAssertFalse(ShareExtensionBridge.isInInbox(URL(fileURLWithPath: "/tmp/other/\(id).pdf"), inbox: inbox))
    }
}
