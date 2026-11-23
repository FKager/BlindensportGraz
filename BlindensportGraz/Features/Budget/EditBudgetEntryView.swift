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

    /// What's missing; shown above the buttons and read out.
    @State private var formMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                FormTitleHeader(title: "Eintrag bearbeiten")
                BudgetEntryFields(category: $entry.category, amount: $amount, date: $entry.date, note: $entry.note,
                                  selectedEventID: $selectedEventID, allEvents: allEvents)
                FormActionButtons(primaryTitle: "Fertig", cancelTitle: nil, message: formMessage,
                                  onPrimary: attemptSave)
            }
            .onAppear {
                amount = entry.amount
                selectedEventID = entry.event?.id
            }
        }
    }

    /// "Fertig" is never greyed out: it says what's missing instead.
    private func attemptSave() {
        if (amount ?? 0) <= 0 {
            show(String(localized: "Bitte gib einen Betrag größer als 0 ein."))
            return
        }
        formMessage = nil
        performPrimary()
    }

    private func performPrimary() {
        guard let amount, amount > 0 else { return }
        entry.amount = amount
        entry.event = selectedEventID.flatMap { id in allEvents.first { $0.id == id } }
        BudgetEntryService.save(entry, modelContext: modelContext)
        dismiss()

    }

    /// Shown above the buttons and read out, as it appears away from the VoiceOver cursor.
    private func show(_ message: String) {
        formMessage = message
        AccessibilityNotification.Announcement(message).post()
    }
}
