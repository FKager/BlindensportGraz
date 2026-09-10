import Vapor
import CloudKitS2SCore

/// `GET /calendar/:token[.ics]` — one user's read-only webcal feed
/// (architecture-review.md §5 P2). Deliberately registered outside the
/// Basic Auth gate `Configure.swift` applies to everything else — see
/// `Auth.swift`'s `RequireAPIUserExceptCalendarFeed` for why, and
/// `CalendarFeed.swift`'s doc comment for the token-as-credential reasoning.
///
/// `:token` may or may not carry a literal ".ics" suffix in the URL — some
/// calendar clients care about the extension for content-type sniffing, so
/// AccountView's generated URL includes one; the route strips it before
/// looking the token up, so both forms work.
func calendarFeedRoutes(_ app: RoutesBuilder, client: CloudKitS2SClient) {
    app.get("calendar", ":token") { req async throws -> Response in
        let raw = try req.parameters.require("token")
        let token = raw.hasSuffix(".ics") ? String(raw.dropLast(4)) : raw
        guard !token.isEmpty else { throw Abort(.notFound) }

        let users = try await client.queryRecords(recordType: "UserIdentity")
        guard let user = users.first(where: { $0.stringField("calendarToken") == token }) else {
            // Deliberately the same 404 shape as an unknown path — doesn't
            // hint at whether a token ever existed.
            throw Abort(.notFound)
        }
        let role = user.stringField("role") ?? "member"

        var userTeamIDs: Set<String> = []
        if role != "admin" {
            let memberships = try await client.queryRecords(recordType: "TeamMembership")
            userTeamIDs = Set(memberships
                .filter { $0.stringField("userID") == user.recordName }
                .compactMap { $0.stringField("teamID") })
        }

        async let trainingRecords = client.queryRecords(recordType: "Training")
        async let tournamentRecords = client.queryRecords(recordType: "Tournament")
        let allRecords = try await trainingRecords + tournamentRecords

        let events = allRecords.compactMap { dto -> CalendarFeed.EventFields? in
            guard let title = dto.stringField("title"),
                  let start = dto.dateField("startDate"),
                  let end = dto.dateField("endDate") else { return nil }
            return CalendarFeed.EventFields(
                uid: dto.recordName, title: title, location: dto.stringField("location") ?? "",
                startDate: start, endDate: end, teamIDs: dto.stringListField("teamIDs")
            )
        }

        let visible = CalendarFeed.visibleEvents(events, role: role, userTeamIDs: userTeamIDs)
        let ics = CalendarFeed.render(visible)

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/calendar; charset=utf-8")
        headers.add(name: .contentDisposition, value: "inline; filename=\"blindensportgraz.ics\"")
        return Response(status: .ok, headers: headers, body: .init(string: ics))
    }
}
