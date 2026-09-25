import Foundation
import SwiftData
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#510. The invoice screen's payment controls, pressed the way Dan presses
/// them: the foot, the sheet's Record, and Mark cleared, each asserted by what it
/// hands back rather than by what it draws alone (L442).
@MainActor
struct InvoicePaymentViewTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    /// A sent invoice owing 408.28, numbered 1123, and the context holding it.
    private static func sent(_ context: ModelContext) -> Invoice {
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        client.email = "booker@example.com"
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        context.insert(invoice)
        invoice.add(LineItem.flat(Money(dollars: 375), describedAs: "Photography"))
        invoice.number = 1_123
        invoice.sentStatus = .sent(route: .ovationSentIt, at: noon)
        return invoice
    }

    private static func context() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    private static func present(_ invoice: Invoice) -> InvoiceScreenPresenter {
        InvoiceScreenPresenter(invoice: invoice, footer: .fixed, today: today)
    }

    /// Controls that record what they were asked to do.
    private final class Asked {
        var opened = 0
        var recorded: [PaymentEntry] = []
        var cleared: [PersistentIdentifier] = []
        func controls(isOpen: Bool = false, refused: String? = nil)
            -> InvoiceScreenView.PaymentControls {
            InvoiceScreenView.PaymentControls(
                isOpen: isOpen, refused: refused,
                open: { self.opened += 1 },
                record: { self.recorded.append($0) },
                close: {},
                markCleared: { self.cleared.append($0) })
        }
    }

    private static func text(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    private static func button(_ words: String, in view: some View) throws -> InspectableView<ViewType.Button> {
        try view.inspect().find(ViewType.Button.self, where: { button in
            (try? button.labelView().text().string()) == words
        })
    }

    @Test("a sent invoice's foot offers Record a payment, and pressing it opens the sheet")
    func thefootOpensTheSheet() throws {
        let asked = Asked()
        let view = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context())),
                                     close: {}, payment: asked.controls())
        #expect(try Self.text(in: view).contains("Record a payment"))
        #expect(!(try Self.text(in: view).contains("Review")), "a sent invoice offers no Review")
        try Self.button("Record a payment", in: view).tap()
        #expect(asked.opened == 1)
    }

    @Test("a paid invoice's foot says Paid in full and offers no payment")
    func apaidFoot() throws {
        let context = try Self.context()
        let invoice = Self.sent(context)
        let payment = Payment(client: invoice.client, amount: Money(cents: 40_828),
                              method: .zelle, receivedOn: Self.today)
        context.insert(payment)
        context.insert(PaymentAllocation(payment: payment, invoice: invoice,
                                         amount: Money(cents: 40_828), allocatedOn: Self.today))
        let view = InvoiceScreenView(presenter: Self.present(invoice), close: {},
                                     payment: Asked().controls())
        let drawn = try Self.text(in: view)
        #expect(drawn.contains("Paid in full"))
        #expect(!drawn.contains("Record a payment"))
    }

    @Test("Record in the open sheet hands back what the sheet opened with: what is owed, today and Zelle")
    func recordHandsBackTheStart() throws {
        let asked = Asked()
        let view = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context())),
                                     close: {}, payment: asked.controls(isOpen: true))
        #expect(try Self.text(in: view).contains("Record a payment on invoice 1123"))
        try Self.button("Record", in: view).tap()
        let entry = try #require(asked.recorded.first)
        #expect(asked.recorded.count == 1)
        #expect(entry.amount == Money(cents: 40_828))
        #expect(entry.method == .zelle)
        #expect(entry.received.dayKey == Self.today.dayKey)
    }

    @Test("a refused payment is said in the sheet, in the recorder's own words")
    func arefusalIsSaid() throws {
        let refusal = PaymentRecordingRefusal.nothingIsOwed.sentence
        let view = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context())),
                                     close: {},
                                     payment: Asked().controls(isOpen: true, refused: refusal))
        #expect(try Self.text(in: view).contains(refusal))
    }

    /// A refusal answers the press it came from, so an edit to the form tells the
    /// host, which clears it (L680). Hosted, because an edit is a change to the
    /// sheet's own state and only a hosted view runs what that change triggers.
    @Test("editing the amount tells the host, so a stale refusal can be cleared")
    func anEditTellsTheHost() async throws {
        final class Count { var edits = 0 }
        let count = Count()
        let starts = InvoiceScreenPresenter.PaymentStart(amount: "408.28", received: Self.today,
                                                         method: .zelle, number: "1123")
        let sheet = PaymentSheet(number: "1123", starts: starts,
                                 refused: PaymentRecordingRefusal.nothingIsOwed.sentence,
                                 isRecording: false, record: { _ in }, close: {},
                                 edited: { count.edits += 1 })
        ViewHosting.host(view: sheet)
        defer { ViewHosting.expel() }
        try await sheet.inspection.inspect { view in
            try view.find(ViewType.TextField.self).setInput("200")
        }
        for _ in 0..<200 where count.edits == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(count.edits >= 1)
    }

    @Test("Mark cleared on a check that has not cleared hands back that check")
    func markClearedHandsBackTheCheck() throws {
        let context = try Self.context()
        let invoice = Self.sent(context)
        let check = Payment(client: invoice.client, amount: Money(dollars: 200),
                            method: .check, receivedOn: Self.today)
        context.insert(check)
        context.insert(PaymentAllocation(payment: check, invoice: invoice,
                                         amount: Money(dollars: 200), allocatedOn: Self.today))
        try context.save()
        let asked = Asked()
        let view = InvoiceScreenView(presenter: Self.present(invoice), close: {},
                                     payment: asked.controls())
        #expect(try Self.text(in: view).contains("Check, not cleared"))
        try Self.button("Mark cleared", in: view).tap()
        #expect(asked.cleared == [check.persistentModelID])
    }

    @Test("with nowhere to record a payment, no Mark cleared is offered")
    func nowritePathOffersNoClearing() throws {
        let context = try Self.context()
        let invoice = Self.sent(context)
        let check = Payment(client: invoice.client, amount: Money(dollars: 200),
                            method: .check, receivedOn: Self.today)
        context.insert(check)
        context.insert(PaymentAllocation(payment: check, invoice: invoice,
                                         amount: Money(dollars: 200), allocatedOn: Self.today))
        let view = InvoiceScreenView(presenter: Self.present(invoice), close: {})
        #expect(throws: (any Error).self) { try Self.button("Mark cleared", in: view) }
    }
}
