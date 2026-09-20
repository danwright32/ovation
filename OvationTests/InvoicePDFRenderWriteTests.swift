import Foundation
import PDFKit
import SwiftData
import Testing

/// ovation#167, L606. The real invoice PDFs, WRITTEN OUT so a person can look at them.
///
/// Every other renderer test reads the file; none of them looks at it the way Dan will.
/// This writes the page the app draws for each of the design's fixture invoices, so the
/// side by side against docs/design/invoice-pdf.html can be opened before merge. What it
/// asserts is modest on purpose: that each file was written and opens as one page. The
/// judgement is a person looking.
///
/// WHERE IT WRITES. `TEST_RUNNER_OVATION_RENDER_DIR` when it is set, otherwise a temporary
/// directory. The prefix is not optional: xcodebuild does not pass the invoking shell's
/// environment to the test process, and a variable without it arrives as nothing
/// (RosterPassRenderTests found this first).
struct InvoicePDFRenderWriteTests {

    private static var renderDirectory: URL {
        if let named = ProcessInfo.processInfo.environment["OVATION_RENDER_DIR"] {
            return URL(fileURLWithPath: named, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appending(path: "ovation-invoice-pdfs", directoryHint: .isDirectory)
    }

    /// "Every element" becomes "every-element.pdf".
    private static func fileName(_ label: String) -> String {
        label.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-") + ".pdf"
    }

    @Test("each design invoice is written out as the PDF the app draws, one page each")
    func writeEachInvoice() throws {
        let folder = Self.renderDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let resources = try InvoicePDFResources.bundled()
        let labels = try InvoiceFixtures.labels
        // EIGHT SINCE ovation#326, which added the settled receipt. One fixture
        // and not two: the page says nothing about money left held, and the
        // allocator never puts more on an invoice than it owes, so a deposit
        // LARGER than the bill draws this same page.
        #expect(labels.count == 8, "the side by side needs every design invoice")
        for label in labels {
            let context = ModelContext(try OvationSchema.container(inMemory: true))
            let document = try InvoiceDocument(invoice: try InvoiceFixtures.invoice(label, in: context), footer: .fixed)
            let url = folder.appending(path: Self.fileName(label))
            try InvoicePDF.render(document, resources: resources).write(to: url, options: .atomic)
            let written = try #require(PDFDocument(url: url), "\(label): the written file does not open")
            #expect(written.pageCount == 1, "\(label): written as \(written.pageCount) pages")
        }
    }
}
