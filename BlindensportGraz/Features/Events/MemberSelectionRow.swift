import SwiftUI
import SwiftData

/// One toggleable row in a Users/Members multi-select list — shared by
/// AddEventView and EventDetailView's "Mitglieder" section. Same
/// Button+checkmark+`.isSelected` trait shape as the Team multi-select rows
/// elsewhere in this app (AddTrainingView/AddTournamentView), just factored
/// out since two call sites (Users, Members) needed it per screen here
/// instead of one.
struct MemberSelectionRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
