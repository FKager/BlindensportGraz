import SwiftUI

/// Tag showing a membership's stored role value on a `TeamDetailView`
/// roster row.
struct MembershipRoleCapsule: View {
    let role: MembershipRole

    var body: some View {
        TagLabel(role.rawValue)
    }
}
