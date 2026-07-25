import Foundation
import CloudKitS2SCore

/// File-loading half of `import-members` — the per-row decode shape and the
/// actual create-or-replace logic now live in `CloudKitS2SCore.ClubMemberBulkImport`,
/// shared with clubmembersapi's `POST /api/members/import` so the CLI and the
/// REST endpoint can't drift apart on what counts as a valid row.
enum ClubMemberImport {
    static func loadRecords(from path: String) throws -> [ClubMemberBulkInput] {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw CLIError.message("Could not read \(path): \(error)")
        }
        do {
            return try JSONDecoder().decode([ClubMemberBulkInput].self, from: data)
        } catch {
            throw CLIError.message("Could not parse \(path) as a JSON array of club members: \(error)")
        }
    }
}
