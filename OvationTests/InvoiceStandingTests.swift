import Foundation
import SwiftData
import Testing

/// ovation#49. Reading a stored invoice as the handful of facts the list bands on.
///
/// THE BANDS ARE PROVED OVER A VALUE TYPE AND THIS IS THE BRIDGE TO IT, which is
/// the half a sweep over `InvoiceStanding` cannot reach: the partition can be
/// perfect and still band every invoice wrongly if the reading that produces the
/// standing is wrong. So the sweep proves the bands, and this proves the reading,
/// and neither stands in for the other (L70).
struct InvoiceStandingTests {

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    /// 2026-11-12, and every date below is written against it so nothing here
    /// depends on when the suite runs (L130).
    private static let shootDay = BusinessDate.stamping(Date(timeIntervalSince1970: 1_794_531_600))
    private static let dayAfter = BusinessDate.stamping(Date(timeIntervalSince1970: 1_794_618_000))

    private static func client(_ context: ModelContext) -> Client {
        let client = Client(name: "A company", taxStatus: .notExempt)
        context.insert(client)
        return client
    }

    private static func invoice(_ context: ModelContext, dated: BusinessDate? = shootDay,
                                due: BusinessDate? = dayAfter) -> Invoice {
        let invoice = Invoice(client: Self.client(context), kind: .photography,
                              invoiceDate: dated,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        invoice.dueDate = due
        context.insert(invoice)
        return invoice
    }

    // MARK: the dates

    @Test("the shoot day is the invoice's own stamped date, read as a day rather than an instant")
    func theShootDayIsTheStampedDate() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        // TODAY IS ZERO, and every other day is counted from it, which is what
        // lets the bands be written without a calendar in them.
        #expect(standing.shootDay == InvoiceBand.today)
        #expect(standing.dueDay == InvoiceBand.today + 1)
    }

    @Test("a draft with no date at all reads as having none, never as today")
    func adatelessDraftKeepsItsNil() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, dated: nil, due: nil)
        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        // DEFAULTING IT TO TODAY WOULD PUT IT IN "SEND IT TODAY" and it would look
        // like an ordinary row, which is precisely the state ovation#49 exists to
        // stop being invisible (L67).
        #expect(standing.shootDay == nil)
        #expect(standing.dueDay == nil)
        #expect(InvoiceBand.allCases.filter { $0.claims(standing) } == [.draftNeedsSending])
    }

    // MARK: the money

    @Test("an invoice with nothing against it reads as owing everything")
    func nothingPaidReadsAsNothing() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        invoice.add(LineItem.hourly(hours: Hours(tenths: 20), at: invoice.hourlyRate,
                                    describedAs: "Photography"))
        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        #expect(standing.money == .nothing)
    }

    @Test("a comped invoice that comes to nothing reads as settled, not as unpaid")
    func acompedInvoiceIsSettled() throws {
        // PRD 1b: a zero invoice is an ordinary invoice that happens to total
        // nothing, and no guard may refuse one. It owes nobody anything, so it is
        // not waiting on money and must not sit in a band that says it is. This
        // follows `paymentState` rather than deciding it again here (L370).
        let context = try Self.store()
        let invoice = Self.invoice(context)
        #expect(invoice.total == .zero)
        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        #expect(standing.money == .allOfItCleared)
    }

    @Test("an uncleared check against a fully paid invoice is its own answer")
    func anUnclearedCheckIsItsOwnAnswer() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Photography"))
        Self.pay(invoice, in: context, method: .check, cleared: false)

        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        #expect(standing.money == .allOfItAwaitingAClearedCheck)
    }

    @Test("the same check once cleared reads as cleared")
    func aclearedCheckReadsAsCleared() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Photography"))
        Self.pay(invoice, in: context, method: .check, cleared: true)

        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        #expect(standing.money == .allOfItCleared)
    }

    @Test("a method with no cleared step never waits on one")
    func amethodWithNoClearedStepNeverWaits() throws {
        // PRD 5.15: only a check gains a cleared step. Reading "not cleared" off a
        // Zelle payment would park it in "confirm it cleared" for ever, with no
        // control anywhere able to answer (L109).
        let context = try Self.store()
        let invoice = Self.invoice(context)
        invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Photography"))
        Self.pay(invoice, in: context, method: .zelle, cleared: false)

        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        #expect(standing.money == .allOfItCleared)
    }

    @Test("a released allocation stops counting, so the invoice owes again")
    func areleasedAllocationStopsCounting() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Photography"))
        Self.pay(invoice, in: context, method: .zelle, cleared: false)
        invoice.releaseActiveAllocations(on: Self.dayAfter)

        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        #expect(standing.money == .nothing)
    }

    // MARK: the endings

    @Test("a cancelled invoice reads as cancelled and lands in the cancelled band")
    func acancelledInvoiceIsCancelled() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        invoice.closure = .cancelled(on: Self.dayAfter, reason: "shoot did not happen")
        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        #expect(standing.ending == .cancelled)
        #expect(InvoiceBand.allCases.filter { $0.claims(standing) } == [.cancelled])
    }

    @Test("a deleted draft reads as deleted, and no band draws it")
    func adeletedDraftIsDrawnNowhere() throws {
        // PRD 1b, Dan 2026-09-20. This is the whole of what deleting does to the
        // list, asserted through the reading rather than only over the value type.
        let context = try Self.store()
        let invoice = Self.invoice(context)
        invoice.closure = .deleted(on: Self.dayAfter, reason: "never going to bill it")
        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        #expect(standing.ending == .deleted)
        #expect(!standing.isDrawn)
        #expect(InvoiceBand.allCases.filter { $0.claims(standing) }.isEmpty)
    }

    // MARK: what is carried straight through

    @Test("the sent status is carried across unchanged, all three of it")
    func thesentStatusIsCarriedThrough() throws {
        let context = try Self.store()
        for status in [SentStatus.notSent,
                       .sent(route: .foundInTheMailbox, at: Date(timeIntervalSince1970: 1)),
                       .couldNotDetermine(checkedAt: Date(timeIntervalSince1970: 1))] {
            let invoice = Self.invoice(context)
            invoice.sentStatus = status
            let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                           couldSettleMoreThanOne: false)
            #expect(standing.sent == status)
        }
    }

    @Test("whether held money could settle more than one is given, never read off the invoice")
    func thecrossInvoiceAnswerIsGiven() throws {
        // PRD 46d is decided across a client's whole set of open invoices, so an
        // invoice cannot answer it about itself. It arrives as an argument, and
        // that is what stops a band quietly depending on a field nobody listed.
        let context = try Self.store()
        let invoice = Self.invoice(context)
        #expect(InvoiceStanding(of: invoice, today: Self.shootDay,
                                couldSettleMoreThanOne: true).couldSettleMoreThanOne)
        #expect(!InvoiceStanding(of: invoice, today: Self.shootDay,
                                 couldSettleMoreThanOne: false).couldSettleMoreThanOne)
    }

    // MARK: putting money on an invoice

    /// Settles `invoice` in full, through the real models rather than by setting a
    /// flag, so what is asserted above is what the app's own arithmetic produces.
    private static func pay(_ invoice: Invoice, in context: ModelContext,
                            method: PaymentMethod, cleared: Bool) {
        let payment = Payment(client: invoice.client, amount: invoice.total,
                              method: method, receivedOn: dayAfter)
        context.insert(payment)
        if cleared { _ = payment.markCleared(on: dayAfter) }
        let allocation = PaymentAllocation(payment: payment, invoice: invoice,
                                           amount: invoice.total, allocatedOn: dayAfter)
        context.insert(allocation)
        invoice.allocations.append(allocation)
        payment.allocations.append(allocation)
    }
}
