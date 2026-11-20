import SwiftUI

/// "Gesamtkosten" under an attendance list; hidden while the total is zero.
struct PraeTotalRow: View {
    let amount: Double

    var body: some View {
        if amount > 0 {
            LabeledContent("Gesamtkosten", value: "\(Int(amount)) €")
        }
    }
}
