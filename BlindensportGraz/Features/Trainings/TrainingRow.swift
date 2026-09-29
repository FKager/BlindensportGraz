import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct TrainingRow: View {
     let training: Training

    // Mirrors TournamentRow.statusColor — deliberately not shown at all for
    // the default "open" status (an "Offen" badge on every single row would
    // just be visual noise; only the two states worth calling out get one).
    var statusColor: Color {
        switch training.status {
        case Training.heldStatus: return .green
        case Training.cancelledStatus: return .red
        default: return .secondary
        }
    }

    var body: some View {
        // Column order per user request: date, then name, then time.
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(training.startDate, format: .dateTime.weekday(.abbreviated))
                Text(training.startDate, format: .dateTime.day().month(.abbreviated))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .leading)

            SportGlyph(sport: training.sport, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(training.title)
                       .font(.headline)
                    if training.status != Training.openStatus {
                        Spacer()
                        Text(training.statusLabel)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .badge(tint: statusColor, opacity: Theme.emphasizedBadgeOpacity)
                            .foregroundStyle(statusColor)
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
       .padding(.vertical, 4)
    }
}
