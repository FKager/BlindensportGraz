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
///   members.private.write — change them
func routes(_ app: Application, store: MemberStore) throws {
    let api = app.grouped("api", "members")

    api.get { req async throws -> [MemberRecord] in
        let admin = try req.admin()
        try admin.require("members.manage")
        return try await store.all(includePrivate: admin.permissions.contains("members.private.read"))
    }

    api.get(":id") { req async throws -> MemberRecord in
        let admin = try req.admin()
        try admin.require("members.manage")
        let id = try req.parameters.require("id")
        guard let record = try await store.get(id: id,
                                               includePrivate: admin.permissions.contains("members.private.read")) else {
            throw Abort(.notFound, reason: "No member with id \(id).")
        }
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
        try await store.save(record, writePrivate: !record.privateData.isEmpty, updatedBy: admin.id)
        let response = try await record.encodeResponse(status: .created, for: req)
        return response
    }

    api.put(":id") { req async throws -> MemberRecord in
        let admin = try req.admin()
        try admin.require("members.manage")
        let id = try req.parameters.require("id")
        let input = try req.content.decode(MemberInput.self)
        try validate(input)
        // Protected fields come from Supabase; an omitted field keeps its
        // stored value, like every other field here. The two dates can't be
        // cleared with "" like svnr/iban, so an explicit JSON null clears them.
        let clearedDates = nullKeys(in: req).intersection(["birthDate", "lastMedicalExamination"])
        let touchesPrivate = input.carriesPrivateData || !clearedDates.isEmpty
        if touchesPrivate { try admin.require("members.private.write") }
        guard let existingRecord = try await store.get(id: id, includePrivate: touchesPrivate) else {
            throw Abort(.notFound, reason: "No member with id \(id).")
        }
        var record = MemberRecord(
            id: existingRecord.id,
            firstName: input.firstName.trimmingCharacters(in: .whitespaces),
            lastName: input.lastName.trimmingCharacters(in: .whitespaces),
            street: input.street ?? "",
            zip: input.zip ?? "",
            city: input.city ?? "",
            country: input.country ?? "",
            email: input.email ?? "",
            phone: input.phone ?? "",
            memberNumber: input.memberNumber ?? "",
            joinedAt: input.joinedAt ?? existingRecord.joinedAt ?? Date(),
            notes: input.notes ?? "",
            gender: input.gender ?? existingRecord.gender ?? "",
            title: input.title ?? existingRecord.title ?? "",
            birthDate: clearedDates.contains("birthDate") ? nil : input.birthDate ?? existingRecord.birthDate,
            sportId: input.sportId ?? existingRecord.sportId ?? "",
            svnr: input.svnr ?? existingRecord.svnr ?? "",
            iban: input.iban ?? existingRecord.iban ?? "",
            lastMedicalExamination: clearedDates.contains("lastMedicalExamination")
                ? nil : input.lastMedicalExamination ?? existingRecord.lastMedicalExamination,
            defaultFunction: input.defaultFunction ?? existingRecord.defaultFunction ?? "",
            memberOfGVSC: input.memberOfGVSC ?? existingRecord.memberOfGVSC ?? true
        )
        let privateChanged = touchesPrivate && record.privateData != existingRecord.privateData
        try await store.save(record, writePrivate: privateChanged, updatedBy: admin.id)
        if !admin.permissions.contains("members.private.read") {
            record.privateData = MemberPrivate()
        } else if !touchesPrivate {
            record.privateData = try await store.privateStore.get(memberID: id) ?? MemberPrivate()
        }
        return record
    }

    api.delete(":id") { req async throws -> HTTPStatus in
        try req.admin().require("members.manage")
        let id = try req.parameters.require("id")
        guard try await store.get(id: id, includePrivate: false) != nil else {
            throw Abort(.notFound, reason: "No member with id \(id).")
        }
        try await store.delete(id: id)
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
        let result = await MemberBulkImport.run(inputs, store: store, updatedBy: admin.id)
        let body: [String: Any] = [
            "succeeded": result.succeeded,
            "failed": result.failed,
            "total": result.total,
            "messages": result.messages
        ]
        return try jsonResponse(body)
    }
}

/// Keys the JSON body sets to null. Codable decodes those the same as an
/// omitted key, but for the protected dates null means "clear it".
private func nullKeys(in req: Request) -> Set<String> {
    guard let buffer = req.body.data,
          let json = try? JSONSerialization.jsonObject(with: Data(buffer: buffer)) as? [String: Any] else {
        return []
    }
    return Set(json.filter { $0.value is NSNull }.keys)
}

private func jsonResponse(_ object: Any) throws -> Response {
    let data = try JSONSerialization.data(withJSONObject: object)
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/json")
    return Response(status: .ok, headers: headers, body: .init(data: data))
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
