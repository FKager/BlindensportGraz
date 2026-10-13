import Vapor
import CloudKitS2SCore

// `MemberRecord` is a typealias for `ClubSchema.ClubMemberRecord` (Phase 9) —
// this conformance is only ever added here, but the compiler can't see that
// across module boundaries, hence `@retroactive`.
extension MemberRecord: @retroactive Content {}

/// Body shape for POST/PUT — same fields as `MemberRecord` minus `id`
/// (assigned server-side on create, taken from the URL path on update).
struct MemberInput: Content {
    var firstName: String
    var lastName: String
    var street: String?
    var zip: String?
    var city: String?
    var country: String?
    var email: String?
    var phone: String?
    var memberNumber: String?
    var joinedAt: Date?
    var notes: String?
    var gender: String?
    var title: String?
    var birthDate: Date?
    var sportId: String?
    var svnr: String?
    var iban: String?
    var lastMedicalExamination: Date?
    var defaultFunction: String?
    var memberOfGVSC: Bool?
}

struct APIErrorBody: Content {
    var error: String
}

/// Permissions (app_permission values, same as the app):
///   members.manage        — read/create/edit/delete roster entries
///   members.private.read  — see svnr, iban, birthDate, lastMedicalExamination
///   members.private.write — change them (stored in Supabase, never CloudKit)
///   club.manage           — the generic /api/records tool
func routes(_ app: Application, client: CloudKitS2SClient, privateStore: MemberPrivateStore) throws {
    let api = app.grouped("api", "members")

    api.get { req async throws -> [MemberRecord] in
        let admin = try req.admin()
        try admin.require("members.manage")
        let records = try await client.queryRecords(recordType: "ClubMember").compactMap(MemberRecord.init(dto:))
        let privateData = admin.permissions.contains("members.private.read") ? try await privateStore.all() : [:]
        return records
            .map { record in
                var record = record
                record.privateData = privateData[record.id.uppercased()] ?? MemberPrivate()
                return record
            }
            .sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
    }

    api.get(":id") { req async throws -> MemberRecord in
        let admin = try req.admin()
        try admin.require("members.manage")
        let id = try req.parameters.require("id")
        guard let dto = try await client.lookupRecord(recordType: "ClubMember", recordName: id),
              var record = MemberRecord(dto: dto) else {
            throw Abort(.notFound, reason: "No member with id \(id).")
        }
        record.privateData = admin.permissions.contains("members.private.read")
            ? try await privateStore.get(memberID: id) ?? MemberPrivate() : MemberPrivate()
        return record
    }

    api.post { req async throws -> Response in
        let admin = try req.admin()
        try admin.require("members.manage")
        let input = try req.content.decode(MemberInput.self)
        try validate(input)
        if input.carriesPrivateData { try admin.require("members.private.write") }
        let record = MemberRecord(
            firstName: input.firstName.trimmingCharacters(in: .whitespaces),
            lastName: input.lastName.trimmingCharacters(in: .whitespaces),
            street: input.street ?? "",
            zip: input.zip ?? "",
            city: input.city ?? "",
            country: input.country ?? "",
            email: input.email ?? "",
            phone: input.phone ?? "",
            memberNumber: input.memberNumber ?? "",
            joinedAt: input.joinedAt ?? Date(),
            notes: input.notes ?? "",
            gender: input.gender ?? "",
            title: input.title ?? "",
            birthDate: input.birthDate,
            sportId: input.sportId ?? "",
            svnr: input.svnr ?? "",
            iban: input.iban ?? "",
            lastMedicalExamination: input.lastMedicalExamination,
            defaultFunction: input.defaultFunction ?? "",
            memberOfGVSC: input.memberOfGVSC ?? true
        )
        try await client.createOrReplaceRecord(recordType: "ClubMember", recordName: record.id, fields: record.ckFields)
        if !record.privateData.isEmpty {
            try await privateStore.save(memberID: record.id, record.privateData, updatedBy: admin.id)
        }
        let response = try await record.encodeResponse(status: .created, for: req)
        return response
    }

    api.put(":id") { req async throws -> MemberRecord in
        let admin = try req.admin()
        try admin.require("members.manage")
        let id = try req.parameters.require("id")
        guard let existingDTO = try await client.lookupRecord(recordType: "ClubMember", recordName: id) else {
            throw Abort(.notFound, reason: "No member with id \(id).")
        }
        let input = try req.content.decode(MemberInput.self)
        try validate(input)
        if input.carriesPrivateData { try admin.require("members.private.write") }
        // Protected fields come from Supabase; an omitted field keeps its
        // stored value, like every other field here.
        var existingRecord = MemberRecord(dto: existingDTO)
        let existingPrivate = input.carriesPrivateData ? try await privateStore.get(memberID: id) : nil
        if let existingPrivate { existingRecord?.privateData = existingPrivate }
        var record = MemberRecord(
            id: id,
            firstName: input.firstName.trimmingCharacters(in: .whitespaces),
            lastName: input.lastName.trimmingCharacters(in: .whitespaces),
            street: input.street ?? "",
            zip: input.zip ?? "",
            city: input.city ?? "",
            country: input.country ?? "",
            email: input.email ?? "",
            phone: input.phone ?? "",
            memberNumber: input.memberNumber ?? "",
            joinedAt: input.joinedAt ?? existingRecord?.joinedAt ?? Date(),
            notes: input.notes ?? "",
            gender: input.gender ?? existingRecord?.gender ?? "",
            title: input.title ?? existingRecord?.title ?? "",
            birthDate: input.birthDate ?? existingRecord?.birthDate,
            sportId: input.sportId ?? existingRecord?.sportId ?? "",
            svnr: input.svnr ?? existingRecord?.svnr ?? "",
            iban: input.iban ?? existingRecord?.iban ?? "",
            lastMedicalExamination: input.lastMedicalExamination ?? existingRecord?.lastMedicalExamination,
            defaultFunction: input.defaultFunction ?? existingRecord?.defaultFunction ?? "",
            memberOfGVSC: input.memberOfGVSC ?? existingRecord?.memberOfGVSC ?? true
        )
        try await client.updateRecord(existingDTO, fields: record.ckFields)
        if input.carriesPrivateData, record.privateData != (existingPrivate ?? MemberPrivate()) {
            try await privateStore.save(memberID: id, record.privateData, updatedBy: admin.id)
        }
        if !admin.permissions.contains("members.private.read") {
            record.privateData = MemberPrivate()
        } else if !input.carriesPrivateData {
            record.privateData = try await privateStore.get(memberID: id) ?? MemberPrivate()
        }
        return record
    }

    api.delete(":id") { req async throws -> HTTPStatus in
        try req.admin().require("members.manage")
        let id = try req.parameters.require("id")
        guard try await client.lookupRecord(recordType: "ClubMember", recordName: id) != nil else {
            throw Abort(.notFound, reason: "No member with id \(id).")
        }
        try await client.deleteRecord(recordType: "ClubMember", recordName: id)
        // No orphaned protected data for a member that no longer exists.
        try await privateStore.delete(memberID: id)
        return .noContent
    }

    /// Bulk create-or-update from a JSON array — the same shape the app's own
    /// export produces and `rootcli import-members` reads, so a roster file
    /// can be posted straight from `curl` without any per-record scripting.
    /// Shares its per-row logic (skip-invalid-rows-not-whole-batch, id/UUID
    /// handling) with `rootcli import-members` via `MemberBulkImport`
    /// rather than reimplementing it a third time.
    api.post("import") { req async throws -> Response in
        let admin = try req.admin()
        try admin.require("members.manage")
        guard let buffer = req.body.data else {
            throw Abort(.badRequest, reason: "Body must be a JSON array of members.")
        }
        let inputs: [MemberBulkInput]
        do {
            inputs = try JSONDecoder().decode([MemberBulkInput].self, from: Data(buffer: buffer))
        } catch {
            throw Abort(.badRequest, reason: "Body must be a JSON array of members: \(error)")
        }
        if inputs.contains(where: { !$0.privateData.isEmpty }) { try admin.require("members.private.write") }
        let result = await MemberBulkImport.run(inputs, client: client, privateStore: privateStore,
                                                updatedBy: admin.id)
        let body: [String: Any] = [
            "succeeded": result.succeeded,
            "failed": result.failed,
            "total": result.total,
            "messages": result.messages
        ]
        return try jsonResponse(body)
    }

    // MARK: - Generic records (any type, not just Member)
    //
    // The routes above give Member a typed, validated form because it's
    // this app's one deliberately-modeled record type (see MemberRecord).
    // Hand-writing that same typed layer for Team/SportEvent/Training/
    // Tournament/TeamMembership/EventParticipation/Attendance/UserIdentity
    // would be ten times the boilerplate for no real validation benefit on an
    // internal admin tool — so these routes work against raw record types and
    // fields via CKFieldCoding instead, covering every model in one place.
    // Raw access to every record type: club.manage (admin/root) only.
    let records = app.grouped("api", "records").grouped(RequirePermission("club.manage"))

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
        do {
            try CloudKitWriteGuard.check(recordType: type, fieldNames: payload.keys)
        } catch {
            throw Abort(.badRequest, reason: "\(error)")
        }
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

/// Route-group middleware for a single permission.
struct RequirePermission: AsyncMiddleware {
    let permission: String

    init(_ permission: String) { self.permission = permission }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        try request.admin().require(permission)
        return try await next.respond(to: request)
    }
}

extension MemberInput {
    /// True if the body sets any protected field (an empty string counts —
    /// it clears the stored value).
    var carriesPrivateData: Bool {
        svnr != nil || iban != nil || birthDate != nil || lastMedicalExamination != nil
    }
}

private func validate(_ input: MemberInput) throws {
    guard !input.firstName.trimmingCharacters(in: .whitespaces).isEmpty,
          !input.lastName.trimmingCharacters(in: .whitespaces).isEmpty else {
        throw Abort(.badRequest, reason: "firstName and lastName are required.")
    }
}
