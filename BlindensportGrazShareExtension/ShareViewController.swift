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

    /// Brings the main app to the foreground with the deep link.
    ///
    /// `NSExtensionContext.open(_:completionHandler:)` does NOT work here —
    /// Apple only supports it for Today and iMessage extensions; from a Share
    /// extension it silently fails (that was the original bug: the sheet
    /// closed and the app never opened). Instead this walks the responder
    /// chain to the process's `UIApplication` and calls
    /// `open(_:options:completionHandler:)` through the Objective-C runtime,
    /// since that API is marked unavailable to extensions at compile time.
    /// It's best effort: the file is already in the App Group inbox, and the
    /// app picks it up the next time it's opened even if this fails.
    private func openHostApp(_ url: URL) {
        guard openViaApplication(url) else {
            showOpenAppHint()
            return
        }
    }

    private func openViaApplication(_ url: URL) -> Bool {
        typealias OpenURLFunction = @convention(c) (
            AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
        ) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")

        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication, application.responds(to: selector) {
                let open = unsafeBitCast(application.method(for: selector), to: OpenURLFunction.self)
                let completion: @convention(block) (Bool) -> Void = { [weak self] opened in
                    Task { @MainActor in
                        if opened {
                            self?.extensionContext?.completeRequest(returningItems: nil)
                        } else {
                            self?.showOpenAppHint()
                        }
                    }
                }
                open(application, selector, url as NSURL, NSDictionary(), completion)
                return true
            }
            responder = current.next
        }
        return false
    }

    /// Fallback when the app couldn't be opened directly: the file is safely
    /// in the inbox, so just tell the user to open the app themselves.
    private func showOpenAppHint() {
        showMessage("Die Datei wurde übergeben. Öffne jetzt Blindensport Graz – das Turnier wird dort vorbereitet.")
    }

    private func finish(errorMessage: String) {
        showMessage(errorMessage)
    }

    /// Shows a message and a "Fertig" button instead of closing on a timer, so
    /// VoiceOver users hear it and can dismiss it themselves.
    private func showMessage(_ message: String) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        statusLabel.text = message
        if doneButton.superview == nil, let stack = statusLabel.superview as? UIStackView {
            stack.addArrangedSubview(doneButton)
        }
        UIAccessibility.post(notification: .screenChanged, argument: statusLabel)
    }

    private lazy var doneButton: UIButton = {
        var configuration = UIButton.Configuration.borderedProminent()
        configuration.title = "Fertig"
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        return button
    }()
}
