import SwiftUI
import SwiftData

struct StatCard: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Decorative — see sectionHeader's identical treatment above;
            // `value`/`title` right below already say everything this card
            // needs to communicate.
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(value)
                .font(.title)
                .bold()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card(tint: color)
        .accessibilityElement(children: .combine)
    }
}
