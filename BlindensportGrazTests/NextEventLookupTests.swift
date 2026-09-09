import XCTest
import SwiftData
@testable import BlindensportGraz

/// Coverage for the App Shortcuts data layer (`NextEventLookup`,
/// architecture-review.md §5): the "soonest upcoming, team-visible" pick and
/// the spoken-line formatting. `makeContext`/`currentUser` (real container +
/// UserDefaults) aren't exercised — the selection functions take an injected
/// `ModelContext` + `User` precisely so they're testable without either.
@MainActor
final class NextEventLookupTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: AppModelSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: AppModelSchema.schema, configurations: [config]))
    }

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: - nextTraining

    func testNextTrainingPicksTheSoonestFutureOneAndIgnoresThePast() throws {
        let context = try makeContext()
        let past = Training(title: "Gestern", sport: "Torball", location: "Graz", startDate: now.addingTimeInterval(-3600))
        let soon = Training(title: "Bald", sport: "Torball", location: "Graz", startDate: now.addingTimeInterval(3600))
        let later = Training(title: "Später", sport: "Torball", location: "Graz", startDate: now.addingTimeInterval(86400))
        [past, soon, later].forEach(context.insert)
        try context.save()

        let next = NextEventLookup.nextTraining(in: context, for: nil, now: now)
        XCTAssertEqual(next?.title, "Bald")
    }

    func testNextTrainingReturnsNilWhenNothingIsUpcoming() throws {
        let context = try makeContext()
        context.insert(Training(title: "Vorbei", sport: "Torball", location: "Graz", startDate: now.addingTimeInterval(-60)))
        try context.save()

        XCTAssertNil(NextEventLookup.nextTraining(in: context, for: nil, now: now))
    }

    func testTeamScopedTrainingIsHiddenFromANonMemberButVisibleToAnAdmin() throws {
        let context = try makeContext()
        let teamA = Team(name: "A", sport: "Torball")
        let teamB = Team(name: "B", sport: "Torball")
        [teamA, teamB].forEach(context.insert)

        let member = User(email: "m@x.at", firstName: "Mel", lastName: "Ott", role: .member)
        context.insert(member)
        context.insert(TeamMembership(user: member, team: teamA))

        let admin = User(email: "a@x.at", firstName: "Al", lastName: "Chef", role: .admin)
        context.insert(admin)

        // Only assigned to team B — the member isn't on it.
        let scoped = Training(title: "Nur B", sport: "Torball", location: "Graz",
                              startDate: now.addingTimeInterval(3600), teams: [teamB])
        context.insert(scoped)
        try context.save()

        XCTAssertNil(NextEventLookup.nextTraining(in: context, for: member, now: now),
                     "a member not on team B must not see a B-scoped training")
        XCTAssertEqual(NextEventLookup.nextTraining(in: context, for: admin, now: now)?.title, "Nur B",
                       "an admin sees every event regardless of team")
    }

    func testUnscopedTrainingIsVisibleToEveryone() throws {
        let context = try makeContext()
        let member = User(email: "m@x.at", firstName: "Mel", lastName: "Ott", role: .member)
        context.insert(member)
        context.insert(Training(title: "Für alle", sport: "Torball", location: "Graz",
                                startDate: now.addingTimeInterval(3600)))
        try context.save()

        XCTAssertEqual(NextEventLookup.nextTraining(in: context, for: member, now: now)?.title, "Für alle")
        XCTAssertEqual(NextEventLookup.nextTraining(in: context, for: nil, now: now)?.title, "Für alle")
    }

    // MARK: - nextTournament

    func testNextTournamentPicksSoonestUpcoming() throws {
        let context = try makeContext()
        context.insert(Tournament(title: "Alt", sport: "Torball", location: "Wien",
                                  startDate: now.addingTimeInterval(-86400), endDate: now))
        context.insert(Tournament(title: "Neu", sport: "Torball", location: "Linz",
                                  startDate: now.addingTimeInterval(7 * 86400), endDate: now.addingTimeInterval(8 * 86400)))
        try context.save()

        XCTAssertEqual(NextEventLookup.nextTournament(in: context, for: nil, now: now)?.title, "Neu")
    }

    // MARK: - spokenLine

    func testSpokenLineIncludesLocationWhenPresentAndOmitsTimeWhenAsked() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let withLoc = NextEventLookup.spokenLine(kind: "Training", title: "Abendtraining",
                                                 date: date, location: "Sporthalle", includeTime: true)
        XCTAssertTrue(withLoc.hasPrefix("Dein nächstes Training: Abendtraining am "))
        XCTAssertTrue(withLoc.hasSuffix(" in Sporthalle."))

        let noLoc = NextEventLookup.spokenLine(kind: "Turnier", title: "Herbstcup",
                                               date: date, location: "  ", includeTime: false)
        XCTAssertTrue(noLoc.hasPrefix("Dein nächstes Turnier: Herbstcup am "))
        XCTAssertTrue(noLoc.hasSuffix("."))
        XCTAssertFalse(noLoc.contains(" in "))
    }
}
