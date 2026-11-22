import Foundation
import SwiftData

/// Launch argument `-ui-testing` (BlindensportGrazUITests): the app starts
/// signed out with an in-memory database and never talks to a server, so
/// the UI tests see the same screens on every Mac and in CI. With
/// `-ui-testing-sample-schedule` the schedule gets two upcoming entries;
/// without it, it's empty. Debug builds only; a TestFlight / App Store
/// build ignores both.
enum UITestMode {
    nonisolated static var isActive: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        false
        #endif
    }

    static func insertSampleSchedule(into context: ModelContext) {
        guard isActive, ProcessInfo.processInfo.arguments.contains("-ui-testing-sample-schedule") else { return }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        context.insert(Training(title: "Blindenfußballtraining", sport: "Blindenfußball", location: "Graz",
                                startDate: tomorrow))
        context.insert(Tournament(title: "Torballturnier", sport: "Torball", location: "Wien",
                                  startDate: tomorrow.addingTimeInterval(7 * 86_400),
                                  endDate: tomorrow.addingTimeInterval(8 * 86_400)))
        try? context.save()
    }
}
