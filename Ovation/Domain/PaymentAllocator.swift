// ovation#60 step 3b, PRD 5.14b. The one place an allocation is written.
//
// THE RULE IT EXISTS FOR: the allocations of one payment may never exceed its
// amount, and PRD 5.14b says that is enforced WHERE IT IS STORED rather than by
// whichever screen happens to be allocating, with "a constraint or a lock and not
// careful ordering in application code". A sum that quietly exceeds the money
// actually received produces invoices reading as paid out of money nobody sent.
//
// SWIFTDATA HAS NO CHECK CONSTRAINT, so the enforcement is a serialized writer.
// `@ModelActor` gives this type its own context on its own executor, so read,
// decide and write happen with nothing else in between: two callers arriving at
// once are queued rather than both finding the same headroom. That is the whole
// reason allocation does not live on the model as a method, where every screen
// would have its own context and the check would be advice.
//
// THE RACE IS PROVED BY HOLDING TWO CALLERS THERE AT ONCE, not by hoping an
// interleaving reproduces (L157). `PaymentTests` starts two allocations of more
// than half the payment concurrently and asserts exactly one is refused.
//
// IT REFUSES BY NAME AND WRITES NOTHING (L215, L11). A refusal says what is left
// and what was asked for, so the caller can offer the difference rather than
// reporting a bare failure.
import Foundation
import SwiftData

enum AllocationRefusal: Error, Equatable {
    /// The rule this actor exists for. Carries both numbers so the message can
    /// say what is actually possible.
    case wouldTakeMoreThanArrived(unallocated: Money, asked: Money)
    /// An allocation of nothing records no decision, and one below zero is a
    /// release written the wrong way round.
    case amountIsNotPositive(asked: Money)
    case noSuchPayment
    case noSuchInvoice
}

@ModelActor
actor PaymentAllocator {

    /// Puts a share of one payment against one invoice.
    func allocate(
        _ amount: Money,
        from paymentID: PersistentIdentifier,
        to invoiceID: PersistentIdentifier,
        on day: BusinessDate
    ) throws {
        guard amount > .zero else { throw AllocationRefusal.amountIsNotPositive(asked: amount) }
        guard let payment = self[paymentID, as: Payment.self] else {
            throw AllocationRefusal.noSuchPayment
        }
        guard let invoice = self[invoiceID, as: Invoice.self] else {
            throw AllocationRefusal.noSuchInvoice
        }

        // Read, decide and write, with nothing able to run between them because
        // this actor is the only writer of allocations.
        let free = payment.unallocated
        guard amount <= free else {
            throw AllocationRefusal.wouldTakeMoreThanArrived(unallocated: free, asked: amount)
        }

        let allocation = PaymentAllocation(payment: payment, invoice: invoice,
                                           amount: amount, allocatedOn: day)
        modelContext.insert(allocation)
        try modelContext.save()
    }

    /// Releases everything standing against one invoice, which is what cancelling
    /// it does to the money on it (PRD 5.14d). The rows are marked, never
    /// deleted, so what was decided and when is still readable afterwards.
    ///
    /// It runs on the same actor as `allocate`, so a release and an allocation
    /// cannot interleave and leave the sum wrong in the other direction.
    func releaseAllAllocations(of invoiceID: PersistentIdentifier, on day: BusinessDate) throws {
        guard let invoice = self[invoiceID, as: Invoice.self] else {
            throw AllocationRefusal.noSuchInvoice
        }
        for allocation in invoice.allocations where allocation.releasedOn == nil {
            allocation.releasedOn = day
        }
        try modelContext.save()
    }
}
