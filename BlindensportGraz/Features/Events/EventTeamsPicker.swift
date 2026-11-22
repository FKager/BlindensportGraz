import SwiftUI

/// "Beteiligte Teams" while editing an event: tapping a team adds or removes
/// it. Selected teams carry a checkmark and the selected trait for VoiceOver.
/// Shown only when there are teams to choose from.
struct EventTeamsPicker: View {
    let event: SportEvent
    /// The teams this user may assign.
    let teams: [Team]

    var body: some View {
        if !teams.isEmpty {
            Section(heading: "Beteiligte Teams") {
                ForEach(teams) { team in
                    Button {
                        toggle(team)
                    } label: {
                        HStack {
                            Text(team.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected(team) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Palette.info)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(isSelected(team) ? .isSelected : [])
                }
                Text("Keine Auswahl = für alle sichtbar")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
    }

    private func isSelected(_ team: Team) -> Bool {
        event.teams.contains { $0.id == team.id }
    }

    private func toggle(_ team: Team) {
        if isSelected(team) {
            event.teams.removeAll { $0.id == team.id }
        } else {
            event.teams.append(team)
        }
    }
}
