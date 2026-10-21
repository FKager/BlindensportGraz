import Foundation
import CloudKitS2SCore

/// `rootcli cloudkit-copy-to-supabase [--dry-run|--apply] [--since <ISO8601>]`
///
/// Copies the club data still in CloudKit into Supabase (v0.3.0 cutover),
/// keeping every record name as the row id. Upserts, so it is safe to re-run.
/// `--since` copies only records changed in CloudKit after that time — use
/// it for the catch-up run after the cutover, so edits already made in
/// Supabase by the new app aren't overwritten by unchanged CloudKit copies.
///
/// Needs the CloudKit S2S variables and SUPABASE_URL/SUPABASE_SERVICE_KEY.
enum CloudKitCopyCommand {
    static func run(_ args: [String], cloudKit: CloudKitS2SClient) async throws {
        let usage = "rootcli cloudkit-copy-to-supabase [--dry-run|--apply] [--since <ISO8601 time>]"
        var apply = false
        var since: Date?
        var rest = args[...]
        while let arg = rest.popFirst() {
            switch arg {
            case "--apply": apply = true
            case "--dry-run": apply = false
            case "--since":
                guard let raw = rest.popFirst(), let date = ISO8601DateFormatter().date(from: raw) else {
                    throw CLIError.message("--since needs an ISO8601 time, e.g. 2026-10-20T18:00:00Z. Usage: \(usage)")
                }
                since = date
            default:
                throw CLIError.message("Usage: \(usage)")
            }
        }
        let supabase = try SupabaseAdminClient.fromEnvironment()

        var records: [String: [CKRecordDTO]] = [:]
        var unreadable: [String] = []
        for type in CloudKitCopy.recordTypes {
            do {
                records[type] = try await cloudKit.queryRecords(recordType: type)
            } catch let error as CLIError where "\(error)".contains("could not find record_type") {
                records[type] = [] // never saved in this environment's schema
            } catch let error as CLIError where "\(error)".contains("not marked queryable") {
                // No recordName index: CloudKit can't list this type without a
                // filter — the app's own pulls never saw these records. List
                // them through a QUERYABLE timestamp field instead.
                if let found = try await queryWithoutRecordNameIndex(type, cloudKit: cloudKit) {
                    records[type] = found
                } else {
                    records[type] = []
                    unreadable.append(type)
                }
            }
        }
        let users = Set(try await supabase.listUsers().map { $0.id.uuidString.lowercased() })
        let result = try CloudKitCopy.map(records, existingUserIDs: users, since: since)

        print("CloudKit records:", CloudKitCopy.recordTypes
            .map { "\($0)=\(records[$0]?.count ?? 0)" }.joined(separator: " "))
        if !unreadable.isEmpty {
            print("Not listable in CloudKit (no recordName index): \(unreadable.joined(separator: ", ")) — "
                  + "these come from the devices via the app's one-time local upload.")
        }
        if let since { print("Only records modified after \(since).") }
        for batch in result.batches where !batch.rows.isEmpty {
            print("  \(batch.table): \(batch.rows.count) row(s)")
        }
        if !result.skipped.isEmpty {
            print("Skipped \(result.skipped.count):")
            result.skipped.forEach { print("  - \($0)") }
        }
        guard apply else {
            print("Dry run — nothing written. Re-run with --apply.")
            return
        }

        for batch in result.batches where !batch.rows.isEmpty {
            for chunk in batch.rows.chunked(500) {
                try await supabase.upsert(table: batch.table, rows: chunk, onConflict: batch.conflictKey)
            }
            print("  ✓ \(batch.table)")
        }
        print("Done.")
    }

    /// QUERYABLE timestamp fields per type without a recordName index. Every
    /// field is queried (`> 1970`) and the results merged, so a record
    /// missing one timestamp is still found through another.
    static let timestampFields = [
        "BudgetEntry": ["createdAt", "date"],
        "EventMembership": ["addedAt"],
    ]

    /// Nil when the type has no known timestamp field or none is queryable.
    static func queryWithoutRecordNameIndex(_ type: String, cloudKit: CloudKitS2SClient) async throws -> [CKRecordDTO]? {
        guard let fields = timestampFields[type] else { return nil }
        var byName: [String: CKRecordDTO] = [:]
        var anyQueryable = false
        for field in fields {
            let filter: [String: Any] = ["fieldName": field, "comparator": "GREATER_THAN",
                                         "fieldValue": ["value": 0, "type": "TIMESTAMP"]]
            do {
                for record in try await cloudKit.queryRecords(recordType: type, filterBy: [filter]) {
                    byName[record.recordName] = record
                }
                anyQueryable = true
            } catch let error as CLIError where "\(error)".contains("not marked queryable") {
                continue
            }
        }
        guard anyQueryable else { return nil }
        FileHandle.standardError.write(Data("\(type): no recordName index, listed via \(fields.joined(separator: "/")) filter (\(byName.count) records)\n".utf8))
        return Array(byName.values)
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
