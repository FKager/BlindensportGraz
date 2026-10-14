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
func calendarFeedRoutes(_ app: RoutesBuilder, supabase: SupabaseAdminClient) {
    app.get("calendar", ":token") { req async throws -> Response in
        let raw = try req.parameters.require("token")
        let token = raw.hasSuffix(".ics") ? String(raw.dropLast(4)) : raw
        // Tokens are hex (profiles.calendar_token / legacy UUIDs); anything
        // else can't match and must not reach the PostgREST filter.
        guard !token.isEmpty, token.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { throw Abort(.notFound) }

        let profiles = try await supabase.select(table: "profiles", columns: "id",
                                                 filters: [("calendar_token", "eq.\(token)")])
        guard let userID = profiles.first?["id"] as? String else {
            // Deliberately the same 404 shape as an unknown path — doesn't
            // hint at whether a token ever existed.
            throw Abort(.notFound)
        }
        let roles = try await supabase.select(table: "user_roles", columns: "role",
                                              filters: [("user_id", "eq.\(userID)")])
        let storedRole = roles.first?["role"] as? String ?? "member"
        // CalendarFeed knows member/coach/admin; root sees everything too.
        let role = storedRole == "root" ? "admin" : storedRole
        var userTeamIDs: Set<String> = []
        if role != "admin" {
            let memberships = try await supabase.select(table: "team_memberships", columns: "team_id",
                                                        filters: [("user_id", "eq.\(userID)")])
            userTeamIDs = Set(memberships.compactMap { ($0["team_id"] as? String)?.lowercased() })
        }

        let rows = try await supabase.select(table: "events",
                                             columns: "id,title,location,start_date,end_date,team_ids",
                                             filters: [("kind", "in.(training,tournament)")])
        let events = rows.compactMap { row -> CalendarFeed.EventFields? in
            guard let id = row["id"] as? String, let title = row["title"] as? String,
                  let start = (row["start_date"] as? String).flatMap(SupabaseTimestamp.parse),
                  let end = (row["end_date"] as? String).flatMap(SupabaseTimestamp.parse) else { return nil }
            // UIDs stay the uppercase ids the CloudKit-era feed used, so
            // subscribed calendars keep their entries across the move.
            return CalendarFeed.EventFields(
                uid: id.uppercased(), title: title, location: row["location"] as? String ?? "",
                startDate: start, endDate: end,
                teamIDs: (row["team_ids"] as? [String] ?? []).map { $0.lowercased() }
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
