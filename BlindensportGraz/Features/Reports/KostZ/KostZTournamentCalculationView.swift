import SwiftUI
import SwiftData

/// Admin-only screen (see TournamentDetailView's toolbar) that totals one
/// tournament's own coach/assistant Attendance.praeAmount records and
/// exports its KostZ form — the per-tournament counterpart to
/// KostZCalculationView's per-month one. No month/year picker: the
/// tournament itself supplies the period (its own start/end dates) and the
/// cost basis (its own PRAE entries), so there's nothing to choose. Same
/// self-contained NavigationStack + eager-export-on-.task pattern as
/// KostZCalculationView, for the same VoiceOver-nested-sheet reason.
struct KostZTournamentCalculationView: View {
    let tournament: Tournament
    let currentUser: User?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // Intentionally unfiltered — see KostZCalculationView's identical
    // @Query comment above (`#Predicate` on `MembershipRole` compiles but
    // crashes at runtime; filtering stays in `eligiblePeople` post-fetch).
    @Query private var allMemberships: [TeamMembership]
    @Query private var allReceipts: [ExpenseReceipt]

    @State private var exportURL: URL?
    @State private var exportError: String?

    private var summary: KostZTournamentSummary {
        KostZCalculator.summary(for: tournament, allMemberships: allMemberships)
    }

    private var receipts: [ExpenseReceipt] {
        allReceipts.filter { $0.tournament?.id == tournament.id }
    }

    private func addReceipt(_ data: Data) {
        let receipt = ExpenseReceipt(imageData: data, uploadedBy: currentUser?.id.uuidString ?? "",
                                      tournament: tournament)
        modelContext.insert(receipt)
        ExpenseReceiptService.save(receipt, modelContext: modelContext)
    }

    private func deleteReceipt(_ receipt: ExpenseReceipt) {
        ExpenseReceiptService.delete(receipt, modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Honorare Trainer:innen / Helfer:innen") {
                    if summary.personAmounts.isEmpty {
                        Text("Keine Einsätze mit hinterlegtem PRAE-Betrag bei diesem Turnier.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(summary.personAmounts) { entry in
                            HStack {
                                Text(entry.person.displayName)
                                Spacer()
                                Text(entry.amount, format: .currency(code: "EUR"))
                            }
                        }
                        HStack {
                            Text("Gesamt").bold()
                            Spacer()
                            Text(summary.total, format: .currency(code: "EUR"))
                                .bold()
                        }
                        LabeledContent("Anzahl Personen", value: "\(summary.personCount)")
                    }
                }

                ExpenseReceiptsSection(receipts: receipts, currentUser: currentUser,
                                        onAdd: addReceipt, onDelete: deleteReceipt)

                Section("Export") {
                    Text("Nur die Zeile „HONORARE / VERGÜTUNGEN“ sowie Zeitraum und Personenanzahl werden vorausgefüllt — alle übrigen Kostenarten, Beilagen-Nummern und der Ort müssen weiterhin von Hand ergänzt werden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("KostZ-Formular exportieren", systemImage: "doc.fill")
                        }
                    } else {
                        Label("KostZ-Formular wird vorbereitet …", systemImage: "doc.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("KostZ: \(tournament.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Export fehlgeschlagen", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .task(id: summary.total) {
                exportURL = nil
                do {
                    exportURL = try KostZExporter.export(summary: summary)
                } catch {
                    exportError = error.localizedDescription
                }
            }
        }
    }
}
