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

/// Why a payment could not be recorded or cleared (ovation#510). Each is its own
/// case, so the sheet can say which one stopped it rather than that something did
/// (L11).
enum PaymentRecordingRefusal: Error, Equatable {
    /// Nothing typed, or a negative figure: a payment of nothing records no money.
    case amountIsNotPositive(asked: Money)
    case noSuchInvoice
    /// A draft has not been sent, so nothing has been asked of the client yet.
    /// Money arriving first is a deposit, which is ovation#96, not this.
    case invoiceIsNotSent
    /// A cancelled or deleted invoice takes no money (PRD 13, 14d).
    case invoiceIsClosed
    /// Paid in full already. More money would only be held, and holding it
    /// against an invoice that owes nothing is not a decision this sheet makes.
    case nothingIsOwed
    case noSuchPayment
    /// Only a check has a cleared step (PRD 15).
    case hasNoClearedStep

    /// What the screen says when a payment was not recorded or cleared, in the
    /// words of the thing that stopped it, because a press that did nothing and
    /// gives no reason leaves pressing it again as the only diagnosis (L109).
    var sentence: String {
        switch self {
        case .amountIsNotPositive:
            return "A payment needs an amount above nothing, so it was not recorded."
        case .noSuchInvoice:
            return "That invoice is no longer there, so the payment was not recorded."
        case .invoiceIsNotSent:
            return "This invoice has not been sent, so it takes no payment yet."
        case .invoiceIsClosed:
            return "This invoice was cancelled, so it takes no payment."
        case .nothingIsOwed:
            return "This invoice is already paid in full, so the payment was not recorded."
        case .noSuchPayment:
            return "That payment is no longer there, so nothing was cleared."
        case .hasNoClearedStep:
            return "Only a check waits to clear, so this payment needs no clearing."
        }
    }
}

/// Why a client's held money could not be put on an invoice or taken off it
/// (ovation#185, PRD 14h to 14j). Each is its own case, so the invoice can say
/// which one stopped it rather than that something did (L11).
enum HeldMoneyRefusal: Error, Equatable {
    case noSuchInvoice
    /// A cancelled or deleted invoice takes no money (PRD 13, 14d).
    case invoiceIsClosed
    /// Held money belongs to a client (PRD 14a), and an invoice with none has
    /// nobody's money to take.
    case invoiceHasNoClient
    /// Paid, including paid by a check that has not cleared (Dan, 2026-09-26),
    /// or a comped invoice owing nothing: PRD 14h's "a PAID invoice is not one".
    case nothingIsOwed
    /// Ovation could not settle whether this went out, which is its own question
    /// (ovation#45) and not one held money answers (PRD 14j).
    case sendIsUnsettled
    case clientHoldsNothing
    /// `Remove` pressed where no held money stands on the invoice.
    case nothingToRemove

    /// What the invoice says when nothing was applied or taken off, in the words of
    /// the thing that stopped it (L109).
    var sentence: String {
        switch self {
        case .noSuchInvoice:
            return "That invoice is no longer there, so no held money was moved."
        case .invoiceIsClosed:
            return "This invoice was cancelled, so it takes no held money."
        case .invoiceHasNoClient:
            return "This invoice has no client, so there is nobody's held money to use."
        case .nothingIsOwed:
            return "Nothing is owed on this invoice, so no held money was put on it."
        case .sendIsUnsettled:
            return "Ovation could not tell whether this invoice went out, so no held money was put on it."
        case .clientHoldsNothing:
            return "This client is holding no money, so none was put on the invoice."
        case .nothingToRemove:
            return "No held money is on this invoice, so there was nothing to remove."
        }
    }
}

/// What putting a client's held money on one invoice came to, read back after
/// the save: what went on, and what the client still holds (PRD 14k).
struct HeldMoneyApplied: Sendable, Equatable {
    let applied: Money
    let stillHeld: Money
}

/// What recording a payment did, read back after the one save.
struct RecordedPayment: Sendable, Equatable {
    let payment: PersistentIdentifier
    /// What went against the invoice.
    let allocated: Money
    /// What the invoice could not take, which stays on the client (PRD 14a).
    let held: Money
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
    ///
    /// ITS ONE USER IS `PaymentTests.acancellationAndAnAllocationCannotInterleave`,
    /// which sets it through `setBeforeWriting` and so never spells this name.
    /// ovation#487 was filed because a search for `beforeWriting` in the suites
    /// found nothing and read as the seam being unused.
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

        // MONEY ALREADY RECEIVED AND NOT YET SPOKEN FOR IS HELD MONEY (PRD 14a), so
        // an allocation made here, after the payment was recorded, is held money
        // applied, and the invoice offers `Remove` on it (PRD 14i).
        let allocation = PaymentAllocation(payment: payment, invoice: invoice,
                                           amount: amount, allocatedOn: day,
                                           source: .heldMoney)
        modelContext.insert(allocation)
        try modelContext.save()
    }

    /// Records money that arrived for one sent invoice (ovation#510, PRD 51m).
    ///
    /// THE PAYMENT AND ITS ALLOCATION ARE ONE SAVE. Written as two, a failure
    /// between them leaves money arrived and pointed at nothing, which the Clients
    /// screen would show as money held that Dan never meant to hold. So both are
    /// inserted and saved together, under the same gate every other writer of
    /// money takes (ovation#175).
    ///
    /// MORE THAN IS OWED IS RECORDED IN FULL, because the payment is the amount
    /// actually written (PRD 14), and the invoice takes only what it owes: the rest
    /// is unallocated on the client, which is where PRD 14a puts an overpayment.
    ///
    /// ONE PRESS IS ONE PAYMENT, HOWEVER IT ARRIVES. `press` becomes the payment's
    /// identity, so a double click or a retry after a write that looked like it
    /// failed finds the first payment and answers with it instead of recording
    /// the money twice. It is checked first, under the gate, because a second
    /// arrival after the first paid the invoice in full must get the first
    /// answer, not a refusal that nothing is owed.
    @discardableResult
    func record(
        _ amount: Money,
        method: PaymentMethod,
        receivedOn day: BusinessDate,
        onto invoiceID: PersistentIdentifier,
        press: UUID
    ) async throws -> RecordedPayment {
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }

        guard amount > .zero else { throw PaymentRecordingRefusal.amountIsNotPositive(asked: amount) }
        guard let invoice = try find(invoiceID, as: Invoice.self) else {
            throw PaymentRecordingRefusal.noSuchInvoice
        }
        if let earlier = try modelContext.fetch(FetchDescriptor<Payment>(
            predicate: #Predicate { $0.id == press })).first {
            let standing = earlier.activeAllocations.filter { $0.invoice?.id == invoice.id }
            return RecordedPayment(payment: earlier.persistentModelID,
                                   allocated: Money.sum(of: standing.map(\.amount)),
                                   held: earlier.unallocated)
        }
        guard case .sent = invoice.sentStatus else { throw PaymentRecordingRefusal.invoiceIsNotSent }
        guard invoice.closure == nil else { throw PaymentRecordingRefusal.invoiceIsClosed }
        let owed = invoice.amountOutstanding
        guard owed > .zero else { throw PaymentRecordingRefusal.nothingIsOwed }

        let payment = Payment(client: invoice.client, amount: amount, method: method,
                              receivedOn: day)
        payment.id = press
        modelContext.insert(payment)
        let share = amount < owed ? amount : owed
        modelContext.insert(PaymentAllocation(payment: payment, invoice: invoice,
                                              amount: share, allocatedOn: day,
                                              source: .recordedWithThePayment))
        try modelContext.save()
        return RecordedPayment(payment: payment.persistentModelID,
                               allocated: share, held: amount - share)
    }

    /// Marks a check cleared on the day Mark cleared is pressed (PRD 15, 51n).
    ///
    /// Under the same gate, because it writes a payment another writer may be
    /// allocating from. Pressing it again on a check already cleared changes
    /// nothing: the day it cleared is a fact, and a second press is not a newer one.
    func markCleared(_ paymentID: PersistentIdentifier, on day: BusinessDate) async throws {
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }
        guard let payment = try find(paymentID, as: Payment.self) else {
            throw PaymentRecordingRefusal.noSuchPayment
        }
        guard payment.canBeCleared else { throw PaymentRecordingRefusal.hasNoClearedStep }
        guard payment.clearedOn == nil else { return }
        payment.markCleared(on: day)
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

    // MARK: a client's held money on an invoice (ovation#185, PRD 14g to 14k)

    /// Applies held money wherever PRD 14h says Ovation does it by itself, and
    /// gives back whatever an invoice's shrinking total has left it holding more
    /// of than it is owed. Answers the invoices it changed, in no order.
    ///
    /// PRD 14h: a client with money held and EXACTLY ONE open invoice has it put
    /// on that invoice, as much as fits. PRD 14j: with more than one, nothing is
    /// put on any of them, and each offers `Use it here` instead. Which invoices
    /// are open is `InvoiceStanding.isOpenForHeldMoney`, the one predicate the
    /// list's held money band is counted over too, so the invoice and the list
    /// cannot disagree about how many are open (L16, L370).
    ///
    /// IT IS A FIXED POINT, which is what makes it safe to run on every write.
    /// After one pass every client either holds nothing, or has no single open
    /// invoice still owed, or has set that invoice aside with `Remove`, so a
    /// second pass finds nothing to do and saves nothing. It saves only when it
    /// changed something, because its own save is itself a write the app reacts
    /// to, and a pass that always saved would never stop.
    ///
    /// UNDER THE ONE GATE every writer of money takes (ovation#175), so a pass and
    /// a payment being recorded, a cancellation, or a second pass cannot both find
    /// the same money free (PRD 14b).
    @discardableResult
    func placeHeldMoney(on day: BusinessDate) async throws -> [PersistentIdentifier] {
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }

        var touched: [PersistentIdentifier] = []
        for client in try modelContext.fetch(FetchDescriptor<Client>()) {
            let live = client.invoices.filter { $0.closure == nil }
            // AN INVOICE MAY NEVER TAKE MORE THAN IT IS OWED (ovation#108), and a
            // draft's total moves as it is edited. Where it has fallen below the
            // held money on it, the held money is put back and what still fits
            // goes on again, so the record keeps both decisions (PRD 5.14d).
            for invoice in live where invoice.amountOutstanding < .zero {
                let standing = invoice.allocations.filter { $0.releasedOn == nil && $0.isHeldMoney }
                guard !standing.isEmpty else { continue }
                let heldOnIt = Money.sum(of: standing.map(\.amount))
                for allocation in standing { allocation.releasedOn = day }
                let fits = min(heldOnIt, max(invoice.amountOutstanding, .zero))
                spread(fits, of: client, onto: invoice, on: day)
                touched.append(invoice.persistentModelID)
            }

            let open = InvoiceStanding.invoicesOpenForHeldMoney(of: client, on: day)
            guard open.count == 1, let only = open.first,
                  only.heldMoneyRemovedOn == nil else { continue }
            let fits = min(client.moneyHeld, only.amountOutstanding)
            guard fits > .zero else { continue }
            spread(fits, of: client, onto: only, on: day)
            if !touched.contains(only.persistentModelID) {
                touched.append(only.persistentModelID)
            }
        }
        if !touched.isEmpty { try modelContext.save() }
        return touched
    }

    /// Puts the client's held money on this invoice, as much as fits: `Use it
    /// here` where the client has more than one open invoice (PRD 14j), and `Use
    /// it` where Dan took it off with `Remove` (PRD 14i).
    ///
    /// A SECOND PRESS ANSWERS WITH THE FIRST. Applying takes as much as fits, so
    /// once it has run either the client holds nothing or the invoice owes nothing,
    /// and a press arriving after that finds the money already where it was sent.
    /// Refusing it would tell Dan something failed when nothing did.
    @discardableResult
    func applyHeldMoney(to invoiceID: PersistentIdentifier,
                        on day: BusinessDate) async throws -> HeldMoneyApplied {
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }

        guard let invoice = try find(invoiceID, as: Invoice.self) else {
            throw HeldMoneyRefusal.noSuchInvoice
        }
        guard invoice.closure == nil else { throw HeldMoneyRefusal.invoiceIsClosed }
        let alreadyOn = Money.sum(of: invoice.allocations
            .filter { $0.releasedOn == nil && $0.isHeldMoney }.map(\.amount))
        guard let client = invoice.client else { throw HeldMoneyRefusal.invoiceHasNoClient }
        if alreadyOn > .zero,
           invoice.amountOutstanding <= .zero || client.moneyHeld <= .zero {
            return HeldMoneyApplied(applied: alreadyOn, stillHeld: client.moneyHeld)
        }
        guard Self.isOpenForHeldMoney(invoice, on: day) else {
            switch invoice.sentStatus {
            case .couldNotDetermine, .attempting: throw HeldMoneyRefusal.sendIsUnsettled
            case .notSent, .sent: throw HeldMoneyRefusal.nothingIsOwed
            }
        }
        let fits = min(client.moneyHeld, invoice.amountOutstanding)
        guard fits > .zero else {
            throw invoice.amountOutstanding > .zero
                ? HeldMoneyRefusal.clientHoldsNothing : HeldMoneyRefusal.nothingIsOwed
        }
        spread(fits, of: client, onto: invoice, on: day)
        // PRESSING IT TAKES BACK AN EARLIER `Remove`, so Ovation may again keep this
        // invoice's held money right by itself as its total moves.
        invoice.heldMoneyRemovedOn = nil
        try modelContext.save()
        return HeldMoneyApplied(applied: alreadyOn + fits, stillHeld: client.moneyHeld)
    }

    /// Takes the client's held money back off this invoice, which is `Remove` on
    /// the held money line (PRD 14i). Answers how much went back to the client.
    ///
    /// THE TRUE INVERSE OF APPLYING IT. Applying wrote allocations and nothing
    /// else, since every figure an invoice or a client shows is derived from the
    /// allocations that stand, so releasing them puts every one of those figures
    /// back. They are released and never deleted (PRD 5.14d), and the day is
    /// recorded on the invoice so the next pass does not put it straight back.
    ///
    /// ONLY HELD MONEY. A payment recorded against this invoice is not held money
    /// and is never taken off by this; that is a refund or a correction, and
    /// neither is this control.
    ///
    /// A SECOND PRESS CHANGES NOTHING. Once it is off there is nothing standing to
    /// release, and the day it was removed is a fact that a second press is not a
    /// newer version of.
    @discardableResult
    func removeHeldMoney(from invoiceID: PersistentIdentifier,
                         on day: BusinessDate) async throws -> Money {
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }

        guard let invoice = try find(invoiceID, as: Invoice.self) else {
            throw HeldMoneyRefusal.noSuchInvoice
        }
        let standing = invoice.allocations.filter { $0.releasedOn == nil && $0.isHeldMoney }
        guard !standing.isEmpty else {
            if invoice.heldMoneyRemovedOn != nil { return .zero }
            throw HeldMoneyRefusal.nothingToRemove
        }
        for allocation in standing { allocation.releasedOn = day }
        invoice.heldMoneyRemovedOn = day
        try modelContext.save()
        return Money.sum(of: standing.map(\.amount))
    }

    /// Whether this invoice is one the client's held money could settle, asked
    /// through the list's own predicate and never decided again here (L16).
    private static func isOpenForHeldMoney(_ invoice: Invoice, on day: BusinessDate) -> Bool {
        InvoiceStanding(of: invoice, today: day, couldSettleMoreThanOne: false)
            .isOpenForHeldMoney
    }

    /// Writes `amount` of the client's held money onto the invoice, one allocation
    /// per payment it comes out of, OLDEST MONEY FIRST, which is the order PRD
    /// 14e already takes a refund across payments in.
    ///
    /// ITS CALLER HAS ALREADY BOUNDED THE AMOUNT by what the client holds and what
    /// the invoice owes, under the gate, so each allocation here fits both of
    /// PaymentAllocator's ceilings by construction.
    private func spread(_ amount: Money, of client: Client, onto invoice: Invoice,
                        on day: BusinessDate) {
        var left = amount
        let holding = client.payments
            .filter { $0.unallocated > .zero }
            .sorted { ($0.receivedOn.dayKey, $0.id.uuidString) < ($1.receivedOn.dayKey, $1.id.uuidString) }
        for payment in holding where left > .zero {
            let share = min(payment.unallocated, left)
            let allocation = PaymentAllocation(payment: payment, invoice: invoice, amount: share,
                                               allocatedOn: day, source: .heldMoney)
            modelContext.insert(allocation)
            left = left - share
        }
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
