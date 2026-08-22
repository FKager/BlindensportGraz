import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // URLSession/URLRequest live here on Linux/Windows, not in Foundation itself.
#endif
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto // swift-crypto: API-compatible drop-in for CryptoKit on non-Apple platforms.
#endif

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
public final class CloudKitS2SClient {
    private let config: Config
    private let privateKey: P256.Signing.PrivateKey
    private let host = "https://api.apple-cloudkit.com"

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public init(config: Config) throws {
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

    public func queryRecords(recordType: String) async throws -> [CKRecordDTO] {
        let body: [String: Any] = ["query": ["recordType": recordType]]
        let json = try await send(endpoint: "records/query", body: body)
        let records = json["records"] as? [[String: Any]] ?? []
        return records.compactMap(CKRecordDTO.init)
    }

    /// Fetches a single record by its exact record name (id). More targeted
    /// than `queryRecords` + filter — used wherever the caller already knows
    /// the id, e.g. GET/PUT/DELETE /api/members/:id. Returns nil if no record
    /// exists at that name (CloudKit's lookup endpoint reports a per-record
    /// "NOT_FOUND" error object instead of the full record in that case,
    /// which simply fails `CKRecordDTO.init`'s required-fields check).
    public func lookupRecord(recordType: String, recordName: String) async throws -> CKRecordDTO? {
        let body: [String: Any] = ["records": [["recordName": recordName]]]
        let json = try await send(endpoint: "records/lookup", body: body)
        let records = json["records"] as? [[String: Any]] ?? []
        return records.first.flatMap(CKRecordDTO.init)
    }

    /// Matches by record id or full name (firstName + lastName,
    /// case-insensitively). Errors out on zero or multiple matches rather
    /// than guessing.
    public func findUser(matching identifier: String) async throws -> CKRecordDTO {
        let users = try await queryRecords(recordType: "UserIdentity")
        let needle = identifier.lowercased()
        let matches = users.filter { user in
            let fullName = [user.stringField("firstName") ?? "", user.stringField("lastName") ?? ""]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return user.recordName.lowercased() == needle ||
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
    public func updateRecord(_ record: CKRecordDTO, fields: [String: Any]) async throws -> [String: Any] {
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
        let json = try await send(endpoint: "records/modify", body: body)
        try checkModifyResult(json, endpoint: "records/modify")
        return json
    }

    /// Creates a record at `recordName`, or unconditionally overwrites it if one
    /// already exists there — no recordChangeTag needed, unlike `updateRecord`.
    /// Used for batch imports, where re-running the same file should just apply
    /// the current data rather than fail on a stale change tag. Matches the app's
    /// own push semantics (CloudKitSync's `save(_:)` doesn't check for conflicts
    /// either), so this stays consistent with what the app itself would do.
    @discardableResult
    public func createOrReplaceRecord(recordType: String, recordName: String, fields: [String: Any]) async throws -> [String: Any] {
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
        let json = try await send(endpoint: "records/modify", body: body)
        try checkModifyResult(json, endpoint: "records/modify")
        return json
    }

    /// Uploads a local file as a CKAsset for `fieldName` on `recordType`,
    /// returning the raw "singleFile" dict CloudKit's asset-upload response
    /// contains — embed that directly as `["value": <this>, "type":
    /// "ASSETID"]` in a subsequent `createOrReplaceRecord`/`updateRecord`
    /// call's fields dict. Two-step per Apple's CloudKit Web Services
    /// Reference ("Uploading Assets"): `assets/upload` (a normal signed S2S
    /// request, like every other endpoint here) returns a short-lived,
    /// pre-authorized upload URL; the file bytes are then POSTed directly
    /// to THAT url — not through `send()`, since asset-upload URLs are
    /// already pre-authorized and don't use/expect S2S request signing.
    public func uploadAsset(recordType: String, fieldName: String, fileURL: URL) async throws -> [String: Any] {
        let tokenBody: [String: Any] = [
            "tokens": [["recordType": recordType, "fieldName": fieldName]]
        ]
        let tokenJSON = try await send(endpoint: "assets/upload", body: tokenBody)
        guard let tokens = tokenJSON["tokens"] as? [[String: Any]], let token = tokens.first,
              let urlString = token["url"] as? String, let uploadURL = URL(string: urlString) else {
            throw CLIError.message("CloudKit assets/upload did not return an upload URL: \(tokenJSON)")
        }

        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw CLIError.message("Could not read asset file at \(fileURL.path): \(error)")
        }

        // The pre-authorized upload URL expects a multipart/form-data body
        // (a raw-bytes POST body returns "Bad Request", confirmed live) —
        // one "files" part carrying the asset's bytes.
        let boundary = "----RootCLIAssetUpload-\(UUID().uuidString)"
        var multipartBody = Data()
        multipartBody.append("--\(boundary)\r\n".data(using: .utf8)!)
        multipartBody.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        multipartBody.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        multipartBody.append(fileData)
        multipartBody.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = multipartBody
        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
        guard let http = uploadResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: uploadData, encoding: .utf8) ?? "unknown error"
            throw CLIError.message("Asset upload to CloudKit failed: \(body)")
        }
        let uploadJSON = (try? JSONSerialization.jsonObject(with: uploadData)) as? [String: Any] ?? [:]
        guard let singleFile = uploadJSON["singleFile"] as? [String: Any] else {
            throw CLIError.message("Asset upload response missing 'singleFile': \(uploadJSON)")
        }
        return singleFile
    }

    /// Deletes unconditionally (no recordChangeTag check), matching this
    /// file's other "operator tooling doesn't need optimistic-concurrency
    /// safety" conventions above.
    @discardableResult
    public func deleteRecord(recordType: String, recordName: String) async throws -> [String: Any] {
        let body: [String: Any] = [
            "operations": [[
                "operationType": "forceDelete",
                "record": [
                    "recordName": recordName,
                    "recordType": recordType
                ] as [String: Any]
            ]]
        ]
        let json = try await send(endpoint: "records/modify", body: body)
        try checkModifyResult(json, endpoint: "records/modify")
        return json
    }

    /// `records/modify` returns HTTP 200 for the whole batch call even when
    /// an individual operation inside it failed — CloudKit reports
    /// per-operation failures as a "serverErrorCode"/"reason" pair embedded
    /// in that record's entry in the response's "records" array, not as a
    /// non-2xx HTTP status. `send()` itself stays tolerant of per-record
    /// errors (query/lookup legitimately use a per-record NOT_FOUND as
    /// normal, expected data — see `lookupRecord`'s doc comment — not a
    /// failure to surface), so every write path checks explicitly instead.
    /// Found live: `rootcli set-role`'s RoleChangeLog write was silently
    /// no-oping whenever the record type didn't exist yet in schema,
    /// because nothing checked for this — the "Warning: ... write failed"
    /// message right above this call site never actually printed.
    private func checkModifyResult(_ json: [String: Any], endpoint: String) throws {
        let records = json["records"] as? [[String: Any]] ?? []
        for record in records {
            guard let errorCode = record["serverErrorCode"] as? String else { continue }
            let reason = (record["reason"] as? String) ?? "no reason given"
            let recordName = (record["recordName"] as? String) ?? "unknown record"
            throw CLIError.message("CloudKit \(endpoint) failed for record '\(recordName)': \(errorCode) — \(reason)")
        }
    }
}
