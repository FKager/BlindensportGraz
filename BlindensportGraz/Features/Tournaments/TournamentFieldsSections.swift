import SwiftUI

/// The tournament's own editable fields: name, sport, venue, address,
/// dates, team limit and status.
struct TournamentFieldsSections: View {
    @Bindable var tournament: Tournament

    var body: some View {
        Section(heading: "Turnier") {
            StackedField(label: "Name", text: $tournament.title)
            SportPicker(selection: $tournament.sport, allowsNone: true)
            StackedField(label: "Veranstaltungsort", text: $tournament.location)
        }
        EventAddressSection(event: tournament)
        Section(heading: "Zeitraum") {
            DatePicker("Start", selection: $tournament.startDate, displayedComponents: [.date])
            DatePicker("Ende", selection: $tournament.endDate, displayedComponents: [.date])
        }
        Section(heading: "Details") {
            NumberPicker("Max. Teams", value: $tournament.maxTeams, values: Array(2...64))
            Picker("Status", selection: $tournament.status) {
                Text("Geplant").tag("planned")
                Text("Laufend").tag("ongoing")
                Text("Beendet").tag("finished")
            }
        }
    }
}
