import SwiftUI
import SwiftData

/// Shared field set for adding/editing a BudgetEntry — matches this app's
/// Add-view vs. Detail/edit-view split (e.g. AddEventView/EventDetailView)
/// rather than one generic form: AddBudgetEntryView builds a brand-new
/// instance from local @State, EditBudgetEntryView binds an existing
/// @Bindable entry directly, same as TrainingDetailView's editable fields.
struct BudgetEntryFields: View {
    @Binding var category: BudgetCategory
    @Binding var amount: Double?
    @Binding var date: Date
    @Binding var note: String
    @Binding var selectedEventID: UUID?
    let allEvents: [SportEvent]

    // Only the 4 real, admin-selectable categories — `.other` is
    // corrupt/legacy-data-only and never offered here.
    static let selectableCategories: [BudgetCategory] = [.fixedSubsidy, .donation, .eventCost, .otherExpense]

    var body: some View {
        Section("Eintrag") {
            Picker("Kategorie", selection: $category) {
                ForEach(Self.selectableCategories, id: \.self) { c in
                    Text(c.displayLabel).tag(c)
                }
            }
            TextField("Betrag (€)", value: $amount, format: .number)
                .keyboardType(.decimalPad)
            DatePicker("Datum", selection: $date, displayedComponents: .date)
            TextField("Notiz", text: $note)
        }
        Section("Verknüpftes Ereignis") {
            Picker("Ereignis", selection: $selectedEventID) {
                Text("Kein Ereignis").tag(UUID?.none)
                ForEach(allEvents.sorted { $0.startDate > $1.startDate }) { event in
                    Text(event.title).tag(Optional(event.id))
                }
            }
        }
    }
}
