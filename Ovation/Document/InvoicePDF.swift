// ovation#167, PRD 50 to 50f, plan A4. THE INVOICE PDF, drawn from an InvoiceDocument.
//
// EVERY WORD COMES FROM THE DOCUMENT. This file decides where things go and how they
// look, never what they say, so the page cannot disagree with what the review sheet
// and the tests read (InvoiceDocument.swift).
//
// THE GEOMETRY IS THE DESIGN RECORD'S, translated rather than copied.
// docs/design/invoice-pdf.html draws the page at 816 by 1056 CSS pixels, which is US
// Letter at 96dpi; this lays it out at 612 by 792 POINTS, every length the design's
// pixels times 0.75 (the design's first web idiom). Where the design leans on a web
// behaviour, flex rows and table columns, the same widths are computed here.
//
// CGFloat IS A LAYOUT QUANTITY, NOT MONEY (scripts/check-forbidden-constructs.sh).
// Every figure on the page arrives as text already written by PDFText from integer
// cents; nothing here computes an amount.
//
// MEASURED BEFORE IT WAS WRITTEN (recorded on ovation#167, 2026-09-14): Merriweather
// is a variable font and is set to its bold instance through the weight axis; the
// mark is drawn with drawPDFPage, which copies its paths into the page, so it stays
// vector with no image in the file.
import CoreGraphics
import CoreText
import Foundation

/// The bundled files the page is drawn with, each proven readable when this is made.
///
/// LOADED ONCE, CHECKED BY NAME. A font that cannot be read would otherwise fall back
/// to a system face without a word, and the page would ship in the wrong type (L42),
/// so every file is opened here and a missing one is refused naming it (L11).
struct InvoicePDFResources {

    enum Refusal: Error, Equatable {
        /// A font file that is missing or is not a font, by its file name.
        case fontUnreadable(String)
        /// Dan's mark is missing or is not a PDF. A different refusal from a font,
        /// because the remedy is a different file.
        case markUnreadable
    }

    static let regularFile = "Lato-Regular.ttf"
    static let boldFile = "Lato-Bold.ttf"
    static let serifFile = "Merriweather-Variable.ttf"
    static let markFile = "DanWright-black.pdf"

    /// Every file this reads, in the order it checks them.
    let files: [URL]

    fileprivate let regular: CTFontDescriptor
    fileprivate let bold: CTFontDescriptor
    fileprivate let serif: CTFontDescriptor
    fileprivate let mark: CGPDFPage

    /// The files inside a folder holding them flat, which is how Xcode copies them into
    /// Contents/Resources.
    init(folder: URL) throws {
        func url(_ name: String) -> URL { folder.appending(path: name) }
        func font(_ name: String) throws -> CTFontDescriptor {
            guard let found = CTFontManagerCreateFontDescriptorsFromURL(url(name) as CFURL) as? [CTFontDescriptor],
                  let first = found.first
            else { throw Refusal.fontUnreadable(name) }
            return first
        }
        regular = try font(Self.regularFile)
        bold = try font(Self.boldFile)
        serif = try font(Self.serifFile)
        guard let document = CGPDFDocument(url(Self.markFile) as CFURL), let page = document.page(at: 1) else {
            throw Refusal.markUnreadable
        }
        mark = page
        files = [Self.regularFile, Self.boldFile, Self.serifFile, Self.markFile].map(url)
    }

    /// The copies bundled with whatever is running: the app, or the pure test bundle,
    /// which compiles this file in and carries the same resources.
    static func bundled() throws -> InvoicePDFResources {
        guard let folder = Bundle(for: BundleMarker.self).resourceURL else {
            throw Refusal.fontUnreadable(regularFile)
        }
        return try InvoicePDFResources(folder: folder)
    }

    /// Only here so `Bundle(for:)` can find the bundle this code was compiled into.
    private final class BundleMarker {}
}

enum InvoicePDF {

    enum Failure: Error, Equatable {
        /// CoreGraphics would not make a PDF context to draw into.
        case contextUnavailable
        /// The invoice needs more than one page. Refused rather than cut off, because a
        /// client reading a truncated page cannot tell what is missing (plan A4).
        case overflowsOnePage
    }

    /// The design's pixels, as points.
    private static func pt(_ pixels: CGFloat) -> CGFloat { pixels * 0.75 }

    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792

    /// PRD 50: the letterhead's inks, as the design record writes them.
    private enum Ink {
        static let text = color(0x22, 0x1F, 0x20)
        static let muted = color(0x57, 0x54, 0x4F)
        static let label = color(0x6B, 0x67, 0x62)
        static let hairline = color(0xE4, 0xE1, 0xDD)
        static let bar = color(0x7F, 0xA9, 0x9E)

        /// A colour channel is not money: CGColor takes CGFloat and has no integer form.
        static func color(_ red: Int, _ green: Int, _ blue: Int) -> CGColor {
            CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        }
    }

    /// Draws the page and returns the PDF's bytes.
    static func render(_ document: InvoiceDocument, resources: InvoicePDFResources) throws -> Data {
        let bytes = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: bytes as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil)
        else { throw Failure.contextUnavailable }
        var page = Page(context: context, resources: resources)
        context.beginPDFPage(nil)
        do {
            try page.draw(document)
        } catch {
            context.endPDFPage()
            context.closePDF()
            throw error
        }
        context.endPDFPage()
        context.closePDF()
        return bytes as Data
    }

    /// One page being laid out, top down. `cursor` is the distance from the top of the
    /// page to where the next thing goes; CoreGraphics counts from the bottom, so every
    /// draw converts.
    private struct Page {
        let context: CGContext
        let resources: InvoicePDFResources
        var cursor: CGFloat = 0

        private let left = pt(64)
        private var width: CGFloat { pageWidth - pt(64) * 2 }
        /// Where content must stop: above the bottom padding and the colour bar.
        private var floor: CGFloat { pageHeight - pt(54) }

        init(context: CGContext, resources: InvoicePDFResources) {
            self.context = context
            self.resources = resources
        }

        // MARK: type

        private enum Face { case regular, bold, serifBold }

        private func font(_ face: Face, px: CGFloat) -> CTFont {
            let size = pt(px)
            switch face {
            case .regular: return CTFontCreateWithFontDescriptor(resources.regular, size, nil)
            case .bold: return CTFontCreateWithFontDescriptor(resources.bold, size, nil)
            case .serifBold:
                // The weight axis, 'wght', set to the bold instance the design names.
                let weightAxis = (0x77 << 24) | (0x67 << 16) | (0x68 << 8) | 0x74
                let bold = CTFontDescriptorCreateCopyWithVariation(resources.serif, weightAxis as CFNumber, 700)
                return CTFontCreateWithFontDescriptor(bold, size, nil)
            }
        }

        private struct Style {
            var face: Face
            var px: CGFloat
            var ink: CGColor
            var tracking: CGFloat = 0
            var uppercase = false
            var lineHeight: CGFloat = 1.55
        }

        private static let body = Style(face: .regular, px: 10.5, ink: Ink.text)
        private static let bodyBold = Style(face: .bold, px: 10.5, ink: Ink.text)
        private static let muted = Style(face: .regular, px: 10.5, ink: Ink.muted)
        /// `.lbl`: 8px bold capitals tracked 0.14em, line height 1.
        ///
        /// THE TRACKING STAYS, AND IT HAS A COST. A PDF's text layer reads tracked capitals
        /// as separate letters, so a client copying this label gets "A M O U N T D U E";
        /// names, dates and figures are untracked and copy exactly. ActualText written
        /// through CoreGraphics tags did not change what PDFKit reads. Dan saw the page with
        /// and without the spacing and kept it (2026-09-14, ovation#167).
        private static let label = Style(face: .bold, px: 8, ink: Ink.label, tracking: 0.14, uppercase: true, lineHeight: 1)
        private static let big = Style(face: .serifBold, px: 25, ink: Ink.text, lineHeight: 1.1)
        private static let title = Style(face: .serifBold, px: 27, ink: Ink.text, lineHeight: 1.1)

        private func attributed(_ string: String, _ style: Style, alignment: CTTextAlignment) -> NSAttributedString {
            let font = self.font(style.face, px: style.px)
            var align = alignment
            var line = pt(style.px) * style.lineHeight
            let settings = [
                CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: &align),
                CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: &line),
                CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: &line),
            ]
            let paragraph = CTParagraphStyleCreate(settings, settings.count)
            return NSAttributedString(string: style.uppercase ? string.uppercased() : string, attributes: [
                // LIGATURES OFF. Lato joins ti, ft and ffi into single glyphs the PDF's text
                // layer cannot map back, so a client copying "Meeting" got "Mee+ng" and
                // "matinee" read "maBnee" (measured 2026-09-14). The page must say in its
                // text exactly what it says in ink.
                kCTLigatureAttributeName as NSAttributedString.Key: 0,
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: style.ink,
                kCTKernAttributeName as NSAttributedString.Key: pt(style.px) * style.tracking,
                kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraph,
            ])
        }

        /// How tall `string` sets in a column of `width`.
        private func height(_ string: String, _ style: Style, width: CGFloat) -> CGFloat {
            guard !string.isEmpty else { return 0 }
            let setter = CTFramesetterCreateWithAttributedString(attributed(string, style, alignment: .left))
            let size = CTFramesetterSuggestFrameSizeWithConstraints(
                setter, CFRange(location: 0, length: 0), nil,
                CGSize(width: width, height: .greatestFiniteMagnitude), nil)
            return ceil(size.height)
        }

        /// Sets `string` with its top at `top` (from the top of the page) in a column,
        /// and answers how tall it was.
        @discardableResult
        private func text(_ string: String, _ style: Style, x: CGFloat, top: CGFloat, width: CGFloat,
                          alignment: CTTextAlignment = .left) -> CGFloat {
            guard !string.isEmpty else { return 0 }
            let tall = height(string, style, width: width)
            let setter = CTFramesetterCreateWithAttributedString(attributed(string, style, alignment: alignment))
            let path = CGPath(rect: CGRect(x: x, y: pageHeight - top - tall, width: width, height: tall), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil), context)
            return tall
        }

        private func rule(top: CGFloat, x: CGFloat, width: CGFloat, ink: CGColor) {
            context.setFillColor(ink)
            context.fill(CGRect(x: x, y: pageHeight - top - pt(1), width: width, height: pt(1)))
        }

        private func checkRoom() throws {
            if cursor > floor { throw Failure.overflowsOnePage }
        }

        // MARK: the page, top to bottom, in the design's order

        mutating func draw(_ document: InvoiceDocument) throws {
            cursor = pt(54)
            head(document)
            strip(document)
            cursor += text(document.title, Self.title, x: left, top: cursor, width: width)
            cursor += pt(18)
            try items(document)
            cursor += pt(20)
            try money(document)
            cursor += pt(30)
            try foot(document)
            footbar()
        }

        /// The mark at the left, contained in 218 by 54 pixels; the amount due at the right.
        private mutating func head(_ document: InvoiceDocument) {
            let box = CGRect(x: left, y: pageHeight - cursor - pt(54), width: pt(218), height: pt(54))
            let bounds = resources.mark.getBoxRect(.mediaBox)
            let scale = min(box.width / bounds.width, box.height / bounds.height)
            context.saveGState()
            context.translateBy(x: box.minX, y: box.minY + (box.height - bounds.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            context.drawPDFPage(resources.mark)
            context.restoreGState()

            var top = cursor
            top += text(document.amountDueLabel, Self.label, x: left, top: top, width: width, alignment: .right)
            top += pt(5)
            top += text(document.amountDue, Self.big, x: left, top: top, width: width, alignment: .right)
            top += pt(3)
            top += text(document.dueLine, Self.muted, x: left, top: top, width: width, alignment: .right)
            cursor = max(top, cursor + pt(54)) + pt(30)
        }

        /// Bill to, Invoice, Issued: three equal columns between two rules.
        private mutating func strip(_ document: InvoiceDocument) {
            rule(top: cursor, x: left, width: width, ink: Ink.text)
            let gap = pt(34)
            let column = (width - gap * CGFloat(document.strip.count - 1)) / CGFloat(max(document.strip.count, 1))
            var tallest: CGFloat = 0
            for (index, pair) in document.strip.enumerated() {
                let x = left + CGFloat(index) * (column + gap)
                var top = cursor + pt(12)
                top += text(pair.first ?? "", Self.label, x: x, top: top, width: column)
                top += pt(4)
                top += text(pair.count > 1 ? pair[1] : "", Self.body, x: x, top: top, width: column)
                tallest = max(tallest, top - cursor)
            }
            cursor += tallest + pt(12)
            rule(top: cursor, x: left, width: width, ink: Ink.hairline)
            cursor += pt(1) + pt(24)
        }

        /// Description, Hours, Rate, Amount, at the design's column widths.
        private mutating func items(_ document: InvoiceDocument) throws {
            let widths = [width - pt(74) - pt(84) - pt(96), pt(74), pt(84), pt(96)]
            var xs: [CGFloat] = []
            var x = left
            for w in widths { xs.append(x); x += w }
            var headTall: CGFloat = 0
            for (index, heading) in document.columns.enumerated() where index < widths.count {
                headTall = max(headTall, text(heading, Self.label, x: xs[index], top: cursor, width: widths[index],
                                              alignment: index == 0 ? .left : .right))
            }
            cursor += headTall + pt(7)
            rule(top: cursor, x: left, width: width, ink: Ink.text)
            cursor += pt(1)
            for row in document.items {
                var top = cursor + pt(9)
                let described = text(row[0], Self.bodyBold, x: xs[0], top: top, width: widths[0])
                var descriptionTall = described
                if row.count > 1, !row[1].isEmpty {
                    descriptionTall += pt(2) + text(row[1], Self.muted, x: xs[0], top: top + described + pt(2), width: widths[0])
                }
                var figuresTall: CGFloat = 0
                for index in 2..<min(row.count, 5) {
                    figuresTall = max(figuresTall, text(row[index], Self.body, x: xs[index - 1], top: top,
                                                        width: widths[index - 1], alignment: .right))
                }
                top += max(descriptionTall, figuresTall) + pt(9)
                cursor = top
                try checkRoom()
                rule(top: cursor, x: left, width: width, ink: Ink.hairline)
                cursor += pt(1)
            }
        }

        /// The money block, 268 pixels wide at the right, with the heavy last row.
        private mutating func money(_ document: InvoiceDocument) throws {
            let blockWidth = pt(268)
            let x = left + width - blockWidth
            for (index, row) in document.money.enumerated() {
                let last = index == document.money.count - 1
                let label = row.first ?? ""
                let figure = row.count > 1 ? row[1] : ""
                if label == "Taxable" {
                    cursor += pt(3)
                    rule(top: cursor, x: x, width: blockWidth, ink: Ink.hairline)
                    cursor += pt(1) + pt(3)
                }
                if last {
                    cursor += pt(5)
                    rule(top: cursor, x: x, width: blockWidth, ink: Ink.text)
                    cursor += pt(1) + pt(8)
                } else {
                    cursor += pt(5)
                }
                let tall = max(text(label, Self.body, x: x, top: cursor, width: blockWidth),
                               text(figure, last ? Self.bodyBold : Self.body, x: x, top: cursor, width: blockWidth,
                                    alignment: .right))
                cursor += tall + (last ? 0 : pt(5))
                try checkRoom()
            }
        }

        /// Payment, Note, Contact: three equal columns under a hairline.
        private mutating func foot(_ document: InvoiceDocument) throws {
            rule(top: cursor, x: left, width: width, ink: Ink.hairline)
            cursor += pt(1) + pt(12)
            let gap = pt(30)
            let count = CGFloat(max(document.foot.count, 1))
            let column = (width - gap * (count - 1)) / count
            var tallest: CGFloat = 0
            for (index, block) in document.foot.enumerated() {
                let x = left + CGFloat(index) * (column + gap)
                var top = cursor
                top += text(block.label, Self.label, x: x, top: top, width: column)
                for line in block.lines {
                    top += pt(4)
                    top += text(line, Self.body, x: x, top: top, width: column)
                }
                tallest = max(tallest, top - cursor)
            }
            cursor += tallest
            try checkRoom()
        }

        /// The letterhead's colour bar across the foot of the page, 20 pixels tall.
        private func footbar() {
            context.setFillColor(Ink.bar)
            context.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pt(20)))
        }
    }
}
