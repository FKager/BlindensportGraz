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

    /// What's missing; shown above the buttons and read out.
    @State private var formMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                FormTitleHeader(title: "Neuer Eintrag")
                BudgetEntryFields(category: $category, amount: $amount, date: $date, note: $note,
                                  selectedEventID: $selectedEventID, allEvents: allEvents)
                FormActionButtons(primaryTitle: "Speichern", cancelTitle: "Abbrechen", message: formMessage,
                                  onPrimary: attemptSave, onCancel: { dismiss() })
            }
        }
    }

    /// "Speichern" is never greyed out: it says what's missing instead.
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
        let event = selectedEventID.flatMap { id in allEvents.first { $0.id == id } }
        let entry = BudgetEntry(category: category, amount: amount, date: date, note: note,
                                event: event, createdBy: currentUser?.id.uuidString ?? "")
        modelContext.insert(entry)
        BudgetEntryService.save(entry, modelContext: modelContext)
        dismiss()

    }

    /// Shown above the buttons and read out, as it appears away from the VoiceOver cursor.
    private func show(_ message: String) {
        formMessage = message
        AccessibilityNotification.Announcement(message).post()
    }
}
