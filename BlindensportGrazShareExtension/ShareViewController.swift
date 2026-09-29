import UIKit
import UniformTypeIdentifiers

/// Minimal Share Extension: this is the target that makes "Blindensport
/// Graz" appear in iOS's system share sheet for a file (Files app, Mail
/// attachment, Safari download, AirDrop, ...) — user request ("I want to
/// have the possibility that BlindensportGraz appears in share function of
/// the iphone. When I share a file, a tournament should be created
/// automatically").
///
/// Deliberately does NONE of the actual work here: it accepts the one
/// shared file, copies it into the shared App Group container
/// (`ShareExtensionBridge`), and hands off to the main app via a custom
/// URL scheme deep link — see that file's doc comment for why (extension
/// processes are short-lived/memory-constrained; the main app already has
/// a complete "Turnier aus Einladung erstellen" flow, this just routes
/// into it with real app resources instead of duplicating it here).
///
/// Plain `UIViewController` principal class (see Info.plist's
/// `NSExtensionPrincipalClass`), no storyboard — this codebase is
/// otherwise all-SwiftUI, but a Share Extension's root view controller is
/// simplest as a thin, code-only UIKit shell for something this small (one
/// spinner + one label, no user interaction needed at all beyond a
/// possible "Abbrechen" tap while it works).
final class ShareViewController: UIViewController {
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureUI()
        handleSharedItem()
    }

    private func configureUI() {
        statusLabel.text = "Wird an Blindensport Graz übergeben …"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)

        let stack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
        activityIndicator.startAnimating()
    }

    private func handleSharedItem() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachment = item.attachments?.first else {
            finish(errorMessage: "Keine Datei gefunden.")
            return
        }

        let dataType = UTType.data.identifier
        guard attachment.hasItemConformingToTypeIdentifier(dataType) else {
            finish(errorMessage: "Dieser Inhalt wird nicht unterstützt.")
            return
        }

        attachment.loadFileRepresentation(forTypeIdentifier: dataType) { [weak self] url, error in
            guard let self else { return }
            guard let url, error == nil else {
                Task { @MainActor in
                    self.finish(errorMessage: "Datei konnte nicht gelesen werden.")
                }
                return
            }
            // `url` is only guaranteed valid for the duration of this
            // callback (the system deletes the temp file right after it
            // returns) — copy it into the App Group container synchronously
            // before doing anything else.
            let deepLink = ShareExtensionBridge.store(fileAt: url)
            Task { @MainActor in
                guard let deepLink else {
                    self.finish(errorMessage: "Datei konnte nicht übergeben werden.")
                    return
                }
                self.openHostApp(deepLink)
            }
        }
    }

    /// `NSExtensionContext.open(_:completionHandler:)` is the App Extension
    /// Programming Guide's sanctioned way for an extension to bring its own
    /// containing app to the foreground with a deep link — no private
    /// `UIApplication` workaround needed (extensions don't have a
    /// `UIApplication` instance to call `.open(_:)` on directly).
    private func openHostApp(_ url: URL) {
        extensionContext?.open(url) { [weak self] _ in
            Task { @MainActor in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    private func finish(errorMessage: String) {
        statusLabel.text = errorMessage
        activityIndicator.stopAnimating()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
