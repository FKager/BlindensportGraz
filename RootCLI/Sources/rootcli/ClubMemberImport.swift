import Foundation

/// Mirrors the app's `ClubMember` model (Models.swift) field-for-field. `id` is
/// optional and, when given, must be a UUID string — it becomes the CKRecord
/// name, so re-running an import with the same `id`s updates those records in
/// place (via `forceReplace`) instead of creating duplicates. `firstName` and
/// `lastName` are required; everything else defaults the way the app's own
/// AddClubMemberView does.
struct ClubMemberInput: Decodable {
    var id: String?
    // Optional (not required) so a missing key is treated the same as an empty
    // string — skipped per-entry by the caller — rather than aborting the
    // whole file's decode, which is what a non-optional String would do.
    var firstName: String?
    var lastName: String?
    var street: String?
    var zip: String?
    var city: String?
    var email: String?
    var phone: String?
    var memberNumber: String?
    var joinedAt: String?
    var notes: String?
}

enum ClubMemberImport {
    static func loadRecords(from path: String) throws -> [ClubMemberInput] {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw CLIError.message("Could not read \(path): \(error)")
        }
        do {
            return try JSONDecoder().decode([ClubMemberInput].self, from: data)
        } catch {
            throw CLIError.message("Could not parse \(path) as a JSON array of club members: \(error)")
        }
    }

    /// Accepts "yyyy-MM-dd" or full ISO8601; returns nil (caller defaults to
    /// "now") rather than throwing, so one malformed date doesn't sink the batch.
    static func parseJoinedAt(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        return dayFormatter.date(from: raw)
    }
}
