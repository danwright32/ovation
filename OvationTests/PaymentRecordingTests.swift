import Foundation
import SwiftData
import Testing

/// ovation#510. Recording a payment on a sent invoice, and clearing a check.
///
/// A PAYMENT AND ITS ALLOCATION ARE ONE WRITE. Recorded as two, a failure between
/// them would leave money arrived and pointed at nothing, which reads on the
/// Clients screen as money held that Dan never meant to hold (PRD 14a). So every
/// case below reads the store back from a fresh context and asserts BOTH sides.
struct PaymentRecordingTests {

    /// 2026-09-26 12:00 America/New_York.
    private static let day = Date(timeIntervalSince1970: 1_790_438_400)

    private static func store() throws -> ModelContainer {
        try OvationSchema.container(inMemory: true)
    }

    /// A sent invoice owing `owing`, or a draft where `sent` is false.
    private static func invoice(
        _ context: ModelContext, owing: Money, sent: Bool = true
    ) -> Invoice {
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .exempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .fromABooking,
                              invoiceDate: .stamping(day),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        context.insert(invoice)
        invoice.add(LineItem.flat(owing, describedAs: "Photography"))
        if sent { invoice.sentStatus = .sent(route: .ovationSentIt, at: day) }
        return invoice
    }

    private static func read(_ container: ModelContainer, _ id: UUID) throws -> Invoice {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.id == id })
    }

    private static func payments(_ container: ModelContainer) throws -> [Payment] {
        try ModelContext(container).fetch(FetchDescriptor<Payment>())
    }

    // MARK: recording

    @Test("a payment in full is recorded with its allocation in one write, and the invoice is paid")
    func aPaymentInFull() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, owing: Money(cents: 40_828))
        try context.save()

        let recorded = try await PaymentAllocator(modelContainer: container)
            .record(Money(cents: 40_828), method: .zelle, receivedOn: .stamping(Self.day),
                    onto: invoice.persistentModelID, press: UUID())

        let read = try Self.read(container, invoice.id)
        #expect(read.paymentState == .paid)
        #expect(read.amountOutstanding == .zero)
        let payment = try #require(try Self.payments(container).only)
        #expect(payment.amount == Money(cents: 40_828))
        #expect(payment.method == .zelle)
        #expect(payment.receivedOn.dayKey == BusinessDate.stamping(Self.day).dayKey)
        #expect(payment.client?.id == read.client?.id, "the money belongs to the invoice's client")
        #expect(payment.allocated == Money(cents: 40_828))
        #expect(recorded.held == .zero)
    }

    @Test("a part payment leaves the rest outstanding")
    func aPartPayment() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, owing: Money(cents: 40_828))
        try context.save()

        try await PaymentAllocator(modelContainer: container)
            .record(Money(dollars: 200), method: .check, receivedOn: .stamping(Self.day),
                    onto: invoice.persistentModelID, press: UUID())

        let read = try Self.read(container, invoice.id)
        #expect(read.paymentState == .partlyPaid)
        #expect(read.amountOutstanding == Money(cents: 20_828))
    }

    @Test("more than is owed is recorded in full, and what the invoice cannot take is held on the client")
    func moreThanIsOwedIsHeld() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, owing: Money(cents: 40_828))
        try context.save()

        let recorded = try await PaymentAllocator(modelContainer: container)
            .record(Money(dollars: 500), method: .check, receivedOn: .stamping(Self.day),
                    onto: invoice.persistentModelID, press: UUID())

        #expect(recorded.held == Money(cents: 9_172))
        let payment = try #require(try Self.payments(container).only)
        #expect(payment.amount == Money(dollars: 500), "the amount actually written, PRD 14")
        #expect(payment.allocated == Money(cents: 40_828))
        #expect(payment.unallocated == Money(cents: 9_172), "held on the client, PRD 14a")
        #expect(try Self.read(container, invoice.id).paymentState == .paid)
    }

    @Test("an amount of nothing or less is refused by name and writes nothing")
    func nothingIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, owing: Money(dollars: 100))
        try context.save()
        let recorder = PaymentAllocator(modelContainer: container)

        for asked in [Money.zero, Money(cents: -500)] {
            await #expect(throws: PaymentRecordingRefusal.amountIsNotPositive(asked: asked)) {
                try await recorder.record(asked, method: .zelle, receivedOn: .stamping(Self.day),
                                          onto: invoice.persistentModelID, press: UUID())
            }
        }
        #expect(try Self.payments(container).isEmpty)
    }

    @Test("a draft takes no payment, because nothing has been sent to be paid")
    func aDraftIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let draft = Self.invoice(context, owing: Money(dollars: 100), sent: false)
        try context.save()

        await #expect(throws: PaymentRecordingRefusal.invoiceIsNotSent) {
            try await PaymentAllocator(modelContainer: container)
                .record(Money(dollars: 100), method: .zelle, receivedOn: .stamping(Self.day),
                        onto: draft.persistentModelID, press: UUID())
        }
        #expect(try Self.payments(container).isEmpty)
    }

    @Test("an invoice already paid in full takes no more, and says so rather than holding it")
    func aPaidInvoiceIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, owing: Money(dollars: 100))
        try context.save()
        let recorder = PaymentAllocator(modelContainer: container)
        try await recorder.record(Money(dollars: 100), method: .zelle,
                                  receivedOn: .stamping(Self.day),
                                  onto: invoice.persistentModelID, press: UUID())

        await #expect(throws: PaymentRecordingRefusal.nothingIsOwed) {
            try await recorder.record(Money(dollars: 20), method: .zelle,
                                      receivedOn: .stamping(Self.day),
                                      onto: invoice.persistentModelID, press: UUID())
        }
        #expect(try Self.payments(container).count == 1)
    }

    @Test("a cancelled invoice takes no payment")
    func aCancelledInvoiceIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, owing: Money(dollars: 100))
        invoice.closure = .cancelled(on: .stamping(Self.day), reason: "the concert moved")
        try context.save()

        await #expect(throws: PaymentRecordingRefusal.invoiceIsClosed) {
            try await PaymentAllocator(modelContainer: container)
                .record(Money(dollars: 100), method: .zelle, receivedOn: .stamping(Self.day),
                        onto: invoice.persistentModelID, press: UUID())
        }
        #expect(try Self.payments(container).isEmpty)
    }

    @Test("the SAME press arriving twice records one payment, however it arrives")
    func onePressIsOnePayment() async throws {
        // Assume it runs twice: a double click, or a retry after a write that
        // looked like it failed. The press carries its own identity, so the
        // second arrival finds the first rather than recording the money again.
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, owing: Money(dollars: 400))
        try context.save()
        let recorder = PaymentAllocator(modelContainer: container)
        let press = UUID()
        let invoiceID = invoice.persistentModelID
        let day = BusinessDate.stamping(Self.day)

        let outcomes = await withTaskGroup(of: RecordedPayment?.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    try? await recorder.record(Money(dollars: 150), method: .zelle,
                                               receivedOn: day, onto: invoiceID, press: press)
                }
            }
            var found: [RecordedPayment] = []
            for await outcome in group { if let outcome { found.append(outcome) } }
            return found
        }

        #expect(outcomes.count == 2, "both arrivals are answered, neither refused")
        #expect(Set(outcomes.map(\.payment)).count == 1, "and both are answered with one payment")
        #expect(try Self.payments(container).count == 1)
        #expect(try Self.read(container, invoice.id).amountOutstanding == Money(dollars: 250))
    }

    @Test("two DIFFERENT presses are two payments, because two checks can arrive")
    func twoPressesAreTwoPayments() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, owing: Money(dollars: 400))
        try context.save()
        let recorder = PaymentAllocator(modelContainer: container)
        for _ in 0..<2 {
            try await recorder.record(Money(dollars: 150), method: .check,
                                      receivedOn: .stamping(Self.day),
                                      onto: invoice.persistentModelID, press: UUID())
        }
        #expect(try Self.payments(container).count == 2)
        #expect(try Self.read(container, invoice.id).amountOutstanding == Money(dollars: 100))
    }

    // MARK: clearing

    @Test("a check waits to clear, and every other method is cleared when it is recorded")
    func onlyACheckWaits() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, owing: Money(dollars: 1_000))
        try context.save()
        let recorder = PaymentAllocator(modelContainer: container)
        for method in PaymentMethod.allCases {
            try await recorder.record(Money(dollars: 100), method: method,
                                      receivedOn: .stamping(Self.day),
                                      onto: invoice.persistentModelID, press: UUID())
        }
        let waiting = try Self.payments(container).filter(\.isWaitingToClear).map(\.method)
        #expect(waiting == [.check])
    }

    @Test("Mark cleared clears a check on the day it is pressed")
    func markingACheckCleared() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, owing: Money(dollars: 100))
        try context.save()
        let recorder = PaymentAllocator(modelContainer: container)
        let recorded = try await recorder.record(Money(dollars: 100), method: .check,
                                                 receivedOn: .stamping(Self.day),
                                                 onto: invoice.persistentModelID, press: UUID())
        let later = BusinessDate.stamping(Self.day.addingTimeInterval(6 * 86_400))

        try await recorder.markCleared(recorded.payment, on: later)

        let payment = try #require(try Self.payments(container).only)
        #expect(!payment.isWaitingToClear)
        #expect(payment.clearedOn?.dayKey == later.dayKey)
    }

    @Test("a payment that has no cleared step is refused by name rather than stamped")
    func clearingAZellePaymentIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, owing: Money(dollars: 100))
        try context.save()
        let recorder = PaymentAllocator(modelContainer: container)
        let recorded = try await recorder.record(Money(dollars: 100), method: .zelle,
                                                 receivedOn: .stamping(Self.day),
                                                 onto: invoice.persistentModelID, press: UUID())

        await #expect(throws: PaymentRecordingRefusal.hasNoClearedStep) {
            try await recorder.markCleared(recorded.payment, on: .stamping(Self.day))
        }
        #expect(try Self.payments(container).only?.clearedOn == nil)
    }
}

private extension Array {
    /// The one element, or nil where there is not exactly one.
    var only: Element? { count == 1 ? first : nil }
}
