import CryptoKit
import Foundation
import SwiftData
import Testing

/// ovation#167, PRD 10c, plan A5. THE PREVIEW IS THE ATTACHMENT: one render, shown and sent.
///
/// WHAT IS COMPARED IS WHAT THE PAGE WAS HANDED. A test that renders twice and compares
/// two outputs would pass while proving nothing, and a test that reads the session's own
/// record of what it rendered is the session agreeing with itself (L70). So the page is a
/// sink that keeps every byte it was given, the attachment is read from the session, and
/// the hashes are computed HERE, with CryptoKit, from those two sets of bytes.
///
/// AND THE COMPARISON IS FIRST SEEN TO TELL TWO RENDERS APART. A PDF carries a creation date
/// and a document identifier, so two renders of one invoice differ by bytes; if they did not,
/// equal hashes below would say nothing about whether one render was used (PRD 10c).
@MainActor
struct ReviewSessionTests {

    /// Stands in for the page view: records every set of bytes it was handed, in order.
    private final class RecordingPage: InvoicePageSink {
        private(set) var shown: [Data] = []
        private(set) var scales: [InvoicePageScale] = []
        func display(_ bytes: Data, at scale: InvoicePageScale) {
            shown.append(bytes)
            scales.append(scale)
        }
    }

    private static func hash(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func document(_ label: String = "Every element") throws -> InvoiceDocument {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        return try InvoiceDocument(invoice: try InvoiceFixtures.invoice(label, in: context), footer: .fixed)
    }

    // MARK: the control

    @Test("two renders of one invoice are different bytes, so a matching hash below means one render")
    func twoRendersDiffer() throws {
        let document = try Self.document()
        let resources = try InvoicePDFResources.bundled()
        let first = try InvoicePDF.render(document, resources: resources)
        let second = try InvoicePDF.render(document, resources: resources)
        #expect(Self.hash(first) != Self.hash(second),
                "if two renders were identical, the one render guard below could not fail")
    }

    // MARK: one render, shown and sent

    @Test("the bytes the page was handed are the bytes the send attaches, by hash")
    func thePreviewIsTheAttachment() throws {
        let session = ReviewSession(document: try Self.document(), resources: try InvoicePDFResources.bundled())
        let page = RecordingPage()
        try session.show(on: page)
        let attached = try session.attachment()
        let shown = try #require(page.shown.last, "the page was never handed anything")
        #expect(Self.hash(shown) == Self.hash(attached))
    }

    @Test("showing the page again, at another scale, hands over the same bytes and renders nothing new")
    func zoomingDoesNotRenderAgain() throws {
        let session = ReviewSession(document: try Self.document(), resources: try InvoicePDFResources.bundled())
        let page = RecordingPage()
        try session.show(on: page)
        try session.zoom(to: .opened, on: page)
        try session.show(on: page)
        #expect(page.scales == [.fitted, .opened, .opened], "the zoom was read back as having happened")
        #expect(Set(page.shown.map(Self.hash)).count == 1, "every showing carried the same bytes")
        #expect(session.renderCount == 1)
        #expect(Self.hash(try session.attachment()) == Self.hash(try #require(page.shown.first)))
        #expect(session.renderCount == 1, "asking for the attachment did not render again")
    }

    @Test("a second page view on the same session is handed the same bytes, as a remount would be")
    func aRemountIsHandedTheSameBytes() throws {
        let session = ReviewSession(document: try Self.document(), resources: try InvoicePDFResources.bundled())
        let before = RecordingPage(), after = RecordingPage()
        try session.show(on: before)
        try session.show(on: after)
        #expect(Self.hash(try #require(before.shown.first)) == Self.hash(try #require(after.shown.first)))
        #expect(session.renderCount == 1)
    }

    // MARK: staleness (for ovation#42)

    @Test("the render names the document it was made from, so an edited invoice is seen as stale")
    func anEditMakesTheRenderStale() throws {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let invoice = try InvoiceFixtures.invoice("Ordinary", in: context)
        let session = ReviewSession(document: try InvoiceDocument(invoice: invoice, footer: .fixed),
                                    resources: try InvoicePDFResources.bundled())
        try session.show(on: RecordingPage())
        #expect(!session.isStale(against: try InvoiceDocument(invoice: invoice, footer: .fixed)),
                "the same invoice, unedited, is not stale")
        invoice.dueDate = try InvoiceFixtures.businessDate("November 24, 2026")
        #expect(session.isStale(against: try InvoiceDocument(invoice: invoice, footer: .fixed)),
                "a moved due date changes what the page says, so the render no longer matches")
    }

    // MARK: failure (L11)

    @Test("a render that fails is reported, and the page is handed nothing")
    func aFailedRenderHandsThePageNothing() throws {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let invoice = try InvoiceFixtures.invoice("Ordinary", in: context)
        for index in 1...40 {
            invoice.add(LineItem.flat(Money(dollars: 10), describedAs: "Extra \(index)"))
        }
        let session = ReviewSession(document: try InvoiceDocument(invoice: invoice, footer: .fixed),
                                    resources: try InvoicePDFResources.bundled())
        let page = RecordingPage()
        #expect(throws: InvoicePDF.Failure.overflowsOnePage) { try session.show(on: page) }
        #expect(page.shown.isEmpty)
        #expect(throws: InvoicePDF.Failure.overflowsOnePage) { try session.attachment() }
    }
}
