import SwiftUI

/// "Kontoinformationen" on the Account tab.
struct AccountInfoSection: View {
    let user: User
    /// Whether the user's roster entry is a Grazer VSC member.
    let isGVSCMember: Bool

    var body: some View {
        Section(heading: "Kontoinformationen") {
            LabeledContent("E-Mail", value: user.email)
            LabeledContent("Mitglied seit",
                           value: user.createdAt.formatted(date: .abbreviated, time: .omitted))
            LabeledContent("Teams", value: "\(user.memberships.count)")
            LabeledContent("Teilnahmen", value: "\(user.participations.count)")
            LabeledContent("Grazer VSC") {
                Label(isGVSCMember ? "Mitglied" : "Kein Mitglied",
                      systemImage: isGVSCMember ? "checkmark.seal.fill" : "xmark.seal")
                    .foregroundStyle(isGVSCMember ? Theme.Palette.success : Theme.Palette.secondary)
            }
        }
    }
}
