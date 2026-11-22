import Foundation
import SwiftData

/// Launch argument `-ui-testing` (BlindensportGrazUITests): the app starts
/// with an in-memory database and never talks to a server, so the UI tests
/// see the same screens on every Mac and in CI. Signed out by default;
/// - `-ui-testing-sample-schedule`: two upcoming entries in the schedule
/// - `-ui-testing-signed-in`: signed in as a sample admin (local only, no
///   token; the server would refuse anything) with a sample team, member and event.
/// Debug builds only; a TestFlight / App Store build ignores all of them.
enum UITestMode {
    nonisolated static var isActive: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        false
        #endif
    }

    nonisolated static var isSignedIn: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-ui-testing-signed-in")
    }

    /// The sample admin's account id.
    nonisolated static let adminID = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!

    /// Claims of the sample admin (AuthContext uses them instead of a session).
    nonisolated static var adminClaims: AccessClaims {
        AccessClaims(userID: adminID, email: "admin@example.org", role: .admin, approved: true)
    }

    static func insertSampleData(into context: ModelContext) {
        guard isActive else { return }
        let arguments = ProcessInfo.processInfo.arguments
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        if arguments.contains("-ui-testing-sample-schedule") {
            context.insert(Training(title: "Blindenfußballtraining", sport: "Blindenfußball", location: "Graz",
                                    startDate: tomorrow))
            context.insert(Tournament(title: "Torballturnier", sport: "Torball", location: "Wien",
                                      startDate: tomorrow.addingTimeInterval(7 * 86_400),
                                      endDate: tomorrow.addingTimeInterval(8 * 86_400)))
        }
        if isSignedIn {
            let admin = User(id: adminID, email: "admin@example.org", firstName: "Anna", lastName: "Admin",
                             role: .admin)
            let team = Team(name: "Torball Herren", sport: "Torball")
            let member = Member(firstName: "Max", lastName: "Muster", city: "Graz")
            context.insert(admin)
            context.insert(team)
            context.insert(member)
            context.insert(TeamMembership(user: admin, team: team, role: .coach))
            context.insert(TeamMembership(member: member, team: team))
            let party = SportEvent(title: "Vereinsfeier", sport: "", location: "Graz",
                                   startDate: tomorrow.addingTimeInterval(14 * 86_400),
                                   endDate: tomorrow.addingTimeInterval(14 * 86_400 + 3 * 3_600))
            party.kind = "event"
            context.insert(party)
        }
        try? context.save()
    }
}
