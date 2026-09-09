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

    /// `owing` is the flat line the invoice charges, and it is passed EXPLICITLY
    /// by every test that allocates against it (ovation#108). Before that rule
    /// existed these fixtures allocated hundreds of dollars to invoices with no
    /// lines at all, which total nothing and owe nothing, so the tests were
    /// asserting payment side behaviour on exactly the nonsense state ovation#108
    /// exists to refuse. Nil means no lines, which two tests below want on
    /// purpose.
    private static func invoice(
        _ context: ModelContext, for client: Client, owing: Money? = nil
    ) -> Invoice {
        let invoice = Invoice(client: client, kind: .fromABooking,
                              invoiceDate: .stamping(day),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        context.insert(invoice)
        if let owing { invoice.add(LineItem.flat(owing, describedAs: "Photography")) }
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

    @Test("and the cleared date cannot be set any other way, so the rule cannot be skipped")
    func clearedIsOnlyReachableThroughTheRefusal() throws {
        // ovation#48. The check only rule lived in `markCleared`, which every
        // call site had to choose to use, and a rule each caller must opt into is
        // enforced by nothing: the first site to assign the field directly gives
        // a Zelle payment a cleared date nothing can explain (L621, L27).
        //
        // ASSERTED ON THE SOURCE, because the compiler is the enforcement and a
        // test cannot write the line that would fail. Making the setter private
        // found one such assignment on the day it shipped, in ovation#61's own
        // export test, which is what the rule predicts rather than a coincidence.
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Ovation/Domain/Payment.swift"),
            encoding: .utf8)
        #expect(source.contains("private(set) var clearedOn"))
    }

    // MARK: allocation, and the ceiling it can never cross

    @Test("one payment can settle two invoices, split between them")
    func onePaymentSettlesTwoInvoices() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let first = Self.invoice(context, for: client, owing: Money(dollars: 500))
        let second = Self.invoice(context, for: client, owing: Money(dollars: 500))
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
        let invoice = Self.invoice(context, for: client, owing: Money(dollars: 1_000))
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
        let invoice = Self.invoice(context, for: client, owing: Money(dollars: 1_000))
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
        let first = Self.invoice(context, for: client, owing: Money(dollars: 1_000))
        let second = Self.invoice(context, for: client, owing: Money(dollars: 1_000))
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

    @Test("an invoice deleted since the caller read it is REFUSED, not a crash")
    func adeletedInvoiceIsRefusedRatherThanFatal() async throws {
        // Measured while building ovation#37: `self[id, as:]` handed the
        // identifier of a deleted row returns a NON-NIL object that traps the
        // moment any property is read, "this model instance was invalidated
        // because its backing data could no longer be found in the store". That
        // is the process dying rather than a refusal, and a row deleted between a
        // screen reading it and this running is an ordinary race.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client, owing: Money(dollars: 100))
        let payment = Self.payment(context, for: client, Money(dollars: 100))
        try context.save()
        let invoiceID = invoice.persistentModelID
        context.delete(invoice)
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        await #expect(throws: AllocationRefusal.noSuchInvoice) {
            try await allocator.allocate(Money(dollars: 10), from: payment.persistentModelID,
                                         to: invoiceID, on: .stamping(Self.day))
        }
    }

    @Test("a payment deleted since the caller read it is refused too, by its own name")
    func adeletedPaymentIsRefusedRatherThanFatal() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client, owing: Money(dollars: 100))
        let payment = Self.payment(context, for: client, Money(dollars: 100))
        try context.save()
        let paymentID = payment.persistentModelID
        context.delete(payment)
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        await #expect(throws: AllocationRefusal.noSuchPayment) {
            try await allocator.allocate(Money(dollars: 10), from: paymentID,
                                         to: invoice.persistentModelID, on: .stamping(Self.day))
        }
    }

    @Test("releasing against an invoice that is gone is refused rather than fatal")
    func areleaseOnADeletedInvoiceIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client, owing: Money(dollars: 100))
        try context.save()
        let invoiceID = invoice.persistentModelID
        context.delete(invoice)
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        await #expect(throws: AllocationRefusal.noSuchInvoice) {
            try await allocator.releaseAllAllocations(of: invoiceID, on: .stamping(Self.day))
        }
    }

    // MARK: the other ceiling, which is what the invoice actually owes

    @Test("an allocation past what the invoice OWES is refused by name, carrying what is left")
    func overApplicationIsRefused() async throws {
        // ovation#108. The payment side ceiling was enforced from the first
        // version and the invoice side was not, so $5,000 of a $5,000 payment
        // could be applied to a $100 invoice. The invoice then reads `paid` with
        // an outstanding balance of minus $4,900 and the client's held money
        // reads as fully spent. Both numbers are truthful about their own side
        // and the pair is nonsense, which is the shape that survives review.
        //
        // PRD 5.14a already gives the surplus a home: money received and not yet
        // allocated sits on the client, visibly. So an over application is not an
        // alternative way to hold money, it HIDES money that should still be on
        // the Clients screen.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client, owing: Money(dollars: 100))
        let payment = Self.payment(context, for: client, Money(dollars: 5_000))
        try context.save()
        // $100 plus 8.875% is $108.88.
        #expect(invoice.total == Money(cents: 10_888))

        let allocator = PaymentAllocator(modelContainer: container)
        await #expect(throws: AllocationRefusal.wouldExceedWhatIsOwed(
            outstanding: Money(cents: 10_888), asked: Money(dollars: 5_000))) {
            try await allocator.allocate(Money(dollars: 5_000), from: payment.persistentModelID,
                                         to: invoice.persistentModelID, on: .stamping(Self.day))
        }

        let reader = ModelContext(container)
        let readPayment = try #require(try reader.fetch(FetchDescriptor<Payment>()).first)
        #expect(readPayment.allocated == Money.zero, "the refused one wrote nothing at all")
        #expect(readPayment.unallocated == Money(dollars: 5_000))
        let readClient = try #require(try reader.fetch(FetchDescriptor<Client>()).first)
        #expect(readClient.moneyHeld == Money(dollars: 5_000),
                "and the surplus is still visible on the client, which is where 5.14a puts it")
    }

    @Test("allocating EXACTLY what is owed is accepted, so the refusal is not off by one")
    func payingAnInvoiceInFullIsAccepted() async throws {
        // The boundary in the other direction. A refusal at `>=` would make a
        // fully paid invoice unreachable, which is the ordinary case.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client, owing: Money(dollars: 100))
        let payment = Self.payment(context, for: client, Money(dollars: 5_000))
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        try await allocator.allocate(Money(cents: 10_888), from: payment.persistentModelID,
                                     to: invoice.persistentModelID, on: .stamping(Self.day))

        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Invoice>())
            .first { $0.id == invoice.id })
        #expect(read.paymentState == .paid)
        #expect(read.amountOutstanding == Money.zero)
    }

    @Test("the ceiling reads through what ALREADY stands, not just the allocation being made")
    func theCeilingCountsWhatIsAlreadyAllocated() async throws {
        // Two allocations that are each within the total and together are not. A
        // check written against `amount <= invoice.total` rather than against
        // what is OUTSTANDING passes both and lands in the same nonsense state.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client, owing: Money(dollars: 100))
        let payment = Self.payment(context, for: client, Money(dollars: 5_000))
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        try await allocator.allocate(Money(dollars: 100), from: payment.persistentModelID,
                                     to: invoice.persistentModelID, on: .stamping(Self.day))
        await #expect(throws: AllocationRefusal.wouldExceedWhatIsOwed(
            outstanding: Money(cents: 888), asked: Money(dollars: 100))) {
            try await allocator.allocate(Money(dollars: 100), from: payment.persistentModelID,
                                         to: invoice.persistentModelID, on: .stamping(Self.day))
        }

        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Payment>()).first)
        #expect(read.allocated == Money(dollars: 100))
    }

    @Test("releasing what stood against an invoice makes it owed again, and allocatable again")
    func releasingRestoresTheHeadroom() async throws {
        // The ceiling is derived from the allocations that still stand, so a
        // release has to give the room back. Storing an "amount applied" on the
        // invoice would need somebody to remember to undo it here.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client, owing: Money(dollars: 100))
        let payment = Self.payment(context, for: client, Money(dollars: 5_000))
        try context.save()

        let allocator = PaymentAllocator(modelContainer: container)
        try await allocator.allocate(Money(cents: 10_888), from: payment.persistentModelID,
                                     to: invoice.persistentModelID, on: .stamping(Self.day))
        try await allocator.releaseAllAllocations(of: invoice.persistentModelID,
                                                  on: .stamping(Self.day))
        try await allocator.allocate(Money(cents: 10_888), from: payment.persistentModelID,
                                     to: invoice.persistentModelID, on: .stamping(Self.day))

        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Invoice>())
            .first { $0.id == invoice.id })
        #expect(read.paymentState == .paid)
        #expect(read.amountPaid == Money(cents: 10_888))
    }

    @Test("an invoice that owes NOTHING takes no money at all, rather than a little")
    func aZeroInvoiceRefusesEveryAllocation() async throws {
        // PRD 5.1b makes a zero total legitimate, and `paymentState` already
        // reads it as paid the moment it exists. Nothing is outstanding on it, so
        // every allocation is an over application, including the smallest one.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client)
        let payment = Self.payment(context, for: client, Money(dollars: 5_000))
        try context.save()
        #expect(invoice.total == Money.zero)

        let allocator = PaymentAllocator(modelContainer: container)
        await #expect(throws: AllocationRefusal.wouldExceedWhatIsOwed(
            outstanding: Money.zero, asked: Money(cents: 1))) {
            try await allocator.allocate(Money(cents: 1), from: payment.persistentModelID,
                                         to: invoice.persistentModelID, on: .stamping(Self.day))
        }
    }

    // MARK: releasing, which is not deleting

    @Test("releasing an allocation returns the money to unallocated and keeps the record")
    func releasingKeepsTheRecord() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context)
        let invoice = Self.invoice(context, for: client, owing: Money(dollars: 1_000))
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
        let cancelled = Self.invoice(context, for: client, owing: Money(dollars: 1_000))
        let other = Self.invoice(context, for: client, owing: Money(dollars: 1_000))
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
        let invoice = Self.invoice(context, for: client, owing: Money(dollars: 1_000))
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
