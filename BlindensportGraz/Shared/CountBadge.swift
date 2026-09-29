import SwiftUI

/// Filled red number bubble for "N items need attention" on a list row
/// (e.g. pending change requests in the Verein hub).
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Theme.Fill.danger, in: .capsule)
    }
}
