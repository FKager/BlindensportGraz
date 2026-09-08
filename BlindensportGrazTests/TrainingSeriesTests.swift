import XCTest
import SwiftData
@testable import BlindensportGraz

/// Coverage for the recurring-training-series feature (architecture-review.md
/// §5): `TrainingFavorite.seriesStartDates` (pure date math) and
/// `TrainingService.partitionSeriesDates` (the "which dates are already
/// taken" preview). `TrainingService.createSeries` itself isn't unit-tested
/// — it calls `TrainingService.save` → `CloudKitSync`, which new tests must
/// not touch (cerebrum rule); its logic is `partitionSeriesDates` +
/// `Training(...)` inserts, both covered indirectly.
@MainActor
final class TrainingSeriesTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return cal
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self,
            EventImage.self, Attendance.self, TrainingFavorite.self, RoleChangeLog.self,
            ExpenseReceipt.self, PendingPush.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func favorite(weekday: Int = 4 /* Wednesday */) -> TrainingFavorite {
        TrainingFavorite(title: "Abendtraining", sport: "Torball",
                         startHour: 18, startMinute: 30, endHour: 20, endMinute: 0,
                         weekday: weekday)
    }

    // MARK: - seriesStartDates

    func testSeriesStartDatesHasRequestedCountAllOnTheFavoritesWeekdayOneWeekApart() {
        let cal = calendar
        // A Monday reference.
        let reference = cal.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 9))!
        let dates = favorite(weekday: 4).seriesStartDates(count: 6, from: reference, calendar: cal)

        XCTAssertEqual(dates.count, 6)
        for date in dates {
            XCTAssertEqual(cal.component(.weekday, from: date), 4, "every occurrence is on the favorite's weekday")
            XCTAssertEqual(cal.component(.hour, from: date), 18)
            XCTAssertEqual(cal.component(.minute, from: date), 30)
        }
        for (earlier, later) in zip(dates, dates.dropFirst()) {
            XCTAssertEqual(cal.dateComponents([.day], from: earlier, to: later).day, 7)
        }
    }

    func testSeriesFirstDateMatchesSuggestedStartDate() {
        let cal = calendar
        let reference = cal.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 9))!
        let fav = favorite(weekday: 4)

        let first = try? XCTUnwrap(fav.seriesStartDates(count: 3, from: reference, calendar: cal).first)
        let suggested = TrainingFavorite.suggestedStartDate(startHour: fav.startHour, startMinute: fav.startMinute,
                                                            weekday: fav.weekday, from: reference, calendar: cal)
        XCTAssertEqual(first, suggested)
    }

    func testSeriesStartDatesIsEmptyForNonPositiveCount() {
        XCTAssertTrue(favorite().seriesStartDates(count: 0).isEmpty)
        XCTAssertTrue(favorite().seriesStartDates(count: -3).isEmpty)
    }

    // MARK: - partitionSeriesDates

    func testPartitionSeparatesDatesAlreadyTakenByAnExistingEvent() throws {
        let context = try makeContext()
        let cal = calendar
        let reference = cal.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 9))!
        let fav = favorite(weekday: 4)
        let dates = fav.seriesStartDates(count: 4, from: reference, calendar: cal)

        // Pre-create a training that collides with the 2nd date only
        // (same title + sport + minute — the SportEvent.duplicate rule).
        let clash = Training(title: fav.title, sport: fav.sport, location: "Graz", startDate: dates[1])
        context.insert(clash)
        try context.save()

        let result = TrainingService.partitionSeriesDates(title: fav.title, sport: fav.sport,
                                                          startDates: dates, modelContext: context)
        XCTAssertEqual(result.taken, [dates[1]])
        XCTAssertEqual(result.open, [dates[0], dates[2], dates[3]])
    }

    func testPartitionReturnsEverythingOpenWhenNothingClashes() throws {
        let context = try makeContext()
        let cal = calendar
        let reference = cal.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 9))!
        let fav = favorite(weekday: 4)
        let dates = fav.seriesStartDates(count: 4, from: reference, calendar: cal)

        let result = TrainingService.partitionSeriesDates(title: fav.title, sport: fav.sport,
                                                          startDates: dates, modelContext: context)
        XCTAssertEqual(result.open, dates)
        XCTAssertTrue(result.taken.isEmpty)
    }
}
