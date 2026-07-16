import Foundation

/// Minimal read-only view over a CloudKit Web Services JSON record — just
/// enough to find a UserIdentity record and carry its recordChangeTag through
/// to an update, without a full CKRecord modeling layer.
struct CKRecordDTO {
    let recordName: String
    let recordType: String
    let changeTag: String
    let fields: [String: Any]

    init?(_ dict: [String: Any]) {
        guard let recordName = dict["recordName"] as? String,
              let recordType = dict["recordType"] as? String,
              let changeTag = dict["recordChangeTag"] as? String,
              let fields = dict["fields"] as? [String: Any] else { return nil }
        self.recordName = recordName
        self.recordType = recordType
        self.changeTag = changeTag
        self.fields = fields
    }

    func stringField(_ name: String) -> String? {
        (fields[name] as? [String: Any])?["value"] as? String
    }

    func boolField(_ name: String) -> Bool {
        guard let value = (fields[name] as? [String: Any])?["value"] else { return false }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }
}
