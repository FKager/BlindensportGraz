import SwiftUI
import SwiftData
import Combine

struct TournamentRow: View {
   let tournament: Tournament

  var statusColor: Color {
      switch tournament.status {
       case "planned": return .blue
        case "ongoing": return .green
         case "finished": return .gray
          default: return .secondary
           }
     }

  var body: some View {
    // Column order matches TrainingRow, per user request: date, then name, then time.
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
          Text(tournament.startDate, format: .dateTime.weekday(.abbreviated))
          Text(tournament.startDate, format: .dateTime.day().month(.abbreviated))
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(width: 44, alignment: .leading)

      SportGlyph(sport: tournament.sport, size: 32)

      VStack(alignment: .leading, spacing: 6) {
          HStack {
              Text(tournament.title)
                .font(.headline)
               Spacer()
             Text(tournament.status)
                 .font(.caption)
                 .padding(.horizontal, 8)
                 .padding(.vertical, 2)
                 .badge(tint: statusColor, opacity: Theme.emphasizedBadgeOpacity)
                 .foregroundStyle(statusColor)
          }
          // Team count removed from the overview per user request
          // 2026-09-14 — still shown in TournamentDetailView's "Details"
          // section (LabeledContent("Max. Teams", ...)), just not the row.
          Label(tournament.sport, systemImage: SportIcon.symbolName(for: tournament.sport))
              .font(.caption)
              .foregroundStyle(.secondary)

         HStack {
            Image(systemName: "mappin.and.ellipse")
                .accessibilityHidden(true)
             // City alongside the venue name — user request: name, city,
             // date, cost in the overview. Only appended when set, same
             // "don't show an empty field" convention as elsewhere (e.g.
             // SportEvent.locationWithCountry).
             Text(tournament.city.isEmpty ? tournament.location : "\(tournament.location), \(tournament.city)")
          }
          .font(.caption)
          .foregroundStyle(.secondary)

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
             .foregroundStyle(.secondary)
         }
       }

      Spacer()

      Text(tournament.startDate, format: .dateTime.hour().minute())
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
       .padding(.vertical, 4)
    }
}
