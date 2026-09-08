// Plan 1.10, ovation#37 and ovation#71. The one place an invoice number is
// written, by either writer.
//
// ONE CONTINUOUS SEQUENCE STARTING AT 1123. A cancelled invoice KEEPS its
// number, so the sequence stays continuous and no two invoices ever share one:
// reissuing a cancelled number would put two different invoices under one number
// in a client's records and in the accountant's.
//
// THE FLOOR IS DERIVED FROM THE STORE, NEVER A CONSTANT, and the collision that
// makes it so arrives two milestones early. The QuickBooks import is a SECOND
// WRITER of this field, and it writes numbers QuickBooks issued before the
// allocator has issued anything. A read modify write over Ovation allocated
// numbers only cannot see them, so an allocated number lands on an imported one,
// and the allocator's own tests pass throughout because no fixture contains an
// imported row (L101). So it allocates above the maximum number present in the
// store, imported rows included, and never below where the sequence starts: an
// import can legitimately carry an older, smaller number, and that must not pull
// the sequence back into numbers a client has already seen.
//
// BOTH WRITERS ARE IN HERE, and that is the point rather than a convenience. A
// rule enforced at one site is not enforced by the system, because every other
// writer can produce the same state (L280). `allocate` issues the next number
// and `claim` takes the one QuickBooks issued, and neither can reach the field
// without the other's ceiling having been consulted, in whichever order the two
// happen to run.
//
// AN IMPORTED INVOICE KEEPS ITS ORIGINAL NUMBER (ovation#71). That number is
// what the client has, what the accountant has, and what a bank reference points
// at, so a collision is a REFUSAL naming both rather than a renumber.
//
// THE MECHANISM IS A SERIALIZED WRITER, AND THERE IS DELIBERATELY NO UNIQUE
// ATTRIBUTE. The issue asked for a database constraint rather than careful
// ordering, and PRD 42a forbids one with a measurement: on this Mac, Swift 6.3.3
// on macOS 26.5.1, a model with a unique attribute given a second record
// carrying the same value did NOT throw, and the fetch returned ONE row holding
// the second value. The first was gone with no error anywhere. A constraint that
// destroys the original rather than refusing the duplicate is worse than none.
//
// So `@ModelActor` gives this its own context on its own executor, read, decide
// and write happen with nothing in between, and the guarantee is proved by
// holding two callers at the decision point at once rather than by hoping an
// interleaving reproduces (L157), and by asserting over the STORE rather than
// over what the allocator returned (L225).
//
// EVERY WRITE IS READ BACK (L127). An identifier you supply to a store is a
// request until something confirms it, and here the confirmation is cheap.
import Foundation
import SwiftData

enum InvoiceNumberRefusal: Error, Equatable {
    case noSuchInvoice
    /// Renumbering an invoice that already has one would break the link to every
    /// record outside Ovation, so it is refused and the existing number is named.
    case alreadyNumbered(existing: Int64)
    /// The number an import asked for is already held. Carries it so the report
    /// can name both invoices (ovation#72).
    case numberAlreadyHeld(number: Int64)
    case numberIsNotPositive(asked: Int64)
    /// The write went in and came back as something else. It has never been seen
    /// and it is not ignorable: it means the store did not hold what this actor
    /// believes, which is the one assumption everything above rests on.
    case readBackDisagreed(wrote: Int64, found: Int64?)
}

@ModelActor
actor InvoiceNumberAllocator {

    /// Where the sequence starts. It is a FLOOR, not a counter: the number
    /// actually issued is derived from the store every time.
    static let sequenceStartsAt: Int64 = 1_123

    /// Issues the next number in the sequence to a draft.
    @discardableResult
    func allocate(to invoiceID: PersistentIdentifier) throws -> Int64 {
        let all = try allInvoices()
        guard let invoice = all.first(where: { $0.persistentModelID == invoiceID }) else {
            throw InvoiceNumberRefusal.noSuchInvoice
        }
        if let existing = invoice.number {
            throw InvoiceNumberRefusal.alreadyNumbered(existing: existing)
        }

        let taken = Set(all.compactMap(\.number))
        var next = max(Self.sequenceStartsAt, (taken.max() ?? 0) + 1)
        // A store whose highest number is not its only one can still have a gap
        // at `next` filled by something this loop has not considered, so the
        // membership test is asked rather than assumed. It cannot spin: the set
        // is finite and `next` only rises.
        while taken.contains(next) { next += 1 }

        try write(next, onto: invoice)
        return next
    }

    /// Takes the number an import's source already issued, or refuses.
    ///
    /// It does NOT renumber on a collision. See the header.
    func claim(_ number: Int64, for invoiceID: PersistentIdentifier) throws {
        guard number > 0 else {
            throw InvoiceNumberRefusal.numberIsNotPositive(asked: number)
        }
        let all = try allInvoices()
        guard let invoice = all.first(where: { $0.persistentModelID == invoiceID }) else {
            throw InvoiceNumberRefusal.noSuchInvoice
        }
        if let existing = invoice.number {
            throw InvoiceNumberRefusal.alreadyNumbered(existing: existing)
        }
        guard !Set(all.compactMap(\.number)).contains(number) else {
            throw InvoiceNumberRefusal.numberAlreadyHeld(number: number)
        }

        try write(number, onto: invoice)
    }

    /// Every invoice in the store, and the target is found IN it rather than
    /// through the identifier subscript.
    ///
    /// THE SUBSCRIPT IS NOT SAFE FOR A ROW THAT HAS BEEN DELETED. Handed the
    /// identifier of an invoice deleted since the caller read it, it returns a
    /// non-nil object that traps the moment any property is read: "this model
    /// instance was invalidated because its backing data could no longer be found
    /// in the store". That is not a refusal, it is the process dying, and a row
    /// deleted between a screen reading it and this running is an ordinary race
    /// rather than an exotic one. A fetch simply does not return it, so the
    /// guard above can refuse by name.
    ///
    /// ONE FETCH SERVES BOTH QUESTIONS, the target and the numbers already taken,
    /// so this is cheaper than the subscript version was rather than dearer.
    ///
    /// THE SCALE, STATED (L24): the FreshBooks history holds 171 issued invoices
    /// across nine years, so this is a few hundred rows and grows by tens a year.
    /// Reading all of them to find one maximum is the right shape at that size
    /// and would not be at a hundred thousand.
    ///
    /// CANCELLED AND DISMISSED ROWS COUNT. Their numbers are spent: a cancelled
    /// invoice keeps its number and a client may be holding a copy of it.
    private func allInvoices() throws -> [Invoice] {
        try modelContext.fetch(FetchDescriptor<Invoice>())
    }

    private func write(_ number: Int64, onto invoice: Invoice) throws {
        invoice.number = number
        try modelContext.save()

        // READ BACK. The write is a request until the store says otherwise, and a
        // number that did not land is one the next allocation will hand out
        // again (L127).
        let id = invoice.id
        let stored = try modelContext.fetch(FetchDescriptor<Invoice>())
            .first { $0.id == id }?.number
        guard stored == number else {
            throw InvoiceNumberRefusal.readBackDisagreed(wrote: number, found: stored)
        }
    }
}
