import SwiftUI
import SwiftData

/// Visible sync/offline indicator — audit.md SwiftData & CloudKit Finding 3
/// (no user-visible sync/pending state anywhere) + Enhancements #3/#4, plus
/// architecture-review.md 2.3 (a pending-writes count + a manual retry).
/// Placed once in `MainTabView` (wraps every tab) rather than per-screen, so
/// it's globally visible regardless of which tab is active.
///
/// Deliberately unobtrusive: shows nothing at all during normal operation
/// (`.idle`/`.synced` while online with an empty outbox) — only surfaces
/// when there's something the user should actually know about (offline, a
/// sync that failed after all retries, or writes still queued). Never a
/// full-screen blocker; a thin banner at the top that pushes content down
/// via `.safeAreaInset`, matching this app's existing toast-notification
/// convention (see `BlindensportGrazApp`'s `showToast` NotificationCenter
/// posts) rather than inventing a new one.
struct SyncStatusBanner: View {
    private let syncState = SyncState.shared
    private let networkMonitor = NetworkMonitor.shared
    @Environment(\.modelContext) private var modelContext
    @State private var isRetrying = false

    var body: some View {
        Group {
            if !networkMonitor.isOnline {
                banner(
                    text: pendingSuffix("Offline – Änderungen werden synchronisiert, sobald wieder eine Verbindung besteht."),
                    systemImage: "wifi.slash",
                    color: .orange
                )
            } else if syncState.status == .failed {
                banner(
                    text: pendingSuffix("Synchronisierung fehlgeschlagen."),
                    systemImage: "exclamationmark.triangle.fill",
                    color: .red,
                    showsRetry: true
                )
            } else if syncState.status == .syncing || isRetrying {
                banner(
                    text: "Synchronisiert…",
                    systemImage: "arrow.triangle.2.circlepath",
                    color: .secondary
                )
            } else if syncState.pendingCount > 0 {
                banner(
                    text: pendingText(syncState.pendingCount),
                    systemImage: "arrow.triangle.2.circlepath.circle",
                    color: .orange,
                    showsRetry: true
                )
            }
        }
    }

    private func pendingText(_ count: Int) -> String {
        count == 1
            ? "1 Änderung noch nicht synchronisiert."
            : "\(count) Änderungen noch nicht synchronisiert."
    }

    /// Appends the pending-count sentence to another status line when the
    /// outbox is non-empty, so "offline" / "failed" also tell the user how
    /// much is waiting.
    private func pendingSuffix(_ base: String) -> String {
        syncState.pendingCount > 0 ? "\(base) \(pendingText(syncState.pendingCount))" : base
    }

    private func banner(text: String, systemImage: String, color: Color, showsRetry: Bool = false) -> some View {
        HStack(spacing: 8) {
            Label(text, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Not decorative — this is the one piece of information this
                // view exists to announce, so VoiceOver should read it like
                // any other status text, not skip it as chrome.
                .accessibilityElement(children: .combine)

            if showsRetry {
                Button("Jetzt synchronisieren") { retry() }
                    .font(.caption.bold())
                    .buttonStyle(.borderless)
                    .disabled(isRetrying || !networkMonitor.isOnline)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Theme.tintedCardFill(color))
    }

    private func retry() {
        guard !isRetrying else { return }
        isRetrying = true
        Task {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
            isRetrying = false
        }
    }
}
