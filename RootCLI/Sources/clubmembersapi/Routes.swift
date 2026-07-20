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
}

private func validate(_ input: ClubMemberInput) throws {
    guard !input.firstName.trimmingCharacters(in: .whitespaces).isEmpty,
          !input.lastName.trimmingCharacters(in: .whitespaces).isEmpty else {
        throw Abort(.badRequest, reason: "firstName and lastName are required.")
    }
}
