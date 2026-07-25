import Vapor
import CloudKitS2SCore

extension ClubMemberRecord: Content {}

/// Body shape for POST/PUT — same fields as `ClubMemberRecord` minus `id`
/// (assigned server-side on create, taken from the URL path on update).
struct ClubMemberInput: Content {
    var firstName: String
    var lastName: String
    var street: String?
    var zip: String?
    var city: String?
    var email: String?
    var phone: String?
    var memberNumber: String?
    var joinedAt: Date?
    var notes: String?
}

struct APIErrorBody: Content {
    var error: String
}

func routes(_ app: Application, client: CloudKitS2SClient) throws {
    let api = app.grouped("api", "members")

    api.get { req async throws -> [ClubMemberRecord] in
        let records = try await client.queryRecords(recordType: "ClubMember")
        return records.compactMap(ClubMemberRecord.init(dto:))
            .sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
    }

    api.get(":id") { req async throws -> ClubMemberRecord in
        let id = try req.parameters.require("id")
        guard let dto = try await client.lookupRecord(recordType: "ClubMember", recordName: id),
              let record = ClubMemberRecord(dto: dto) else {
            throw Abort(.notFound, reason: "No club member with id \(id).")
        }
        return record
    }

    api.post { req async throws -> Response in
        let input = try req.content.decode(ClubMemberInput.self)
        try validate(input)
        let record = ClubMemberRecord(
            firstName: input.firstName.trimmingCharacters(in: .whitespaces),
            lastName: input.lastName.trimmingCharacters(in: .whitespaces),
            street: input.street ?? "",
            zip: input.zip ?? "",
            city: input.city ?? "",
            email: input.email ?? "",
            phone: input.phone ?? "",
            memberNumber: input.memberNumber ?? "",
            joinedAt: input.joinedAt ?? Date(),
            notes: input.notes ?? ""
        )
        try await client.createOrReplaceRecord(recordType: "ClubMember", recordName: record.id, fields: record.ckFields)
        let response = try await record.encodeResponse(status: .created, for: req)
        return response
    }

    api.put(":id") { req async throws -> ClubMemberRecord in
        let id = try req.parameters.require("id")
        guard let existingDTO = try await client.lookupRecord(recordType: "ClubMember", recordName: id) else {
            throw Abort(.notFound, reason: "No club member with id \(id).")
        }
        let input = try req.content.decode(ClubMemberInput.self)
        try validate(input)
        let record = ClubMemberRecord(
            id: id,
            firstName: input.firstName.trimmingCharacters(in: .whitespaces),
            lastName: input.lastName.trimmingCharacters(in: .whitespaces),
            street: input.street ?? "",
            zip: input.zip ?? "",
            city: input.city ?? "",
            email: input.email ?? "",
            phone: input.phone ?? "",
            memberNumber: input.memberNumber ?? "",
            joinedAt: input.joinedAt ?? ClubMemberRecord(dto: existingDTO)?.joinedAt ?? Date(),
            notes: input.notes ?? ""
        )
        try await client.updateRecord(existingDTO, fields: record.ckFields)
        return record
    }

    api.delete(":id") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id")
        guard try await client.lookupRecord(recordType: "ClubMember", recordName: id) != nil else {
            throw Abort(.notFound, reason: "No club member with id \(id).")
        }
        try await client.deleteRecord(recordType: "ClubMember", recordName: id)
        return .noContent
    }

    /// Bulk create-or-update from a JSON array — the same shape the app's own
    /// export produces and `rootcli import-members` reads, so a roster file
    /// can be posted straight from `curl` without any per-record scripting.
    /// Shares its per-row logic (skip-invalid-rows-not-whole-batch, id/UUID
    /// handling) with `rootcli import-members` via `ClubMemberBulkImport`
    /// rather than reimplementing it a third time.
    api.post("import") { req async throws -> Response in
        guard let buffer = req.body.data else {
            throw Abort(.badRequest, reason: "Body must be a JSON array of club members.")
        }
        let inputs: [ClubMemberBulkInput]
        do {
            inputs = try JSONDecoder().decode([ClubMemberBulkInput].self, from: Data(buffer: buffer))
        } catch {
            throw Abort(.badRequest, reason: "Body must be a JSON array of club members: \(error)")
        }
        let result = await ClubMemberBulkImport.run(inputs, client: client)
        let body: [String: Any] = [
            "succeeded": result.succeeded,
            "failed": result.failed,
            "total": result.total,
            "messages": result.messages
        ]
        return try jsonResponse(body)
    }

    // MARK: - Generic records (any type, not just ClubMember)
    //
    // The routes above give ClubMember a typed, validated form because it's
    // this app's one deliberately-modeled record type (see ClubMemberRecord).
    // Hand-writing that same typed layer for Team/SportEvent/Training/
    // Tournament/TeamMembership/EventParticipation/Attendance/UserIdentity
    // would be ten times the boilerplate for no real validation benefit on an
    // internal admin tool — so these routes work against raw record types and
    // fields via CKFieldCoding instead, covering every model in one place.
    let records = app.grouped("api", "records")

    records.get(":type") { req async throws -> Response in
        let type = try req.parameters.require("type")
        let dtos = try await client.queryRecords(recordType: type)
        let list = dtos.map { dto -> [String: Any] in
            var obj: [String: Any] = ["id": dto.recordName]
            for (key, value) in CKFieldCoding.decode(dto.fields) { obj[key] = value }
            return obj
        }
        return try jsonResponse(list)
    }

    records.get(":type", ":id") { req async throws -> Response in
        let type = try req.parameters.require("type")
        let id = try req.parameters.require("id")
        guard let dto = try await client.lookupRecord(recordType: type, recordName: id) else {
            throw Abort(.notFound, reason: "No \(type) record with id \(id).")
        }
        var obj: [String: Any] = ["id": dto.recordName]
        for (key, value) in CKFieldCoding.decode(dto.fields) { obj[key] = value }
        return try jsonResponse(obj)
    }

    /// Insert-or-update: always upserts via `createOrReplaceRecord`, whether
    /// or not `id` already exists — this is the generic "easier way to insert
    /// or update data" the admin tooling was extended for, so it deliberately
    /// doesn't require a prior GET/change-tag round trip the way `updateRecord`
    /// (used by /api/members) does.
    records.put(":type", ":id") { req async throws -> Response in
        let type = try req.parameters.require("type")
        let id = try req.parameters.require("id")
        guard let buffer = req.body.data,
              let json = try? JSONSerialization.jsonObject(with: Data(buffer: buffer)) as? [String: Any] else {
            throw Abort(.badRequest, reason: "Body must be a JSON object of field: value pairs.")
        }
        var payload = json
        payload.removeValue(forKey: "id") // "id" is the record name (URL path), not a CKRecord field.
        let fields = payload.reduce(into: [String: Any]()) { acc, pair in
            acc[pair.key] = CKFieldCoding.encode(pair.value)
        }
        try await client.createOrReplaceRecord(recordType: type, recordName: id, fields: fields)
        var obj = payload
        obj["id"] = id
        return try jsonResponse(obj)
    }

    records.delete(":type", ":id") { req async throws -> HTTPStatus in
        let type = try req.parameters.require("type")
        let id = try req.parameters.require("id")
        guard try await client.lookupRecord(recordType: type, recordName: id) != nil else {
            throw Abort(.notFound, reason: "No \(type) record with id \(id).")
        }
        try await client.deleteRecord(recordType: type, recordName: id)
        return .noContent
    }
}

private func jsonResponse(_ object: Any) throws -> Response {
    let data = try JSONSerialization.data(withJSONObject: object)
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/json")
    return Response(status: .ok, headers: headers, body: .init(data: data))
}

private func validate(_ input: ClubMemberInput) throws {
    guard !input.firstName.trimmingCharacters(in: .whitespaces).isEmpty,
          !input.lastName.trimmingCharacters(in: .whitespaces).isEmpty else {
        throw Abort(.badRequest, reason: "firstName and lastName are required.")
    }
}
