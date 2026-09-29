import SwiftUI
import SwiftData

/// PRAE amount for one present helper/coach: a swipe-to-select wheel in €5
/// steps (the common case, "select via swipe" user requirement) plus an
/// exact-amount text field for values off that grid (user request
/// 2026-09-14). Both are clamped to `0...maxPrae`.
///
/// Same local-state pattern as `AttendanceRow`: edits save via `.onChange`
/// of the local values; model changes (e.g. from a sync pull) only update
/// what's displayed.
struct PraeAmountRow: View {
    /// Width of the exact-amount field; fits two to three digits at any text size.
    @ScaledMetric(relativeTo: .body) private var amountFieldWidth = 44.0

    let attendance: Attendance
    let maxPrae: Int

    @Environment(\.modelContext) private var modelContext
    /// Exact amount in whole euros, as typed.
    @State private var amount = 0
    /// Wheel position: `amount` rounded to the nearest €5 step.
    @State private var wheelStep = 0

    private var storedAmount: Int {
        Int((attendance.praeAmount ?? 0).rounded())
    }

    var body: some View {
        HStack {
            Text("PRAE (€)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            TextField("Betrag", value: $amount, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: amountFieldWidth)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("PRAE Betrag genau eingeben")
            Picker("PRAE (€)", selection: $wheelStep) {
                ForEach(Array(stride(from: 0, through: maxPrae, by: 5)), id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(width: 100, height: 90)
            .clipped()
        }
        .onChange(of: storedAmount, initial: true) { _, stored in
            amount = stored
        }
        // No `initial:` here — the stored-amount sync above seeds `amount`,
        // and an initial run with the default 0 would wipe the stored value.
        .onChange(of: amount) { _, newAmount in
            amountChanged(to: newAmount)
        }
        .onChange(of: wheelStep) { _, step in
            // Only a real wheel move changes the amount — not the wheel
            // following an off-grid typed value (37 € shows as 35 on the wheel).
            if step != roundedToStep(amount) {
                amount = step
            }
        }
    }

    private func amountChanged(to newAmount: Int) {
        let clamped = min(maxPrae, max(0, newAmount))
        if clamped != newAmount {
            amount = clamped
            return
        }
        wheelStep = roundedToStep(clamped)
        guard clamped != storedAmount else { return }
        attendance.praeAmount = clamped > 0 ? Double(clamped) : nil
        AttendanceService.save(attendance, modelContext: modelContext)
    }

    private func roundedToStep(_ value: Int) -> Int {
        min(maxPrae, max(0, Int((Double(value) / 5).rounded()) * 5))
    }
}
