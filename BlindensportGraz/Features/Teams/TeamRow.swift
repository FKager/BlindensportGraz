import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TeamRow: View {
    let team: Team

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .purple],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                Text(team.name.prefix(1).uppercased())
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)
                    // Fixed-size avatar badge — wrapping isn't meaningful for a
                    // single initial, so shrink instead of clipping at large
                    // Dynamic Type sizes (audit.md Accessibility Finding 4).
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(team.name)
                    .font(.headline)
                Text(team.sport)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(team.memberships.count) Mitglieder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
