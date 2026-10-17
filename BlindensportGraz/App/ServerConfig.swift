import Foundation

/// Where the web admin server (`webadmin/`, serves `/calendar/<token>.ics`) is
/// reachable — architecture-review.md §5 P2 (webcal calendar feed). `nil`
/// until the club deploys it somewhere public (see `webadmin/README.md`'s
/// Deployment section). The calendar-feed URL
/// `AccountView` builds is still shown, with a clearly-marked placeholder
/// host, rather than hiding the feature entirely — the token and route are
/// ready to use the moment a real host is set here and the app rebuilt.
enum ServerConfig {
    /// Bare host, e.g. `"cal.blindensportgraz.at"` — no scheme, no path, no
    /// trailing slash. Release builds (prod Supabase) use the web admin on
    /// nuc; Debug builds talk to staging, whose calendar tokens that server
    /// doesn't know, so they keep the placeholder.
    #if DEBUG
    static let clubMembersAPIHost: String? = nil
    #else
    static let clubMembersAPIHost: String? = "bs.a11y.it"
    #endif
}
