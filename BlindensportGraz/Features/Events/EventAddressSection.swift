import SwiftUI

/// Editable address of an event, training or tournament.
struct EventAddressSection: View {
    @Bindable var event: SportEvent

    var body: some View {
        Section(heading: "Adresse") {
            TextField("Straße", text: $event.street)
            TextField("PLZ", text: $event.zip)
            TextField("Ort", text: $event.city)
            TextField("Land", text: $event.country)
        }
    }
}
