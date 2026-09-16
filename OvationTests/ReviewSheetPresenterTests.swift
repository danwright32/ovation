import Foundation
import SwiftData
import Testing

/// ovation#318, PR B of the plan on ovation#167. What the review sheet SAYS, decided
/// once, where a test can read it.
///
/// PRD 52a to 52c. The sheet is the only place Dan sees what ships before it ships
/// (L64), so every choice on it, which recipients are drawn, whether anyone was
/// passed over, and how large the page is, belongs to a presenter rather than to a
/// view: a decision made inside a view body can only be checked by rendering it,
/// and the states that matter here are the ones no fixture happens to produce.
///
/// THE PAGE IS SCALED, NEVER RESTYLED (PRD 52b, 10c). The preview is the
/// attachment, so the width the page is drawn at is derived from the one render's
/// own page size, and a review screen that re-typeset the page to fit a column
/// would be showing a different document from the one that is sent.
@MainActor
struct ReviewSheetPresenterTests {

    // MARK: how big the page is drawn

    @Test("the page opens at 47% of the real page, which is 380 points of 612")
    func thePageStartsFitted() throws {
        let presenter = try Self.presenter()

        #expect(presenter.scale == .fitted)
        #expect(presenter.pageWidth == 380, "380pt of an 816px page in an 800pt sheet (PRD 52b)")
    }

    @Test("pressing the way to open it draws the page at 81%, from the same render")
    func openingTheePageRedrawsTheSameRender() throws {
        let presenter = try Self.presenter()
        let page = RecordingPage()
        try presenter.show(on: page)

        try presenter.open(on: page)

        #expect(presenter.scale == .opened)
        #expect(presenter.pageWidth == 661, "1.08 of 612pt (PRD 52b)")
        #expect(page.shown.map(\.scale) == [.fitted, .opened])
        #expect(page.shown.map(\.bytes).allSatisfy { $0 == page.shown[0].bytes },
                "the same bytes, because the preview IS the attachment (PRD 10c)")
        #expect(presenter.renderCount == 1, "one render, whatever the scale")
    }

    @Test("and closing it again goes back to the fitted page, still from that render")
    func closingReturnsToFitted() throws {
        let presenter = try Self.presenter()
        let page = RecordingPage()
        try presenter.open(on: page)

        try presenter.close(on: page)

        #expect(presenter.scale == .fitted)
        #expect(presenter.renderCount == 1)
    }

    // MARK: who it goes to (PRD 52c)

    @Test("the ordinary case states the address and says nothing about why")
    func oneAddressIsStatedPlainly() throws {
        let presenter = try Self.presenter(mainAddress: "booker@example.com")

        #expect(presenter.recipients == ["booker@example.com"])
        #expect(presenter.passedOver == nil,
                "going to whoever booked the shoot is the default, and saying so is saying nothing")
    }

    @Test("two addresses in one field are two recipients, and still no explanation")
    func severalAddressesInOneFieldAreListed() throws {
        // Measured on the 2026-09-05 export: 1 of 31 clients genuinely carries two
        // addresses in one field, and Dan writes them on purpose (PRD 38, 38a).
        let presenter = try Self.presenter(mainAddress: "one@example.com, two@example.com")

        #expect(presenter.recipients == ["one@example.com", "two@example.com"])
        #expect(presenter.passedOver == nil)
    }

    @Test("a genuine override says who was passed over, once for the group")
    func agenuineOverrideNamesWhoWasPassedOver() throws {
        let presenter = try Self.presenter(mainAddress: "booker@example.com",
                                           overrideAddress: "accounts@example.com")

        #expect(presenter.recipients == ["accounts@example.com"])
        #expect(presenter.passedOver == "booker@example.com")
    }

    @Test("an override that copies the main address is not one, so nothing is said")
    func acopiedOverrideIsNotAnOverride() throws {
        // 30 of the 31 real clients carry exactly this, and treating it as an
        // override would put a line on every send for a case that does not occur.
        let presenter = try Self.presenter(mainAddress: "booker@example.com",
                                           overrideAddress: " Booker@Example.com ")

        #expect(presenter.recipients == ["booker@example.com"])
        #expect(presenter.passedOver == nil)
    }

    @Test("an override with no main address to compare names nobody")
    func anoverrideWithNoMainAddressNamesNobody() throws {
        // The line reads "not <main address>, who booked it", and there is no main
        // address to put in it. A sentence with a hole in it is worse than none.
        let presenter = try Self.presenter(mainAddress: "", overrideAddress: "accounts@example.com")

        #expect(presenter.recipients == ["accounts@example.com"])
        #expect(presenter.passedOver == nil)
    }

    @Test("no recipient at all is its own state, stated, and never an empty list")
    func noRecipientsIsItsOwnState() throws {
        // An empty list drawn as an empty list reads as a screen that has not
        // loaded, and it is the one case where pressing Send must not be possible
        // (L10, L67).
        let presenter = try Self.presenter(mainAddress: "not an address")

        #expect(presenter.recipients.isEmpty)
        #expect(presenter.noRecipientsSentence ==
                "This client has no address to send to, so nothing can go out.")
    }

    @Test("and a client with an address has no such sentence")
    func thenoRecipientsSentenceIsAbsentWhenThereAreSome() throws {
        let presenter = try Self.presenter(mainAddress: "booker@example.com")

        #expect(presenter.noRecipientsSentence == nil)
    }

    @Test("the sheet says which invoice it is about, from the page being reviewed")
    func thesubtitleNamesTheInvoiceAndClient() throws {
        let presenter = try Self.presenter()

        #expect(presenter.subtitle == "Invoice 1123, A Client")
    }

    // MARK: staging

    private static func presenter(mainAddress: String = "booker@example.com",
                                  overrideAddress: String? = nil) throws -> ReviewSheetPresenter {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "A Client", taxStatus: .notExempt)
        client.email = mainAddress
        client.contractEmail = overrideAddress
        context.insert(client)
        let invoice = try InvoiceFixtures.invoice("Ordinary", in: context)
        invoice.client = client
        invoice.number = 1_123
        try context.save()

        let document = try InvoiceDocument(invoice: invoice, footer: .fixed)
        let session = ReviewSession(document: document, resources: try InvoicePDFResources.bundled())
        return ReviewSheetPresenter(session: session, document: document, client: client,
                                    dueDate: invoice.dueDate)
    }
}

/// A page that records what it was handed, so a test reads the scale and the bytes
/// rather than a screenshot (L146).
@MainActor
final class RecordingPage: InvoicePageSink {
    struct Shown: Equatable {
        let bytes: Data
        let scale: InvoicePageScale
    }
    private(set) var shown: [Shown] = []

    func display(_ bytes: Data, at scale: InvoicePageScale) {
        shown.append(Shown(bytes: bytes, scale: scale))
    }
}
