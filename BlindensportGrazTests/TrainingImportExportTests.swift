import XCTest
import SwiftData
@testable import BlindensportGraz

// NOTE: like MemberImportExportTests (see bug-202), every test here that
// reaches importTrainings/exportFile touches CloudKitSync.shared, which
// lazily constructs a real CKContainer — running xcodebuild test with
// CODE_SIGNING_ALLOWED=NO strips the iCloud entitlement CloudKit needs, so
// the process hard-crashes the moment any code path touches CKContainer.
// This is a CloudKit SDK behavior tied to unsigned local test runs, not an
// app bug — exclude this suite the same way (-skip-testing:
// BlindensportGrazTests/TrainingImportExportTests) when running unsigned.
@MainActor
final class TrainingImportExportTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self,
            EventImage.self, Attendance.self, TrainingFavorite.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func date(hour: Int, day: Int = 1, month: Int = 7, year: Int = 2026) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = hour
        return Calendar.current.date(from: components)!
    }

    /// A freshly-exported file, re-imported into the same list, should
    /// update the existing entry in place (matched by `id`) rather than
    /// creating a duplicate — makes "export, edit externally, re-import" a
    /// safe round trip, same guarantee as MemberImportExport.
    func testExportThenReimportIsIdempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let training = Training(title: "Wochentraining", sport: "Torball", location: "ASKÖ-Halle",
                                 startDate: date(hour: 18), durationMinutes: 90)
        context.insert(training)
        try context.save()

        let url = try TrainingImportExport.exportFile(trainings: [training])
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)

        let result = TrainingImportExport.importTrainings(from: data, into: [training], modelContext: context)

        XCTAssertEqual(result.created, 0)
        XCTAssertEqual(result.updated, 1)
        let all = try context.fetch(FetchDescriptor<Training>())
        XCTAssertEqual(all.count, 1, "re-importing the same exported file must not duplicate the entry")
        XCTAssertEqual(all.first?.location, "ASKÖ-Halle")
    }

    func testImportCreatesNewTraining() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let json = """
        [{"title":"Neues Training","sport":"Goalball","startDate":"2026-08-19T18:00:00Z","durationMinutes":60}]
        """
        let result = TrainingImportExport.importTrainings(from: Data(json.utf8), into: [], modelContext: context)

        XCTAssertEqual(result.created, 1)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.skipped, 0)
        let all = try context.fetch(FetchDescriptor<Training>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Neues Training")
        XCTAssertEqual(all.first?.sport, "Goalball")
        XCTAssertEqual(all.first?.durationMinutes, 60)
    }

    func testImportSkipsEntryWithoutTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let json = """
        [{"sport":"Torball","startDate":"2026-08-19T18:00:00Z"}]
        """
        let result = TrainingImportExport.importTrainings(from: Data(json.utf8), into: [], modelContext: context)

        XCTAssertEqual(result.created, 0)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(result.skippedDetails.first?.contains("Titel") == true)
    }

    func testImportSkipsEntryWithoutValidStartDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let json = """
        [{"title":"Ohne Datum","sport":"Torball"}]
        """
        let result = TrainingImportExport.importTrainings(from: Data(json.utf8), into: [], modelContext: context)

        XCTAssertEqual(result.created, 0)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(result.skippedDetails.first?.contains("Startdatum") == true)
    }

    /// Matching by title + startDate (within the same minute) is the
    /// fallback used when a row has no `id` — e.g. a hand-written or
    /// externally-generated import file.
    func testImportMatchesExistingByTitleAndStartDateWhenNoID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let training = Training(title: "Wochentraining", sport: "Torball", location: "Alte Halle",
                                 startDate: date(hour: 18), durationMinutes: 90)
        context.insert(training)

        let json = """
        [{"title":"Wochentraining","sport":"Torball","location":"Neue Halle","startDate":"2026-07-01T18:00:00Z"}]
        """
        let result = TrainingImportExport.importTrainings(from: Data(json.utf8), into: [training], modelContext: context)

        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.created, 0)
        XCTAssertEqual(training.location, "Neue Halle")
    }

    /// Unlike MemberImportExport's fill-if-blank semantics, importing an
    /// update should overwrite an already-set field with any new non-empty
    /// value provided — mirrors TeamImportExport's "sync to latest".
    func testImportOverwritesExistingNonEmptyFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let training = Training(id: UUID(), title: "Wochentraining", sport: "Torball", location: "Alte Halle",
                                 startDate: date(hour: 18), durationMinutes: 90, focusArea: "Altbestand")
        context.insert(training)

        let json = """
        [{"id":"\(training.id.uuidString)","title":"Wochentraining","sport":"Torball",
          "location":"Neue Halle","focusArea":"Technik","startDate":"2026-07-01T19:00:00Z","durationMinutes":120}]
        """
        let result = TrainingImportExport.importTrainings(from: Data(json.utf8), into: [training], modelContext: context)

        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(training.location, "Neue Halle")
        XCTAssertEqual(training.focusArea, "Technik")
        XCTAssertEqual(training.durationMinutes, 120)
        XCTAssertEqual(Calendar.current.component(.hour, from: training.startDate), 19)
    }

    /// A team name that matches an existing Team (case-insensitively) gets
    /// assigned; one that doesn't match resolves to nothing and is reported
    /// in skippedDetails, but doesn't block the rest of the row.
    func testImportResolvesTeamsByNameAndReportsUnresolvedOnes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Grazer VSC Damen", sport: "Torball")
        context.insert(team)

        let json = """
        [{"title":"Wochentraining","sport":"Torball","startDate":"2026-08-19T18:00:00Z",
          "teams":["grazer vsc damen","Unbekanntes Team"]}]
        """
        let result = TrainingImportExport.importTrainings(from: Data(json.utf8), into: [], modelContext: context)

        XCTAssertEqual(result.created, 1)
        let all = try context.fetch(FetchDescriptor<Training>())
        XCTAssertEqual(all.first?.teams.map(\.id), [team.id])
        XCTAssertTrue(result.skippedDetails.contains { $0.contains("Unbekanntes Team") })
    }

    /// An omitted (or entirely-unresolvable) teams list on an UPDATE must
    /// not silently clear the existing team assignment.
    func testImportLeavesExistingTeamsUntouchedWhenTeamsFieldOmitted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Grazer VSC Damen", sport: "Torball")
        context.insert(team)
        let training = Training(id: UUID(), title: "Wochentraining", sport: "Torball", location: "Alte Halle",
                                 startDate: date(hour: 18), durationMinutes: 90, teams: [team])
        context.insert(training)

        let json = """
        [{"id":"\(training.id.uuidString)","title":"Wochentraining","sport":"Torball",
          "location":"Neue Halle","startDate":"2026-07-01T18:00:00Z"}]
        """
        _ = TrainingImportExport.importTrainings(from: Data(json.utf8), into: [training], modelContext: context)

        XCTAssertEqual(training.teams.map(\.id), [team.id])
    }
}
