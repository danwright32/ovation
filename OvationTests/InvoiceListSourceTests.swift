import Foundation
import SwiftData
import Testing

/// ovation#451. The invoice list re-deriving on every write that feeds it.
///
/// WHAT WAS WRONG. `OvationApp` built the presenter once, inside the launch, and
/// held the result as values. The list, the sidebar card's counts and the rail's
/// held money figure were a photograph of the store taken at launch, and nothing
/// rebuilt any of them. It was invisible by construction: nothing in the app
/// could change an invoice yet, so the photograph was always current and every
/// test passed (L3, L14).
///
/// THE TWO DERIVED FIGURES ARE TESTED TOGETHER, deliberately. The list and the
/// held money line come from one read and are two separate pieces of state on the
/// app, which is exactly the shape where one is rebuilt and the other is
/// forgotten, and the forgotten one goes on reading correctly-formed and wrong.
@MainActor
struct InvoiceListSourceTests {

    /// 2026-11-12, so nothing here depends on when the suite runs (L130).
    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    private static func problems() -> ProblemsStore {
        ProblemsStore(journal: InMemoryProblemsJournal())
    }

    /// HELD MONEY IS DERIVED, never set: it is what arrived less what is spoken
    /// for (`Client.moneyHeld`). So a client holding money is a client with an
    /// unallocated payment, which is also the only way the app can produce one.
    private static func client(_ context: ModelContext, holding held: Money = .zero) -> Client {
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        if held > .zero { pay(context, client, held) }
        return client
    }

    /// ZELLE RATHER THAN A CHECK, and that is a choice rather than a detail. A
    /// check gains a cleared step (PRD 5.15), so a fully allocated check lands in
    /// `checkNotCleared` and not in `paidOrCleared`. These cases are about the
    /// list re-deriving, so they use the method with no second step, and the
    /// clearing rule is `InvoiceBandTests`' subject rather than this suite's.
    @discardableResult
    private static func pay(_ context: ModelContext, _ client: Client, _ amount: Money) -> Payment {
        let payment = Payment(client: client, amount: amount, method: .zelle,
                              receivedOn: .stamping(noon))
        context.insert(payment)
        return payment
    }

    /// An invoice that is actually owed something, because an invoice with no
    /// line is owed nothing and is settled before anybody looks at it, which would
    /// make every band below the wrong one for the wrong reason.
    @discardableResult
    private static func invoice(
        _ context: ModelContext, for client: Client,
        dollars: Int64 = 400, due: BusinessDate? = nil, sent: Bool = false
    ) -> Invoice {
        // NO TAX ON THE FIXTURE, so the amount owed is the line and nothing else.
        // With sales tax on it, a payment of the line amount leaves the invoice
        // part paid, and a case about the list re-deriving would be failing on the
        // arithmetic instead (L48).
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: .stamping(noon),
                              hourlyRate: Money(dollars: 250),
                              taxRate: TaxRate(thousandthsOfAPercent: 0))
        invoice.dueDate = due
        invoice.add(LineItem.flat(Money(dollars: dollars), describedAs: "Photography"))
        if sent {
            invoice.number = 1_123
            invoice.sentStatus = .sent(route: .ovationSentIt, at: noon)
        }
        context.insert(invoice)
        return invoice
    }

    private static func band(_ source: InvoiceListSource) -> InvoiceBand? {
        source.list?.bands.first?.band
    }

    // MARK: the defect itself

    /// THE ACCEPTANCE TEST FOR ovation#451, and it is written over a real
    /// container and a real writer actor rather than over a stubbed read. The
    /// defect was that a value survived a write; a test whose write is a closure
    /// call cannot see the thing that actually went wrong, which is that SwiftData
    /// contexts do not merge (L52, L472).
    @Test("a writer actor's save re-derives the list")
    func awriteRedrawsTheList() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let setUp = ModelContext(container)
        let client = Self.client(setUp, holding: Money(dollars: 400))
        let invoice = Self.invoice(setUp, for: client, sent: true)
        try setUp.save()

        let source = InvoiceListSource(over: container, problems: Self.problems(),
                                       now: { Self.noon })
        defer { source.stop() }
        #expect(Self.band(source) == .sentAwaitingPayment, "the band before anything wrote")

        let payment = try #require(try ModelContext(container)
            .fetch(FetchDescriptor<Payment>()).first)
        try await PaymentAllocator(modelContainer: container).allocate(
            Money(dollars: 400), from: payment.persistentModelID,
            to: invoice.persistentModelID, on: .stamping(Self.noon))

        #expect(await Self.settle { Self.band(source) == .paidOrCleared },
                "the invoice was paid in full and the list still bands it as waiting")
    }

    /// THE SECOND FIGURE FROM THE SAME READ. PRD 46b's held money line is on the
    /// rail rather than in the list, and was a separate piece of state on the app,
    /// so it is the one a rebuild of "the list" leaves behind.
    @Test("the rail's held money figure re-derives with the list")
    func heldMoneyRedrawsToo() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let setUp = ModelContext(container)
        let client = Self.client(setUp, holding: Money(dollars: 400))
        let invoice = Self.invoice(setUp, for: client, sent: true)
        try setUp.save()

        let source = InvoiceListSource(over: container, problems: Self.problems(),
                                       now: { Self.noon })
        defer { source.stop() }
        #expect(source.heldMoney == "400.00", "the figure at the start")

        // SPENT BY THE REAL WRITER, from its own context, exactly as the app does
        // it. The money stops being held because it was applied to the invoice,
        // which is the only way it stops being held (PRD 14k).
        let payment = try #require(try ModelContext(container)
            .fetch(FetchDescriptor<Payment>()).first)
        try await PaymentAllocator(modelContainer: container).allocate(
            Money(dollars: 400), from: payment.persistentModelID,
            to: invoice.persistentModelID, on: .stamping(Self.noon))

        #expect(await Self.settle { source.heldMoney == nil },
                "the money was applied to the invoice and the rail still says something")
    }

    /// A QUANTITY OF NOTHING IS NOT DRAWN (PRD 46b), and that has to survive a
    /// re-read in the other direction too: the figure appearing is as much a
    /// change as it going away.
    @Test("held money appearing is drawn, having not been there before")
    func heldMoneyAppearing() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let setUp = ModelContext(container)
        let client = Self.client(setUp)
        Self.invoice(setUp, for: client)
        try setUp.save()

        let source = InvoiceListSource(over: container, problems: Self.problems(),
                                       now: { Self.noon })
        defer { source.stop() }
        #expect(source.heldMoney == nil, "nothing is held at the start")

        // Written from another context, exactly as a writer actor writes.
        let writer = ModelContext(container)
        let there = try #require(try writer.fetch(FetchDescriptor<Client>()).first)
        Self.pay(writer, there, Money(dollars: 250))
        try writer.save()

        #expect(await Self.settle { source.heldMoney == "250.00" },
                "money arrived and the rail does not say 250.00")
    }

    // MARK: the day the list is read on

    /// THE CLOCK IS READ AT EVERY READ, not captured at launch. The bands are
    /// decided against a day (PRD 46), so an app left open overnight would go on
    /// banding against the day it was opened, and an invoice would become overdue
    /// with the screen never saying so. The defect and its fix are the same shape:
    /// a value that was true once and is then held (L175).
    @Test("a re-read bands against the day it is read on, not the day of launch")
    func thebandsFollowTheClock() throws {
        let container = try OvationSchema.container(inMemory: true)
        let setUp = ModelContext(container)
        let client = Self.client(setUp)
        Self.invoice(setUp, for: client,
                     due: .stamping(Self.noon.addingTimeInterval(86_400)), sent: true)
        try setUp.save()

        var today = Self.noon
        let source = InvoiceListSource(over: container, problems: Self.problems(),
                                       now: { today })
        defer { source.stop() }
        #expect(Self.band(source) == .sentAwaitingPayment,
                "it is not yet due, so it cannot be overdue")

        today = Self.noon.addingTimeInterval(86_400 * 5)
        source.reread()

        #expect(Self.band(source) == .overdue,
                "five days past its due date and the list still bands it as waiting")
    }

    // MARK: a read that fails

    /// A FAILED RE-READ IS NOT AN EMPTY LIST, for the same reason a failed read at
    /// launch is not: this screen's empty state says everything is paid, and a
    /// list drawn empty because the fetch threw says that too (L10, L215).
    ///
    /// AND IT DOES NOT KEEP THE LAST GOOD ANSWER EITHER. A stale list of rows that
    /// may no longer exist, drawn exactly like a current one, is the defect this
    /// issue is about wearing a different hat.
    @Test("a re-read that throws raises the problem and draws no list")
    func afailedRereadRaises() throws {
        var readFails = false
        let problems = Self.problems()
        let source = InvoiceListSource(
            read: {
                if readFails { throw CocoaError(.fileReadUnknown) }
                return ([], [])
            },
            problems: problems, now: { Self.noon })
        defer { source.stop() }

        #expect(source.list != nil, "the first read succeeded, so there is a list")
        #expect(problems.open.isEmpty, "nothing is wrong yet")

        readFails = true
        source.reread()

        #expect(source.list == nil, "a list was still drawn after the read threw")
        #expect(problems.open.map(\.kind) == [InvoiceListSource.invoicesUnreadable],
                "the failure was not reported")
    }

    /// A RE-READ THAT WORKS IS PROOF THE INVOICES ARE READABLE, which is the whole
    /// of what the problem claimed. It is resolved for the same reason the launch
    /// sequence resolves the backup folder notice on a backup happening: nothing
    /// else retracts it, `ProblemsStore` never retracts on its own, and a standing
    /// notice about a condition that has passed is one Dan learns to click past
    /// (L36).
    @Test("a read that recovers resolves the problem it raised")
    func arecoveredReadResolves() throws {
        var readFails = true
        let problems = Self.problems()
        let source = InvoiceListSource(
            read: {
                if readFails { throw CocoaError(.fileReadUnknown) }
                return ([], [])
            },
            problems: problems, now: { Self.noon })
        defer { source.stop() }
        #expect(problems.open.count == 1, "the first read failed, so there is a problem")

        readFails = false
        source.reread()

        #expect(source.list != nil, "the read recovered and there is still no list")
        #expect(problems.open.isEmpty,
                "the invoices are readable again and the notice still stands")
        let resolved = try #require(problems.all.first)
        #expect(resolved.resolutionReason?.isEmpty == false,
                "resolved with no reason, which is a notice tidied away rather than settled")
    }

    // MARK: waiting

    /// Waits on the CONDITION rather than on a duration, because a fixed wait
    /// asserts about the machine's load (L290). The deadline only exists so a
    /// broken case fails instead of hanging.
    private static func settle(
        within seconds: Double = 5,
        until condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: the screen it builds (ovation#457)

    /// THE TYPES COME FROM THE SAME READ AS THE INVOICE. This is the only place
    /// that owns the store, so if it does not fetch them the screen offers an
    /// empty list and draws no way to add a line at all, which is indistinguishable
    /// from a store with no types in it (L3, L622).
    @Test("the screen it builds is offered the store's active service types")
    func thescreenCarriesTheServiceTypes() throws {
        let container = try OvationSchema.container(inMemory: true)
        let setUp = ModelContext(container)
        let client = Self.client(setUp)
        let invoice = Self.invoice(setUp, for: client)
        let retired = ServiceType(name: "Contact sheets", role: .ordinary,
                                  defaultUnitAmount: nil)
        retired.retiredOn = .stamping(Self.noon)
        setUp.insert(retired)
        setUp.insert(ServiceType(name: "Rush turnaround", role: .ordinary,
                                 defaultUnitAmount: Money(dollars: 150)))
        try setUp.save()
        let source = InvoiceListSource(over: container, problems: Self.problems(),
                                       now: { Self.noon })
        defer { source.stop() }

        let screen = try #require(source.screen(for: invoice.persistentModelID,
                                                footer: .fixed))

        #expect(screen.serviceTypes.map(\.name) == ["Rush turnaround"],
                "the retired type was offered, or the active one was not")
        #expect(screen.mayAddLine)
    }

    /// THE POSITIVE CONTROL. Without it a source that never fetched would pass
    /// the case above whenever the store happened to hold one type (L159).
    @Test("and a store with no service type offers no line to add")
    func astoreWithNoTypesOffersNoLine() throws {
        let container = try OvationSchema.container(inMemory: true)
        let setUp = ModelContext(container)
        let client = Self.client(setUp)
        let invoice = Self.invoice(setUp, for: client)
        try setUp.save()
        let source = InvoiceListSource(over: container, problems: Self.problems(),
                                       now: { Self.noon })
        defer { source.stop() }

        let screen = try #require(source.screen(for: invoice.persistentModelID,
                                                footer: .fixed))

        #expect(screen.serviceTypes.isEmpty)
        #expect(screen.mayAddLine == false)
    }
}
