import XCTest
@testable import BlindensportGraz

/// Roles are granted only server-side (Supabase `set_user_role`, RootCLI with
/// the service key). The app must not contain any client-side elevation path.
@MainActor
final class NoClientRoleGrantTests: XCTestCase {
    /// Scans the app's source files (Simulator processes share the host Mac's
    /// filesystem) rather than asserting against a symbol that, if
    /// reintroduced, would just make this file fail to compile.
    func testNoClientSideElevationSymbolsInSource() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let sourceDir = thisFile
            .deletingLastPathComponent() // BlindensportGrazTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("BlindensportGraz")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sourceDir, includingPropertiesForKeys: nil))
        let swiftFiles = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(swiftFiles.isEmpty, "expected Swift sources at \(sourceDir.path)")

        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for symbol in ["testAdminEmail", "elevateIfTestAdmin", "elevateIfDesignatedRoot",
                           "service_role", "SUPABASE_SERVICE_ROLE_KEY"] {
                XCTAssertFalse(contents.contains(symbol),
                               "\(file.lastPathComponent) contains forbidden symbol \(symbol)")
            }
        }
    }
}
