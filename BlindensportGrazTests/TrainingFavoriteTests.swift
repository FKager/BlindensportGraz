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
        XCTAssertEqual(favorite?.weekday, Calendar.current.component(.weekday, from: date(hour: 18, minute: 30)))

        let all = try context.fetch(FetchDescriptor<TrainingFavorite>())
        XCTAssertEqual(all.count, 1)
    }

    func testRecordUsageStoresAddress() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let (favorite, _) = TrainingFavorite.recordUsage(
            title: "Wochentraining", sport: "Torball",
            startDate: date(hour: 18), durationMinutes: 90,
            location: "ASKÖ-Halle", street: "Musterstraße 1", zip: "8010", city: "Graz",
            in: context
        )

        XCTAssertEqual(favorite?.location, "ASKÖ-Halle")
        XCTAssertEqual(favorite?.street, "Musterstraße 1")
        XCTAssertEqual(favorite?.zip, "8010")
        XCTAssertEqual(favorite?.city, "Graz")
    }

    func testRecordUsageUpdatesAddressOnExistingMatch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        _ = TrainingFavorite.recordUsage(title: "Wochentraining", sport: "Torball",
                                          startDate: date(hour: 18), durationMinutes: 90,
                                          location: "Alte Halle", street: "", zip: "", city: "Graz", in: context)
        let (favorite, _) = TrainingFavorite.recordUsage(title: "Wochentraining", sport: "Torball",
                                                           startDate: date(hour: 18), durationMinutes: 90,
                                                           location: "Neue Halle", street: "Neustraße 2", zip: "8020", city: "Graz",
                                                           in: context)

        XCTAssertEqual(favorite?.location, "Neue Halle")
        XCTAssertEqual(favorite?.street, "Neustraße 2")
        XCTAssertEqual(favorite?.zip, "8020")
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

    func testSuggestedStartDateIsExactlyOneWeekLaterWhenWeekdayMatchesToday() {
        let reference = date(hour: 10, day: 1, month: 7, year: 2026)
        let referenceWeekday = Calendar.current.component(.weekday, from: reference)
        let suggested = TrainingFavorite.suggestedStartDate(startHour: 18, startMinute: 30, weekday: referenceWeekday, from: reference)

        let calendar = Calendar.current
        // When the target weekday IS today's own weekday, that's the
        // "otherwise" branch (today is not BEFORE the target) — roll a full
        // week forward rather than suggesting today. Always exactly +7 days,
        // regardless of the calendar's first-weekday convention.
        let expectedDay = calendar.date(byAdding: .day, value: 7, to: reference)!
        XCTAssertEqual(calendar.component(.day, from: suggested), calendar.component(.day, from: expectedDay))
        XCTAssertEqual(calendar.component(.month, from: suggested), calendar.component(.month, from: expectedDay))
        XCTAssertEqual(calendar.component(.year, from: suggested), calendar.component(.year, from: expectedDay))
        XCTAssertEqual(calendar.component(.hour, from: suggested), 18)
        XCTAssertEqual(calendar.component(.minute, from: suggested), 30)
    }

    /// Reproduces the user-reported bug directly: last training Wed 12.08.2026,
    /// today (reference) Thu 13.08.2026 — today is already past this week's
    /// Wednesday, so the suggestion must roll to NEXT week's Wednesday
    /// (19.08.2026), not stay stuck 7-13 days out from some other anchor.
    func testSuggestedStartDateMatchesUserReportedExample() {
        let calendar = Calendar.current
        let reference = date(hour: 9, day: 13, month: 8, year: 2026) // Thursday
        XCTAssertEqual(calendar.component(.weekday, from: reference), 5, "sanity check: 13.08.2026 is a Thursday")
        let wednesday = 4 // Calendar.weekday: 1 = Sunday ... 4 = Wednesday

        let suggested = TrainingFavorite.suggestedStartDate(startHour: 18, startMinute: 0, weekday: wednesday, from: reference)

        let expected = date(hour: 18, day: 19, month: 8, year: 2026)
        XCTAssertEqual(calendar.component(.day, from: suggested), calendar.component(.day, from: expected))
        XCTAssertEqual(calendar.component(.month, from: suggested), calendar.component(.month, from: expected))
        XCTAssertEqual(calendar.component(.year, from: suggested), calendar.component(.year, from: expected))
    }

    /// When today is still BEFORE the target weekday within the current
    /// week, the suggestion must stay in THIS week (as little as 1 day out)
    /// rather than jumping a full week ahead — this is exactly what the
    /// previous `.weekOfYear`-bucketing implementation got wrong: it always
    /// snapped to next week regardless of how close the target weekday was.
    func testSuggestedStartDateStaysInSameWeekWhenTodayIsBeforeTargetWeekday() {
        let calendar = Calendar.current
        let reference = date(hour: 10, day: 1, month: 7, year: 2026) // Wednesday
        XCTAssertEqual(calendar.component(.weekday, from: reference), 4, "sanity check: 01.07.2026 is a Wednesday")
        let friday = 6 // later this same week

        let suggested = TrainingFavorite.suggestedStartDate(startHour: 18, startMinute: 0, weekday: friday, from: reference)

        let expected = calendar.date(byAdding: .day, value: 2, to: reference)! // Wed -> Fri, 2 days out
        XCTAssertEqual(calendar.component(.day, from: suggested), calendar.component(.day, from: expected))
        XCTAssertEqual(calendar.component(.month, from: suggested), calendar.component(.month, from: expected))
        XCTAssertEqual(calendar.component(.year, from: suggested), calendar.component(.year, from: expected))
        XCTAssertEqual(calendar.component(.hour, from: suggested), 18)
    }

    /// When today is ON OR AFTER the target weekday (it already happened
    /// this week), the suggestion must roll to next week.
    func testSuggestedStartDateRollsToNextWeekWhenTodayIsAfterTargetWeekday() {
        let calendar = Calendar.current
        let reference = date(hour: 10, day: 3, month: 7, year: 2026) // Friday
        XCTAssertEqual(calendar.component(.weekday, from: reference), 6, "sanity check: 03.07.2026 is a Friday")
        let wednesday = 4 // earlier this same week, already passed

        let suggested = TrainingFavorite.suggestedStartDate(startHour: 18, startMinute: 0, weekday: wednesday, from: reference)

        let expected = calendar.date(byAdding: .day, value: 5, to: reference)! // Fri -> next Wed, 5 days out
        XCTAssertEqual(calendar.component(.day, from: suggested), calendar.component(.day, from: expected))
        XCTAssertEqual(calendar.component(.month, from: suggested), calendar.component(.month, from: expected))
        XCTAssertEqual(calendar.component(.year, from: suggested), calendar.component(.year, from: expected))
        XCTAssertEqual(calendar.component(.hour, from: suggested), 18)
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
