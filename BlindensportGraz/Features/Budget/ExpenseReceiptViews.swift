import SwiftUI
import PhotosUI
import UIKit

/// Upload/view/delete UI for KostZ expense receipts (audit.md Enhancement
/// #10) — mirrors `EventImagesSection`'s reusable-section approach (works
/// purely off a resolved `[ExpenseReceipt]` array + add/delete closures, no
/// knowledge of whether the caller is month- or tournament-scoped) rather
/// than writing new list-rendering code from scratch.
///
/// **Embedded on `KostZCalculationView`/`KostZTournamentCalculationView`
/// only, not also duplicated onto the PRAE screens.** KostZ is this app's
/// existing club-wide, one-document-per-accounting-period screen (see
/// `KostZCalculationView`'s own doc comment); a shared pile of expense
/// receipts for a period is a natural fit there. PRAE is scoped per
/// recipient instead (one person's own honorarium paperwork), a finer grain
/// `ExpenseReceipt`'s month/tournament-level scoping doesn't match — adding
/// a second, differently-scoped receipts UI there would need its own model
/// shape, out of scope for this phase. Both period types (month AND
/// tournament) are still fully covered via the two KostZ screens.
///
/// **No expand-to-full-screen `.sheet`** — both KostZ screens embedding
/// this are themselves already sheet-presented (from `TrainingsListView`'s
/// Berichte menu / `TournamentDetailView`'s toolbar), and nesting a second
/// sheet on top of a sheet is a known VoiceOver-freeze pattern in this app
/// (cerebrum.md's 2026-07-18 entries). Tapping a receipt expands it inline
/// in place instead.
struct ExpenseReceiptsSection: View {
    let receipts: [ExpenseReceipt]
    let currentUser: User?
    let onAdd: (Data) -> Void
    let onDelete: (ExpenseReceipt) -> Void

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var expandedReceiptID: UUID?

    private func canDelete(_ receipt: ExpenseReceipt) -> Bool {
        guard let user = currentUser else { return false }
        return user.role == .admin || receipt.uploadedBy == user.id.uuidString
    }

    var body: some View {
        Section("Belege (\(receipts.count))") {
            if receipts.isEmpty {
                Text("Noch keine Belege")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(receipts.sorted { $0.uploadedAt > $1.uploadedAt }) { receipt in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            expandedReceiptID = (expandedReceiptID == receipt.id) ? nil : receipt.id
                        } label: {
                            HStack {
                                if let uiImage = UIImage(data: receipt.imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .accessibilityHidden(true)
                                }
                                Text(receipt.note.isEmpty ? "Beleg" : receipt.note)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(receipt.uploadedAt, format: .dateTime.day().month())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("\(receipt.note.isEmpty ? "Beleg" : receipt.note), hochgeladen am \(receipt.uploadedAt.formatted(.dateTime.day().month().year()))")
                        .accessibilityHint("Doppeltippen, um den Beleg zu vergrößern")

                        if expandedReceiptID == receipt.id, let uiImage = UIImage(data: receipt.imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .accessibilityLabel(receipt.note.isEmpty ? "Beleg" : receipt.note)
                        }
                    }
                    .swipeActions {
                        if canDelete(receipt) {
                            Button(role: .destructive) {
                                onDelete(receipt)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            .accessibilityLabel("Beleg löschen")
                        }
                    }
                }
            }

            PhotosPicker(selection: $selectedItems, matching: .images) {
                Label("Beleg hinzufügen", systemImage: "doc.badge.plus")
            }
        }
        .onChange(of: selectedItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let raw = try? await item.loadTransferable(type: Data.self),
                       let compressed = ImageProcessing.downscaledJPEGData(from: raw) {
                        onAdd(compressed)
                    }
                }
                selectedItems = []
            }
        }
    }
}
