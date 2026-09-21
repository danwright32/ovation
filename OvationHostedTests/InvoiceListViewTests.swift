import SwiftData
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#49, PRD section 6, 46, 46d, 47. The invoice list, rendered and read
/// rather than reasoned about.
///
/// WHY THESE ARE HOSTED, for the reason `RosterPassViewTests` gives: the precedent
/// is postroll#846 and #855, where presenters shared a surface, one heading landed
/// over another's buttons, and every model level test passed throughout. What
/// these assert lives in the binding, so they render the real view.
///
/// THEY RUN AT THE REAL COUNT (L606). A two row fixture and a green suite are the
/// two ways a screen ships unseen, and this one is a list whose whole job is to
/// hold everything. The count is the one the design record was settled at, eleven
/// invoices across five bands, plus the shapes ovation#49's sweep proved exist and
/// no design fixture holds.
@MainActor
struct InvoiceListViewTests {

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    private static let today = BusinessDate.stamping(Date(timeIntervalSince1970: 1_794_531_600))

    private static func day(_ offset: Int) -> BusinessDate {
        .stamping(Date(timeIntervalSince1970: 1_794_531_600 + Double(offset) * 86_400))
    }

    /// The design record's own population, built as the app records it: drafts to
    /// send, overdue invoices to chase, one uncleared check, one invoice whose
    /// send could not be determined, and one client holding money against two open
    /// invoices.
    private static func theRealList(_ context: ModelContext)
        -> (invoices: [Invoice], held: [Client: Money]) {
        func client(_ name: String) -> Client {
            let c = Client(name: name, taxStatus: .notExempt)
            context.insert(c)
            return c
        }
        func invoice(_ c: Client, _ shootName: String, on day: BusinessDate?,
                     due: BusinessDate? = nil, number: Int64? = nil, sent: Bool = false,
                     amount: Int64 = 1_240) -> Invoice {
            let i = Invoice(client: c, kind: .photography, invoiceDate: day,
                            hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
            i.dueDate = due
            i.number = number
            if sent {
                i.sentStatus = .sent(route: .ovationSentIt,
                                     at: Date(timeIntervalSince1970: 1_794_000_000))
            }
            i.add(LineItem.flat(Money(dollars: amount), describedAs: "Photography"))
            if let day { i.add(Shoot(name: shootName, when: .dayOnly(day), venue: nil)) }
            else { i.add(Shoot(name: shootName, when: nil, venue: nil)) }
            context.insert(i)
            return i
        }

        let harbor = client("Harbor Light Opera")
        let westfield = client("Westfield Choral Society")
        let ninth = client("Ninth Street Players")
        let cedar = client("Cedar Hill Youth Orchestra")
        let saints = client("Saint Anne's Chamber Series")
        let alder = client("Alder Street Opera")
        let kestrel = client("Kestrel Quartet")

        var all: [Invoice] = []
        all.append(invoice(harbor, "Tosca, opening night", on: today, amount: 3_700))
        all.append(invoice(westfield, "Autumn Evensong", on: day(-34), due: day(-34),
                           number: 1021, sent: true))
        all.append(invoice(ninth, "The Winter Guest", on: day(-12), due: day(-12),
                           number: 1029, sent: true, amount: 960))
        // ONE CLIENT WITH TWO OPEN INVOICES, which PRD 14j is about and which the
        // design record had none of until ovation#190.
        all.append(invoice(cedar, "Family concert", on: day(-29), due: day(-29),
                           number: 1026, sent: true, amount: 620))
        all.append(invoice(cedar, "Autumn Gala", on: day(-17), due: day(-17),
                           number: 1044, sent: true, amount: 1_400))
        all.append(invoice(cedar, "Side by Side concert", on: day(-2), amount: 1_400))
        // AN INVOICE HOLDING A NUMBER IT WAS NEVER SENT WITH (PRD 46g).
        all.append(invoice(harbor, "Autumn Winds", on: day(-1), number: 1041, amount: 780))
        // A DRAFT WITH NO SHOOT DATE, the state ovation#49 exists for.
        all.append(invoice(kestrel, "Quartet in E minor", on: nil, amount: 1_650))
        // A COMPED SHOOT, which PRD 1b says is an ordinary invoice.
        all.append(invoice(harbor, "Benefit matinee", on: day(-3), amount: 0))
        let check = invoice(saints, "Advent Vespers", on: day(-20), due: day(-6),
                            number: 1033, sent: true, amount: 1_100)
        Self.settle(check, in: context, on: day(-5), method: .check, cleared: false)
        all.append(check)
        let unknown = invoice(alder, "La Boheme, act three", on: day(-18), due: day(-4),
                              number: 1037, sent: true, amount: 1_320)
        unknown.sentStatus = .couldNotDetermine(
            checkedAt: Date(timeIntervalSince1970: 1_794_400_000))
        all.append(unknown)

        return (all, [cedar: Money(dollars: 500)])
    }

    private static func view(_ context: ModelContext)
        -> (view: InvoiceListView, presenter: InvoiceListPresenter) {
        let (invoices, held) = theRealList(context)
        let presenter = InvoiceListPresenter(invoices: invoices, heldMoney: held, today: today)
        return (InvoiceListView(presenter: presenter, heldMoney: "500.00",
                                selected: .constant(nil)), presenter)
    }

    // MARK: every invoice is on the screen

    @Test("every invoice in the store is drawn, at the real count")
    func everyInvoiceIsDrawn() throws {
        let context = try Self.store()
        let (view, presenter) = Self.view(context)
        let drawn = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }

        // THE COUNT IS ASSERTED, not a sample of it. A list whose job is to hold
        // everything is exactly the surface where a missing row is invisible.
        #expect(presenter.bands.flatMap(\.rows).count == 11)
        for row in presenter.bands.flatMap(\.rows) {
            #expect(drawn.contains(row.shoot), "the screen is missing \(row.shoot)")
        }
    }

    @Test("the dateless draft is on the screen, saying it has no date")
    func thedatelessDraftIsDrawn() throws {
        let context = try Self.store()
        let (view, _) = Self.view(context)
        let drawn = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        #expect(drawn.contains("Quartet in E minor"))
        #expect(drawn.contains("no date"))
        // AND IT OFFERS THE THING IT IS WAITING FOR (PRD 46f).
        #expect(drawn.contains("Add date"))
    }

    @Test("an invoice holding a number it never sent with says draft")
    func aheldNumberSaysDraft() throws {
        // PRD 46g, Dan 2026-09-19, chosen over showing the number with both drawn
        // on the real screen. The Invoice column means the client has this number.
        let context = try Self.store()
        let (_, presenter) = Self.view(context)
        let holding = try #require(presenter.bands.flatMap(\.rows)
            .first { $0.shoot == "Autumn Winds" })
        #expect(holding.number == "draft")
    }

    // MARK: no headings, and no red

    @Test("no band heading is drawn, because the bands decide the order and nothing else")
    func nobandHeadingIsDrawn() throws {
        // PRD 46. The words below are the names of the bands as section 6 lists
        // them; none may appear on the screen.
        let context = try Self.store()
        let (view, _) = Self.view(context)
        let drawn = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        for heading in ["Send it today", "Chase it", "Should have been sent",
                        "Confirm it cleared", "Waiting on them", "Nothing to do yet",
                        "Paid or cleared", "Cancelled"] {
            #expect(!drawn.contains(heading), "a band heading is drawn: \(heading)")
        }
    }

    @Test("lateness is an age rather than an alarm")
    func latenessIsAnAge() throws {
        // PRD 45, Dan 2026-09-06: red "feels like something is wrong", and an
        // overdue invoice is not an error.
        let context = try Self.store()
        let (view, _) = Self.view(context)
        let drawn = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        #expect(drawn.contains("34d"))
    }

    // MARK: the held money band

    @Test("the waiting band says what is held, above the invoices it could settle")
    func thewaitingBandSaysWhatIsHeld() throws {
        let context = try Self.store()
        let (view, presenter) = Self.view(context)
        let drawn = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        #expect(drawn.contains("500.00 held"))
        // PRD 46d: it MOVES its rows rather than copying them, so the two invoices
        // are drawn once, here.
        let place = try #require(presenter.bands.first { $0.band == .toPlace })
        #expect(place.rows.count == 2)
        #expect(presenter.bands.flatMap(\.rows).filter { $0.shoot == "Family concert" }.count == 1)
    }

    // MARK: the empty day

    @Test("an empty list says the healthy thing rather than drawing nothing")
    func anemptyListSaysSo() throws {
        // L610: a positive statement on the healthy day. Nothing drawn at all
        // reads as a screen that failed to load (L10).
        let presenter = InvoiceListPresenter(invoices: [], heldMoney: [:], today: Self.today)
        let view = InvoiceListView(presenter: presenter, heldMoney: nil,
                                   selected: .constant(nil))
        let drawn = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        #expect(drawn.contains { $0.contains("Nothing is waiting") })
    }

    // MARK: what a screen reader hears

    @Test("a row is read as one line, in the order the line reads")
    func arowIsReadAsOneLine() throws {
        // L20 and PRD 5.41. Five separate labels would be read out as five
        // unrelated fragments, which is what a grid of Text views produces unless
        // the row says otherwise.
        let row = InvoiceListPresenter.Row(
            invoiceID: try Self.anyID(), client: "Westfield Choral Society",
            shoot: "Autumn Evensong", otherShoots: 0, shootDate: "18 Jul 2026",
            number: "1021", amount: "1,240.00", action: "Remind", age: "34d")
        #expect(InvoiceListView.spoken(row)
                == "Westfield Choral Society, Autumn Evensong, 18 Jul 2026, "
                + "invoice 1021, 1,240.00, 34d past due, Remind")
    }

    @Test("a draft is read as a draft rather than as an invoice number")
    func adraftIsReadAsADraft() throws {
        let row = InvoiceListPresenter.Row(
            invoiceID: try Self.anyID(), client: "Kestrel Quartet",
            shoot: "Quartet in E minor", otherShoots: 0, shootDate: "no date",
            number: "draft", amount: "1,650.00", action: "Add date", age: nil)
        #expect(InvoiceListView.spoken(row)
                == "Kestrel Quartet, Quartet in E minor, no date, draft, "
                + "1,650.00, Add date")
    }

    @Test("one shoot and several are separate words")
    func oneShootAndSeveralAreSeparateWords() {
        // "+1 shoots" is the kind of line that makes a person stop trusting the
        // rest of the screen.
        #expect(InvoiceListView.moreShoots(1) == "+1 shoot")
        #expect(InvoiceListView.moreShoots(2) == "+2 shoots")
    }

    // MARK: helpers

    /// A persistent id to build a Row with, taken from a real inserted invoice
    /// because `PersistentIdentifier` cannot be made up.
    private static func anyID() throws -> PersistentIdentifier {
        let context = try store()
        let client = Client(name: "A company", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        context.insert(invoice)
        return invoice.persistentModelID
    }

    private static func settle(_ invoice: Invoice, in context: ModelContext,
                               on day: BusinessDate, method: PaymentMethod, cleared: Bool) {
        let payment = Payment(client: invoice.client, amount: invoice.total,
                              method: method, receivedOn: day)
        context.insert(payment)
        if cleared { _ = payment.markCleared(on: day) }
        let allocation = PaymentAllocation(payment: payment, invoice: invoice,
                                           amount: invoice.total, allocatedOn: day)
        context.insert(allocation)
        invoice.allocations.append(allocation)
        payment.allocations.append(allocation)
    }
}
