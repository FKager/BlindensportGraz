import Foundation
import CryptoKit

/// Talks to CloudKit Web Services' public database directly over HTTPS using
/// Server-to-Server authentication (an ECDSA P-256 key registered in CloudKit
/// Dashboard), bypassing the app entirely. This is what lets an operator flip
/// a user's `role`/`isRoot` fields without installing the app or having an
/// account in it — see RootCLI/README.md for how the key is provisioned and
/// why write access to UserIdentity should be restricted to this key alone.
///
/// Protocol reference: Apple's "CloudKit Web Services Reference", Server-to-Server
/// authentication. Every request is signed by concatenating
/// `date : base64(SHA256(body)) : path` and ECDSA-signing that string with the
/// registered private key; CryptoKit's `signature(for:)` already does the
/// SHA-256-then-sign step internally, so we hand it the raw message string.
final class CloudKitS2SClient {
    private let config: Config
    private let privateKey: P256.Signing.PrivateKey
    private let host = "https://api.apple-cloudkit.com"

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(config: Config) throws {
        self.config = config
        let pem: String
        do {
            pem = try String(contentsOf: URL(fileURLWithPath: config.privateKeyPath), encoding: .utf8)
        } catch {
            throw CLIError.message("Could not read private key at \(config.privateKeyPath): \(error)")
        }
        do {
            self.privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw CLIError.message("""
                Could not parse the private key at \(config.privateKeyPath) as a PKCS8 PEM P-256 key: \(error)
                If this key came straight from `openssl ecparam -genkey`, convert it first:
                  openssl pkcs8 -topk8 -nocrypt -in original.pem -out pkcs8.pem
                """)
        }
    }

    private func requestPath(for endpoint: String) -> String {
        "/database/1/\(config.containerID)/\(config.environment)/public/\(endpoint)"
    }

    private func send(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        let path = requestPath(for: endpoint)
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let date = dateFormatter.string(from: Date())
        let bodyHashBase64 = Data(SHA256.hash(data: bodyData)).base64EncodedString()
        let message = "\(date):\(bodyHashBase64):\(path)"
        guard let messageData = message.data(using: .utf8) else {
            throw CLIError.message("Could not encode the request signature message.")
        }
        let signatureBase64: String
        do {
            signatureBase64 = try privateKey.signature(for: messageData).derRepresentation.base64EncodedString()
        } catch {
            throw CLIError.message("Failed to sign request: \(error)")
        }

        var request = URLRequest(url: URL(string: host + path)!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.keyID, forHTTPHeaderField: "X-Apple-CloudKit-Request-KeyID")
        request.setValue(date, forHTTPHeaderField: "X-Apple-CloudKit-Request-ISO8601Date")
        request.setValue(signatureBase64, forHTTPHeaderField: "X-Apple-CloudKit-Request-SignatureV1")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIError.message("No HTTP response from CloudKit.")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let reason = (json["reason"] as? String) ?? String(data: data, encoding: .utf8) ?? "unknown error"
            throw CLIError.message("CloudKit request to \(endpoint) failed (HTTP \(http.statusCode)): \(reason)")
        }
        return json
    }

    func queryRecords(recordType: String) async throws -> [CKRecordDTO] {
        let body: [String: Any] = ["query": ["recordType": recordType]]
        let json = try await send(endpoint: "records/query", body: body)
        let records = json["records"] as? [[String: Any]] ?? []
        return records.compactMap(CKRecordDTO.init)
    }

    /// Matches by record id, username, or full name (firstName + lastName,
    /// case-insensitively). Errors out on zero or multiple matches rather
    /// than guessing.
    func findUser(matching identifier: String) async throws -> CKRecordDTO {
        let users = try await queryRecords(recordType: "UserIdentity")
        let needle = identifier.lowercased()
        let matches = users.filter { user in
            let fullName = [user.stringField("firstName") ?? "", user.stringField("lastName") ?? ""]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return user.recordName.lowercased() == needle ||
                user.stringField("username")?.lowercased() == needle ||
                fullName.lowercased() == needle
        }
        guard let match = matches.first else {
            throw CLIError.message("No UserIdentity found matching '\(identifier)'. Run `rootcli list` to see known accounts.")
        }
        guard matches.count == 1 else {
            throw CLIError.message("'\(identifier)' matched \(matches.count) accounts; re-run with the exact record id shown by `rootcli list`.")
        }
        return match
    }

    @discardableResult
    func updateRecord(_ record: CKRecordDTO, fields: [String: Any]) async throws -> [String: Any] {
        let body: [String: Any] = [
            "operations": [[
                "operationType": "update",
                "record": [
                    "recordName": record.recordName,
                    "recordType": record.recordType,
                    "recordChangeTag": record.changeTag,
                    "fields": fields
                ] as [String: Any]
            ]]
        ]
        return try await send(endpoint: "records/modify", body: body)
    }

    /// Creates a record at `recordName`, or unconditionally overwrites it if one
    /// already exists there — no recordChangeTag needed, unlike `updateRecord`.
    /// Used for batch imports, where re-running the same file should just apply
    /// the current data rather than fail on a stale change tag. Matches the app's
    /// own push semantics (CloudKitSync's `save(_:)` doesn't check for conflicts
    /// either), so this stays consistent with what the app itself would do.
    @discardableResult
    func createOrReplaceRecord(recordType: String, recordName: String, fields: [String: Any]) async throws -> [String: Any] {
        let body: [String: Any] = [
            "operations": [[
                "operationType": "forceReplace",
                "record": [
                    "recordName": recordName,
                    "recordType": recordType,
                    "fields": fields
                ] as [String: Any]
            ]]
        ]
        return try await send(endpoint: "records/modify", body: body)
    }
}
