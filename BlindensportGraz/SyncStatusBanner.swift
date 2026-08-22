import SwiftUI

/// Visible sync/offline indicator — audit.md SwiftData & CloudKit Finding 3
/// (no user-visible sync/pending state anywhere) + Enhancements #3/#4.
/// Placed once in `MainTabView` (wraps every tab) rather than per-screen, so
/// it's globally visible regardless of which tab is active.
///
/// Deliberately unobtrusive: shows nothing at all during normal operation
/// (`.idle`/`.synced` while online) — only surfaces when there's something
/// the user should actually know about (offline, or a sync that failed
/// after all retries). Never a full-screen blocker; a thin banner at the
/// top that pushes content down via `.safeAreaInset`, matching this app's
/// existing toast-notification convention (see `BlindensportGrazApp`'s
/// `showToast` NotificationCenter posts) rather than inventing a new one.
struct SyncStatusBanner: View {
    private let syncState = SyncState.shared
    private let networkMonitor = NetworkMonitor.shared

    var body: some View {
        Group {
            if !networkMonitor.isOnline {
                banner(
                    text: "Offline – Änderungen werden synchronisiert, sobald wieder eine Verbindung besteht.",
                    systemImage: "wifi.slash",
                    color: .orange
                )
            } else if syncState.status == .failed {
                banner(
                    text: "Synchronisierung fehlgeschlagen. Wird automatisch erneut versucht.",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .red
                )
            } else if syncState.status == .syncing {
                banner(
                    text: "Synchronisiert…",
                    systemImage: "arrow.triangle.2.circlepath",
                    color: .secondary
                )
            }
        }
    }

    private func banner(text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            // Not decorative — this is the one piece of information this
            // view exists to announce, so VoiceOver should read it like any
            // other status text, not skip it as chrome.
            .accessibilityElement(children: .combine)
    }
}
