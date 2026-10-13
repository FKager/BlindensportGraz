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
                // No recordName index: CloudKit can't list this type at all —
                // the app's own pulls never saw these records either, so they
                // live only on the devices that wrote them. v0.3.0 uploads
                // its locally held rows of these types on first launch.
                records[type] = []
                unreadable.append(type)
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
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
