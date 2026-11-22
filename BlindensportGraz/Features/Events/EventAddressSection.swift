import SwiftUI

/// Editable address of an event, training or tournament.
struct EventAddressSection: View {
    @Bindable var event: SportEvent

    var body: some View {
        Section(heading: "Adresse") {
            StackedField(label: "Straße", text: $event.street)
            StackedField(label: "PLZ", text: $event.zip)
            StackedField(label: "Ort", text: $event.city)
            StackedField(label: "Land", text: $event.country)
        }
    }
}
