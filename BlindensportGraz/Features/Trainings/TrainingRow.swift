import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct TrainingRow: View {
    /// Width of the date column; grows with Dynamic Type so the date never clips.
    @ScaledMetric(relativeTo: .caption) private var dateColumnWidth = 44.0
    /// From xxLarge text the columns stack, so nothing is cut off (accessibility audit).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isStacked: Bool { dynamicTypeSize >= .xxLarge }

    private var detailLayout: AnyLayout {
        isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xxs))
            : AnyLayout(HStackLayout())
    }

    private var rowLayout: AnyLayout {
        isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.m))
    }

     let training: Training

    // Mirrors TournamentRow.statusColor — deliberately not shown at all for
    // the default "open" status (an "Offen" badge on every single row would
    // just be visual noise; only the two states worth calling out get one).
    var statusColor: Color {
        switch training.status {
        case Training.heldStatus: return Theme.Palette.success
        case Training.cancelledStatus: return Theme.Palette.danger
        default: return Theme.Palette.secondary
        }
    }

    var body: some View {
        // Column order per user request: date, then name, then time.
        rowLayout {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(training.startDate, format: .dateTime.weekday(.abbreviated))
                Text(training.startDate, format: .dateTime.day().month(.abbreviated))
            }
            .font(.caption)
            .foregroundStyle(Theme.Palette.secondary)
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
                detailLayout {
                    Label(training.sport, systemImage: SportIcon.symbolName(for: training.sport))
                    if !isStacked { Spacer() }
                    Label(training.location, systemImage: "mappin.and.ellipse")
                   }
                   .font(.caption)
                   .foregroundStyle(Theme.Palette.secondary)
            }
            // The text column gets the width first; the time keeps only what it needs.
            .layoutPriority(1)

            if !isStacked { Spacer() }

            Text(training.startDate, format: .dateTime.hour().minute())
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondary)
        }
       .padding(.vertical, Theme.Spacing.xs)
    }
}
