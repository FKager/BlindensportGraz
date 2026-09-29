import SwiftUI

/// Small tinted badge showing a membership's stored role value on a
/// `TeamDetailView` roster row.
struct MembershipRoleCapsule: View {
    let role: MembershipRole

    var body: some View {
        Text(role.rawValue)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .badge(tint: .blue)
    }
}
