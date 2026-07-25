import Foundation

/// Generic bridge between plain JSON/Swift values and CloudKit Web Services'
/// field wire format (`{"value": ..., "type": ...}`). Every existing tool in
/// this package (`ClubMemberRecord`, `rootcli set-role`/`set-root`) hand-rolls
/// this encoding per field, which only scales because there's exactly one
/// modeled record type (`ClubMember`) plus two one-off fields. A generic
/// record editor that covers every type in the app (Team, SportEvent,
/// Training, Tournament, TeamMembership, EventParticipation, Attendance,
/// UserIdentity, ClubMember) can't reasonably hand-write a mirror struct per
/// type — that's the same "silently drifts from Models.swift" problem
/// `ClubMemberRecord` was built to solve, just multiplied by ten. This lets
/// the CLI's `record` subcommand and clubmembersapi's `/api/records` routes
/// share one place that knows CloudKit's wire types instead.
public enum CKFieldCoding {
    /// Record types this app's CloudKitSync.swift actually publishes, for
    /// CLI help text and the generic web UI's type picker. Not enforced —
    /// `record`/`/api/records` work against any record type string, known or
    /// not. `EventImage` is deliberately excluded: it carries a CKAsset
    /// (binary file), which this text/JSON-field editor doesn't handle.
    public static let knownTypes = [
        "UserIdentity", "ClubMember", "Team", "TeamMembership",
        "SportEvent", "Training", "Tournament",
        "TrainingAttendance", "TournamentAttendance", "EventParticipation",
    ]

    /// Encodes a plain value (String, Bool, Int, Double, Date, [String], or
    /// a comma-separated String standing in for a list) into CloudKit's wire
    /// format. `type` is an explicit override ("INT64", "DOUBLE",
    /// "TIMESTAMP", "STRING_LIST", "STRING"); when nil, the type is inferred
    /// from the Swift value's own kind (adequate for JSON request bodies,
    /// where numbers/bools/arrays already arrive as distinct JSON types —
    /// CLI args arrive as plain strings, so `set` requires the explicit
    /// `field:TYPE=value` form for anything non-string).
    public static func encode(_ value: Any, type: String? = nil) -> [String: Any] {
        switch type?.uppercased() {
        case "INT64":
            if let b = value as? Bool { return ["value": b ? 1 : 0, "type": "INT64"] }
            if let i = value as? Int { return ["value": i, "type": "INT64"] }
            if let s = value as? String, let i = Int(s) { return ["value": i, "type": "INT64"] }
            return ["value": 0, "type": "INT64"]
        case "DOUBLE":
            if let d = value as? Double { return ["value": d, "type": "DOUBLE"] }
            if let s = value as? String, let d = Double(s) { return ["value": d, "type": "DOUBLE"] }
            return ["value": 0.0, "type": "DOUBLE"]
        case "TIMESTAMP":
            if let date = value as? Date {
                return ["value": Int64(date.timeIntervalSince1970 * 1000), "type": "TIMESTAMP"]
            }
            if let s = value as? String, let date = ISO8601DateFormatter().date(from: s) {
                return ["value": Int64(date.timeIntervalSince1970 * 1000), "type": "TIMESTAMP"]
            }
            return ["value": Int64(Date().timeIntervalSince1970 * 1000), "type": "TIMESTAMP"]
        case "STRING_LIST":
            if let arr = value as? [String] { return ["value": arr, "type": "STRING_LIST"] }
            if let s = value as? String {
                let items = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                return ["value": items, "type": "STRING_LIST"]
            }
            return ["value": [], "type": "STRING_LIST"]
        case "STRING":
            return ["value": "\(value)"]
        default:
            // No explicit type given: infer from the value's own Swift/JSON kind.
            if let arr = value as? [String] { return ["value": arr, "type": "STRING_LIST"] }
            if let b = value as? Bool { return ["value": b ? 1 : 0, "type": "INT64"] }
            if let i = value as? Int { return ["value": i, "type": "INT64"] }
            if let d = value as? Double { return ["value": d, "type": "DOUBLE"] }
            if let date = value as? Date {
                return ["value": Int64(date.timeIntervalSince1970 * 1000), "type": "TIMESTAMP"]
            }
            return ["value": "\(value)"] // STRING is CloudKit's default when "type" is omitted.
        }
    }

    /// Parses `field=value` / `field:TYPE=value` CLI arguments (as used by
    /// `rootcli record set`) into a CloudKit field dict ready for
    /// `createOrReplaceRecord`/`updateRecord`.
    public static func parseCLIAssignments(_ args: [String]) -> [String: [String: Any]] {
        var fields: [String: [String: Any]] = [:]
        for arg in args {
            guard let eq = arg.firstIndex(of: "=") else { continue }
            let keyPart = String(arg[arg.startIndex..<eq])
            let value = String(arg[arg.index(after: eq)...])
            let name: String
            let type: String?
            if let colon = keyPart.firstIndex(of: ":") {
                name = String(keyPart[keyPart.startIndex..<colon])
                type = String(keyPart[keyPart.index(after: colon)...])
            } else {
                name = keyPart
                type = nil
            }
            fields[name] = encode(value, type: type)
        }
        return fields
    }

    /// Converts a `CKRecordDTO`'s raw `fields` (CloudKit wire format) back
    /// into a flat `[String: Any]` suitable for JSON output — unwraps the
    /// `{"value": ...}` envelope and turns TIMESTAMP integers back into
    /// ISO8601 strings, so callers never deal with CloudKit's wire shape
    /// directly.
    public static func decode(_ fields: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, raw) in fields {
            guard let dict = raw as? [String: Any], let value = dict["value"] else { continue }
            if (dict["type"] as? String) == "TIMESTAMP", let ms = (value as? NSNumber)?.doubleValue {
                result[key] = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: ms / 1000))
            } else {
                result[key] = value
            }
        }
        return result
    }
}
