import SwiftUI
import os

/// Toolbar share button for a file the screen prepares ahead of time
/// (exports, calendar entries). If building the file failed, the button
/// stays in place but dimmed, labelled as not possible and with the reason
/// as hint, and the error is logged — instead of the button silently
/// missing, which VoiceOver users can't tell from "no export here".
struct ExportShareButton: View {
    /// nil while the file is being prepared.
    let file: Result<URL, any Error>?
    let label: String
    var systemImage = "square.and.arrow.up"

    var body: some View {
        switch file {
        case .success(let url):
            ShareLink(item: url) { Image(systemName: systemImage) }
                .accessibilityLabel(label)
        case .failure(let error):
            Button {} label: { Image(systemName: systemImage) }
                .disabled(true)
                .accessibilityLabel("\(label) nicht möglich")
                .accessibilityHint(error.localizedDescription)
        case nil:
            EmptyView()
        }
    }

    private static let logger = Logger(subsystem: "it.a11y.BlindensportGraz", category: "Export")

    /// Builds the file; a failure is logged and kept for the button.
    static func prepare(_ what: String, _ build: () throws -> URL) -> Result<URL, any Error> {
        do {
            return .success(try build())
        } catch {
            logger.error("\(what, privacy: .public) export failed: \(String(describing: error), privacy: .public)")
            return .failure(error)
        }
    }
}
