import SwiftUI
import SwiftData

/// Always-visible sync status for the account screen: "Status: Online /
/// Offline / Synchronisiert… / Synchronisierung fehlgeschlagen", when the
/// last sync succeeded, unsent changes, and the last error. Tapping it
/// starts a sync — also while "offline", since the network monitor can be
/// wrong. Complements `SyncStatusBanner`, which only appears when
/// something needs attention.
struct SyncStatusRow: View {
    private let syncState = SyncState.shared
    private let networkMonitor = NetworkMonitor.shared
    @Environment(\.modelContext) private var modelContext
    @State private var isSyncing = false

    var body: some View {
        Section("Synchronisierung") {
            Button(action: sync) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    Image(systemName: systemImage)
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(statusText)
                            .foregroundStyle(.primary)
                        if let lastSyncedAt = syncState.lastSyncedAt {
                            Text("Zuletzt synchronisiert: \(lastSyncedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if syncState.pendingCount > 0 {
                            Text(syncState.pendingCount == 1
                                 ? "1 Änderung noch nicht synchronisiert."
                                 : "\(syncState.pendingCount) Änderungen noch nicht synchronisiert.")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.warning)
                        }
                        if syncState.status == .failed, let error = syncState.lastError {
                            Text(error)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                    if isBusy {
                        ProgressView()
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Tippen, um jetzt zu synchronisieren.")
        }
    }

    private var isBusy: Bool { isSyncing || syncState.status == .syncing }

    private var statusText: String {
        if isBusy { return String(localized: "Status: Synchronisiert…") }
        if !networkMonitor.isOnline { return String(localized: "Status: Offline") }
        if syncState.status == .failed { return String(localized: "Status: Synchronisierung fehlgeschlagen") }
        return String(localized: "Status: Online")
    }

    private var systemImage: String {
        if isBusy { return "arrow.triangle.2.circlepath" }
        if !networkMonitor.isOnline { return "wifi.slash" }
        if syncState.status == .failed { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var color: Color {
        if isBusy { return .secondary }
        if !networkMonitor.isOnline { return Theme.Palette.warning }
        if syncState.status == .failed { return Theme.Palette.danger }
        return Theme.Palette.success
    }

    private func sync() {
        guard !isBusy else { return }
        isSyncing = true
        Task {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
            isSyncing = false
            // The result isn't otherwise announced while focus stays here.
            AccessibilityNotification.Announcement(statusText).post()
        }
    }
}
