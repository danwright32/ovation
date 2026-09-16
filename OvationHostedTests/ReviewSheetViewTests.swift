import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#318, PR B. The half of the review sheet that model level tests cannot
/// see: what is actually on it.
///
/// The precedent is the one RootViewTests names (postroll#846, #855): several
/// presenters shared one surface and every model level test passed while one
/// heading sat over another's buttons. These render the real sheet and read it.
///
/// THE WORDS COME FROM THE SETTLED DESIGN, `docs/design/review-send.html`, which is
/// the record of what Dan approved on 2026-09-09 (PRD 52): the title "Review and
/// send", the subtitle naming the invoice and client, "Press the page to read it at
/// full size" above the page, "Going to" over the recipients, and "not <address>,
/// who booked it" where somebody was passed over.
@MainActor
struct ReviewSheetViewTests {

    @Test("the sheet carries the title and names the invoice it is about")
    func thesheetNamesWhatItIsShowing() throws {
        let sheet = try Self.sheet()

        #expect(throws: Never.self) { try sheet.inspect().find(text: "Review and send") }
        #expect(throws: Never.self) { try sheet.inspect().find(text: "Invoice 1123, A Client") }
    }

    @Test("the way to open the page is on the sheet at rest, above the page")
    func thewayToOpenThePageIsVisibleAtRest() throws {
        // PRD 52b: the page is taller than the sheet's visible area, so anything
        // beneath it is below the fold and would not be found at all.
        let sheet = try Self.sheet()

        #expect(throws: Never.self) {
            try sheet.inspect().find(button: "Press the page to read it at full size")
        }
    }

    @Test("pressing it opens the page, and the sheet then offers the way back")
    func pressingItOpensAndOffersTheWayBack() throws {
        let (sheet, presenter) = try Self.sheetAndPresenter()

        try sheet.inspect().find(button: "Press the page to read it at full size").tap()

        #expect(presenter.scale == .opened)
        #expect(throws: Never.self) {
            try sheet.inspect().find(button: "Press the page to read it at the size it fits")
        }
    }

    @Test("the recipients are stated under Going to")
    func therecipientsAreStated() throws {
        let sheet = try Self.sheet(mainAddress: "booker@example.com")

        #expect(throws: Never.self) { try sheet.inspect().find(text: "Going to") }
        #expect(throws: Never.self) { try sheet.inspect().find(text: "booker@example.com") }
    }

    @Test("and nothing says why, because going to whoever booked it is the default")
    func theordinaryCaseExplainsNothing() throws {
        let sheet = try Self.sheet(mainAddress: "booker@example.com")

        #expect(throws: (any Error).self) {
            try sheet.inspect().find(ViewType.Text.self, where: {
                try $0.string().contains("who booked it")
            })
        }
    }

    @Test("a genuine override names who was passed over, in the design's words")
    func anoverrideNamesWhoWasPassedOver() throws {
        let sheet = try Self.sheet(mainAddress: "booker@example.com",
                                   overrideAddress: "accounts@example.com")

        #expect(throws: Never.self) { try sheet.inspect().find(text: "accounts@example.com") }
        #expect(throws: Never.self) {
            try sheet.inspect().find(text: "not booker@example.com, who booked it")
        }
    }

    @Test("a client with nowhere to send says so, rather than drawing an empty list")
    func nowhereToSendIsStated() throws {
        let sheet = try Self.sheet(mainAddress: "not an address")

        #expect(throws: Never.self) {
            try sheet.inspect().find(text: "This client has no address to send to, so nothing can go out.")
        }
    }

    @Test("a due date already past is a band across the sheet, under the title")
    func theDueDateBandIsDrawn() throws {
        let presenter = try ReviewSampleWorld.presenter(
            dueDate: .stamping(Date(timeIntervalSince1970: 1_789_000_000)),
            now: { Date(timeIntervalSince1970: 1_789_000_000 + 7 * 24 * 60 * 60) })
        let sheet = ReviewSheet(presenter: presenter, close: {})

        let said = try #require(presenter.dueDateWarning)
        #expect(said.contains("7 days past"))
        #expect(throws: Never.self) { try sheet.inspect().find(text: said) }
    }

    @Test("and an ordinary due date draws no band at all")
    func noBandOnAnOrdinaryInvoice() throws {
        // A band on every send is a band nobody reads (L36).
        let presenter = try ReviewSampleWorld.presenter(
            dueDate: .stamping(Date(timeIntervalSince1970: 1_789_000_000)),
            now: { Date(timeIntervalSince1970: 1_789_000_000 - 30 * 24 * 60 * 60) })
        let sheet = ReviewSheet(presenter: presenter, close: {})

        #expect(presenter.dueDateWarning == nil)
        #expect(throws: (any Error).self) {
            try sheet.inspect().find(ViewType.Text.self, where: {
                try $0.string().contains("due date")
            })
        }
    }

    @Test("the page carries an accessible name, so it is not an unnamed rectangle")
    func thepageIsNamed() throws {
        // PRD 52 and ovation#318 B6: the page is the whole point of the screen and a
        // screen reader is handed a PDF view with nothing to say about it otherwise.
        let sheet = try Self.sheet()

        #expect(throws: Never.self) {
            try sheet.inspect().find(viewWithAccessibilityLabel: "The invoice that ships, as it will be sent")
        }
    }

    // MARK: staging

    private static func sheet(mainAddress: String = "booker@example.com",
                              overrideAddress: String? = nil) throws -> ReviewSheet {
        try sheetAndPresenter(mainAddress: mainAddress, overrideAddress: overrideAddress).0
    }

    private static func sheetAndPresenter(
        mainAddress: String = "booker@example.com", overrideAddress: String? = nil
    ) throws -> (ReviewSheet, ReviewSheetPresenter) {
        let presenter = try ReviewSampleWorld.presenter(mainAddress: mainAddress,
                                                        overrideAddress: overrideAddress)
        return (ReviewSheet(presenter: presenter, close: {}), presenter)
    }
}
