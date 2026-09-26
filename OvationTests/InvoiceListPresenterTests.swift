import Foundation
import SwiftData
import Testing

/// ovation#49, PRD section 6, 46a, 46d. The list itself: which rows are in which
/// band, in what order, and the counts the card carries.
///
/// THE CARD AND THE LIST ARE ONE DERIVATION READ TWICE, which is the fault PRD 46a
/// says in its own words its mapping exists to prevent, and which Dan found on
/// 2026-09-10 as a band saying 2 above a list that did not hold 2. So the counts
/// here are asserted AGAINST the rows they claim to count, never against a number
/// written beside them (L107).
@MainActor
struct InvoiceListPresenterTests {

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    /// 2026-11-12. Everything is written relative to it, so no case depends on
    /// when the suite runs (L130).
    private static let today = BusinessDate.stamping(Date(timeIntervalSince1970: 1_794_531_600))

    private static func day(_ offset: Int) -> BusinessDate {
        .stamping(Date(timeIntervalSince1970: 1_794_531_600 + Double(offset) * 86_400))
    }

    private static func client(_ context: ModelContext, _ name: String) -> Client {
        let client = Client(name: name, taxStatus: .notExempt)
        context.insert(client)
        return client
    }

    @discardableResult
    private static func invoice(
        _ context: ModelContext, for client: Client, shoot: BusinessDate? = today,
        due: BusinessDate? = nil, number: Int64? = nil, sent: Bool = false,
        amount: Int64 = 100
    ) -> Invoice {
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: shoot,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        invoice.dueDate = due
        invoice.number = number
        if sent {
            invoice.sentStatus = .sent(route: .ovationSentIt,
                                       at: Date(timeIntervalSince1970: 1_794_000_000))
        }
        invoice.add(LineItem.flat(Money(dollars: amount), describedAs: "Photography"))
        context.insert(invoice)
        return invoice
    }

    /// Puts a named shoot on an invoice, which is what the row's heavy column is.
    @discardableResult
    private static func shoot(_ invoice: Invoice, named name: String,
                              on day: BusinessDate) -> Shoot {
        let shoot = Shoot(name: name, when: .dayOnly(day), venue: nil)
        invoice.add(shoot)
        return shoot
    }

    private static func present(_ invoices: [Invoice],
                                held: [Client: Money] = [:]) -> InvoiceListPresenter {
        InvoiceListPresenter(invoices: invoices, heldMoney: held, today: today)
    }

    // MARK: the bands and their order

    @Test("the bands come back in the order the list draws them, and empty ones are not there")
    func bandsComeBackInOrderAndOnlyWhenTheyHold() throws {
        let context = try Self.store()
        let client = Self.client(context, "Harbor Light Opera")
        // One draft today, one overdue, one cancelled: three bands, and the five
        // between and around them hold nothing.
        Self.invoice(context, for: client, shoot: Self.today)
        Self.invoice(context, for: client, shoot: Self.day(-30), due: Self.day(-16),
                     number: 1021, sent: true)
        let cancelled = Self.invoice(context, for: client, shoot: Self.day(-40), number: 1019,
                                     sent: true)
        cancelled.closure = .cancelled(on: Self.day(-5), reason: "shoot did not happen")

        let list = Self.present([cancelled] + context.registeredInvoices(excluding: cancelled))
        #expect(list.bands.map(\.band) == [.draftShootToday, .overdue, .cancelled])
        // AN EMPTY BAND IS NOT DRAWN AT ALL. PRD 46 draws no headings, so an empty
        // band would be empty air in the middle of the list with nothing saying
        // what the gap is.
        #expect(list.bands.allSatisfy { !$0.rows.isEmpty })
    }

    @Test("oldest first within each band, and the order does not depend on what the store returned")
    func oldestFirstWithinEachBand() throws {
        let context = try Self.store()
        let client = Self.client(context, "Cedar Hill Youth Orchestra")
        let newer = Self.invoice(context, for: client, shoot: Self.day(-10), due: Self.day(-3),
                                 number: 1044, sent: true)
        let older = Self.invoice(context, for: client, shoot: Self.day(-30), due: Self.day(-20),
                                 number: 1026, sent: true)
        let middle = Self.invoice(context, for: client, shoot: Self.day(-20), due: Self.day(-9),
                                  number: 1030, sent: true)

        // HANDED IN THE WRONG ORDER DELIBERATELY. A collection read from a store
        // carries no order unless the read declares one, so a list that happened to
        // come back sorted would pass while declaring nothing (L343).
        let list = Self.present([newer, middle, older])
        let overdue = try #require(list.bands.first { $0.band == .overdue })
        #expect(overdue.rows.map(\.number) == ["1026", "1030", "1044"])
    }

    @Test("a dateless draft sorts with the oldest, because that is what it is treated as")
    func adatelessDraftSortsOldest() throws {
        let context = try Self.store()
        let client = Self.client(context, "Kestrel Quartet")
        let dated = Self.invoice(context, for: client, shoot: Self.day(-3))
        let dateless = Self.invoice(context, for: client, shoot: nil)

        let list = Self.present([dated, dateless])
        let band = try #require(list.bands.first { $0.band == .draftNeedsSending })
        // It is banded as needing sending on the reading that a missing date is
        // long ago, so it must SORT that way too or the row's position argues with
        // the band it is in (L545).
        #expect(band.rows.map(\.shootDate) == ["no date", Self.written(Self.day(-3))])
    }

    // MARK: held money, which moves rows rather than copying them

    @Test("a client holding money with two open invoices has both moved to the top band")
    func heldMoneyWithTwoOpenInvoicesMovesThem() throws {
        let context = try Self.store()
        let client = Self.client(context, "Cedar Hill Youth Orchestra")
        let one = Self.invoice(context, for: client, shoot: Self.day(-30), due: Self.day(-20),
                               number: 1026, sent: true)
        let two = Self.invoice(context, for: client, shoot: Self.day(-10), due: Self.day(-3),
                               number: 1044, sent: true)

        let list = Self.present([one, two], held: [client: Money(dollars: 500)])
        #expect(list.bands.map(\.band) == [.toPlace])
        // MOVED, NOT COPIED (PRD 46d). Drawing an invoice twice is the fault Dan
        // found in the design file on 2026-09-10, and a count over the bands then
        // disagrees with the list.
        #expect(list.bands.flatMap(\.rows).count == 2)
    }

    @Test("with only one open invoice the money is applied and nothing is moved")
    func heldMoneyWithOneOpenInvoiceMovesNothing() throws {
        // PRD 14h: Ovation applies it itself when there is exactly one open
        // invoice, so there is nothing to ask and no band to ask it in.
        let context = try Self.store()
        let client = Self.client(context, "Riverside Wind Ensemble")
        let only = Self.invoice(context, for: client, shoot: Self.day(-30), due: Self.day(-20),
                                number: 1033, sent: true)

        let list = Self.present([only], held: [client: Money(dollars: 500)])
        #expect(list.bands.map(\.band) == [.overdue])
    }

    @Test("a paid invoice is not an open one, so two invoices one of which is paid moves nothing")
    func apaidInvoiceIsNotOpen() throws {
        // PRD 14h states both halves, and both are asserted, because refusing only
        // the arithmetic leaves an invoice reading Paid in full beside a control
        // asking whether to put more money on it.
        let context = try Self.store()
        let client = Self.client(context, "Alder Street Opera")
        let open = Self.invoice(context, for: client, shoot: Self.day(-30), due: Self.day(-20),
                                number: 1037, sent: true)
        let paid = Self.invoice(context, for: client, shoot: Self.day(-40), due: Self.day(-26),
                                number: 1031, sent: true)
        Self.settle(paid, in: context, on: Self.day(-25))

        let list = Self.present([open, paid], held: [client: Money(dollars: 500)])
        #expect(!list.bands.contains { $0.band == .toPlace })
    }

    @Test("a client holding nothing is never moved, however many invoices are open")
    func noHeldMoneyMovesNothing() throws {
        let context = try Self.store()
        let client = Self.client(context, "Ninth Street Players")
        let one = Self.invoice(context, for: client, shoot: Self.day(-30), due: Self.day(-20),
                               number: 1029, sent: true)
        let two = Self.invoice(context, for: client, shoot: Self.day(-10), due: Self.day(-3),
                               number: 1040, sent: true)

        #expect(!Self.present([one, two]).bands.contains { $0.band == .toPlace })
        // And zero is not "some", which is the shape a presence check gets wrong
        // (L706).
        #expect(!Self.present([one, two], held: [client: .zero])
            .bands.contains { $0.band == .toPlace })
    }

    // DRAFTS COUNT AS OPEN INVOICES (ovation#453). Dan, 2026-09-23: "drafts COUNT
    // as open invoices for PRD 14j. A client with money on account and more than
    // one open invoice, drafts included, has it applied to none of them, and each
    // (draft or sent) offers `Use it here`; their drafts join the held money
    // band." The two cases below asserted the reverse, which had been read off
    // the design record's Cedar Hill fixture rather than decided, and they are
    // inverted rather than adjusted because that reading is what was reversed
    // (L252).

    @Test("a draft is one of the invoices held money could settle, so it joins the band")
    func adraftJoinsTheHeldMoneyBand() throws {
        let context = try Self.store()
        let client = Self.client(context, "Cedar Hill Youth Orchestra")
        let one = Self.invoice(context, for: client, shoot: Self.day(-30), due: Self.day(-20),
                               number: 1026, sent: true)
        let two = Self.invoice(context, for: client, shoot: Self.day(-10), due: Self.day(-3),
                               number: 1044, sent: true)
        let draft = Self.invoice(context, for: client, shoot: Self.day(-2))

        let list = Self.present([one, two, draft], held: [client: Money(dollars: 500)])
        #expect(list.bands.map(\.band) == [.toPlace])
        let place = try #require(list.bands.first { $0.band == .toPlace })
        #expect(place.rows.map(\.number) == ["1026", "1044", "draft"])
        // EACH OFFERS `Use it here`, the draft as well as the sent ones, and the
        // card counts all three under To place rather than the draft under To send.
        #expect(place.rows.map(\.action) == Array(repeating: "Use it here", count: 3))
        #expect(list.card == [.init(label: "To place", count: 3)])
    }

    @Test("two drafts are more than one open invoice, so held money waits on both")
    func twodraftsWaitOnHeldMoney() throws {
        let context = try Self.store()
        let client = Self.client(context, "Cedar Hill Youth Orchestra")
        let a = Self.invoice(context, for: client, shoot: Self.day(-4))
        let b = Self.invoice(context, for: client, shoot: Self.day(-2))

        let list = Self.present([a, b], held: [client: Money(dollars: 500)])
        #expect(list.bands.map(\.band) == [.toPlace])
        #expect(list.bands.flatMap(\.rows).count == 2)
    }

    @Test("one draft and one sent invoice are two open invoices, and both wait")
    func adraftAndASentInvoiceBothWait() throws {
        // The issue's own case: money held against one issued invoice and one
        // draft. Before ovation#453 this counted as ONE open invoice, so the money
        // would have been applied to the sent one with no question asked.
        let context = try Self.store()
        let client = Self.client(context, "Cedar Hill Youth Orchestra")
        let sent = Self.invoice(context, for: client, shoot: Self.day(-10), due: Self.day(4),
                                number: 1044, sent: true)
        let draft = Self.invoice(context, for: client, shoot: Self.day(-2))

        let list = Self.present([sent, draft], held: [client: Money(dollars: 500)])
        let place = try #require(list.bands.first { $0.band == .toPlace })
        #expect(place.rows.map(\.number) == ["1044", "draft"])
        #expect(list.bands.count == 1)
    }

    @Test("an invoice whose send is unsettled is neither a draft nor sent, and does not count")
    func anunsettledSendIsNotCounted() throws {
        // WHAT THE DECISION DOES NOT SAY IS LEFT AS IT WAS. Dan's words name drafts
        // and sent invoices, and an invoice whose send could not be settled
        // (ovation#45, ovation#460) is neither: it keeps its own band and its own
        // question, `Mark unsent`, rather than being swept into this one.
        let context = try Self.store()
        let client = Self.client(context, "Alder Street Opera")
        let draft = Self.invoice(context, for: client, shoot: Self.day(-2))
        let unsettled = Self.invoice(context, for: client, shoot: Self.day(-18),
                                     due: Self.day(-4), number: 1037)
        unsettled.sentStatus = .couldNotDetermine(
            checkedAt: Date(timeIntervalSince1970: 1_794_400_000))

        let list = Self.present([draft, unsettled], held: [client: Money(dollars: 500)])
        #expect(!list.bands.contains { $0.band == .toPlace })
        #expect(list.bands.map(\.band) == [.draftNeedsSending, .sayWhetherItWasSent])
    }

    @Test("one client's held money never moves another client's invoices")
    func heldMoneyIsScopedToItsOwnClient() throws {
        let context = try Self.store()
        let holder = Self.client(context, "Cedar Hill Youth Orchestra")
        let other = Self.client(context, "Westfield Choral Society")
        let a = Self.invoice(context, for: holder, shoot: Self.day(-30), due: Self.day(-20),
                             number: 1026, sent: true)
        let b = Self.invoice(context, for: holder, shoot: Self.day(-10), due: Self.day(-3),
                             number: 1044, sent: true)
        let theirs = Self.invoice(context, for: other, shoot: Self.day(-20), due: Self.day(-6),
                                  number: 1035, sent: true)

        let list = Self.present([a, b, theirs], held: [holder: Money(dollars: 500)])
        let place = try #require(list.bands.first { $0.band == .toPlace })
        #expect(Set(place.rows.map(\.number)) == ["1026", "1044"])
        let overdue = try #require(list.bands.first { $0.band == .overdue })
        #expect(overdue.rows.map(\.number) == ["1035"])
    }

    // MARK: the card, counted from the rows it claims to count

    @Test("every card line's figure equals the rows it rolls up, on the same derivation")
    func thecardCountsTheRowsBeneathIt() throws {
        let context = try Self.store()
        let client = Self.client(context, "Harbor Light Opera")
        Self.invoice(context, for: client, shoot: Self.today)               // to send
        Self.invoice(context, for: client, shoot: Self.day(-2))             // to send
        Self.invoice(context, for: client, shoot: Self.day(-30), due: Self.day(-16),
                     number: 1021, sent: true)                              // to chase
        let check = Self.invoice(context, for: client, shoot: Self.day(-20), due: Self.day(-6),
                                 number: 1033, sent: true)                  // to confirm
        Self.settle(check, in: context, on: Self.day(-5), method: .check, cleared: false)

        let list = Self.present(context.registeredInvoices())
        #expect(list.card == [.init(label: "To send", count: 2),
                              .init(label: "To chase", count: 1),
                              .init(label: "To confirm", count: 1)])
        // PRD 46a: the card is a rollup, and its figure is counted from the ROWS
        // it claims to count, on the row's own action. Counting from the band
        // instead would be wrong for a blocked draft and for a moved row, which
        // the two tests below are about.
        for line in list.card {
            #expect(line.count == list.bands.flatMap(\.rows)
                .filter { InvoiceListPresenter.cardLine(for: $0.action) == line.label }
                .count)
        }
        // AND EVERY ROW THE CARD COUNTS IS A ROW ON THE SCREEN. The two halves
        // together are what stops a figure and the list under it coming apart.
        #expect(list.card.reduce(0) { $0 + $1.count }
                == list.bands.flatMap(\.rows).filter(\.isCountedOnCard).count)
    }

    @Test("a draft that cannot be sent yet is drawn and is not counted on the card")
    func ablockedDraftIsDrawnAndNotCounted() throws {
        // PRD 46f, Dan 2026-09-19. Its lines count things he can act on from the
        // list, and pressing the action on a blocked draft would do nothing.
        let context = try Self.store()
        let client = Self.client(context, "Kestrel Quartet")
        Self.invoice(context, for: client, shoot: Self.today)
        let blocked = Self.invoice(context, for: client, shoot: nil)

        let list = Self.present(context.registeredInvoices())
        let send = list.card.first { $0.label == "To send" }
        #expect(send?.count == 1, "the blocked draft was counted on the card")
        // AND IT IS STILL DRAWN. Not counting it must never become not showing it:
        // the row is how Dan finds out it needs a date at all (PRD 46f).
        #expect(list.bands.flatMap(\.rows).contains { $0.invoiceID == blocked.persistentModelID })
    }

    @Test("a line with nothing to count is not drawn, because a card of zeroes is noise")
    func acardLineWithNothingIsNotDrawn() throws {
        let context = try Self.store()
        let client = Self.client(context, "Harbor Light Opera")
        Self.invoice(context, for: client, shoot: Self.today)

        let list = Self.present(context.registeredInvoices())
        #expect(list.card.map(\.label) == ["To send"])
    }

    @Test("a row the top band moved is counted under To place, never under the band it left")
    func amovedRowIsCountedWhereItIsDrawn() throws {
        // The design file derives the row's action once for exactly this reason:
        // counting it in the band it was taken out of is how the card and the list
        // come apart.
        let context = try Self.store()
        let client = Self.client(context, "Cedar Hill Youth Orchestra")
        let one = Self.invoice(context, for: client, shoot: Self.day(-30), due: Self.day(-20),
                               number: 1026, sent: true)
        let two = Self.invoice(context, for: client, shoot: Self.day(-10), due: Self.day(-3),
                               number: 1044, sent: true)

        let list = Self.present([one, two], held: [client: Money(dollars: 500)])
        #expect(list.card == [.init(label: "To place", count: 2)])
        #expect(!list.card.contains { $0.label == "To chase" })
    }

    // MARK: what a row says

    @Test("a draft's invoice column says draft, and so does one holding a number it never sent with")
    func adraftSaysDraftEvenHoldingANumber() throws {
        // PRD 46g, Dan 2026-09-19. The column means the client has this number, not
        // that one was reserved.
        let context = try Self.store()
        let client = Self.client(context, "Riverside Wind Ensemble")
        let plain = Self.invoice(context, for: client, shoot: Self.day(-2))
        let holding = Self.invoice(context, for: client, shoot: Self.day(-1), number: 1041)

        let list = Self.present([plain, holding])
        let band = try #require(list.bands.first { $0.band == .draftNeedsSending })
        #expect(band.rows.map(\.number) == ["draft", "draft"])
    }

    @Test("a part paid row says which figure it is showing, because the export disagrees on purpose")
    func apartPaidRowNamesItsFigure() throws {
        // PRD section 6: under accrual the export carries the invoice's FULL value
        // in the year it was issued, so the same invoice is two different numbers
        // in two places deliberately, and an unlabelled pair reads as a defect.
        let context = try Self.store()
        let client = Self.client(context, "Westfield Choral Society")
        let part = Self.invoice(context, for: client, shoot: Self.day(-30), due: Self.day(-16),
                                number: 1021, sent: true, amount: 1000)
        Self.settle(part, in: context, on: Self.day(-10), amount: Money(dollars: 400))

        let list = Self.present([part])
        let row = try #require(list.bands.flatMap(\.rows).first)
        #expect(row.amount.contains("owed of"))
    }

    @Test("an ordinary row shows one figure and does not label it")
    func anordinaryRowIsJustTheAmount() throws {
        let context = try Self.store()
        let client = Self.client(context, "Harbor Light Opera")
        let plain = Self.invoice(context, for: client, shoot: Self.today, amount: 1000)

        let row = try #require(Self.present([plain]).bands.flatMap(\.rows).first)
        #expect(!row.amount.contains("owed"))
    }

    // MARK: the shoot, which carries the row's weight

    @Test("the shoot is its own field beside the client, never one string with both")
    func theshootIsItsOwnField() throws {
        // Dan, 2026-09-09: the shoot carries the weight and the client is drawn
        // lighter, settled against three alternatives. Flattening them into one
        // string makes that impossible to draw and the decision unenforceable.
        let context = try Self.store()
        let client = Self.client(context, "Harbor Light Opera")
        let invoice = Self.invoice(context, for: client, shoot: Self.today)
        Self.shoot(invoice, named: "Tosca, opening night", on: Self.today)

        let row = try #require(Self.present([invoice]).bands.flatMap(\.rows).first)
        #expect(row.client == "Harbor Light Opera")
        #expect(row.shoot == "Tosca, opening night")
        #expect(row.otherShoots == 0)
    }

    @Test("a combined invoice names its last shoot and counts the rest")
    func acombinedInvoiceNamesTheLastShoot() throws {
        // PRD 5.1a: Dan combines drafts, each shoot its own line, so the row has
        // several shoots to show in one cell.
        let context = try Self.store()
        let client = Self.client(context, "Harbor Light Opera")
        let invoice = Self.invoice(context, for: client, shoot: Self.day(-5))
        Self.shoot(invoice, named: "Tosca, dress rehearsal", on: Self.day(-5))
        Self.shoot(invoice, named: "Tosca, opening night", on: Self.day(-1))

        let row = try #require(Self.present([invoice]).bands.flatMap(\.rows).first)
        #expect(row.shoot == "Tosca, opening night")
        #expect(row.otherShoots == 1)
    }

    @Test("a run inside one month spans its dates without repeating the month")
    func arunInsideOneMonthCollapsesTheSpan() throws {
        let context = try Self.store()
        let client = Self.client(context, "Harbor Light Opera")
        let invoice = Self.invoice(context, for: client, shoot: Self.day(-5))
        Self.shoot(invoice, named: "Tosca, dress rehearsal", on: Self.day(-5))
        Self.shoot(invoice, named: "Tosca, opening night", on: Self.day(-1))

        let row = try #require(Self.present([invoice]).bands.flatMap(\.rows).first)
        // 7 to 11 Nov 2026, rather than "7 Nov 2026 to 11 Nov 2026".
        #expect(row.shootDate == "7 to 11 Nov 2026")
    }

    @Test("a comped invoice says comped rather than showing a zero among the money")
    func acompedInvoiceSaysSo() throws {
        // PRD 1b: a zero invoice is an ordinary invoice that happens to total
        // nothing, and a bare 0.00 in a column of money reads as a fault.
        let context = try Self.store()
        let client = Self.client(context, "Thornbury Youth Theatre")
        let comped = Self.invoice(context, for: client, shoot: Self.today, amount: 0)

        let row = try #require(Self.present([comped]).bands.flatMap(\.rows).first)
        #expect(row.amount == "comped")
    }

    // MARK: helpers

    private static func written(_ day: BusinessDate) -> String {
        BusinessCalendar.shortDate(day) ?? ""
    }

    /// Puts money on an invoice through the real models.
    private static func settle(_ invoice: Invoice, in context: ModelContext, on day: BusinessDate,
                               method: PaymentMethod = .zelle, cleared: Bool = true,
                               amount: Money? = nil) {
        let paid = amount ?? invoice.total
        let payment = Payment(client: invoice.client, amount: paid, method: method,
                              receivedOn: day)
        context.insert(payment)
        if cleared, method.gainsAClearedStep { _ = payment.markCleared(on: day) }
        let allocation = PaymentAllocation(payment: payment, invoice: invoice, amount: paid,
                                           allocatedOn: day)
        context.insert(allocation)
        invoice.allocations.append(allocation)
        payment.allocations.append(allocation)
    }
}

private extension ModelContext {
    /// Every invoice inserted in this test, in no particular order, which is the
    /// point: the presenter declares the order, not the store.
    func registeredInvoices(excluding: Invoice? = nil) -> [Invoice] {
        let all = (try? fetch(FetchDescriptor<Invoice>())) ?? []
        return all.filter { $0.persistentModelID != excluding?.persistentModelID }
    }
}
