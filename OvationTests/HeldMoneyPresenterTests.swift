import Foundation
import SwiftData
import Testing

/// ovation#185, PRD 14h to 14k and 14m. What the invoice screen draws about a
/// client's held money, under the Total, in the design record's own order.
///
/// THE ROWS ARE ASSERTED WHOLE, label, figure and weight in order from the Total
/// down, for the reason `InvoicePaymentPresenterTests` gives: the rules are about
/// the relationship between rows. Held money sits below the Total and never inside
/// the subtotal (14k), and Outstanding carries the weight only where it is drawn
/// (14m).
@MainActor
struct HeldMoneyPresenterTests {

    /// 2026-11-12 12:00 in New York, so nothing depends on when the suite runs.
    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    private struct World {
        let container: ModelContainer
        let context: ModelContext
        let client: Client

        func read(_ invoice: Invoice) throws -> Invoice {
            try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
                .first { $0.id == invoice.id })
        }
    }

    private static func world(taxStatus: TaxStatus = .notExempt) throws -> World {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: taxStatus)
        client.email = "booker@example.com"
        context.insert(client)
        return World(container: container, context: context, client: client)
    }

    /// 375.00 for a taxed client: tax 33.28, total 408.28, the design's own figures.
    @discardableResult
    private static func invoice(_ world: World, charging: Money = Money(dollars: 375),
                                sent: Bool = true) -> Invoice {
        let invoice = Invoice(client: world.client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity,
                              createdOn: today)
        world.context.insert(invoice)
        invoice.add(LineItem.flat(charging, describedAs: "Photography"))
        if sent { invoice.sentStatus = .sent(route: .ovationSentIt, at: noon) }
        return invoice
    }

    /// Money the client holds: a payment with nothing allocated from it.
    private static func holding(_ world: World, _ amount: Money) {
        world.context.insert(Payment(client: world.client, amount: amount, method: .zelle,
                                     receivedOn: today))
    }

    private static func present(_ invoice: Invoice) -> InvoiceScreenPresenter {
        InvoiceScreenPresenter(invoice: invoice, footer: .fixed, today: today)
    }

    /// The rows from the Total down, as label, figure and weight.
    private static func fromTheTotal(_ presenter: InvoiceScreenPresenter) -> [String] {
        let rows = presenter.money
        guard let at = rows.firstIndex(where: { $0.label == "Total" }) else { return [] }
        return rows[at...].map { "\($0.label)|\($0.value)|\($0.isTotal ? "heavy" : "plain")" }
    }

    private static func place(_ world: World) async throws {
        try await PaymentAllocator(modelContainer: world.container).placeHeldMoney(on: today)
    }

    // MARK: applied, PRD 14h and 14k

    @Test("held money applied is a line under the Total carrying Remove, Outstanding carries the weight, and the rest is said")
    func appliedWithSomeLeft() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world)
        try world.context.save()
        try await Self.place(world)

        let presenter = Self.present(try world.read(invoice))

        #expect(Self.fromTheTotal(presenter) == [
            "Total|408.28|plain",
            "Held money applied|-408.28|plain",
            "Outstanding|0.00|heavy",
            "$91.72 stays held on the client.||plain",
        ])
        let held = try #require(presenter.money.first { $0.label == "Held money applied" })
        #expect(held.takesOffHeld == invoice.persistentModelID, "Remove sits on this line (PRD 14i)")
        #expect(presenter.money.first { $0.label.hasSuffix("stays held on the client.") }?
                    .isSentence == true)
    }

    @Test("held money smaller than the invoice leaves the rest outstanding and says nothing is left held")
    func appliedWithNoneLeft() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 200))
        let invoice = Self.invoice(world)
        try world.context.save()
        try await Self.place(world)

        let presenter = Self.present(try world.read(invoice))

        #expect(Self.fromTheTotal(presenter) == [
            "Total|408.28|plain",
            "Held money applied|-200.00|plain",
            "Outstanding|208.28|heavy",
        ])
        #expect(presenter.paymentStarts?.amount == "208.28",
                "the payment sheet starts at what is still owed after it")
    }

    @Test("held money and a payment are each their own line, and Outstanding is drawn once")
    func appliedBesideAPayment() async throws {
        let world = try Self.world()
        let invoice = Self.invoice(world)
        try world.context.save()
        try await PaymentAllocator(modelContainer: world.container)
            .record(Money(dollars: 100), method: .zelle, receivedOn: Self.today,
                    onto: invoice.persistentModelID, press: UUID())
        Self.holding(world, Money(dollars: 50))
        try world.context.save()
        try await Self.place(world)

        let presenter = Self.present(try world.read(invoice))

        #expect(Self.fromTheTotal(presenter) == [
            "Total|408.28|plain",
            "Held money applied|-50.00|plain",
            "Paid 12 Nov by Zelle|-100.00|plain",
            "Outstanding|258.28|heavy",
        ])
    }

    // MARK: offered, PRD 14j and 14i

    @Test("with two open invoices nothing is applied, and each says why and offers Use it here")
    func twoOpenOffersUseItHere() throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world)
        Self.invoice(world, charging: Money(dollars: 300), sent: false)
        try world.context.save()

        let presenter = Self.present(try world.read(invoice))

        #expect(Self.fromTheTotal(presenter) == [
            "Total|408.28|heavy",
            "Cedar Hill Youth Orchestra is holding|$500.00|plain",
            "2 invoices are open for this client, so it was not put on either.||plain",
        ])
        let offer = try #require(presenter.money.first { $0.offersHeld != nil }?.offersHeld)
        #expect(offer.word == "Use it here")
        #expect(offer.invoice == invoice.persistentModelID)
    }

    @Test("with three open invoices the reason does not say either")
    func threeOpenSaysAnyOfThem() throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world)
        Self.invoice(world, charging: Money(dollars: 300), sent: false)
        Self.invoice(world, charging: Money(dollars: 200), sent: false)
        try world.context.save()

        let presenter = Self.present(try world.read(invoice))

        #expect(presenter.money.last?.label
                == "3 invoices are open for this client, so it was not put on any of them.")
    }

    @Test("Remove takes the line off and offers Use it, and the subtotal, the tax and the Total do not move")
    func removeLeavesTheTotalsAlone() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world)
        try world.context.save()
        func totals() throws -> [String] {
            Self.present(try world.read(invoice)).money
                .filter { ["Subtotal", "Sales tax, 8.875%", "Total"].contains($0.label) }
                .map { "\($0.label)|\($0.value)" }
        }
        let before = try totals()
        #expect(before.count == 3, "all three are drawn, or this proves nothing")

        try await Self.place(world)
        let applied = try totals()
        try await PaymentAllocator(modelContainer: world.container)
            .removeHeldMoney(from: invoice.persistentModelID, on: Self.today)
        let removed = try totals()

        // PRD 14k, the assertion the design record's own check makes, here against
        // the real totals: held money never reaches the tax base.
        #expect(applied == before)
        #expect(removed == before)
        let presenter = Self.present(try world.read(invoice))
        #expect(Self.fromTheTotal(presenter) == [
            "Total|408.28|heavy",
            "Cedar Hill Youth Orchestra is holding|$500.00|plain",
        ])
        #expect(presenter.money.first { $0.offersHeld != nil }?.offersHeld?.word == "Use it")
    }

    // MARK: nothing drawn

    @Test("a paid invoice draws neither the applied line nor the offer, however much the client holds")
    func apaidInvoiceDrawsNothing() async throws {
        let world = try Self.world()
        let invoice = Self.invoice(world)
        try world.context.save()
        try await PaymentAllocator(modelContainer: world.container)
            .record(Money(cents: 40_828), method: .check, receivedOn: Self.today,
                    onto: invoice.persistentModelID, press: UUID())
        Self.holding(world, Money(dollars: 500))
        try world.context.save()

        let presenter = Self.present(try world.read(invoice))

        #expect(!presenter.money.contains { $0.offersHeld != nil || $0.takesOffHeld != nil })
        #expect(!presenter.money.contains { $0.label.contains("holding") })
    }

    @Test("a client holding nothing gets nothing here")
    func holdingNothingDrawsNothing() throws {
        let world = try Self.world()
        let invoice = Self.invoice(world)
        Self.invoice(world, charging: Money(dollars: 300), sent: false)
        try world.context.save()

        #expect(Self.fromTheTotal(Self.present(try world.read(invoice))) == ["Total|408.28|heavy"])
    }

    @Test("with no tax status there is no Total, so there is no held money line either")
    func noTotalNoHeldMoney() throws {
        let world = try Self.world(taxStatus: .neverRecorded)
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world)
        Self.invoice(world, charging: Money(dollars: 300), sent: false)
        try world.context.save()

        let presenter = Self.present(try world.read(invoice))

        #expect(!presenter.money.contains { $0.offersHeld != nil || $0.isSentence })
    }
}
