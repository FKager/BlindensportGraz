import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct TrainingRow: View {
    /// Width of the date column; grows with Dynamic Type so the date never clips.
    @ScaledMetric(relativeTo: .caption) private var dateColumnWidth = 44.0

     let training: Training

    // Mirrors TournamentRow.statusColor — deliberately not shown at all for
    // the default "open" status (an "Offen" badge on every single row would
    // just be visual noise; only the two states worth calling out get one).
    var statusColor: Color {
        switch training.status {
        case Training.heldStatus: return Theme.Palette.success
        case Training.cancelledStatus: return Theme.Palette.danger
        default: return .secondary
        }
    }

    var body: some View {
        // Column order per user request: date, then name, then time.
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(training.startDate, format: .dateTime.weekday(.abbreviated))
                Text(training.startDate, format: .dateTime.day().month(.abbreviated))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: dateColumnWidth, alignment: .leading)

            SportGlyph(sport: training.sport, size: 32)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text(training.title)
                       .font(.headline)
                    if training.status != Training.openStatus {
                        Spacer()
                        TagLabel(training.statusLabel, tint: statusColor, emphasized: true)
                    }
                }
                HStack {
                    Label(training.sport, systemImage: SportIcon.symbolName(for: training.sport))
                    Spacer()
                    Label(training.location, systemImage: "mappin.and.ellipse")
                   }
                   .font(.caption)
                   .foregroundStyle(.secondary)
            }

            Spacer()

            Text(training.startDate, format: .dateTime.hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
       .padding(.vertical, Theme.Spacing.xs)
    }
}
