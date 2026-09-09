// ovation#60 step 3b, PRD 5.14b. The one place an allocation is written.
//
// THE TWO RULES IT EXISTS FOR, one per side of the allocation.
//
// PRD 5.14b: the allocations of one payment may never exceed its amount, and
// that is enforced WHERE IT IS STORED rather than by whichever screen happens to
// be allocating, with "a constraint or a lock and not careful ordering in
// application code". A sum that quietly exceeds the money actually received
// produces invoices reading as paid out of money nobody sent.
//
// PRD 5.14a: an invoice may never take more than it is owed (ovation#108). This
// half was missing, so $5,000 of a $5,000 payment could be applied to a $100
// invoice. The invoice then read `paid` with an outstanding balance of minus
// $4,900 and the client's held money read as fully spent: both numbers truthful
// about their own side, the pair nonsense, which is the shape that survives
// review because each half is correct in isolation. 5.14a already gives the
// surplus a home, visibly on the client, so an over application is not an
// alternative way to hold money, it HIDES money that belongs on the Clients
// screen. It is settled here rather than deferred: an invoice may never be
// deliberately over applied.
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
    /// The ceiling on the OTHER side (ovation#108, PRD 5.14a). Carries what is
    /// actually outstanding, so the caller can offer that amount instead.
    case wouldExceedWhatIsOwed(outstanding: Money, asked: Money)
    /// An allocation of nothing records no decision, and one below zero is a
    /// release written the wrong way round.
    case amountIsNotPositive(asked: Money)
    case noSuchPayment
    case noSuchInvoice
}

@ModelActor
actor PaymentAllocator {

    /// Run after this actor has decided and before it writes, and used by
    /// nothing but the suite (ovation#175).
    ///
    /// THE RACE IS PROVED BY HOLDING BOTH CALLERS THERE AT ONCE, not by hoping
    /// an interleaving reproduces (L157). Two writers of the same rows cannot be
    /// raced by starting them and looking, because the window is microseconds
    /// and a green run would mean nothing. This is the seam that opens it on
    /// purpose, and it is here from the day the gate is, rather than retrofitted
    /// (L524, L284).
    var beforeWriting: (@Sendable () async -> Void)?

    func setBeforeWriting(_ hook: (@Sendable () async -> Void)?) {
        beforeWriting = hook
    }

    /// Puts a share of one payment against one invoice.
    func allocate(
        _ amount: Money,
        from paymentID: PersistentIdentifier,
        to invoiceID: PersistentIdentifier,
        on day: BusinessDate
    ) async throws {
        // EVERY WRITER OF MONEY AGAINST AN INVOICE TAKES THE SAME GATE
        // (ovation#175). This actor's own executor excludes a second allocation
        // and nothing else: `InvoiceCloser` releases the same rows from a
        // different actor with its own context.
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }

        guard amount > .zero else { throw AllocationRefusal.amountIsNotPositive(asked: amount) }
        guard let payment = try find(paymentID, as: Payment.self) else {
            throw AllocationRefusal.noSuchPayment
        }
        guard let invoice = try find(invoiceID, as: Invoice.self) else {
            throw AllocationRefusal.noSuchInvoice
        }

        // Read, decide and write, with nothing able to run between them because
        // this actor is the only writer of allocations.
        let free = payment.unallocated
        guard amount <= free else {
            throw AllocationRefusal.wouldTakeMoreThanArrived(unallocated: free, asked: amount)
        }

        // THE ORDER OF THE TWO CEILINGS IS FIXED, and the payment's comes first
        // because it is the stronger claim: money nobody sent cannot be spent at
        // all, whereas an invoice's ceiling is about where money that really
        // arrived should go. A caller refused on one may then be refused on the
        // other, and that is honest rather than tidy: each refusal names the
        // number that actually binds it, and neither answers for the other (L11).
        //
        // IT READS WHAT IS OUTSTANDING, NOT THE TOTAL. `amountOutstanding` is
        // derived from the allocations that still stand, so two allocations that
        // are each under the total and together are not are caught, and a release
        // gives the room back with nothing having to remember to undo a flag.
        let owed = invoice.amountOutstanding
        guard amount <= owed else {
            throw AllocationRefusal.wouldExceedWhatIsOwed(outstanding: owed, asked: amount)
        }

        if let beforeWriting { await beforeWriting() }

        let allocation = PaymentAllocation(payment: payment, invoice: invoice,
                                           amount: amount, allocatedOn: day)
        modelContext.insert(allocation)
        try modelContext.save()
    }

    /// Releases everything standing against one invoice, which is what cancelling
    /// it does to the money on it (PRD 5.14d). The rows are marked, never
    /// deleted, so what was decided and when is still readable afterwards.
    ///
    /// It takes the store's `MoneyWriteGate`, which is what actually excludes an
    /// allocation from interleaving with it.
    ///
    /// THIS DOCSTRING USED TO SAY SOMETHING THAT WAS NOT TRUE (ovation#175). It
    /// said "it runs on the same actor as `allocate`, so a release and an
    /// allocation cannot interleave", and that was true of THIS release and
    /// false of the other one: `InvoiceCloser.cancel` releases the same rows
    /// from a different actor with its own context. A recorded guarantee is the
    /// whole record of an exclusion, so every later reader took it as
    /// established (L407).
    func releaseAllAllocations(of invoiceID: PersistentIdentifier,
                               on day: BusinessDate) async throws {
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }

        guard let invoice = try find(invoiceID, as: Invoice.self) else {
            throw AllocationRefusal.noSuchInvoice
        }
        // The rule itself lives on the invoice, because `InvoiceCloser` needs the
        // same one and each writer saves in its own context (L370).
        invoice.releaseActiveAllocations(on: day)
        try modelContext.save()
    }

    /// The row behind an identifier, or nil where there is no longer one.
    ///
    /// NOT `self[id, as:]`, and the difference is the process staying alive.
    /// Handed the identifier of a row DELETED since the caller read it, the
    /// subscript returns a NON-NIL object that traps the moment any property is
    /// read: "this model instance was invalidated because its backing data could
    /// no longer be found in the store". Measured on all three paths here while
    /// building ovation#37, each one crashing the test process rather than
    /// refusing.
    ///
    /// A row deleted between a screen reading it and this running is an ordinary
    /// race, not an exotic one, and the refusals for it were already written and
    /// already tested. They simply could not be reached. A fetch does not return
    /// a deleted row, so they can be.
    private func find<T: PersistentModel>(
        _ id: PersistentIdentifier, as type: T.Type
    ) throws -> T? {
        try modelContext.fetch(FetchDescriptor<T>()).first { $0.persistentModelID == id }
    }
}
