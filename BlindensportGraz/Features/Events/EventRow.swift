import SwiftUI
import SwiftData

struct EventRow: View {
    /// Width of the day/month badge; grows with Dynamic Type.
    @ScaledMetric(relativeTo: .title2) private var dateBadgeWidth = 50.0

    let event: SportEvent

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack {
                Text(event.startDate, format: .dateTime.day())
                      .font(.title2)
                      .bold()
                      // Fixed-width date badge — shrink rather than clip at
                      // large Dynamic Type sizes (audit.md Accessibility
                      // Finding 4), matching TeamRow's avatar-badge fix.
                      .minimumScaleFactor(0.5)
                      .lineLimit(1)
                Text(event.startDate, format: .dateTime.month(.abbreviated))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .minimumScaleFactor(0.5)
                      .lineLimit(1)
              }
              .frame(width: dateBadgeWidth)
              .padding(.vertical, Theme.Spacing.xs)
              .background(Theme.Accent.events.opacity(Theme.badgeOpacity), in: RoundedRectangle(cornerRadius: Theme.Radius.small))

            SportGlyph(sport: event.sport, size: 28)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(event.title)
                      .font(.headline)
                Text(event.sport)
                      .font(.subheadline)
                      .foregroundStyle(.secondary)
                Label(event.location, systemImage: "mappin.and.ellipse")
                      .font(.caption)
                      .foregroundStyle(.secondary)
              }
          }
          .padding(.vertical, Theme.Spacing.xs)
      }
}
