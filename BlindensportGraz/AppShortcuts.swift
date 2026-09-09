import AppIntents

/// Siri / Shortcuts / Spotlight entry points (architecture-review.md §5).
/// Zero-setup: `AppShortcutsProvider` needs no Siri entitlement and no
/// separate extension target — the intents run in the app's own process
/// (the system launches it in the background if needed), so they read the
/// real SwiftData store via `NextEventLookup` with no App Group required.

struct NextTrainingIntent: AppIntent {
    static let title: LocalizedStringResource = "Nächstes Training"
    static let description = IntentDescription("Sagt dir, wann und wo dein nächstes Training stattfindet.")
    // Answers inline via Siri/Shortcuts — no need to bring the app forward.
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = NextEventLookup.makeContext() else {
            return .result(dialog: "Die Trainingsdaten sind gerade nicht verfügbar.")
        }
        let user = NextEventLookup.currentUser(in: context)
        guard let training = NextEventLookup.nextTraining(in: context, for: user) else {
            return .result(dialog: "Du hast kein bevorstehendes Training.")
        }
        return .result(dialog: IntentDialog(stringLiteral: NextEventLookup.spokenLine(
            kind: "Training", title: training.title, date: training.startDate,
            location: training.location, includeTime: true
        )))
    }
}

struct NextTournamentIntent: AppIntent {
    static let title: LocalizedStringResource = "Nächstes Turnier"
    static let description = IntentDescription("Sagt dir, wann und wo dein nächstes Turnier stattfindet.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = NextEventLookup.makeContext() else {
            return .result(dialog: "Die Turnierdaten sind gerade nicht verfügbar.")
        }
        let user = NextEventLookup.currentUser(in: context)
        guard let tournament = NextEventLookup.nextTournament(in: context, for: user) else {
            return .result(dialog: "Du hast kein bevorstehendes Turnier.")
        }
        return .result(dialog: IntentDialog(stringLiteral: NextEventLookup.spokenLine(
            kind: "Turnier", title: tournament.title, date: tournament.startDate,
            location: tournament.location, includeTime: false
        )))
    }
}

struct BlindensportShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextTrainingIntent(),
            phrases: [
                "Nächstes Training in \(.applicationName)",
                "Wann ist mein nächstes Training in \(.applicationName)",
                "Mein nächstes Training in \(.applicationName)"
            ],
            shortTitle: "Nächstes Training",
            systemImageName: "figure.run"
        )
        AppShortcut(
            intent: NextTournamentIntent(),
            phrases: [
                "Nächstes Turnier in \(.applicationName)",
                "Wann ist mein nächstes Turnier in \(.applicationName)"
            ],
            shortTitle: "Nächstes Turnier",
            systemImageName: "trophy.fill"
        )
    }
}
