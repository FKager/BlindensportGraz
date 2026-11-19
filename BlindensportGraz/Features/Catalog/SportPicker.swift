import SwiftUI
import SwiftData

/// "Sportart" picker fed by the club's sport list (`ClubSport`), see
/// `CatalogOptions`. With `allowsNone` the first option is "Keine" (empty).
struct SportPicker: View {
    @Binding var selection: String
    var allowsNone = false

    @Query private var sports: [ClubSport]

    private var names: [String] {
        CatalogOptions.including(selection, in: CatalogOptions.sportNames(from: sports))
    }

    var body: some View {
        Picker("Sportart", selection: $selection) {
            if allowsNone {
                Text("Keine").tag("")
            }
            ForEach(names, id: \.self) { name in
                Label(name, systemImage: SportIcon.symbolName(for: name)).tag(name)
            }
        }
        .onAppear {
            if selection.isEmpty, !allowsNone, let first = names.first { selection = first }
        }
    }
}
