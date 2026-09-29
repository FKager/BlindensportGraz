import SwiftUI
import SwiftData

/// Admin-only club finance overview — pushed from the "Verein" tab's admin
/// hub (`VereinHubList`/`VereinSplitView` in VereinView.swift/VereinSplitView.swift), so it doesn't
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
