import XCTest
import SwiftData
@testable import BlindensportGraz

/// Validates the SwiftData model-inheritance assumptions the SportEvent/
/// Training/Tournament refactor depends on, before trusting any downstream
/// view code built on top of them. See .wolf/cerebrum.md and the plan this
/// refactor was built from for the reasoning behind each assertion.
@available(iOS 26, *)
final class InheritanceQueryTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self,
            EventImage.self, Attendance.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Polymorphic pickup: fetching the base type returns subclass instances too.
    func testFetchingBaseTypeReturnsSubclassInstances() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let event = SportEvent(title: "Sommerfest", sport: "Torball", location: "Graz",
                                startDate: .now, endDate: .now)
        let training = Training(title: "Torball Training", sport: "Torball", location: "Graz", startDate: .now)
        let tournament = Tournament(title: "Torball Cup", sport: "Torball", location: "Graz",
                                     startDate: .now, endDate: .now)
        context.insert(event)
        context.insert(training)
        context.insert(tournament)
        try context.save()

        let all = try context.fetch(FetchDescriptor<SportEvent>())
        XCTAssertEqual(all.count, 3, "expected base-type fetch to include Training/Tournament instances too")
    }

    /// The `kind` discriminator correctly isolates plain SportEvent instances
    /// from Training/Tournament, which EventsListView/DashboardView depend on.
    func testKindDiscriminatorFiltersToPlainEventsOnly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let event = SportEvent(title: "Sommerfest", sport: "Torball", location: "Graz",
                                startDate: .now, endDate: .now)
        let training = Training(title: "Torball Training", sport: "Torball", location: "Graz", startDate: .now)
        let tournament = Tournament(title: "Torball Cup", sport: "Torball", location: "Graz",
                                     startDate: .now, endDate: .now)
        context.insert(event)
        context.insert(training)
        context.insert(tournament)
        try context.save()

        var descriptor = FetchDescriptor<SportEvent>(predicate: #Predicate { $0.kind == "event" })
        let onlyEvents = try context.fetch(descriptor)
        XCTAssertEqual(onlyEvents.count, 1)
        XCTAssertEqual(onlyEvents.first?.id, event.id)
        XCTAssertTrue(type(of: onlyEvents.first!) == SportEvent.self)

        descriptor = FetchDescriptor<SportEvent>(predicate: #Predicate { $0.kind == "training" })
        XCTAssertEqual(try context.fetch(descriptor).first?.id, training.id)

        descriptor = FetchDescriptor<SportEvent>(predicate: #Predicate { $0.kind == "tournament" })
        XCTAssertEqual(try context.fetch(descriptor).first?.id, tournament.id)
    }

    /// A concrete-subclass-typed fetch (as DashboardView's Training/Tournament
    /// queries already are) returns only that subclass, not siblings.
    func testConcreteSubclassFetchExcludesSiblings() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        context.insert(SportEvent(title: "Sommerfest", sport: "Torball", location: "Graz", startDate: .now, endDate: .now))
        context.insert(Training(title: "Torball Training", sport: "Torball", location: "Graz", startDate: .now))
        context.insert(Tournament(title: "Torball Cup", sport: "Torball", location: "Graz", startDate: .now, endDate: .now))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Training>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Tournament>()).count, 1)
    }

    /// CloudKitSync's collapsed `findEvent(id:)` helper needs a SportEvent-typed
    /// fetch by id to resolve to a Training/Tournament instance when that's
    /// what was actually inserted under that id.
    func testFetchingBaseTypeByIdResolvesSubclassInstance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let training = Training(title: "Torball Training", sport: "Torball", location: "Graz", startDate: .now)
        context.insert(training)
        try context.save()

        let trainingID = training.id
        let descriptor = FetchDescriptor<SportEvent>(predicate: #Predicate { $0.id == trainingID })
        let resolved = try context.fetch(descriptor).first
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved is Training)
    }

    /// Team.sportEvents' deleteRule: .nullify must prevent a dangling
    /// reference when a Team with an assigned SportEvent is deleted.
    func testDeletingTeamNullifiesEventReferenceWithoutCrashing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let team = Team(name: "Torball 1", sport: "Torball")
        let event = SportEvent(title: "Sommerfest", sport: "Torball", location: "Graz",
                                startDate: .now, endDate: .now, teams: [team])
        context.insert(team)
        context.insert(event)
        try context.save()

        context.delete(team)
        try context.save()

        let survivingEvents = try context.fetch(FetchDescriptor<SportEvent>())
        XCTAssertEqual(survivingEvents.count, 1)
        XCTAssertTrue(survivingEvents.first?.teams.isEmpty ?? false, "expected the deleted team to be nullified out, not left dangling")
    }

    /// Regression test for bug-163: deleting a TeamMembership that has an
    /// Attendance record used to leave a corrupted local row, since
    /// Attendance.membership is a non-optional to-one relationship and, with
    /// no explicit cascade rule, SwiftData's default nullify can't null a
    /// non-optional property — any later access to the dangling Attendance's
    /// `.membership.id` (exactly what TrainingDetailView.attendance(for:)
    /// does) then crashed with a fatal SwiftData assertion. TeamMembership.
    /// attendances' cascade rule must delete the Attendance instead.
    func testDeletingTeamMembershipCascadeDeletesItsAttendanceWithoutCrashing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let member = Member(firstName: "Anna", lastName: "Sportlerin")
        context.insert(member)
        let membership = TeamMembership(member: member, team: team, role: .player)
        context.insert(membership)
        let training = Training(title: "Torball Training", sport: "Torball", location: "Graz",
                                 startDate: .now, teams: [team])
        context.insert(training)
        let attendance = Attendance(event: training, membership: membership, attended: true)
        context.insert(attendance)
        try context.save()

        context.delete(membership)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<Attendance>()).isEmpty,
                       "expected the dependent Attendance to be cascade-deleted, not left dangling")

        // The real crash site: iterating the training's remaining attendances
        // and comparing membership ids must not touch a corrupted row.
        let survivingTraining = try XCTUnwrap(try context.fetch(FetchDescriptor<Training>()).first)
        XCTAssertNoThrow(_ = survivingTraining.attendances.first { $0.membership.id == membership.id })
    }

    // MARK: - SportEvent.duplicate (name + Sportart + Zeitpunkt uniqueness)

    func testDuplicateMatchesAcrossEventKinds() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let when = Date(timeIntervalSince1970: 1_800_000_000)

        context.insert(Training(title: "Torball Training", sport: "Torball", location: "Graz", startDate: when))
        try context.save()

        // A tournament with the same name/sport/day is still a "duplicate" —
        // the rule spans every event kind, and the base-type fetch is polymorphic.
        XCTAssertNotNil(SportEvent.duplicate(title: "Torball Training", sport: "Torball",
                                             startDate: when, granularity: .day, in: context))
        // Different sport → not a duplicate.
        XCTAssertNil(SportEvent.duplicate(title: "Torball Training", sport: "Goalball",
                                          startDate: when, in: context))
    }

    func testDuplicateIgnoresCaseAndSurroundingWhitespaceInTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let when = Date(timeIntervalSince1970: 1_800_000_000)

        context.insert(SportEvent(title: "Sommerfest", sport: "Torball", location: "Graz",
                                  startDate: when, endDate: when))
        try context.save()

        XCTAssertNotNil(SportEvent.duplicate(title: "  sommerFEST ", sport: "Torball",
                                             startDate: when, in: context))
    }

    func testDuplicateMinuteGranularityDistinguishesTimes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let when = Date(timeIntervalSince1970: 1_800_000_000)

        context.insert(Training(title: "Abendtraining", sport: "Torball", location: "Graz", startDate: when))
        try context.save()

        // Same day, one hour later → distinct at .minute granularity.
        XCTAssertNil(SportEvent.duplicate(title: "Abendtraining", sport: "Torball",
                                          startDate: when.addingTimeInterval(3600), in: context))
        // Same instant → match.
        XCTAssertNotNil(SportEvent.duplicate(title: "Abendtraining", sport: "Torball",
                                             startDate: when, in: context))
    }

    func testDuplicateDayGranularityIgnoresTimeOfDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        let evening = morning.addingTimeInterval(8 * 3600)

        context.insert(Tournament(title: "Herbstcup", sport: "Torball", location: "Graz",
                                  startDate: morning, endDate: morning))
        try context.save()

        XCTAssertNotNil(SportEvent.duplicate(title: "Herbstcup", sport: "Torball",
                                             startDate: evening, granularity: .day, in: context))
    }

    func testDuplicateExcludesTheEventBeingEdited() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let when = Date(timeIntervalSince1970: 1_800_000_000)

        let training = Training(title: "Torball Training", sport: "Torball", location: "Graz", startDate: when)
        context.insert(training)
        try context.save()

        XCTAssertNil(SportEvent.duplicate(title: "Torball Training", sport: "Torball",
                                          startDate: when, excluding: training.id, in: context))
    }

    func testDuplicateWithBlankTitleIsNeverAMatch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let when = Date(timeIntervalSince1970: 1_800_000_000)

        context.insert(SportEvent(title: "", sport: "Torball", location: "Graz", startDate: when, endDate: when))
        try context.save()

        XCTAssertNil(SportEvent.duplicate(title: "   ", sport: "Torball", startDate: when, in: context))
    }
}
