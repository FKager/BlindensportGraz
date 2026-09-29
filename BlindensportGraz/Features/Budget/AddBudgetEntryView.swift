import SwiftUI
import SwiftData

struct AddBudgetEntryView: View {
    let currentUser: User?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allEvents: [SportEvent]

    @State private var category: BudgetCategory = .otherExpense
    @State private var amount: Double?
    @State private var date = Date()
    @State private var note = ""
    @State private var selectedEventID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                BudgetEntryFields(category: $category, amount: $amount, date: $date, note: $note,
                                  selectedEventID: $selectedEventID, allEvents: allEvents)
            }
            .navigationTitle("Neuer Eintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard let amount, amount > 0 else { return }
                        let event = selectedEventID.flatMap { id in allEvents.first { $0.id == id } }
                        let entry = BudgetEntry(category: category, amount: amount, date: date, note: note,
                                                event: event, createdBy: currentUser?.id.uuidString ?? "")
                        modelContext.insert(entry)
                        BudgetEntryService.save(entry, modelContext: modelContext)
                        dismiss()
                    }
                    .disabled((amount ?? 0) <= 0)
                }
            }
        }
    }
}
