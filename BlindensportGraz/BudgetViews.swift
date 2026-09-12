import SwiftUI
import SwiftData

/// Admin-only club finance overview — pushed from the "Verein" tab's admin
/// hub (`VereinHubList`/`VereinSplitView` in TeamsViews.swift), so it doesn't
/// wrap its own NavigationStack (same convention as `RoleChangeLogView`,
/// which made the identical move off a sheet earlier). Year-scoped (like
/// SeasonDashboardView), combining logged `BudgetEntry` records with the
/// existing `Attendance.praeAmount` total via `BudgetSummary` so the "cost of
/// running events" figure is honest without double-entry.
struct BudgetView: View {
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [BudgetEntry]
    @Query private var allAttendances: [Attendance]

    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var showAdd = false
    @State private var editingEntry: BudgetEntry?

    private var summary: BudgetSummary.Summary {
        BudgetSummary.summary(year: year, entries: entries, attendances: allAttendances)
    }

    private var yearEntries: [BudgetEntry] {
        entries.filter { Calendar.current.component(.year, from: $0.date) == year }
    }

    private func filteredEntries(_ category: BudgetCategory) -> [BudgetEntry] {
        yearEntries.filter { $0.category == category }.sorted { $0.date > $1.date }
    }

    var body: some View {
        Form {
            Section("Jahr") {
                Stepper("Jahr: \(String(year))", value: $year, in: 2020...2100)
            }

            Section("Überblick") {
                LabeledContent("Einnahmen") {
                    Text(summary.totalIncome, format: .currency(code: "EUR"))
                }
                LabeledContent("Ausgaben") {
                    Text(summary.totalExpense, format: .currency(code: "EUR"))
                }
                LabeledContent("Saldo") {
                    Text(summary.netBalance, format: .currency(code: "EUR"))
                        .foregroundStyle(summary.netBalance < 0 ? .red : .primary)
                        .bold()
                }
            }

            categorySection(.fixedSubsidy)
            categorySection(.donation)

            Section("Kosten Veranstaltungen") {
                HStack {
                    Text("PRAE (Anwesenheit)")
                    Spacer()
                    Text(summary.praeTotal, format: .currency(code: "EUR"))
                        .foregroundStyle(.secondary)
                }
                ForEach(filteredEntries(.eventCost)) { entry in
                    entryRow(entry)
                }
                .onDelete { offsets in delete(offsets, from: filteredEntries(.eventCost)) }
                HStack {
                    Text("Gesamt").bold()
                    Spacer()
                    Text(summary.totalEventCost, format: .currency(code: "EUR")).bold()
                }
            }

            categorySection(.otherExpense)
        }
        .navigationTitle("Vereinsbudget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Eintrag hinzufügen")
            }
        }
        .refreshable {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
        }
        .sheet(isPresented: $showAdd) {
            AddBudgetEntryView(currentUser: currentUser)
        }
        .sheet(item: $editingEntry) { entry in
            EditBudgetEntryView(entry: entry)
        }
    }

    @ViewBuilder
    private func categorySection(_ category: BudgetCategory) -> some View {
        Section(category.displayLabel) {
            let rows = filteredEntries(category)
            if rows.isEmpty {
                Text("Für \(String(year)) wurden noch keine Einträge dieser Art erfasst.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { entry in
                    entryRow(entry)
                }
                .onDelete { offsets in delete(offsets, from: rows) }
                HStack {
                    Text("Gesamt").bold()
                    Spacer()
                    Text(rows.map(\.amount).reduce(0, +), format: .currency(code: "EUR")).bold()
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: BudgetEntry) -> some View {
        Button {
            editingEntry = entry
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.note.isEmpty ? entry.category.displayLabel : entry.note)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Text(entry.date, format: .dateTime.day().month().year())
                        if let title = entry.event?.title {
                            Text("· \(title)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.amount, format: .currency(code: "EUR"))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func delete(_ offsets: IndexSet, from rows: [BudgetEntry]) {
        for index in offsets {
            BudgetEntryService.delete(rows[index], modelContext: modelContext)
        }
    }
}

/// Shared field set for adding/editing a BudgetEntry — matches this app's
/// Add-view vs. Detail/edit-view split (e.g. AddEventView/EventDetailView)
/// rather than one generic form: AddBudgetEntryView builds a brand-new
/// instance from local @State, EditBudgetEntryView binds an existing
/// @Bindable entry directly, same as TrainingDetailView's editable fields.
private struct BudgetEntryFields: View {
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
