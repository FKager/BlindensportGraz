import Foundation
import os

/// Removes files earlier versions left on the device.
nonisolated enum LegacyFileCleanup {
    /// Earlier versions wrote automatic roster snapshots here — including
    /// SVNR, IBAN and birth dates on admin devices — visible in the Files
    /// app and included in device backups. The roster lives in Supabase.
    static let memberBackupsFolder = "MemberBackups"

    /// Deletes the old roster snapshots, if any. Safe to call on every launch.
    static func removeMemberBackups(documents: URL = .documentsDirectory) {
        let folder = documents.appending(path: memberBackupsFolder, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            Logger(subsystem: "it.a11y.BlindensportGraz", category: "LegacyFileCleanup")
                .error("Could not remove old member backups: \(String(describing: error), privacy: .public)")
        }
    }
}
