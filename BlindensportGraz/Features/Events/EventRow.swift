import SwiftUI
import SwiftData

struct EventRow: View {
    /// Type, plus the sport when the event has both ("Langlaufkurs · Ski").
    private var subtitle: String {
        guard !event.eventType.isEmpty, !event.sport.isEmpty else { return event.typeName }
        return "\(event.typeName) · \(event.sport)"
    }

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
                      .foregroundStyle(Theme.Palette.secondary)
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
                Text(subtitle)
                      .font(.subheadline)
                      .foregroundStyle(Theme.Palette.secondary)
                Label(event.location, systemImage: "mappin.and.ellipse")
                      .font(.caption)
                      .foregroundStyle(Theme.Palette.secondary)
              }
          }
          .padding(.vertical, Theme.Spacing.xs)
      }
}
