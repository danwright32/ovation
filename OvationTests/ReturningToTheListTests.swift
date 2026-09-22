import Foundation
import SwiftData
import Testing

/// ovation#125. What the invoice list does when you come back to it.
///
/// ROUND 1 OF ovation#111 SETTLED THAT THE INVOICE TAKES THE WHOLE SCREEN, so the
/// list goes away and comes back, and nothing said what you come back TO. Two
/// separate things have to be right and they have different answers.
///
/// WHERE YOU WERE. The list returns with the row you opened still under your eye.
/// At 24 invoices this already matters and the list grows every week: a list that
/// returns to the top after every invoice makes working through a run of drafts
/// worse the further down them you get, which is exactly when a short fixture
/// stops showing it (L606).
///
/// WHAT CHANGED WHILE YOU WERE AWAY. Acting inside an invoice can move it between
/// bands or take it off the list, so the row you are looking for may not be where
/// you left it and may not be there at all. An item that leaves must not simply
/// vanish from under the eye (L426, L10): the list says so rather than landing
/// silently at the top, which is indistinguishable from never having been
/// anywhere.
@MainActor
struct ReturningToTheListTests {

    private static let today = BusinessDate.stamping(Date(timeIntervalSince1970: 1_794_531_600))

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    /// Three drafts, each waiting on its times, which is what ovation#461 makes
    /// and therefore what a run of them actually looks like.
    private static func drafts(_ context: ModelContext, _ count: Int) -> [Invoice] {
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        return (0..<count).map { index in
            let invoice = Invoice(client: client, kind: .photography,
                                  invoiceDate: today, hourlyRate: Money(dollars: 250),
                                  taxRate: .newYorkCity)
            context.insert(invoice)
            let shoot = Shoot(name: "Shoot \(index)", when: .dayOnly(today), venue: "St Anne's")
            invoice.add(shoot)
            let line = LineItem.hourly(hours: Hours(whole: 1), at: Money(dollars: 250),
                                       describedAs: "Photography", for: shoot)
            line.hours = nil
            invoice.add(line)
            return invoice
        }
    }

    private static func present(_ invoices: [Invoice]) -> InvoiceListPresenter {
        InvoiceListPresenter(invoices: invoices, heldMoney: [:], today: today)
    }

    // MARK: where you were

    @Test("coming back with a row in mind returns to that row")
    func comingbackReturnsToTheRow() throws {
        let context = try Self.store()
        let made = Self.drafts(context, 5)
        let presenter = Self.present(made)
        let wanted = made[3].persistentModelID

        #expect(presenter.returning(to: wanted) == .showing(wanted))
    }

    /// AND A ROW THAT MOVED IS STILL THE ANSWER, because it is moving that makes
    /// this hard: typing the shoot's times changes what the row says and where it
    /// sorts, and the row Dan is looking for when he comes back is the one he
    /// just acted on, wherever it now is.
    @Test("a row that moved while you were away is still the one you come back to")
    func amovedRowIsStillTheAnswer() throws {
        let context = try Self.store()
        let made = Self.drafts(context, 5)
        let wanted = made[0].persistentModelID
        // Priced while the invoice was open, which is what typing the times does.
        made[0].orderedShoots.first?.shotFrom = ClockTime("19:00")
        made[0].orderedShoots.first?.shotUntil = ClockTime("20:30")

        let presenter = Self.present(made)

        #expect(presenter.returning(to: wanted) == .showing(wanted))
        // The control: it really did move, so this case is about a moved row
        // rather than a row that happened to stay put (L159).
        let unpriced = Self.present(Self.drafts(try Self.store(), 5))
        #expect(presenter.card != unpriced.card,
                "the invoice did not change band, so nothing here is about moving")
    }

    // MARK: what changed while you were away

    /// AN ITEM THAT LEAVES MUST NOT SIMPLY VANISH. Nothing in the product can
    /// take an invoice off the list yet, and that is exactly why this is decided
    /// now: ovation#47's cancel and ovation#449's delete both arrive into a list
    /// whose answer is already settled, rather than each inventing one.
    @Test("a row that is no longer on the list is said, not silently dropped")
    func agoneRowIsSaid() throws {
        let context = try Self.store()
        let made = Self.drafts(context, 5)
        let gone = made[2].persistentModelID

        let presenter = Self.present(Array(made.prefix(2)) + made.suffix(2))

        #expect(presenter.returning(to: gone) == .theRowHasGone)
    }

    @Test("coming back with nothing in mind is an ordinary arrival")
    func nothinginMindIsOrdinary() throws {
        let context = try Self.store()
        let presenter = Self.present(Self.drafts(context, 5))

        #expect(presenter.returning(to: nil) == .nothingInParticular)
    }

    /// AND AN EMPTY LIST IS NOT A ROW THAT LEFT. They are different states and
    /// the empty list already says the healthy thing; saying both would state one
    /// fact twice and contradict itself (L605, L10).
    @Test("an empty list says nothing about a row, because the empty state already speaks")
    func anemptyListSaysNothingAboutARow() throws {
        let context = try Self.store()
        let made = Self.drafts(context, 1)
        let presenter = Self.present([])

        #expect(presenter.returning(to: made[0].persistentModelID) == .nothingInParticular)
    }

    /// EVERY ANSWER HAS A SENTENCE OR DELIBERATELY HAS NONE, and the lookup is
    /// total, so a case added later has to be answered rather than taking a
    /// default that reads as a considered silence (L113).
    @Test("only the gone answer says anything, and it says what it measured")
    func onlythegoneAnswerSpeaks() {
        #expect(ReturningToTheList.theRowHasGone.sentence != nil)
        #expect(ReturningToTheList.nothingInParticular.sentence == nil)
        let said = ReturningToTheList.theRowHasGone.sentence ?? ""
        // It may claim only what it measured: the list does not know WHY the row
        // left, so it does not say (L11).
        #expect(said.hasSuffix("."))
        #expect(!said.contains("deleted") && !said.contains("sent"),
                "the sentence claims a reason the list never measured: \(said)")
    }
}
