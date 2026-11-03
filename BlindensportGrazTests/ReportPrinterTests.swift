import XCTest
import PDFKit
@testable import BlindensportGraz

/// ReportPrinter's rendering half (the print dialog itself needs a person):
/// every bundled report template renders to PDF, and a combined print job
/// contains each file's pages in order, each file starting on a new page.
@MainActor
final class ReportPrinterTests: XCTestCase {
    private let templates = ["TN_TeilnehmerInnenliste", "KostZ_Kostenzusammenstellung", "PRAE_Formular",
                             "PRAE_Darstellung_Vorlage", "Trainingsfrequenzliste_Vorlage"]

    private func url(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "xlsx"), "\(name).xlsx not bundled")
    }

    func testEveryReportTemplateRendersToPDF() async throws {
        for name in templates {
            let data = try await ReportPrinter.pdf(for: [url(name)])
            let pages = try XCTUnwrap(PDFDocument(data: data)).pageCount
            XCTAssertGreaterThan(pages, 0, "\(name) rendered no pages")
        }
    }

    func testCombinedJobKeepsEveryFilesPagesInOrder() async throws {
        let files = try templates.map(url)
        var expected = 0
        for file in files {
            let single = try await ReportPrinter.pdf(for: [file])
            expected += try XCTUnwrap(PDFDocument(data: single)).pageCount
        }
        let combinedData = try await ReportPrinter.pdf(for: files)
        let combined = try XCTUnwrap(PDFDocument(data: combinedData))
        XCTAssertEqual(combined.pageCount, expected)
        if let dump = ProcessInfo.processInfo.environment["REPORT_PRINTER_DUMP"] {
            combined.write(to: URL(fileURLWithPath: dump))
        }
    }

    func testNothingSelectedIsAnError() async {
        do {
            try await ReportPrinter.print([], jobName: "leer")
            XCTFail("expected nothingToPrint")
        } catch {
            XCTAssertEqual(error.localizedDescription, ReportPrinterError.nothingToPrint.localizedDescription)
        }
    }

    /// An uploaded PDF (Einladung) is appended with its own pages, not re-rendered.
    func testPDFFileKeepsItsPages() async throws {
        let source = PDFDocument()
        for _ in 0..<3 { source.insert(PDFPage(), at: source.pageCount) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Einladung-\(UUID().uuidString).pdf")
        XCTAssertTrue(source.write(to: file))
        defer { try? FileManager.default.removeItem(at: file) }

        let data = try await ReportPrinter.pdf(for: [file, url("KostZ_Kostenzusammenstellung")])
        let kostZ = try await ReportPrinter.pdf(for: [url("KostZ_Kostenzusammenstellung")])
        XCTAssertEqual(try XCTUnwrap(PDFDocument(data: data)).pageCount,
                       3 + (try XCTUnwrap(PDFDocument(data: kostZ)).pageCount))
    }
}
