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

    // MARK: a stored date that will not read back

    @Test("a due date that cannot be read is not the same as having none, and does not read as waiting")
    func anunreadableDueDateDoesNotReadAsWaiting() throws {
        // L50. `BusinessCalendar.startOfDay(forDayKey:)` PARSES the stored key, so
        // it can fail, and a failure used to become the same nil as "no due date".
        // That put the invoice in "waiting on them", which is the permissive side:
        // an invoice long past its terms would sit quietly in the band for ones
        // that are not due yet, with nothing anywhere saying the date could not be
        // read.
        let context = try Self.store()
        let invoice = Self.invoice(context)
        invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Photography"))
        invoice.sentStatus = .sent(route: .ovationSentIt,
                                   at: Date(timeIntervalSince1970: 1_700_000_000))
        invoice.dueDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "not a day")

        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        #expect(standing.datesCouldNotBeRead)
        #expect(standing.dueDay == nil)
        // IT LANDS IN FRONT OF DAN. A record whose stored date will not read back
        // is a fault, and the one screen that reaches invoices is where he has any
        // chance of seeing it (L42: a control that exists to protect somebody fails
        // closed).
        #expect(InvoiceBand.allCases.filter { $0.claims(standing) } == [.overdue])
    }

    @Test("an invoice with genuinely no due date still reads as waiting, not as a fault")
    func agenuinelyAbsentDueDateIsNotAFault() throws {
        // The positive control for the test above. Without it, a change that
        // flagged EVERY invoice as unreadable would pass it (L159).
        let context = try Self.store()
        let invoice = Self.invoice(context, due: nil)
        invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Photography"))
        invoice.sentStatus = .sent(route: .ovationSentIt,
                                   at: Date(timeIntervalSince1970: 1_700_000_000))

        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        #expect(!standing.datesCouldNotBeRead)
        #expect(InvoiceBand.allCases.filter { $0.claims(standing) } == [.sentAwaitingPayment])
    }

    @Test("a shoot date that cannot be read puts the draft where a person will see it")
    func anunreadableShootDateSurfaces() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, due: nil)
        invoice.invoiceDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "nope")

        let standing = InvoiceStanding(of: invoice, today: Self.shootDay,
                                       couldSettleMoreThanOne: false)
        #expect(standing.datesCouldNotBeRead)
        #expect(InvoiceBand.allCases.filter { $0.claims(standing) } == [.draftNeedsSending])
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

    // MARK: which invoices held money could settle (ovation#453)

    /// THE ONE PREDICATE PRD 14h AND 14j COUNT OVER, asserted across every send
    /// state rather than the two the list's fixtures happen to hold. Dan,
    /// 2026-09-23: drafts COUNT as open invoices, "(draft or sent)". The two states
    /// that are neither keep what they had, which was not counted, because the
    /// decision does not name them.
    @Test("a draft and a sent invoice are open for held money, an unsettled send is not")
    func whichSendStatesHeldMoneyCounts() {
        let noon = Date(timeIntervalSince1970: 1_794_531_600)
        let attempt = SendAttempt(destination: ["booker@client.example"],
                                  wasRedirected: false, renderSHA256: "abc", startedAt: noon)
        let counted: [(SentStatus, Bool)] = [
            (.notSent, true),
            (.sent(route: .ovationSentIt, at: noon), true),
            (.couldNotDetermine(checkedAt: noon), false),
            (.attempting(attempt), false),
        ]
        for (sent, expected) in counted {
            #expect(InvoiceStanding(sent: sent).isOpenForHeldMoney == expected, "\(sent)")
        }
        // AND OPEN STILL MEANS OPEN: a cancelled draft or a paid and cleared one
        // is not money waiting on anything.
        #expect(!InvoiceStanding(ending: .cancelled, sent: .notSent).isOpenForHeldMoney)
        #expect(!InvoiceStanding(sent: .notSent, money: .allOfItCleared).isOpenForHeldMoney)
    }
}
