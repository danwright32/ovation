import Foundation
import SwiftData
import Testing
@testable import Ovation

/// ovation#60 step 3b. A payment is its own record, allocated across invoices,
/// and the sum of what is allocated may never exceed what actually arrived.
struct PaymentTests {

    /// 2026-11-12 20:00 America/New_York.
    private static let day = Date(timeIntervalSince1970: 1_794_531_600)

    private static func store() throws -> ModelContainer {
        try OvationSchema.container(inMemory: true)
    }

    private static func client(_ context: ModelContext) -> Client {
        let client = Client(name: "A company", taxStatus: .notExempt)
        context.insert(client)
        return client
    }

    private static func invoice(_ context: ModelContext, for client: Client) -> Invoice {
        let invoice = Invoice(client: client, kind: .fromABooking,
                              invoiceDate: .stamping(day),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        context.insert(invoice)
        return invoice
    }

    private static func payment(
        _ context: ModelContext, for client: Client,
        _ amount: Money, method: PaymentMethod = .zelle
    ) -> Payment {
        let payment = Payment(client: client, amount: amount, method: method,
                              receivedOn: .stamping(day))
        context.insert(payment)
        return payment
    }

    // MARK: what a payment is

    @Test("a payment records the amount actually written, not a share of one invoice")
    func aPaymentIsItsOwnRecord() throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let payment = Self.payment(context, for: Self.client(context), Money(dollars: 500))
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Payment>()).first)
        #expect(read.amount == Money(dollars: 500))
        #expect(read.unallocated == Money(dollars: 500), "none of it is spoken for yet")
        #expect(read.allocated == Money.zero)
    }

    @Test("a check gains a cleared step and nothing else does")
    func onlyAChequeCanBeCleared() throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let cheque = Self.payment(context, for: client, Money(dollars: 500), method: .check)
        let zelle = Self.payment(context, for: client, Money(dollars: 500), method: .zelle)

        #expect(cheque.canBeCleared)
        #expect(!zelle.canBeCleared)
        #expect(cheque.markCleared(on: .stamping(Self.day)))
        #expect(!zelle.markCleared(on: .stamping(Self.day)), "a Zelle payment has nothing to clear")
        #expect(cheque.clearedOn != nil)
        #expect(zelle.clearedOn == nil)
    }

    // MARK: allocation, and the ceiling it can never cross

    @Test("one payment can settle two invoices, split between them")
    func onePaymentSettlesTwoInvoices() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let first = Self.invoice(context, for: client)
        let second = Self.invoice(context, for: client)
        let payment = Self.payment(context, for: client, Money(dollars: 500))
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        try await allocator.allocate(Money(dollars: 300),
                                     from: payment.persistentModelID,
                                     to: first.persistentModelID, on: .stamping(Self.day))
        try await allocator.allocate(Money(dollars: 200),
                                     from: payment.persistentModelID,
                                     to: second.persistentModelID, on: .stamping(Self.day))

        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Payment>()).first)
        #expect(read.allocated == Money(dollars: 500))
        #expect(read.unallocated == Money.zero)
        #expect(read.activeAllocations.count == 2)
    }

    @Test("an allocation that would take more than arrived is refused by name")
    func overAllocationIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client)
        let payment = Self.payment(context, for: client, Money(dollars: 100))
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        try await allocator.allocate(Money(dollars: 60), from: payment.persistentModelID,
                                     to: invoice.persistentModelID, on: .stamping(Self.day))
        await #expect(throws: AllocationRefusal.wouldTakeMoreThanArrived(
            unallocated: Money(dollars: 40), asked: Money(dollars: 60))) {
            try await allocator.allocate(Money(dollars: 60), from: payment.persistentModelID,
                                         to: invoice.persistentModelID, on: .stamping(Self.day))
        }

        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Payment>()).first)
        #expect(read.allocated == Money(dollars: 60), "the refused one wrote nothing at all")
    }

    @Test("an allocation of nothing or less is refused, because it records no decision")
    func anEmptyAllocationIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client)
        let payment = Self.payment(context, for: client, Money(dollars: 100))
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        await #expect(throws: AllocationRefusal.self) {
            try await allocator.allocate(Money.zero, from: payment.persistentModelID,
                                         to: invoice.persistentModelID, on: .stamping(Self.day))
        }
    }

    /// L157: two callers held at the decision point at once, rather than hoping an
    /// interleaving reproduces. Both ask for more than half of what arrived, so
    /// exactly one of them can be right whatever order they run in.
    @Test("two allocations racing for the same money cannot both fit")
    func twoAllocationsCannotBothFit() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let first = Self.invoice(context, for: client)
        let second = Self.invoice(context, for: client)
        let payment = Self.payment(context, for: client, Money(dollars: 100))
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        let paymentID = payment.persistentModelID
        let firstID = first.persistentModelID
        let secondID = second.persistentModelID

        let day = BusinessDate.stamping(Self.day)
        // The outcome is the REFUSAL itself, not merely that something threw. A
        // test satisfied by any error is satisfied by its own fixture failing
        // (L140), and here that would read as the invariant holding.
        let refusals = await withTaskGroup(of: AllocationRefusal?.self) { group in
            for invoiceID in [firstID, secondID] {
                group.addTask {
                    do {
                        try await allocator.allocate(Money(dollars: 60), from: paymentID,
                                                     to: invoiceID, on: day)
                        return nil
                    } catch let refusal as AllocationRefusal {
                        return refusal
                    } catch {
                        Issue.record("an allocation failed for a reason that is not a refusal")
                        return nil
                    }
                }
            }
            var found: [AllocationRefusal] = []
            for await outcome in group { if let outcome { found.append(outcome) } }
            return found
        }

        #expect(refusals.count == 1, "one of them was told there was not enough left")
        #expect(refusals.first == .wouldTakeMoreThanArrived(unallocated: Money(dollars: 40),
                                                            asked: Money(dollars: 60)),
                "and it was told how much was actually left, so it can offer that instead")
        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Payment>()).first)
        #expect(read.allocated == Money(dollars: 60))
        #expect(read.allocated <= read.amount, "the sum never exceeded what arrived")
    }

    // MARK: releasing, which is not deleting

    @Test("releasing an allocation returns the money to unallocated and keeps the record")
    func releasingKeepsTheRecord() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client)
        let payment = Self.payment(context, for: client, Money(dollars: 100))
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        try await allocator.allocate(Money(dollars: 100), from: payment.persistentModelID,
                                     to: invoice.persistentModelID, on: .stamping(Self.day))
        try await allocator.releaseAllAllocations(of: invoice.persistentModelID,
                                                  on: .stamping(Self.day))

        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Payment>()).first)
        #expect(read.unallocated == Money(dollars: 100), "the money still arrived and is free again")
        #expect(read.allocated == Money.zero)
        #expect(read.activeAllocations.isEmpty)
        #expect(try reader.fetch(FetchDescriptor<PaymentAllocation>()).count == 1,
                "the allocation was released, not deleted, so what happened is still readable")
    }

    @Test("released money can be allocated again, which is what cancelling leaves behind")
    func releasedMoneyCanBeUsedAgain() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let cancelled = Self.invoice(context, for: client)
        let other = Self.invoice(context, for: client)
        let payment = Self.payment(context, for: client, Money(dollars: 100))
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        try await allocator.allocate(Money(dollars: 100), from: payment.persistentModelID,
                                     to: cancelled.persistentModelID, on: .stamping(Self.day))
        try await allocator.releaseAllAllocations(of: cancelled.persistentModelID,
                                                  on: .stamping(Self.day))
        try await allocator.allocate(Money(dollars: 100), from: payment.persistentModelID,
                                     to: other.persistentModelID, on: .stamping(Self.day))

        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Payment>()).first)
        #expect(read.allocated == Money(dollars: 100))
        #expect(read.activeAllocations.count == 1)
    }

    // MARK: what an invoice says about itself once money is on it

    @Test("an invoice is paid from what is ALLOCATED to it, never from a typed flag")
    func anInvoiceIsPaidFromItsAllocations() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client)
        invoice.add(LineItem.flat(Money(dollars: 1_000), describedAs: "Photography"))
        let payment = Self.payment(context, for: client, Money(dollars: 1_088))
        try context.save()
        // $1,000 plus 8.875% is $1,088.75.
        #expect(invoice.total == Money(cents: 108_875))

        let allocator = PaymentAllocator(modelContainer: container)
        #expect(invoice.amountPaid == Money.zero)
        #expect(invoice.paymentState == .unpaid)

        try await allocator.allocate(Money(dollars: 500), from: payment.persistentModelID,
                                     to: invoice.persistentModelID, on: .stamping(Self.day))
        let reader = ModelContext(container)
        let partly = try #require(try reader.fetch(FetchDescriptor<Invoice>())
            .first { $0.id == invoice.id })
        #expect(partly.amountPaid == Money(dollars: 500))
        #expect(partly.paymentState == .partlyPaid)
        #expect(partly.amountOutstanding == Money(cents: 58_875))
    }

    @Test("a released allocation stops counting towards the invoice, which is what cancelling means")
    func aReleasedAllocationStopsCountingOnTheInvoice() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client)
        invoice.add(LineItem.flat(Money(dollars: 1_000), describedAs: "Photography"))
        let payment = Self.payment(context, for: client, Money(dollars: 1_100))
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        try await allocator.allocate(Money(cents: 108_875), from: payment.persistentModelID,
                                     to: invoice.persistentModelID, on: .stamping(Self.day))

        let afterPaying = try #require(try ModelContext(container)
            .fetch(FetchDescriptor<Invoice>()).first { $0.id == invoice.id })
        #expect(afterPaying.paymentState == .paid)

        try await allocator.releaseAllAllocations(of: invoice.persistentModelID,
                                                  on: .stamping(Self.day))

        let afterReleasing = try #require(try ModelContext(container)
            .fetch(FetchDescriptor<Invoice>()).first { $0.id == invoice.id })
        #expect(afterReleasing.amountPaid == Money.zero,
                "the released allocation no longer settles anything")
        #expect(afterReleasing.paymentState == .unpaid)
        #expect(afterReleasing.amountOutstanding == afterReleasing.total)
    }

    @Test("an invoice that totals nothing has nothing outstanding, so it is paid the moment it exists")
    func aZeroInvoiceIsPaid() throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, for: Self.client(context))
        #expect(invoice.total == Money.zero)
        #expect(invoice.paymentState == .paid, "PRD 5.1b makes a zero total legitimate")
        #expect(invoice.amountOutstanding == Money.zero)
    }

    @Test("money held on a client is what arrived minus what is spoken for, derived and never stored")
    func moneyHeldOnAClientIsDerived() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client)
        let settled = Self.payment(context, for: client, Money(dollars: 300))
        _ = Self.payment(context, for: client, Money(dollars: 200))
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        try await allocator.allocate(Money(dollars: 300), from: settled.persistentModelID,
                                     to: invoice.persistentModelID, on: .stamping(Self.day))

        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Client>()).first)
        #expect(read.moneyHeld == Money(dollars: 200),
                "a deposit taken before the shoot sits here, and it is not an error")
    }

    // MARK: a refund, which has its own date

    @Test("a refund records what went back and when, against the invoice it came off")
    func aRefundCarriesItsOwnDate() throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client)
        let payment = Self.payment(context, for: client, Money(dollars: 500))
        let refund = Refund(invoice: invoice, payment: payment, amount: Money(dollars: 500),
                            refundedOn: .stamping(Self.day), method: .zelle)
        context.insert(refund)
        try context.save()

        let read = try #require(try ModelContext(container)
            .fetch(FetchDescriptor<Refund>()).first)
        #expect(read.amount == Money(dollars: 500))
        #expect(read.refundedOn.dayKey == BusinessCalendar.dayKey(for: Self.day))
        #expect(read.invoice?.id == invoice.id)
    }
}
