import Foundation

/// Minimal read-only view over a CloudKit Web Services JSON record — just
/// enough to find a record and carry its recordChangeTag through to an
/// update, without a full CKRecord modeling layer.
public struct CKRecordDTO {
    public let recordName: String
    public let recordType: String
    public let changeTag: String
    public let fields: [String: Any]
    /// Server modification time (`modified.timestamp`, ms since epoch); nil
    /// if the response didn't include it.
    public let modifiedAt: Date?

    public init(recordName: String, recordType: String, fields: [String: Any], modifiedAt: Date? = nil) {
        self.recordName = recordName
        self.recordType = recordType
        self.changeTag = ""
        self.fields = fields
        self.modifiedAt = modifiedAt
    }

    public init?(_ dict: [String: Any]) {
        guard let recordName = dict["recordName"] as? String,
              let recordType = dict["recordType"] as? String,
              let changeTag = dict["recordChangeTag"] as? String,
              let fields = dict["fields"] as? [String: Any] else { return nil }
        self.recordName = recordName
        self.recordType = recordType
        self.changeTag = changeTag
        self.fields = fields
        self.modifiedAt = ((dict["modified"] as? [String: Any])?["timestamp"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
    }

    public func stringField(_ name: String) -> String? {
        (fields[name] as? [String: Any])?["value"] as? String
    }

    public func boolField(_ name: String) -> Bool {
        guard let value = (fields[name] as? [String: Any])?["value"] else { return false }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    /// Reads a CloudKit TIMESTAMP field, stored as milliseconds since epoch.
    public func dateField(_ name: String) -> Date? {
        guard let value = (fields[name] as? [String: Any])?["value"] else { return nil }
        guard let number = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1000)
    }

    /// Reads an INT64 or DOUBLE field.
    public func numberField(_ name: String) -> NSNumber? {
        (fields[name] as? [String: Any])?["value"] as? NSNumber
    }

    /// Reads a CloudKit STRING_LIST field (e.g. `teamIDs` on Training/
    /// Tournament/SportEvent) — empty (not nil) when absent, since callers
    /// treat "no team scoping" as "visible to everyone", same as the app.
    public func stringListField(_ name: String) -> [String] {
        (fields[name] as? [String: Any])?["value"] as? [String] ?? []
    }
}
