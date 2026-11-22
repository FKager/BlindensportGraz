import SwiftUI
import SwiftData
import Combine

struct TournamentRow: View {
    /// Width of the date column; grows with Dynamic Type so the date never clips.
    @ScaledMetric(relativeTo: .caption) private var dateColumnWidth = 44.0
    /// From xxLarge text the columns stack, so nothing is cut off (accessibility audit).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isStacked: Bool { dynamicTypeSize >= .xxLarge }

    private var rowLayout: AnyLayout {
        isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.m))
    }

   let tournament: Tournament

  var statusColor: Color {
      switch tournament.status {
       case "planned": return Theme.Palette.info
        case "ongoing": return Theme.Palette.success
         case "finished": return Theme.Palette.secondary
          default: return Theme.Palette.secondary
           }
     }

  var body: some View {
    // Column order matches TrainingRow, per user request: date, then name, then time.
    rowLayout {
      VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
          Text(tournament.startDate, format: .dateTime.weekday(.abbreviated))
          Text(tournament.startDate, format: .dateTime.day().month(.abbreviated))
      }
      .font(.caption)
      .foregroundStyle(Theme.Palette.secondary)
      .frame(width: dateColumnWidth, alignment: .leading)

      SportGlyph(sport: tournament.sport, size: 32)

      VStack(alignment: .leading, spacing: Theme.Spacing.s) {
          // Status under the title, not beside it: beside it, it squeezed
          // the title to "Torball-turnier" (accessibility audit).
          Text(tournament.title)
            .font(.headline)
          TagLabel(tournament.statusLabel, tint: statusColor, emphasized: true)
          // Team count removed from the overview per user request
          // 2026-09-14 — still shown in TournamentDetailView's "Details"
          // section (LabeledContent("Max. Teams", ...)), just not the row.
          // Icon inline with the text; the Label was cut off at larger sizes.
          Text("\(Image(systemName: SportIcon.symbolName(for: tournament.sport))) \(tournament.sport)")
              .font(.caption)
              .foregroundStyle(Theme.Palette.secondary)
              .accessibilityLabel(tournament.sport)

         HStack {
            Image(systemName: "mappin.and.ellipse")
                .accessibilityHidden(true)
             // City alongside the venue name — user request: name, city,
             // date, cost in the overview. Only appended when set, same
             // "don't show an empty field" convention as elsewhere (e.g.
             // SportEvent.cityWithCountry).
             Text(tournament.city.isEmpty ? tournament.location : "\(tournament.location), \(tournament.city)")
          }
          .font(.caption)
          .foregroundStyle(Theme.Palette.secondary)

         // Cost — same "Gesamtkosten" figure (sum of PRAE amounts) shown in
         // TournamentDetailView's Anwesenheit section, see
         // SportEvent.totalPraeAmount. Only shown once something's actually
         // been entered, matching that view's identical conditional.
         if tournament.totalPraeAmount > 0 {
             HStack {
                 Image(systemName: "eurosign.circle")
                     .accessibilityHidden(true)
                 Text("\(Int(tournament.totalPraeAmount)) €")
             }
             .font(.caption)
             .foregroundStyle(Theme.Palette.secondary)
         }
       }
       // The text column gets the width first; the time keeps only what it needs.
       .layoutPriority(1)

      if !isStacked { Spacer() }

      Text(tournament.startDate, format: .dateTime.hour().minute())
          .font(.subheadline)
          .foregroundStyle(Theme.Palette.secondary)
      }
       .padding(.vertical, Theme.Spacing.xs)
    }
}
