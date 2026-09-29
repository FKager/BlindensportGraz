import SwiftUI
import SwiftData

struct EventRow: View {
    let event: SportEvent

    var body: some View {
        HStack(spacing: 12) {
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
              .frame(width: 50)
              .padding(.vertical, 4)
              .background(.blue.opacity(Theme.badgeOpacity), in: RoundedRectangle(cornerRadius: 8))

            SportGlyph(sport: event.sport, size: 28)

            VStack(alignment: .leading, spacing: 4) {
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
          .padding(.vertical, 4)
      }
}
