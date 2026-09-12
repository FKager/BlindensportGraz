import SwiftUI
import SwiftData

/// Creates a weekly-recurring series of trainings from a `TrainingFavorite`
/// in one action (architecture-review.md §5). Reached from a favorite chip's
/// context menu / accessibility action in `AddTrainingView`. The favorite
/// already stores everything a `Training` needs (title, sport, weekday,
/// time, duration, address, teams) — this screen only asks "how many weeks"
/// and previews which dates are already taken.
struct TrainingSeriesView: View {
    let favorite: TrainingFavorite
    let allTeams: [Team]
    let currentUser: User?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var weeks = 8
    @State private var resultMessage: String?
    @State private var isShowingResult = false
    @State private var isCreating = false
    // Bumped once the on-appear sync below completes, purely to force
    // `takenDates` to recompute against the freshened local store — this
    // view holds no @Query, so a background modelContext insert from
    // syncAll() wouldn't otherwise trigger a re-render. See bug-437: the
    // duplicate check here (and in createSeries()) reads ONLY the local
    // SwiftData store, so a stale store — this device hasn't pulled a
    // training someone else already created for these dates — used to
    // silently create real duplicates.
    @State private var refreshTrigger = 0

    private var startDates: [Date] { favorite.seriesStartDates(count: weeks) }

    private var takenDates: [Date] {
        TrainingService.partitionSeriesDates(title: favorite.title, sport: favorite.sport,
                                             startDates: startDates, modelContext: modelContext).taken
    }

    private var weekdayName: String {
        var comps = DateComponents(); comps.weekday = favorite.weekday
        let date = Calendar.current.nextDate(after: .now, matching: comps, matchingPolicy: .nextTime) ?? .now
        return date.formatted(.dateTime.weekday(.wide))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vorlage") {
                    LabeledContent("Training", value: favorite.title)
                    LabeledContent("Sportart", value: favorite.sport)
                    LabeledContent("Wochentag", value: weekdayName)
                    LabeledContent("Uhrzeit", value: "\(favorite.startHour.formatted(.number.precision(.integerLength(2)))):\(favorite.startMinute.formatted(.number.precision(.integerLength(2))))")
                }

                Section("Serie") {
                    Stepper("Anzahl Wochen: \(weeks)", value: $weeks, in: 2...26)
                    if let first = startDates.first, let last = startDates.last {
                        LabeledContent("Erster Termin", value: first.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Letzter Termin", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    if !takenDates.isEmpty {
                        Label("\(takenDates.count) von \(weeks) Terminen existieren bereits und werden übersprungen.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    ForEach(startDates, id: \.self) { date in
                        HStack {
                            Text(date.formatted(date: .complete, time: .shortened))
                            Spacer()
                            if takenDates.contains(date) {
                                Text("vorhanden")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(takenDates.contains(date) ? .secondary : .primary)
                    }
                } header: {
                    Text("Termine")
                }
            }
            .navigationTitle("Serie erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Erstellen") { createSeries() }
                            .disabled(startDates.count == takenDates.count)
                    }
                }
            }
            .alert("Serie erstellt", isPresented: $isShowingResult, presenting: resultMessage) { _ in
                Button("OK") { dismiss() }
            } message: { message in
                Text(message)
            }
            .onChange(of: isShowingResult) { _, isShowing in
                if !isShowing { dismiss() }
            }
            // Refreshes the local store before the "existiert bereits"
            // preview above is computed against it — see refreshTrigger's
            // doc comment / bug-437. `createSeries()` below does its own
            // sync right before writing, so this one is purely for an
            // accurate preview, not the actual duplicate-safety fix.
            .task {
                await SyncOrchestrationService.syncAll(modelContext: modelContext)
                refreshTrigger += 1
            }
        }
    }

    private func createSeries() {
        isCreating = true
        Task {
            // The actual fix for bug-437: this device's local store might
            // not yet have a training someone else created for one of
            // these dates (a different device, or this one before its most
            // recent launch) — TrainingService.createSeries' duplicate
            // check only ever looks at the local store, so syncing first is
            // what makes that check trustworthy right before it runs.
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
            let outcome = TrainingService.createSeries(
                from: favorite, startDates: startDates, allTeams: allTeams,
                createdBy: currentUser?.id.uuidString ?? "", modelContext: modelContext
            )
            var message = "\(outcome.created) Training\(outcome.created == 1 ? "" : "s") erstellt."
            if outcome.skipped > 0 {
                message += " \(outcome.skipped) übersprungen (bereits vorhanden)."
            }
            if outcome.created > 0 {
                NotificationCenter.default.post(
                    name: NSNotification.Name("TrainingCreated"),
                    object: nil,
                    userInfo: [
                        "message": "\(outcome.created) neue Trainings erstellt!",
                        "title": favorite.title,
                        "sport": favorite.sport,
                        "location": favorite.location
                    ]
                )
            }
            isCreating = false
            resultMessage = message
            isShowingResult = true
        }
    }
}
