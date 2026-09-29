import Observation

/// App-wide failure signal for the persistence service layer (audit.md
/// Architecture Finding 6/8) — a local `modelContext.save()` failure used to
/// vanish into a bare `try?` with no user-facing trace at all. Wired
/// specifically into admin-critical actions per audit.md's own stated
/// priority: role changes (`UserListView`'s Picker) and roster edits
/// (`Member`/`MembersViews.swift`) — NOT universally into every save in the
/// app, which is a much bigger UX change than this phase's scope.
///
/// `@Observable` singleton so any view can bind an `.alert(...)` to
/// `ServiceFailureSignal.shared.message` without threading failure state
/// through every call site individually.
@Observable
final class ServiceFailureSignal {
    static let shared = ServiceFailureSignal()
    private init() {}

    var message: String?

    func report(_ message: String) {
        self.message = message
    }

    func clear() {
        message = nil
    }
}
