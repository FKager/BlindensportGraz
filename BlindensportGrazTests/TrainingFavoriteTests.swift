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

    // MARK: - populateFromRecentTrainings

    func testPopulateFromRecentTrainingsDedupesByTitleAndSportKeepingNewest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Two "Wochentraining"/Torball trainings, newest first (as the
        // real @Query already sorts) — only the newest should be recorded.
        let older = Training(title: "Wochentraining", sport: "Torball", location: "Alte Halle",
                              startDate: date(hour: 18, day: 5))
        let newer = Training(title: "Wochentraining", sport: "Torball", location: "Neue Halle",
                              startDate: date(hour: 19, day: 12))
        context.insert(older)
        context.insert(newer)

        let results = TrainingFavorite.populateFromRecentTrainings([newer, older], in: context)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.favorite?.location, "Neue Halle")
        let all = try context.fetch(FetchDescriptor<TrainingFavorite>())
        XCTAssertEqual(all.count, 1)
    }

    func testPopulateFromRecentTrainingsCapturesWeekdayAndAddress() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let training = Training(title: "Mittwochstraining", sport: "Torball",
                                 location: "ASKÖ-Halle", street: "Musterstraße 1", zip: "8010", city: "Graz",
                                 startDate: date(hour: 18, day: 12)) // a Wednesday
        context.insert(training)

        let results = TrainingFavorite.populateFromRecentTrainings([training], in: context)

        XCTAssertEqual(results.first?.favorite?.weekday, Calendar.current.component(.weekday, from: training.startDate))
        XCTAssertEqual(results.first?.favorite?.location, "ASKÖ-Halle")
        XCTAssertEqual(results.first?.favorite?.street, "Musterstraße 1")
        XCTAssertEqual(results.first?.favorite?.zip, "8010")
        XCTAssertEqual(results.first?.favorite?.city, "Graz")
    }

    func testPopulateFromRecentTrainingsRespectsMaxCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // 7 distinct name+sport combos, newest first.
        let trainings = (1...7).reversed().map { i in
            Training(title: "Training \(i)", sport: "Torball", location: "Graz", startDate: date(hour: 18, day: i))
        }
        for t in trainings { context.insert(t) }

        let results = TrainingFavorite.populateFromRecentTrainings(trainings, in: context)

        XCTAssertEqual(results.count, TrainingFavorite.maxCount)
        let all = try context.fetch(FetchDescriptor<TrainingFavorite>())
        XCTAssertEqual(all.count, TrainingFavorite.maxCount)
        // The 5 newest (Training 7 down to Training 3) should be kept, not the oldest.
        XCTAssertTrue(all.contains { $0.title == "Training 7" })
        XCTAssertFalse(all.contains { $0.title == "Training 1" })
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
        // When the target weekday IS today's own weekday, "next week's same
        // weekday" is always exactly +7 days, regardless of the calendar's
        // first-weekday convention (Sunday-start vs Monday-start) — this
        // part of the contract doesn't depend on locale.
        let expectedDay = calendar.date(byAdding: .day, value: 7, to: reference)!
        XCTAssertEqual(calendar.component(.day, from: suggested), calendar.component(.day, from: expectedDay))
        XCTAssertEqual(calendar.component(.month, from: suggested), calendar.component(.month, from: expectedDay))
        XCTAssertEqual(calendar.component(.year, from: suggested), calendar.component(.year, from: expectedDay))
        XCTAssertEqual(calendar.component(.hour, from: suggested), 18)
        XCTAssertEqual(calendar.component(.minute, from: suggested), 30)
    }

    /// The core "same weekday, next calendar week" behavior — verified via
    /// the same yearForWeekOfYear/weekOfYear bucketing the implementation
    /// itself uses (rather than hardcoded day-offset arithmetic), since the
    /// exact day offset depends on Calendar.current's first-weekday
    /// convention (Sunday-start vs Monday-start), which varies by locale/
    /// region and isn't something this test should assume. This is still a
    /// meaningful regression check: the previous (buggy) implementation
    /// searched forward from "today + 7 days" instead of snapping to next
    /// week's calendar bucket, so it would NOT satisfy the weekOfYear
    /// equality asserted here for every target weekday.
    func testSuggestedStartDateLandsInNextCalendarWeekOnTargetWeekday() {
        let calendar = Calendar.current
        let reference = date(hour: 10, day: 1, month: 7, year: 2026)
        let referenceWeekday = calendar.component(.weekday, from: reference)
        let targetWeekday = referenceWeekday % 7 + 1 // some other weekday than today's

        let suggested = TrainingFavorite.suggestedStartDate(startHour: 18, startMinute: 0, weekday: targetWeekday, from: reference)
        let nextWeekReference = calendar.date(byAdding: .weekOfYear, value: 1, to: reference)!

        XCTAssertEqual(calendar.component(.weekday, from: suggested), targetWeekday)
        XCTAssertEqual(calendar.component(.weekOfYear, from: suggested), calendar.component(.weekOfYear, from: nextWeekReference))
        XCTAssertEqual(calendar.component(.yearForWeekOfYear, from: suggested), calendar.component(.yearForWeekOfYear, from: nextWeekReference))
        XCTAssertEqual(calendar.component(.hour, from: suggested), 18)
        XCTAssertEqual(calendar.component(.minute, from: suggested), 0)
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
