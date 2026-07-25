import Foundation

/// Loose, per-row-tolerant input shape for bulk ClubMember import — shared by
/// `rootcli import-members` and clubmembersapi's `POST /api/members/import`,
/// so both accept exactly the same file/body shape (a JSON array, same as
/// what the app's own export produces) and apply exactly the same per-row
/// rules. Fields other than the required firstName/lastName are optional so a
/// missing key decodes as nil instead of aborting the whole array's decode —
/// see the 2026-07-17 cerebrum.md entry on why a non-optional Decodable
/// property is the wrong choice for a bulk importer.
public struct ClubMemberBulkInput: Codable, Sendable {
    public var id: String?
    public var firstName: String?
    public var lastName: String?
    public var street: String?
    public var zip: String?
    public var city: String?
    public var email: String?
    public var phone: String?
    public var memberNumber: String?
    public var joinedAt: String?
    public var notes: String?

    public init(
        id: String? = nil, firstName: String? = nil, lastName: String? = nil,
        street: String? = nil, zip: String? = nil, city: String? = nil,
        email: String? = nil, phone: String? = nil, memberNumber: String? = nil,
        joinedAt: String? = nil, notes: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.street = street
        self.zip = zip
        self.city = city
        self.email = email
        self.phone = phone
        self.memberNumber = memberNumber
        self.joinedAt = joinedAt
        self.notes = notes
    }
}

public struct ClubMemberBulkImportResult: Sendable {
    public var succeeded = 0
    public var failed = 0
    public var messages: [String] = []
    public var total: Int { succeeded + failed }
}

public enum ClubMemberBulkImport {
    /// Creates-or-replaces (via `createOrReplaceRecord`, no change-tag needed)
    /// one `ClubMember` per input. A provided `id` must be a valid UUID string
    /// (it becomes the CKRecord name) — re-running with the same `id`s updates
    /// those records in place; omitting `id` mints a fresh UUID each time, so
    /// re-importing an id-less file duplicates rather than updates. Bad rows
    /// (empty name, non-UUID id) are skipped individually, never abort the batch.
    public static func run(_ inputs: [ClubMemberBulkInput], client: CloudKitS2SClient) async -> ClubMemberBulkImportResult {
        var result = ClubMemberBulkImportResult()
        for input in inputs {
            let firstName = (input.firstName ?? "").trimmingCharacters(in: .whitespaces)
            let lastName = (input.lastName ?? "").trimmingCharacters(in: .whitespaces)
            let fullName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
            guard !firstName.isEmpty, !lastName.isEmpty else {
                result.failed += 1
                result.messages.append("Skipped an entry with an empty firstName or lastName.")
                continue
            }

            let recordName: String
            if let providedID = input.id {
                guard UUID(uuidString: providedID) != nil else {
                    result.failed += 1
                    result.messages.append("Skipped \(fullName): id '\(providedID)' is not a valid UUID.")
                    continue
                }
                recordName = providedID
            } else {
                recordName = UUID().uuidString
            }

            let record = ClubMemberRecord(
                id: recordName,
                firstName: firstName,
                lastName: lastName,
                street: input.street ?? "",
                zip: input.zip ?? "",
                city: input.city ?? "",
                email: input.email ?? "",
                phone: input.phone ?? "",
                memberNumber: input.memberNumber ?? "",
                joinedAt: parseJoinedAt(input.joinedAt) ?? Date(),
                notes: input.notes ?? ""
            )

            do {
                try await client.createOrReplaceRecord(recordType: "ClubMember", recordName: recordName, fields: record.ckFields)
                result.succeeded += 1
                result.messages.append("Imported \(fullName) (\(recordName))")
            } catch {
                result.failed += 1
                result.messages.append("Failed to import \(fullName): \(error)")
            }
        }
        return result
    }

    /// Accepts "yyyy-MM-dd" or full ISO8601; nil (caller defaults to "now")
    /// rather than throwing, so one malformed date doesn't sink the batch.
    public static func parseJoinedAt(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        return dayFormatter.date(from: raw)
    }
}
