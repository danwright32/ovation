import Foundation
import SwiftData
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#185, PRD 14h to 14k. The held money lines under the Total, pressed the
/// way Dan presses them: `Remove` on the applied line and `Use it here` on the
/// offer, each asserted by what it hands back rather than by what it draws alone
/// (L442).
@MainActor
struct HeldMoneyViewTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    private struct World {
        let container: ModelContainer
        let context: ModelContext
        let invoice: Invoice

        @MainActor
        func present() throws -> InvoiceScreenPresenter {
            let read = try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
                .first { $0.id == invoice.id })
            return InvoiceScreenPresenter(invoice: read, footer: .fixed, today: today)
        }
    }

    /// A sent invoice for 408.28, its client holding `holding`, and `alsoOpen`
    /// more drafts of theirs open beside it.
    private static func world(holding: Money, alsoOpen: Int = 0) throws -> World {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        client.email = "booker@example.com"
        context.insert(client)
        func make(sent: Bool) -> Invoice {
            let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                                  hourlyRate: Money(dollars: 250), taxRate: .newYorkCity,
                                  createdOn: today)
            context.insert(invoice)
            invoice.add(LineItem.flat(Money(dollars: 375), describedAs: "Photography"))
            if sent { invoice.sentStatus = .sent(route: .ovationSentIt, at: noon) }
            return invoice
        }
        let invoice = make(sent: true)
        for _ in 0..<alsoOpen { _ = make(sent: false) }
        context.insert(Payment(client: client, amount: holding, method: .zelle, receivedOn: today))
        try context.save()
        return World(container: container, context: context, invoice: invoice)
    }

    /// Controls that record what they were asked to do.
    private final class Asked {
        var applied: [PersistentIdentifier] = []
        var removed: [PersistentIdentifier] = []
        func controls(refused: String? = nil) -> InvoiceScreenView.HeldMoneyControls {
            InvoiceScreenView.HeldMoneyControls(
                refused: refused,
                apply: { self.applied.append($0) },
                remove: { self.removed.append($0) })
        }
    }

    private static func text(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    private static func button(_ words: String, in view: some View) throws
        -> InspectableView<ViewType.Button> {
        try view.inspect().find(ViewType.Button.self, where: { button in
            (try? button.labelView().text().string()) == words
        })
    }

    @Test("the applied line carries Remove, and pressing it hands back this invoice")
    func removeHandsBackTheInvoice() async throws {
        let world = try Self.world(holding: Money(dollars: 500))
        try await PaymentAllocator(modelContainer: world.container).placeHeldMoney(on: Self.today)
        let asked = Asked()
        let view = InvoiceScreenView(presenter: try world.present(), close: {},
                                     heldMoney: asked.controls())

        let drawn = try Self.text(in: view)
        #expect(drawn.contains("Held money applied"))
        #expect(drawn.contains("-408.28"))
        #expect(drawn.contains("Outstanding"))
        #expect(drawn.contains("$91.72 stays held on the client."))
        try Self.button("Remove", in: view).tap()
        #expect(asked.removed == [world.invoice.persistentModelID])
        #expect(asked.applied.isEmpty)
    }

    @Test("with two open invoices the offer says why, and Use it here hands back this invoice")
    func useItHereHandsBackTheInvoice() throws {
        let world = try Self.world(holding: Money(dollars: 500), alsoOpen: 1)
        let asked = Asked()
        let view = InvoiceScreenView(presenter: try world.present(), close: {},
                                     heldMoney: asked.controls())

        let drawn = try Self.text(in: view)
        #expect(drawn.contains("Cedar Hill Youth Orchestra is holding"))
        #expect(drawn.contains("$500.00"))
        #expect(drawn.contains("2 invoices are open for this client, so it was not put on either."))
        try Self.button("Use it here", in: view).tap()
        #expect(asked.applied == [world.invoice.persistentModelID])
        #expect(asked.removed.isEmpty)
    }

    @Test("with nowhere to write, the lines are said and neither word is offered")
    func nowritePathOffersNoControl() async throws {
        let applied = try Self.world(holding: Money(dollars: 500))
        try await PaymentAllocator(modelContainer: applied.container).placeHeldMoney(on: Self.today)
        let offered = try Self.world(holding: Money(dollars: 500), alsoOpen: 1)

        let one = InvoiceScreenView(presenter: try applied.present(), close: {})
        let two = InvoiceScreenView(presenter: try offered.present(), close: {})

        #expect(try Self.text(in: one).contains("Held money applied"))
        #expect(throws: (any Error).self) { try Self.button("Remove", in: one) }
        #expect(try Self.text(in: two).contains("Cedar Hill Youth Orchestra is holding"))
        #expect(throws: (any Error).self) { try Self.button("Use it here", in: two) }
    }

    @Test("a refused press is said, in the allocator's own words")
    func arefusalIsSaid() throws {
        let world = try Self.world(holding: Money(dollars: 500), alsoOpen: 1)
        let refusal = HeldMoneyRefusal.clientHoldsNothing.sentence
        let view = InvoiceScreenView(presenter: try world.present(), close: {},
                                     heldMoney: Asked().controls(refused: refusal))
        #expect(try Self.text(in: view).contains(refusal))
    }
}
