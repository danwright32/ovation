import Foundation
import SwiftData
import Testing

/// ovation#510, PRD 51m and 51n. What the invoice screen offers and draws once an
/// invoice has been sent: the foot's action, what the payment sheet starts with,
/// and the payment lines under the Total.
///
/// THE ROWS ARE ASSERTED WHOLE, label and figure in order, because the design's
/// rules are about the relationship between rows: Outstanding carries the weight
/// only where it is drawn (PRD 14m), and a payment sits below the Total and never
/// inside it (14k). A check on one row at a time would pass a block in the wrong
/// order.
@MainActor
struct InvoicePaymentPresenterTests {

    /// 2026-11-12 12:00 in New York, so nothing depends on when the suite runs.
    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    /// 1.5 hours at $250 for a taxed client: 375.00, tax 33.28, total 408.28.
    private static func invoice(_ context: ModelContext, sent: Bool = true) -> Invoice {
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        client.email = "booker@example.com"
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        context.insert(invoice)
        invoice.add(LineItem.flat(Money(dollars: 375), describedAs: "Photography"))
        if sent { invoice.sentStatus = .sent(route: .ovationSentIt, at: noon) }
        return invoice
    }

    /// A payment against the invoice, allocated as the recorder does.
    @discardableResult
    private static func pay(_ invoice: Invoice, _ amount: Money, by method: PaymentMethod,
                            in context: ModelContext) -> Payment {
        let payment = Payment(client: invoice.client, amount: amount, method: method,
                              receivedOn: today)
        context.insert(payment)
        context.insert(PaymentAllocation(payment: payment, invoice: invoice,
                                         amount: amount, allocatedOn: today))
        return payment
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

    // MARK: the foot

    @Test("a draft's foot offers Review, and no payment")
    func adraftOffersReview() throws {
        let context = try Self.store()
        let presenter = Self.present(Self.invoice(context, sent: false))
        #expect(presenter.footAction == .review)
        #expect(presenter.paymentStarts == nil)
    }

    @Test("a sent invoice that is owed offers Record a payment, starting at what is owed, today and Zelle")
    func asentInvoiceOffersAPayment() throws {
        let context = try Self.store()
        let presenter = Self.present(Self.invoice(context))
        #expect(presenter.footAction == .recordPayment)
        let starts = try #require(presenter.paymentStarts)
        #expect(starts.amount == "408.28")
        #expect(starts.received.dayKey == Self.today.dayKey)
        #expect(starts.method == .zelle)
        #expect(Self.fromTheTotal(presenter) == ["Total|408.28|heavy"],
                "nothing paid draws nothing below the Total")
    }

    @Test("a paid invoice's foot says Paid in full and offers no payment")
    func apaidInvoiceSaysSo() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        Self.pay(invoice, Money(cents: 40_828), by: .zelle, in: context)
        let presenter = Self.present(invoice)
        #expect(presenter.footAction == .paidInFull)
        #expect(presenter.paymentStarts == nil)
        #expect(Self.fromTheTotal(presenter) == ["Total|408.28|heavy"],
                "a Zelle payment in full needs nothing said under the Total")
    }

    /// A comped invoice totals nothing (PRD 5.1b) and nobody paid it, so the foot
    /// makes no claim that it was paid (L11), and there is nothing to record.
    @Test("a sent invoice that totals nothing and took no payment says neither Paid in full nor offers a payment")
    func acompedInvoiceClaimsNothing() throws {
        let context = try Self.store()
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: Self.today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        context.insert(invoice)
        invoice.add(LineItem.flat(.zero, describedAs: "Photography"))
        invoice.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)
        let presenter = Self.present(invoice)
        #expect(presenter.footAction == .none)
        #expect(presenter.paymentStarts == nil)
    }

    @Test("a cancelled invoice offers neither Review nor a payment")
    func acancelledInvoiceOffersNothing() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        invoice.closure = .cancelled(on: Self.today, reason: "the concert moved")
        let presenter = Self.present(invoice)
        #expect(presenter.footAction == .none)
        #expect(presenter.paymentStarts == nil)
    }

    // MARK: the lines under the Total

    @Test("a part payment is a line under the Total, and Outstanding beneath it carries the weight")
    func apartPayment() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        Self.pay(invoice, Money(dollars: 200), by: .zelle, in: context)
        let presenter = Self.present(invoice)
        #expect(Self.fromTheTotal(presenter) == [
            "Total|408.28|plain",
            "Paid 12 Nov by Zelle|-200.00|plain",
            "Outstanding|208.28|heavy",
        ])
        #expect(presenter.paymentStarts?.amount == "208.28", "the sheet starts at what is still owed")
    }

    @Test("a part payment by a check that has not cleared says so, beside Mark cleared")
    func apartPaymentByCheck() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let check = Self.pay(invoice, Money(dollars: 200), by: .check, in: context)
        try context.save()
        let presenter = Self.present(invoice)
        #expect(Self.fromTheTotal(presenter) == [
            "Total|408.28|plain",
            "Check, not cleared|-200.00|plain",
            "Outstanding|208.28|heavy",
        ])
        let row = try #require(presenter.money.first { $0.label == "Check, not cleared" })
        #expect(row.clears == check.persistentModelID, "Mark cleared on this line clears this check")
    }

    @Test("a cleared check reads as paid, with the day it arrived and no Mark cleared")
    func aclearedCheck() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let check = Self.pay(invoice, Money(dollars: 200), by: .check, in: context)
        check.markCleared(on: Self.today)
        let presenter = Self.present(invoice)
        let row = try #require(presenter.money.first { $0.label == "Paid 12 Nov by check" })
        #expect(row.clears == nil)
    }

    @Test("a check paying the whole invoice that has not cleared is a quiet line under the Total")
    func achequeInFullWaiting() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let check = Self.pay(invoice, Money(cents: 40_828), by: .check, in: context)
        try context.save()
        let presenter = Self.present(invoice)
        #expect(presenter.footAction == .paidInFull)
        #expect(Self.fromTheTotal(presenter) == ["Total|408.28|heavy", "Check, not cleared||plain"])
        let row = try #require(presenter.money.last)
        #expect(row.isQuiet)
        #expect(row.clears == check.persistentModelID)
    }

    @Test("two payments are two lines, in the order the money arrived, each with its own identity")
    func twoPayments() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        Self.pay(invoice, Money(dollars: 100), by: .check, in: context)
        Self.pay(invoice, Money(dollars: 100), by: .venmo, in: context)
        try context.save()
        let presenter = Self.present(invoice)
        let paid = presenter.money.filter { $0.value.hasPrefix("-") }
        #expect(paid.count == 2)
        #expect(Set(presenter.money.map(\.id)).count == presenter.money.count,
                "no two rows share an identity, so the screen draws each one")
    }
}
