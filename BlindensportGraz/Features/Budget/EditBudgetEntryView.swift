import SwiftUI
import SwiftData

struct EditBudgetEntryView: View {
    @Bindable var entry: BudgetEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allEvents: [SportEvent]

    // Amount is bound as an Optional locally so the same BudgetEntryFields
    // view (and its "must be > 0" disabled check) works identically for both
    // Add and Edit, then written back to entry.amount only on save.
    @State private var amount: Double?
    @State private var selectedEventID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                BudgetEntryFields(category: $entry.category, amount: $amount, date: $entry.date, note: $entry.note,
                                  selectedEventID: $selectedEventID, allEvents: allEvents)
            }
            .navigationTitle("Eintrag bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        guard let amount, amount > 0 else { return }
                        entry.amount = amount
                        entry.event = selectedEventID.flatMap { id in allEvents.first { $0.id == id } }
                        BudgetEntryService.save(entry, modelContext: modelContext)
                        dismiss()
                    }
                    .disabled((amount ?? 0) <= 0)
                }
            }
            .onAppear {
                amount = entry.amount
                selectedEventID = entry.event?.id
            }
        }
    }
}
