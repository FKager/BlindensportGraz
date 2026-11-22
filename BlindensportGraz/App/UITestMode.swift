import Foundation

/// Launch argument `-ui-testing` (BlindensportGrazUITests): the app starts
/// signed out with an empty, in-memory database, so the UI tests always see
/// the same screens, whatever this Simulator was used for before. Debug
/// builds only; a TestFlight / App Store build ignores it.
enum UITestMode {
    nonisolated static var isActive: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        false
        #endif
    }
}
