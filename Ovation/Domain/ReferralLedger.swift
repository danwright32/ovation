// Plan 1.12, ovation#38. The one writer of the referral ledger, from both the
// earning and the spending side.
//
// THE BALANCE IS A SUM OVER AN APPEND ONLY LOG, never a stored field, and
// `Client.referralBalance` is the one predicate that reads it. A stored balance
// is one number every writer races for, and when it drifts there is no way to
// find out what it should have been.
//
// AN APPEND ONLY LEDGER PROTECTS THE SUM, NEVER THE WRITER, which is the whole
// reason this actor exists. Re-summing always gives the right answer for the
// entries that are there, and says nothing about whether an entry should have
// been there twice.
//
// SO EVERY ENTRY CARRIES AN IDEMPOTENCY KEY, and there are two of them because
// there are two ways the same work gets re-run.
//
//   EARNING is keyed on the BOOKING. Credit fires when the first invoice is
//   marked paid; paid is itself derived from summed payments (PRD 5.14); and
//   both edit-and-resend (ovation#46) and cancel-with-refund (ovation#47) can
//   re-cross that transition. Without the key, an invoice paid, edited, resent
//   and paid again grants the credit twice, and nothing about the ledger's shape
//   prevents it.
//
//   SPENDING is keyed on the INVOICE, for the same reason one stage later:
//   editing and resending re-runs whatever applied the credit, and the client is
//   charged their own credit twice.
//
// THE EARNING KEY IS GLOBAL, NOT PER CLIENT. A booking has one referrer, so the
// same booking granting a credit to two clients is wrong about the booking while
// being right about each client, which is the shape that survives review.
//
// SPENDING MORE THAN THE BALANCE IS ALLOWED. PRD 5.8 says Ovation "warns when a
// booking is flagged as spending credit the client does not have", and a warning
// is not a refusal. Refusing here would make the requirement unimplementable and
// would push the correction into the database by hand.
//
// A CREDIT CAN BE WITHDRAWN, and that is settled here rather than left open,
// which the issue asked for. It is another entry and never a deletion, so the
// history stays readable, and it needs a REASON: a withdrawal without one cannot
// be told from a mistake. The earning entry stays, so its key stays taken, and
// re-earning that booking has to be a deliberate act rather than something a
// retry can do.
//
// THE MECHANISM IS A SERIALIZED WRITER, for the reason `InvoiceNumberAllocator`
// records: PRD 42a measured that a unique attribute on this Mac destroys the
// original rather than refusing the duplicate. So `@ModelActor`, and the
// guarantee is proved by holding two callers at the decision point at once.
import Foundation
import SwiftData

enum ReferralRefusal: Error, Equatable {
    case noSuchClient
    /// Carries the key so a caller can say which booking, and so the refusal can
    /// be told from a client that simply is not there.
    case alreadyEarnedForBooking(key: String)
    case alreadySpentOnInvoice(id: UUID)
    case noEarningForBooking(key: String)
    case hoursAreNotPositive(asked: Hours)
    /// A key that may be empty is not a key: the credit would be granted again on
    /// every retry and the ledger's shape would hide it.
    case bookingKeyIsEmpty
    case reasonIsEmpty
}

@ModelActor
actor ReferralLedger {

    /// Grants credit earned by referring a booking. Once, ever, for that booking.
    func earn(
        _ hours: Hours, for clientID: PersistentIdentifier,
        fromBooking bookingKey: String, on day: BusinessDate
    ) throws {
        let key = bookingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ReferralRefusal.bookingKeyIsEmpty }
        guard hours > .zero else { throw ReferralRefusal.hoursAreNotPositive(asked: hours) }
        guard let client = try find(clientID) else { throw ReferralRefusal.noSuchClient }

        guard try earning(forBooking: key) == nil else {
            throw ReferralRefusal.alreadyEarnedForBooking(key: key)
        }

        modelContext.insert(ReferralLedgerEntry(
            client: client, hours: hours, occurredOn: day,
            earnedFromBookingKey: key, note: nil))
        try modelContext.save()
    }

    /// Spends credit on one invoice. Once, ever, for that invoice.
    func spend(
        _ hours: Hours, for clientID: PersistentIdentifier,
        onInvoice invoiceID: UUID, on day: BusinessDate
    ) throws {
        guard hours > .zero else { throw ReferralRefusal.hoursAreNotPositive(asked: hours) }
        guard let client = try find(clientID) else { throw ReferralRefusal.noSuchClient }

        let alreadySpent = try allEntries().contains { $0.spentOnInvoiceID == invoiceID }
        guard !alreadySpent else { throw ReferralRefusal.alreadySpentOnInvoice(id: invoiceID) }

        modelContext.insert(ReferralLedgerEntry(
            client: client, hours: Hours(tenths: -hours.tenths), occurredOn: day,
            earnedFromBookingKey: nil, spentOnInvoiceID: invoiceID, note: nil))
        try modelContext.save()
    }

    /// Reverses an earning by appending its opposite, with the reason.
    ///
    /// It REFUSES when there is no such earning, rather than appending nothing
    /// and reporting success: an operation that finds its target by matching and
    /// matches nothing otherwise leaves the next step acting on a state nobody
    /// created (L100).
    func withdrawEarning(
        fromBooking bookingKey: String, because reason: String, on day: BusinessDate
    ) throws {
        let key = bookingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ReferralRefusal.bookingKeyIsEmpty }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReferralRefusal.reasonIsEmpty
        }
        guard let earned = try earning(forBooking: key) else {
            throw ReferralRefusal.noEarningForBooking(key: key)
        }

        modelContext.insert(ReferralLedgerEntry(
            client: earned.client, hours: Hours(tenths: -earned.hours.tenths), occurredOn: day,
            earnedFromBookingKey: nil,
            note: "Withdrawn: \(reason.trimmingCharacters(in: .whitespacesAndNewlines))"))
        try modelContext.save()
    }

    private func allEntries() throws -> [ReferralLedgerEntry] {
        try modelContext.fetch(FetchDescriptor<ReferralLedgerEntry>())
    }

    private func earning(forBooking key: String) throws -> ReferralLedgerEntry? {
        try allEntries().first { $0.earnedFromBookingKey == key }
    }

    /// NOT `self[id, as:]`. Handed the identifier of a row deleted since the
    /// caller read it, the subscript returns a non-nil object that traps on the
    /// first property read, which is the process dying rather than a refusal.
    /// Measured on the allocators in ovation#37.
    private func find(_ id: PersistentIdentifier) throws -> Client? {
        try modelContext.fetch(FetchDescriptor<Client>()).first { $0.persistentModelID == id }
    }
}
