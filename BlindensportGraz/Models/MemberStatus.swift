import Foundation

/// `members.status`. Removing an entry takes two steps: anyone who manages
/// members marks it `.delete`, then root removes it (`MemberService.delete`).
nonisolated enum MemberStatus: String, CaseIterable, Sendable {
    case new
    case active
    case delete

    var label: String {
        switch self {
        case .new: "Neu"
        case .active: "Aktiv"
        case .delete: "Zum Löschen markiert"
        }
    }
}
