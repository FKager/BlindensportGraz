import SwiftUI

struct TeamRow: View {
    let team: Team

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(Theme.brandFill)
                Text(team.name.prefix(1).uppercased())
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)
                    // Fixed-size avatar badge — wrapping isn't meaningful for a
                    // single initial, so shrink instead of clipping at large
                    // Dynamic Type sizes (audit.md Accessibility Finding 4).
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    // Decorative: VoiceOver reads the team name right after.
                    .accessibilityHidden(true)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(team.name)
                    .font(.headline)
                Text(team.sport)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondary)
                Text("^[\(team.memberships.count) Mitglied](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
