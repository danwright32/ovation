import CoreGraphics
import Foundation
import PDFKit
import SwiftData
import Testing

/// ovation#167, plan A4. THE RENDERER IS JUDGED ON THE FILE IT WRITES.
///
/// Every assertion here reads the rendered PDF's bytes, or a rasterisation of that
/// PDF, never the values handed to the renderer (L63). What the page SAYS is already
/// held to the design by InvoiceDocumentTests; this holds what the page IS: US Letter,
/// the three faces the design names and nothing else, Merriweather at its bold
/// instance, Dan's mark drawn as paths inside its box, and every word the document
/// decided present in the file.
///
/// The measurements these rest on were taken first, on 2026-09-14, and recorded on
/// ovation#167: CoreGraphics copies the mark's paths into the page rather than making
/// a form, the embedded Merriweather name carries the applied weight after "Light",
/// and the same word at 300 and 700 carries a 1.50 ratio of ink.
struct InvoicePDFRendererTests {

    // MARK: rendering

    private static func document(_ label: String = "Every element") throws -> InvoiceDocument {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let invoice = try InvoiceFixtures.invoice(label, in: context)
        return try InvoiceDocument(invoice: invoice, footer: .fixed)
    }

    private static func render(_ label: String = "Every element") throws -> Data {
        try InvoicePDF.render(try document(label), resources: try InvoicePDFResources.bundled())
    }

    // MARK: reading the file back

    /// Every `/BaseFont /<name>` in the file, with the six letter subset tag dropped.
    private static func embeddedFaces(_ pdf: Data) -> Set<String> {
        let text = String(decoding: pdf, as: UTF8.self)
        let pattern = /\/BaseFont\s*\/(?:[A-Z]{6}\+)?([^\s\/>\]]+)/
        return Set(text.matches(of: pattern).map { String($0.1) })
    }

    private static func imageCount(_ pdf: Data) -> Int {
        String(decoding: pdf, as: UTF8.self).matches(of: /\/Subtype\s*\/Image/).count
    }

    /// Dark pixels in a rectangle given in page points, from the rendered PDF
    /// rasterised at twice size. Memory rows run top down while page points run
    /// bottom up, which is why the rows are counted from 792 (measured: reading them
    /// bottom up found no ink at all).
    private static func ink(_ pdf: Data, in rect: CGRect) throws -> Int {
        let provider = try #require(CGDataProvider(data: pdf as CFData))
        let page = try #require(CGPDFDocument(provider)?.page(at: 1))
        let scale: CGFloat = 2
        let width = Int(612 * scale), height = Int(792 * scale)
        let bitmap = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                            bitmapInfo: CGImageAlphaInfo.none.rawValue))
        bitmap.setFillColor(gray: 1, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bitmap.scaleBy(x: scale, y: scale)
        bitmap.drawPDFPage(page)
        let pixels = try #require(bitmap.data).assumingMemoryBound(to: UInt8.self)
        var count = 0
        for row in Int((792 - rect.maxY) * scale)..<Int((792 - rect.minY) * scale) {
            for column in Int(rect.minX * scale)..<Int(rect.maxX * scale) where pixels[row * width + column] < 128 {
                count += 1
            }
        }
        return count
    }

    // MARK: the page

    @Test("the invoice is one US Letter page, 612 by 792 points")
    func oneLetterPage() throws {
        let pdf = try #require(PDFDocument(data: try Self.render()))
        #expect(pdf.pageCount == 1)
        let box = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        #expect(box == CGRect(x: 0, y: 0, width: 612, height: 792))
    }

    @Test("the file embeds Lato Regular, Lato Bold and Merriweather, and no other face")
    func exactlyTheDesignsFaces() throws {
        let faces = Self.embeddedFaces(try Self.render())
        #expect(faces.contains("Lato-Regular"))
        #expect(faces.contains("Lato-Bold"))
        // ONE FACE AT ONE WEIGHT, possibly more than one embedded instance: CoreText sets
        // the optical size axis from the point size, as a browser does by default, so the
        // title and the amount due embed at their own optical sizes (measured: 20.25 and
        // 18.75 points). The weight is what the design settles, and the next test holds it.
        #expect(!faces.filter { $0.hasPrefix("Merriweather") }.isEmpty, "the title face is missing: \(faces)")
        #expect(faces.filter { !$0.hasPrefix("Lato-Regular") && !$0.hasPrefix("Lato-Bold")
                                && !$0.hasPrefix("Merriweather") }.isEmpty,
                "a system face in the file means a string fell back: \(faces)")
    }

    /// The embedded name reads Light at every weight and carries the instance after
    /// it: wght 2BC0000 is 700.0 in 16.16 fixed point.
    @Test("every Merriweather instance in the file is the bold one, weight 700")
    func merriweatherIsBold() throws {
        let faces = Self.embeddedFaces(try Self.render())
        let merriweather = faces.filter { $0.hasPrefix("Merriweather") }
        #expect(!merriweather.isEmpty, "no Merriweather in the file: \(faces)")
        #expect(merriweather.allSatisfy { $0.contains("_wght2BC0000") },
                "every Merriweather instance is the bold one: \(merriweather)")
    }

    // MARK: Dan's mark

    /// The design draws the mark contained in a 218 by 54 pixel box inside 64 by 54
    /// pixels of padding, at 0.75 points per pixel.
    private static let markBox = CGRect(x: 48, y: 792 - 81, width: 163.5, height: 40.5)

    @Test("the mark is drawn as paths, so the file holds no image at all")
    func theMarkIsVector() throws {
        #expect(Self.imageCount(try Self.render()) == 0)
    }

    @Test("the mark's ink falls inside its box")
    func theMarkIsWhereTheDesignPutsIt() throws {
        let inside = try Self.ink(try Self.render(), in: Self.markBox)
        #expect(inside > 1_000, "the mark measured 1,548 dark pixels at this scale when it was checked")
    }

    // MARK: the words

    /// Whole words compared with whitespace collapsed, because a PDF's text layer
    /// breaks lines wherever the layout did (L278), and compared CASE SENSITIVELY, so a
    /// label drawn in capitals cannot be answered by the same word in a sentence.
    ///
    /// THE SMALL CAPITAL LABELS ARE READ AS LETTERS. They are tracked 0.14em, and a
    /// PDF's text layer reads tracked capitals as separate letters ("A M O U N T D U E",
    /// measured 2026-09-14; ActualText tags written through CoreGraphics did not change
    /// it). Dan kept the spacing, having seen the page both ways (2026-09-14). So a label
    /// is found by its capitals in order with every space removed, and "AMOUNT" must
    /// occur once for the label and once for the column, so neither can answer for the
    /// other (L178).
    ///
    /// THE WHOLE PAGE'S READING ORDER IS NOT ASSERTED, because it is the reader's guess.
    /// PDFKit reads some invoices as two columns, the left half first, depending on
    /// where whitespace falls (measured 2026-09-14 on Tax exempt and Combined run). What
    /// is the file's to get right is that each ROW reads left to right, and
    /// `rowsReadInOrder` measures that by position.
    @Test("every string the document decided is in the file's text, on every design invoice")
    func everyStringIsInTheFile() throws {
        for label in try InvoiceFixtures.labels {
            let document = try Self.document(label)
            let pdf = try #require(PDFDocument(data: try InvoicePDF.render(document,
                                                                            resources: try InvoicePDFResources.bundled())))
            let raw = pdf.string ?? ""
            let words = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let letters = raw.filter { !$0.isWhitespace }

            func capitals(_ string: String) -> String { string.uppercased().filter { !$0.isWhitespace } }
            let labels = [document.amountDueLabel] + document.strip.compactMap(\.first) + document.foot.map(\.label)
            for tracked in labels {
                #expect(letters.contains(capitals(tracked)), "\(label): the label \(tracked) is missing from the PDF")
            }
            for heading in document.columns {
                #expect(letters.contains(capitals(heading)), "\(label): the heading \(heading) is missing from the PDF")
            }
            let amounts = letters.components(separatedBy: "AMOUNT").count - 1
            #expect(amounts >= 2, "\(label): AMOUNT occurs \(amounts) time(s), and the label and the column need one each")

            let prose = [document.amountDue, document.dueLine, document.title]
                + document.strip.compactMap { $0.count > 1 ? $0[1] : nil } + document.items.flatMap { $0 }
                + document.money.flatMap { $0 } + document.foot.flatMap(\.lines)
            for string in prose where !string.isEmpty {
                let expected = string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                #expect(words.contains(expected), "\(label): \(expected) is missing from the PDF")
            }
        }
    }

    /// Plan A4: every line item reads in order on one line. Found by position, not by the
    /// whole page's reading order: each row's description is located on the page, and the
    /// text in a full width band at that height must hold the row's cells left to right.
    @Test("every line item row reads left to right on its own line, on every design invoice")
    func rowsReadInOrder() throws {
        for label in try InvoiceFixtures.labels {
            let document = try Self.document(label)
            let pdf = try #require(PDFDocument(data: try InvoicePDF.render(document,
                                                                            resources: try InvoicePDFResources.bundled())))
            let page = try #require(pdf.page(at: 0))
            for row in document.items {
                let found = pdf.findString(row[0], withOptions: [.literal])
                #expect(found.count == 1, "\(label): \(row[0]) was found \(found.count) time(s) on the page")
                guard let bounds = found.first?.bounds(for: page) else { continue }
                let band = CGRect(x: 0, y: bounds.minY + 1, width: 612, height: max(bounds.height - 2, 1))
                let line = (page.selection(for: band)?.string ?? "")
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
                let cells = [row[0]] + row[2...].filter { !$0.isEmpty }
                var searchFrom = line.startIndex
                for cell in cells {
                    guard let at = line.range(of: cell, range: searchFrom..<line.endIndex) else {
                        Issue.record("\(label): \(cell) is not in order on the line \(row[0]) sits on, which reads: \(line)")
                        break
                    }
                    searchFrom = at.upperBound
                }
            }
        }
    }

    // MARK: refusals, each by name (L11, L42)

    /// Plan A4: an invoice that would run past one page is refused rather than cut
    /// off, because a client reading a truncated page cannot tell what is missing.
    @Test("an invoice too long for one page is refused by name, never printed short")
    func anInvoiceTooLongForOnePageIsRefused() throws {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let invoice = try InvoiceFixtures.invoice("Ordinary", in: context)
        for index in 1...40 {
            invoice.add(LineItem.flat(Money(dollars: 10), describedAs: "Extra \(index)"))
        }
        let document = try InvoiceDocument(invoice: invoice, footer: .fixed)
        #expect(throws: InvoicePDF.Failure.overflowsOnePage) {
            try InvoicePDF.render(document, resources: try InvoicePDFResources.bundled())
        }
    }

    private static func folderWithout(_ missing: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ovation-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bundled = try InvoicePDFResources.bundled()
        for url in bundled.files where url.lastPathComponent != missing {
            try FileManager.default.copyItem(at: url, to: folder.appending(path: url.lastPathComponent))
        }
        return folder
    }

    @Test("a missing font is refused by its file name, before anything is drawn")
    func aMissingFontIsRefusedByName() throws {
        let folder = try Self.folderWithout("Lato-Bold.ttf")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: InvoicePDFResources.Refusal.fontUnreadable("Lato-Bold.ttf")) {
            try InvoicePDFResources(folder: folder)
        }
    }

    @Test("a missing mark is refused as the mark, not as a font")
    func aMissingMarkIsRefusedAsTheMark() throws {
        let folder = try Self.folderWithout("DanWright-black.pdf")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: InvoicePDFResources.Refusal.markUnreadable) {
            try InvoicePDFResources(folder: folder)
        }
    }
}
