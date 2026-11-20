import SwiftData
import SwiftUI

/// The training's own editable fields: title, sport, venue, address, start,
/// duration, focus and status.
struct TrainingFieldsSections: View {
    @Bindable var training: Training
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Section("Training") {
            TextField("Titel", text: $training.title)
            SportPicker(selection: $training.sport, allowsNone: true)
            TextField("Veranstaltungsort", text: $training.location)
        }
        EventAddressSection(event: training)
        Section("Planung") {
            DatePicker("Start", selection: $training.startDate)
                .onChange(of: training.startDate) { training.recomputeEndDate() }
            Stepper("Dauer: \(training.durationMinutes) min", value: $training.durationMinutes, in: 15...240, step: 15)
                .onChange(of: training.durationMinutes) { training.recomputeEndDate() }
            TextField("Schwerpunkt", text: $training.focusArea)
            Picker("Status", selection: $training.status) {
                Text("Offen").tag(Training.openStatus)
                Text("Durchgeführt").tag(Training.heldStatus)
                Text("Abgesagt").tag(Training.cancelledStatus)
            }
            // Same "no attendance for a cancelled training" rule as the
            // list's swipe action — the other place status can change to
            // Abgesagt, so it needs the same side effect.
            .onChange(of: training.status) {
                if training.status == Training.cancelledStatus {
                    AttendanceService.deleteAll(for: training, modelContext: modelContext)
                }
            }
        }
    }
}
