import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#40, PRD 5a and 44a. The first product screen Ovation draws, rendered
/// and read rather than reasoned about.
///
/// WHY THESE ARE HOSTED. The same reason `RootViewTests` is: the precedent is
/// postroll#846 and #855, where presenters shared a surface, one heading landed
/// over another's buttons, and every model level test passed throughout. What
/// these assert lives in the binding, so they render the real view.
///
/// THEY RUN AT THE REAL COUNT. L606: a two row fixture and a green suite are the
/// two ways a screen ships unseen. The roster's real population on 2026-09-11 is
/// 31 clients of which 25 need a sales tax status, so that is what is built here
/// rather than a pair.
@MainActor
struct RosterPassViewTests {

    /// The real shape, measured from the live Downbeat export on 2026-09-11 by
    /// `scripts/measure-booking-export.py`: 31 clients, 25 with no tax status,
    /// and no address that cannot be sent to.
    private static func theRealRoster() -> [Client] {
        var clients: [Client] = []
        for i in 0..<25 {
            let c = Client(name: "Client \(i)", taxStatus: .neverRecorded)
            c.email = "c\(i)@example.example"
            clients.append(c)
        }
        for i in 25..<31 {
            let c = Client(name: "Client \(i)", taxStatus: i.isMultiple(of: 2) ? .exempt : .notExempt)
            c.email = "c\(i)@example.example"
            clients.append(c)
        }
        return clients
    }

    private static func presenter(_ clients: [Client]) -> RosterPresenter {
        RosterPresenter(clients: clients, save: {})
    }

    @Test("the screen says the number it started with, at the real count")
    func itSaysWhatItStartedWith() throws {
        let view = RosterPassView(presenter: Self.presenter(Self.theRealRoster()))

        #expect(throws: Never.self) {
            try view.inspect().find(text: "Started with 25 of 31")
        }
    }

    /// THE TEST ABOVE CANNOT TELL THE TWO FIGURES APART, and a mutation sweep on
    /// 2026-09-11 proved it: replacing `startedWith` with `remaining` in the
    /// footer left all 24 tests passing. On a pass where nothing has been
    /// answered the two numbers are the same, so the fixture was the reason it
    /// passed rather than the code (L159).
    ///
    /// So this answers one, which is the only state in which the defect is
    /// visible. The countdown is the exact thing PRD 5a was written against: a
    /// figure that falls as you work is the standing nag, and saying the number
    /// it BEGAN with is what makes the pass read as a one time job.
    @Test("the starting figure does not move once a client has been answered")
    func theStartingFigureDoesNotCountDown() throws {
        let clients = Self.theRealRoster()
        let presenter = Self.presenter(clients)
        try presenter.answer(clients[0], as: .exempt)

        let view = RosterPassView(presenter: presenter)

        // What it started with, unmoved.
        #expect(throws: Never.self) {
            try view.inspect().find(text: "Started with 25 of 31")
        }
        // And what is LEFT, which is a different number now, so the two really
        // are being read from different places.
        #expect(presenter.remaining == 24)
        #expect(throws: Never.self) {
            try view.inspect().find(text: "24 of 31 clients")
        }
    }

    @Test("the sales tax section names its own count")
    func theTaxSectionNamesItsCount() throws {
        let view = RosterPassView(presenter: Self.presenter(Self.theRealRoster()))

        #expect(throws: Never.self) {
            try view.inspect().find(text: "Sales tax status")
        }
    }

    /// PRD 5a, corrected 2026-09-11. A section with nothing in it is not drawn,
    /// which is the same zero rule as every count in the sidebar card. Asserted
    /// in BOTH directions, because "the heading is absent" is satisfied by a
    /// screen that drew nothing at all (L98).
    @Test("the addresses section is not drawn when no address is unsendable")
    func noAddressSectionWhenNoneAreBroken() throws {
        let view = RosterPassView(presenter: Self.presenter(Self.theRealRoster()))

        #expect(throws: (any Error).self) {
            try view.inspect().find(text: RosterPassView.addressSectionTitle)
        }
        // The screen is genuinely drawn, so the absence above means something.
        #expect(throws: Never.self) {
            try view.inspect().find(text: "Sales tax status")
        }
    }

    @Test("the addresses section IS drawn the moment one address cannot be sent to")
    func theAddressSectionAppearsWhenOneIsBroken() throws {
        var clients = Self.theRealRoster()
        clients[0].email = "ask at the box office"
        let view = RosterPassView(presenter: Self.presenter(clients))

        #expect(throws: Never.self) {
            try view.inspect().find(text: RosterPassView.addressSectionTitle)
        }
    }

    /// Dan, 2026-09-07: a place you are standing in does not vanish underneath
    /// you, and answering the last one is the moment you most deserve to be told
    /// you finished.
    @Test("a settled pass says so rather than drawing an empty list")
    func aSettledPassSaysSo() throws {
        let clients = Self.theRealRoster().map { c -> Client in
            c.taxStatus = .notExempt
            return c
        }
        let view = RosterPassView(presenter: Self.presenter(clients))

        #expect(throws: Never.self) {
            try view.inspect().find(text: "Nothing left to settle")
        }
    }

    /// L415. The failure path, which is the half a happy path render cannot see.
    @Test("a save that failed is said on the screen, not only recorded")
    func aFailureReachesTheScreen() throws {
        let clients = Self.theRealRoster()
        let presenter = RosterPresenter(clients: clients, save: {
            throw RosterViewTestError.theStoreRefused
        })
        try? presenter.answer(clients[0], as: .exempt)

        let view = RosterPassView(presenter: presenter)

        let said = try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(said.contains { $0.contains("could not be saved") })
    }

    /// REVERSED 2026-09-11. See `RosterPresenterTests`: this asserted that no
    /// client's name reached the screen, which is the privacy floor applied to
    /// the one place it does not govern.
    @Test("the failure names the client on screen, so it can be acted on")
    func theFailureNamesTheClientOnScreen() throws {
        let clients = Self.theRealRoster()
        let presenter = RosterPresenter(clients: clients, save: {
            throw RosterViewTestError.theStoreRefused
        })
        try? presenter.answer(clients[0], as: .exempt)

        let view = RosterPassView(presenter: presenter)
        let said = try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(said.contains { $0.contains("Client 0") })
    }

    /// One word for one thing (L118). The settled design file calls it the
    /// sidebar, so the screen says sidebar. `rail` stays in the code comments,
    /// where no reader of the product meets it.
    @Test("the settled screen calls it the sidebar, the word the design record uses")
    func theSettledScreenSaysSidebar() throws {
        let clients = Self.theRealRoster().map { c -> Client in
            c.taxStatus = .notExempt
            return c
        }
        let view = RosterPassView(presenter: Self.presenter(clients))
        let said = try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }

        #expect(said.contains { $0.contains("sidebar") })
        #expect(!said.contains { $0.contains("rail") })
    }

    /// The constant the two tests above compare against is shared with the view,
    /// which is what keeps them about the RULE rather than the wording. So the
    /// wording itself is pinned exactly once, here, against what the design
    /// record says, or the shared constant could drift to anything and nothing
    /// would notice (L103, L70).
    @Test("the two section titles are the ones the design record settled")
    func theSectionTitlesAreTheSettledOnes() {
        #expect(RosterPassView.addressSectionTitle == "Addresses that cannot be sent to")
        #expect(RosterPassView.taxSectionTitle == "Sales tax status")
    }
}

enum RosterViewTestError: Error {
    case theStoreRefused
}

