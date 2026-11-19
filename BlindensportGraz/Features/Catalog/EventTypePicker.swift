import SwiftUI
import SwiftData

/// "Art der Veranstaltung" picker: the club's active event types with the
/// given behaviour (`EventType`), see `CatalogOptions`.
///
/// For trainings and tournaments it only appears when the club has more
/// than one type with that behaviour (e.g. "Training" and "Trainingslager"),
/// preselecting the default type. Hidden, the selection stays empty and the
/// server fills in the default ("Training"/"Turnier").
struct EventTypePicker: View {
    @Binding var selection: String
    let behavior: EventType.Behavior

    @Query private var types: [EventType]

    private var names: [String] {
        CatalogOptions.including(selection, in: CatalogOptions.eventTypeNames(from: types, behavior: behavior))
    }

    /// Plain events always pick a type; trainings and tournaments only when
    /// there is a choice.
    private var isShown: Bool {
        behavior == .event || names.count > 1
    }

    var body: some View {
        if isShown {
            Picker("Art der Veranstaltung", selection: $selection) {
                ForEach(names, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .onAppear {
                guard selection.isEmpty else { return }
                if let name = behavior.defaultTypeName, names.contains(name) {
                    selection = name
                } else if let first = names.first {
                    selection = first
                }
            }
        }
    }
}
