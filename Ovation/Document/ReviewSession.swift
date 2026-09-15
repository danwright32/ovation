// ovation#167, PRD 10c, plan A5. ONE RENDER, SHOWN AND SENT.
//
// THE PREVIEW IS THE ATTACHMENT. The review sheet shows a PDF and the send attaches a PDF,
// and if those were two renders from the same invoice they would agree on the day they were
// written and then drift, with the preview still looking right while the client received
// something else (PRD 10c). So the invoice is rendered HERE, once, and every page view and
// the attachment are handed those same bytes.
//
// IT LIVES IN A SESSION, NEVER IN A VIEW. A SwiftUI view is rebuilt whenever anything it
// reads changes, so a render started from a view renders again on a zoom, an appearance
// change or a reopened sheet. The window's presenter owns this (ovation#318 builds the sheet),
// and nothing reaches the renderer except through it.
//
// A FAILED RENDER IS KEPT TOO. The session makes one attempt; a failure is what every later
// showing and the attachment report, rather than a quiet second attempt that could succeed
// with different bytes (L11).
import CoreGraphics
import Foundation

/// The two sizes the review sheet shows the page at (PRD 52): fitted beside the recipients,
/// and opened to read.
enum InvoicePageScale: Equatable, Sendable {
    /// 47% of the page's width, 380 points of 612.
    case fitted
    /// 81%, opened to read.
    case opened

    /// The factor the page's points are drawn at.
    var factor: CGFloat {
        switch self {
        case .fitted: return 0.621
        case .opened: return 1.08
        }
    }
}

/// Anything that shows the rendered page. It is handed bytes and never renders anything.
@MainActor
protocol InvoicePageSink: AnyObject {
    func display(_ bytes: Data, at scale: InvoicePageScale)
}

/// The one render: its bytes, their hash, and a fingerprint of what the page says.
struct RenderedInvoice: Equatable, Sendable {
    let bytes: Data
    /// SHA-256 of `bytes`, through the app's one hashing rule (DocumentStore).
    let sha256: String
    /// SHA-256 of every string the document decided, in order. Two renders of one invoice
    /// differ by bytes, because a PDF carries a creation date and an identifier, but they say
    /// the same thing and share this, so ovation#42 can refuse to send a render an edit made
    /// stale without mistaking a re-render for an edit.
    let fingerprint: String
}

@MainActor
final class ReviewSession {

    private let document: InvoiceDocument
    private let resources: InvoicePDFResources
    private var outcome: Result<RenderedInvoice, Error>?
    private var scale: InvoicePageScale = .fitted

    /// How many times this session has rendered. At most one, by construction; read by the
    /// tests that hold it to that.
    private(set) var renderCount = 0

    init(document: InvoiceDocument, resources: InvoicePDFResources) {
        self.document = document
        self.resources = resources
    }

    /// The render, made on first use and kept, success or failure.
    func rendered() throws -> RenderedInvoice {
        if let outcome { return try outcome.get() }
        renderCount += 1
        let made = Result {
            let bytes = try InvoicePDF.render(document, resources: resources)
            return RenderedInvoice(bytes: bytes, sha256: DocumentStore.hash(of: bytes),
                                   fingerprint: Self.fingerprint(of: document))
        }
        outcome = made
        return try made.get()
    }

    /// Hands the page to `page` at the current scale.
    func show(on page: InvoicePageSink) throws {
        page.display(try rendered().bytes, at: scale)
    }

    /// Changes the scale and shows the page again, from the same render.
    func zoom(to newScale: InvoicePageScale, on page: InvoicePageSink) throws {
        scale = newScale
        try show(on: page)
    }

    /// The bytes the send attaches: the same object every page view was handed.
    func attachment() throws -> Data {
        try rendered().bytes
    }

    /// Whether `current`, the invoice as it stands now, says something this render does not.
    func isStale(against current: InvoiceDocument) -> Bool {
        Self.fingerprint(of: current) != Self.fingerprint(of: document)
    }

    /// Every string on the page, in the order it is laid out, with separators that cannot
    /// occur in any of them, so moving text between fields changes the fingerprint (L555).
    static func fingerprint(of document: InvoiceDocument) -> String {
        let unit = "\u{1F}", record = "\u{1E}", group = "\u{1D}"
        func rows(_ rows: [[String]]) -> String { rows.map { $0.joined(separator: unit) }.joined(separator: record) }
        let parts = [
            [document.amountDueLabel, document.amountDue, document.dueLine].joined(separator: unit),
            rows(document.strip),
            document.title,
            document.columns.joined(separator: unit),
            rows(document.items),
            rows(document.money),
            document.foot.map { ([$0.label] + $0.lines).joined(separator: unit) }.joined(separator: record),
        ]
        return DocumentStore.hash(of: Data(parts.joined(separator: group).utf8))
    }
}
