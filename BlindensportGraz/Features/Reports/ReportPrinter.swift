import UIKit
import WebKit
import PDFKit

enum ReportPrinterError: LocalizedError {
    case renderFailed(String)
    case nothingToPrint

    var errorDescription: String? {
        switch self {
        case .renderFailed(let name):
            return String(localized: "„\(name)“ konnte nicht für den Druck aufbereitet werden.")
        case .nothingToPrint:
            return String(localized: "Es ist kein Dokument zum Drucken ausgewählt.")
        }
    }
}

/// Prints report files (.xlsx — PRAE, KostZ, TN, Trainingsfrequenzliste …) in
/// one print job. iOS can't print spreadsheets directly, so each file is
/// loaded into an off-screen WKWebView (which renders Office documents) and
/// drawn into A4 PDF pages through its print formatter; the pages of all
/// files are joined, each file starting on a new page, and handed to the
/// system print dialog once (printer, copies, page range).
///
/// Excel page breaks / print areas are not honored by the web renderer: a
/// form continues on the next page wherever A4 ends.
@MainActor
enum ReportPrinter {
    /// A4 in points with a 1 cm margin.
    private static let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private static let printable = paper.insetBy(dx: 28, dy: 28)

    /// Renders all files into one PDF and shows the print dialog.
    /// Returns whether the user actually printed.
    @discardableResult
    static func print(_ files: [URL], jobName: String) async throws -> Bool {
        guard !files.isEmpty else { throw ReportPrinterError.nothingToPrint }
        let pdf = try await pdf(for: files)

        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = jobName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdf
        return await withCheckedContinuation { continuation in
            let completion: UIPrintInteractionController.CompletionHandler = { _, completed, _ in
                continuation.resume(returning: completed)
            }
            // iPad needs an anchor; iPhone presents as a sheet.
            if UIDevice.current.userInterfaceIdiom == .pad, let view = topViewController()?.view {
                controller.present(from: CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1),
                                   in: view, animated: true, completionHandler: completion)
            } else {
                controller.present(animated: true, completionHandler: completion)
            }
        }
    }

    /// One PDF with every file's pages, in order.
    static func pdf(for files: [URL]) async throws -> Data {
        let combined = PDFDocument()
        for file in files {
            let data = try await renderPDF(of: file)
            guard let document = PDFDocument(data: data), document.pageCount > 0 else {
                throw ReportPrinterError.renderFailed(file.lastPathComponent)
            }
            for index in 0..<document.pageCount {
                if let page = document.page(at: index) {
                    combined.insert(page, at: combined.pageCount)
                }
            }
        }
        guard let data = combined.dataRepresentation() else { throw ReportPrinterError.nothingToPrint }
        return data
    }

    private static func renderPDF(of file: URL) async throws -> Data {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: CGSize(width: paper.width, height: paper.height)))
        let loader = PageLoader()
        webView.navigationDelegate = loader
        try await loader.load(file, in: webView)
        // Office documents finish layout shortly after didFinish.
        try await Task.sleep(for: .milliseconds(500))

        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(printable, forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        guard renderer.numberOfPages > 0 else { throw ReportPrinterError.renderFailed(file.lastPathComponent) }
        return data as Data
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

/// Bridges WKNavigationDelegate's load callbacks to async/await.
@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ file: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
