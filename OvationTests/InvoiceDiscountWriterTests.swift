import Foundation
import SwiftData
import Testing

/// ovation#457, PRD 5.4a. Putting a discount on an invoice and taking it off.
///
/// IT VALIDATES NOTHING ITSELF. `Discount`'s two initialisers are the only ways
/// one is made and they already refuse a negative amount and a share outside
/// nothing to everything, so this takes a `Discount` that has been through them.
/// A second set of refusals here would be two rules for one question, and the
/// day one moved the other would not (L370, L263).
///
/// IT IS A WRITER OF MONEY AGAINST AN INVOICE, so it takes the store's
/// `MoneyWriteGate` like the others: a discount changes the invoice's total, and
/// `PaymentAllocator` refuses an allocation larger than what is outstanding,
/// which is derived from that total (ovation#175, L157).
@MainActor
struct InvoiceDiscountWriterTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    private static func draft() throws -> (ModelContainer, PersistentIdentifier) {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: BusinessCalendar.day(forKey: "2026-11-12"),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        invoice.add(LineItem.flat(Money(dollars: 400), describedAs: "Photography"))
        context.insert(invoice)
        try context.save()
        return (container, invoice.persistentModelID)
    }

    private static func read(_ id: PersistentIdentifier,
                             in container: ModelContainer) throws -> Invoice {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == id })
    }

    // MARK: the discount lands

    /// TEN PERCENT IS WHAT THE MENU OFFERS, because it is the commonest of the
    /// five discounts in the whole history (the design record's round 5).
    @Test("a share is recorded as the share it is")
    func ashareIsRecorded() async throws {
        let (container, invoiceID) = try Self.draft()
        let tenth = try #require(Discount(percentBasisPoints: 1_000))

        try await InvoiceDiscountWriter(modelContainer: container)
            .setDiscount(tenth, on: invoiceID)

        let invoice = try Self.read(invoiceID, in: container)
        #expect(invoice.discount?.percentBasisPoints == 1_000)
        #expect(invoice.discountAmount == Money(dollars: 40))
    }

    @Test("an amount is recorded as an amount, with no share to report")
    func anamountIsRecorded() async throws {
        let (container, invoiceID) = try Self.draft()
        let fifty = try #require(Discount(dollars: Money(dollars: 50)))

        try await InvoiceDiscountWriter(modelContainer: container)
            .setDiscount(fifty, on: invoiceID)

        let invoice = try Self.read(invoiceID, in: container)
        #expect(invoice.discount?.percentBasisPoints == nil)
        #expect(invoice.discountAmount == Money(dollars: 50))
    }

    /// NOTHING IS HOW A DISCOUNT IS REMOVED, which is the same write rather than
    /// a second one: the invoice's discount is a value it has or has not got,
    /// and two operations over one field would be two ways to reach one state.
    @Test("nothing takes the discount off")
    func nothingTakesItOff() async throws {
        let (container, invoiceID) = try Self.draft()
        let writer = InvoiceDiscountWriter(modelContainer: container)
        try await writer.setDiscount(Discount(percentBasisPoints: 1_000), on: invoiceID)

        try await writer.setDiscount(nil, on: invoiceID)

        #expect(try Self.read(invoiceID, in: container).discount == nil)
    }

    /// A DISCOUNT OF EVERYTHING IS LEGITIMATE. PRD 5.1b records that a comped
    /// shoot is occasionally invoiced at zero for a corporate client's accounts
    /// payable and that no guard may refuse that invoice, and `Discount` allows
    /// a hundred percent for exactly that reason.
    @Test("a discount of the whole subtotal is written, not refused")
    func awholeSubtotalDiscountIsWritten() async throws {
        let (container, invoiceID) = try Self.draft()

        try await InvoiceDiscountWriter(modelContainer: container)
            .setDiscount(Discount(percentBasisPoints: 10_000), on: invoiceID)

        let invoice = try Self.read(invoiceID, in: container)
        #expect(invoice.taxableAmount == .zero)
        #expect(invoice.total == .zero)
    }

    // MARK: what cannot be written

    @Test("a sent invoice keeps the discount it was sent with")
    func asentInvoiceIsRefused() async throws {
        let (container, invoiceID) = try Self.draft()
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == invoiceID })
        invoice.number = 1_123
        invoice.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)
        try context.save()

        await #expect(throws: InvoiceDiscountRefusal.invoiceWasSent) {
            try await InvoiceDiscountWriter(modelContainer: container)
                .setDiscount(Discount(percentBasisPoints: 1_000), on: invoiceID)
        }
        #expect(try Self.read(invoiceID, in: container).discount == nil)
    }

    @Test("a send that has not settled refuses the change by its own name")
    func anunsettledSendIsRefused() async throws {
        let (container, invoiceID) = try Self.draft()
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == invoiceID })
        invoice.sentStatus = .couldNotDetermine(checkedAt: Self.noon)
        try context.save()

        await #expect(throws: InvoiceDiscountRefusal.sendIsUnsettled) {
            try await InvoiceDiscountWriter(modelContainer: container)
                .setDiscount(nil, on: invoiceID)
        }
    }

    @Test("an invoice that is no longer there is refused by name")
    func agoneInvoiceIsRefused() async throws {
        let (container, invoiceID) = try Self.draft()
        let context = ModelContext(container)
        for each in try context.fetch(FetchDescriptor<Invoice>()) { context.delete(each) }
        try context.save()

        await #expect(throws: InvoiceDiscountRefusal.noSuchInvoice) {
            try await InvoiceDiscountWriter(modelContainer: container)
                .setDiscount(Discount(percentBasisPoints: 1_000), on: invoiceID)
        }
    }

    @Test("every refusal carries a sentence, and none of them is empty")
    func everyrefusalSaysSomething() {
        for refusal in InvoiceDiscountRefusal.allCases {
            #expect(refusal.sentence.isEmpty == false)
            #expect(refusal.sentence.hasSuffix("."))
        }
    }

    /// THE EXCLUSION IS REAL OR IT IS DECORATION (L1), and the wait is on the
    /// gate's own count rather than a duration (L290), ending on either outcome
    /// so a writer that stops taking the gate fails with a sentence rather than
    /// spinning (L511).
    @Test("a discount waits while something else is writing money")
    func adiscountWaitsForTheGate() async throws {
        let (container, invoiceID) = try Self.draft()
        let gate = MoneyWriteGates.gate(for: container)
        await gate.lock()

        let writing = Task {
            try await InvoiceDiscountWriter(modelContainer: container)
                .setDiscount(Discount(percentBasisPoints: 1_000), on: invoiceID)
        }
        var queued = false
        for _ in 0 ..< 10_000 {
            if gate.waiting > 0 { queued = true; break }
            if try Self.read(invoiceID, in: container).discount != nil { break }
            await Task.yield()
        }

        #expect(queued, "the discount writer never queued on the money gate")
        #expect(try Self.read(invoiceID, in: container).discount == nil,
                "the discount was written while the gate was held")

        gate.unlock()
        try await writing.value

        #expect(try Self.read(invoiceID, in: container).discount != nil)
    }
}
