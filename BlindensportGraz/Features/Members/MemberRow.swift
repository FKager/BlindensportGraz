import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MemberRow: View {
    let member: Member
    let isLinked: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(member.fullName)
                    .font(.headline)
                if !member.fullAddress.isEmpty {
                    Text(member.fullAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // Flags all current Grazer VSC members in this list — user
            // request 2026-09-12 ("A flag Member of Grazer VSC should be
            // used and indicate all current members in the Mitglieder
            // list"). This roster also carries helpers/coaches/one-off
            // attendees (e.g. AddNewEventMemberView's memberOfGVSC:false
            // entries) who aren't formal members, so a non-member row
            // deliberately shows no badge at all rather than a "not a
            // member" negative marker.
            if member.memberOfGVSC {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Mitglied bei Grazer VSC")
            }
            if isLinked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Mit einem Benutzerkonto verknüpft")
                    // .help() only reaches pointer/Catalyst UIs — this icon is the
                    // only place this status is conveyed, so VoiceOver needs its
                    // own label rather than the auto-derived SF Symbol name.
                    .accessibilityLabel("Mit einem Benutzerkonto verknüpft")
            }
        }
        .padding(.vertical, 4)
    }
}
