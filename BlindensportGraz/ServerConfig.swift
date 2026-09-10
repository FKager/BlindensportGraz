import Foundation

/// Where `clubmembersapi` (`RootCLI/Sources/clubmembersapi`) is reachable —
/// architecture-review.md §5 P2 (webcal calendar feed). `nil` until the club
/// actually deploys it somewhere public (see `RootCLI/README.md`'s
/// Deployment/TLS section — as of this writing it only runs at
/// `http://127.0.0.1:8080/` for local development). The calendar-feed URL
/// `AccountView` builds is still shown, with a clearly-marked placeholder
/// host, rather than hiding the feature entirely — the token and route are
/// ready to use the moment a real host is set here and the app rebuilt.
enum ServerConfig {
    /// Bare host, e.g. `"cal.blindensportgraz.at"` — no scheme, no path, no
    /// trailing slash.
    static let clubMembersAPIHost: String? = nil
}
