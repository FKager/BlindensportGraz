import Foundation

/// Minimal read-only view over a CloudKit Web Services JSON record — just
/// enough to find a record and carry its recordChangeTag through to an
/// update, without a full CKRecord modeling layer.
public struct CKRecordDTO {
    public let recordName: String
    public let recordType: String
    public let changeTag: String
    public let fields: [String: Any]

    public init?(_ dict: [String: Any]) {
        guard let recordName = dict["recordName"] as? String,
              let recordType = dict["recordType"] as? String,
              let changeTag = dict["recordChangeTag"] as? String,
              let fields = dict["fields"] as? [String: Any] else { return nil }
        self.recordName = recordName
        self.recordType = recordType
        self.changeTag = changeTag
        self.fields = fields
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
}
