import Foundation
import SwiftData
import WidgetKit

/// Bridges the app's SwiftData world to the widget: recompute "what's next"
/// for the signed-in user and hand it over via `WidgetBridge`, then poke
/// WidgetKit to reload. Cheap (two in-memory fetches), so it's fine to call
/// on every sync and every time the app comes to the foreground.
@MainActor
enum WidgetRefresher {
    static func refresh(modelContext: ModelContext, for user: User?) {
        let training = NextEventLookup.nextTraining(in: modelContext, for: user)
        let tournament = NextEventLookup.nextTournament(in: modelContext, for: user)

        let snapshot: NextUpSnapshot?
        switch (training, tournament) {
        case let (t?, u?):
            snapshot = t.startDate <= u.startDate ? snap(t) : snap(u)
        case let (t?, nil):
            snapshot = snap(t)
        case let (nil, u?):
            snapshot = snap(u)
        case (nil, nil):
            snapshot = nil
        }

        WidgetBridge.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func snap(_ t: Training) -> NextUpSnapshot {
        NextUpSnapshot(kind: .training, title: t.title, startDate: t.startDate, location: t.location)
    }

    private static func snap(_ u: Tournament) -> NextUpSnapshot {
        NextUpSnapshot(kind: .tournament, title: u.title, startDate: u.startDate, location: u.location)
    }
}
