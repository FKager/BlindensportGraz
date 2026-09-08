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
                    LabeledContent("Uhrzeit", value: String(format: "%02d:%02d", favorite.startHour, favorite.startMinute))
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
                    Button("Erstellen") { createSeries() }
                        .disabled(startDates.count == takenDates.count)
                }
            }
            .alert("Serie erstellt", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil; dismiss() } }
            )) {
                Button("OK") { resultMessage = nil; dismiss() }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    private func createSeries() {
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
        resultMessage = message
    }
}
