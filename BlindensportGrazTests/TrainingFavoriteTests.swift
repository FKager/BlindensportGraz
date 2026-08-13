import XCTest
import SwiftData
@testable import BlindensportGraz

final class TrainingFavoriteTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self,
            EventImage.self, Attendance.self, TrainingFavorite.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func date(hour: Int, minute: Int = 0, day: Int = 1, month: Int = 7, year: Int = 2026) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    // MARK: - recordUsage

    func testRecordUsageInsertsNewFavorite() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let (favorite, evictedID) = TrainingFavorite.recordUsage(
            title: "Wochentraining", sport: "Torball",
            startDate: date(hour: 18, minute: 30), durationMinutes: 90, in: context
        )

        XCTAssertNotNil(favorite)
        XCTAssertNil(evictedID)
        XCTAssertEqual(favorite?.title, "Wochentraining")
        XCTAssertEqual(favorite?.sport, "Torball")
        XCTAssertEqual(favorite?.startHour, 18)
        XCTAssertEqual(favorite?.startMinute, 30)
        XCTAssertEqual(favorite?.endHour, 20)
        XCTAssertEqual(favorite?.endMinute, 0)

        let all = try context.fetch(FetchDescriptor<TrainingFavorite>())
        XCTAssertEqual(all.count, 1)
    }

    func testRecordUsageStoresManuallySelectedTeams() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Grazer VSC Damen", sport: "Torball")
        context.insert(team)

        let (favorite, _) = TrainingFavorite.recordUsage(
            title: "Wochentraining", sport: "Torball",
            startDate: date(hour: 18), durationMinutes: 90, teams: [team], in: context
        )

        XCTAssertEqual(favorite?.teams.map { $0.id }, [team.id])
    }

    func testRecordUsageUpdatesTeamsOnExistingMatch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let teamA = Team(name: "Grazer VSC Damen", sport: "Torball")
        let teamB = Team(name: "Torball Helfer", sport: "Torball")
        context.insert(teamA)
        context.insert(teamB)

        _ = TrainingFavorite.recordUsage(title: "Wochentraining", sport: "Torball",
                                          startDate: date(hour: 18), durationMinutes: 90, teams: [teamA], in: context)
        let (favorite, _) = TrainingFavorite.recordUsage(title: "Wochentraining", sport: "Torball",
                                                           startDate: date(hour: 18), durationMinutes: 90, teams: [teamB], in: context)

        XCTAssertEqual(favorite?.teams.map { $0.id }, [teamB.id], "should replace, not accumulate, the stored team selection")
    }

    func testRecordUsageUpdatesExistingMatchByTitleAndSportInsteadOfDuplicating() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        _ = TrainingFavorite.recordUsage(title: "Wochentraining", sport: "Torball",
                                          startDate: date(hour: 18), durationMinutes: 90, in: context)
        // Same title (different case/whitespace) + same sport, new time.
        let (favorite, evictedID) = TrainingFavorite.recordUsage(
            title: "  wochentraining  ", sport: "Torball",
            startDate: date(hour: 19), durationMinutes: 60, in: context
        )

        XCTAssertNil(evictedID)
        let all = try context.fetch(FetchDescriptor<TrainingFavorite>())
        XCTAssertEqual(all.count, 1, "should update the existing favorite, not insert a second one")
        XCTAssertEqual(favorite?.startHour, 19)
        XCTAssertEqual(favorite?.endHour, 20)
    }

    func testRecordUsageTreatsSameTitleDifferentSportAsDistinctFavorite() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        _ = TrainingFavorite.recordUsage(title: "Training", sport: "Torball",
                                          startDate: date(hour: 18), durationMinutes: 90, in: context)
        _ = TrainingFavorite.recordUsage(title: "Training", sport: "Goalball",
                                          startDate: date(hour: 18), durationMinutes: 90, in: context)

        let all = try context.fetch(FetchDescriptor<TrainingFavorite>())
        XCTAssertEqual(all.count, 2)
    }

    func testRecordUsageEvictsLeastRecentlyUsedAtMaxCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Insert 5 distinct favorites with strictly increasing lastUsedAt.
        for i in 1...5 {
            let favorite = TrainingFavorite(title: "Training \(i)", sport: "Torball",
                                             startHour: 18, startMinute: 0, endHour: 19, endMinute: 30,
                                             lastUsedAt: date(hour: 12, day: i))
            context.insert(favorite)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingFavorite>()).count, TrainingFavorite.maxCount)

        // A 6th distinct name+sport combo should evict "Training 1" (oldest lastUsedAt).
        let (favorite, evictedID) = TrainingFavorite.recordUsage(
            title: "Training 6", sport: "Torball",
            startDate: date(hour: 18, day: 10), durationMinutes: 90, in: context
        )

        let all = try context.fetch(FetchDescriptor<TrainingFavorite>())
        XCTAssertEqual(all.count, TrainingFavorite.maxCount, "should stay capped at maxCount")
        XCTAssertNotNil(favorite)
        XCTAssertNotNil(evictedID)
        XCTAssertFalse(all.contains { $0.title == "Training 1" })
        XCTAssertTrue(all.contains { $0.title == "Training 6" })
    }

    // MARK: - suggestedStartDate

    func testSuggestedStartDateIsOneWeekLaterAtStoredTime() {
        let reference = date(hour: 10, day: 1, month: 7, year: 2026)
        let suggested = TrainingFavorite.suggestedStartDate(startHour: 18, startMinute: 30, from: reference)

        let calendar = Calendar.current
        let expectedDay = calendar.date(byAdding: .day, value: 7, to: reference)!
        XCTAssertEqual(calendar.component(.day, from: suggested), calendar.component(.day, from: expectedDay))
        XCTAssertEqual(calendar.component(.month, from: suggested), calendar.component(.month, from: expectedDay))
        XCTAssertEqual(calendar.component(.year, from: suggested), calendar.component(.year, from: expectedDay))
        XCTAssertEqual(calendar.component(.hour, from: suggested), 18)
        XCTAssertEqual(calendar.component(.minute, from: suggested), 30)
    }

    // MARK: - durationMinutes

    func testDurationMinutesComputedFromStoredStartAndEndTime() {
        let favorite = TrainingFavorite(title: "T", sport: "Torball",
                                         startHour: 18, startMinute: 0, endHour: 19, endMinute: 30)
        XCTAssertEqual(favorite.durationMinutes, 90)
    }

    func testDurationMinutesClampsToStepperRangeForDegenerateEndBeforeStart() {
        let favorite = TrainingFavorite(title: "T", sport: "Torball",
                                         startHour: 19, startMinute: 0, endHour: 18, endMinute: 0)
        XCTAssertEqual(favorite.durationMinutes, 15, "negative raw duration should clamp to the Stepper's minimum")
    }
}
