// ovation#70. Undoing one QuickBooks import batch, guarded at the moment it runs.
//
// A BACKUP TAKEN BEFORE THE IMPORT IS NOT THE GUARD. It answers "can I get back to
// before the import"; the revert has to answer "is it still safe to undo this
// one", and those come apart the moment anything happens after the import: a
// payment recorded against an imported invoice, a reminder sent about one, a date
// corrected on one. Restoring the old backup would take that work away too (L5).
//
// SO THE REVERT REFUSES, AND NAMES EVERY REASON, WHEN ANY ROW IN THE BATCH:
//
//   - has been edited since the import wrote it, judged against the state the import
//     recorded in the same save (`ImportedState`), never against a flag every
//     writer would have to remember to set (L621);
//   - carries a record of its own the import did not write. Enumerated by name
//     rather than assumed absent, because a delete has to account for everything
//     derived from what it deletes (L38): a payment recorded against an imported
//     invoice, or held money applied to one; a refund; a message Ovation sent about
//     one; referral credit spent on one; and, for an imported payment, any share of
//     it put on an invoice the import did not write, or any refund of it. Expenses
//     and their receipt files are not imported (no expense export exists), so no
//     batch holds one.
//
// THE JUDGEMENT IS MADE INSIDE THE OPERATION (L157). The check, the backup and the
// delete happen on the allocator's actor under the gate every writer of money takes,
// so no payment, refund or cancellation can land between them, and the check is
// asked again, synchronously, after the backup and immediately before the delete.
// What the gate does NOT exclude is stated rather than hidden (L407): a writer that
// is not a money writer, a line or date edit through another actor, can still land
// between that last check and the save. The window is a few instructions wide and
// the backup taken a moment before covers it.
//
// A FRESH BACKUP IS TAKEN AND VERIFIED AT THE MOMENT OF THE REVERT, through the
// closure the caller hands in, after the guard passes and before anything is
// deleted. One that fails stops the revert with nothing deleted (L5).
//
// ALL OR NOTHING. Every row of the batch goes in ONE save, so the store is never
// left in a third state that is neither before nor after the import; a revert that
// can refuse refuses whole, and says which rows stopped it.
import Foundation
import SwiftData

/// What a revert would remove, and what stops it, derived from the store as it is
/// now, so a confirmation reads differently for one invoice and for thirty (L180).
struct ImportRevertPreview: Equatable, Sendable {
    let batch: UUID
    let invoices: Int
    let lines: Int
    let payments: Int
    /// Everything that would refuse the revert, one entry per row it concerns.
    let blockers: [ImportRevertBlocker]
}

/// One imported row the revert cannot remove, and every reason why.
struct ImportRevertBlocker: Equatable, Sendable {
    enum Row: Equatable, Sendable {
        /// An imported invoice, by the number QuickBooks issued it.
        case invoice(number: Int64?)
        /// An imported payment, by the number of the invoice the import put it on.
        case payment(paidInvoice: Int64?)
    }

    enum Reason: Equatable, Sendable {
        case editedSinceImport
        /// Money recorded against the invoice since: a payment, or held money applied.
        case paymentRecordedAgainstIt
        case refundRecorded
        case messageSentAboutIt
        case referralCreditSpentOnIt
        /// Part of an imported payment now settles an invoice the import did not write.
        case paymentPutOnAnotherInvoice
    }

    let row: Row
    let reasons: [Reason]
}

enum ImportRevertOutcome: Equatable, Sendable {
    /// Every row of the batch is gone, and this is the backup taken just before.
    case reverted(invoices: Int, payments: Int, backup: URL)
    /// Nothing was deleted, and this is every row that stopped it.
    case refused([ImportRevertBlocker])
    /// No row in the store carries this batch.
    case nothingToRevert
    /// The backup could not be taken or did not verify, so nothing was deleted.
    case backupFailed(String)
}

/// The store did not hold what the revert wrote.
enum ImportRevertFailure: Error, Equatable {
    case rowsSurvived(count: Int)
}

extension InvoiceNumberAllocator {

    /// What reverting `batch` would remove and what would stop it, read now.
    func previewRevert(of batch: UUID) throws -> ImportRevertPreview {
        let rows = try BatchRows(batch, in: modelContext)
        return ImportRevertPreview(batch: batch, invoices: rows.invoices.count,
                                   lines: rows.invoices.map(\.lineItems.count).reduce(0, +),
                                   payments: rows.payments.count, blockers: try rows.blockers(in: modelContext))
    }

    /// Removes every row `batch` wrote, or refuses and names every row that stops it.
    ///
    /// `takeVerifiedBackup` takes a backup of the store as it is now and answers
    /// where it is, or throws when the backup could not be taken or did not verify.
    func revertImport(_ batch: UUID, takeVerifiedBackup: @Sendable () throws -> URL) async throws -> ImportRevertOutcome {
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }

        let rows = try BatchRows(batch, in: modelContext)
        guard !rows.invoices.isEmpty || !rows.payments.isEmpty else { return .nothingToRevert }
        let found = try rows.blockers(in: modelContext)
        guard found.isEmpty else { return .refused(found) }

        let backup: URL
        do {
            backup = try takeVerifiedBackup()
        } catch {
            return .backupFailed(String(describing: error))
        }

        // ASKED AGAIN, IMMEDIATELY BEFORE THE DELETE, with nothing in between that
        // can suspend this actor: a decision formed before the backup and acted on
        // after it is the race this issue is about (L157).
        let now = try BatchRows(batch, in: modelContext)
        let late = try now.blockers(in: modelContext)
        guard late.isEmpty else { return .refused(late) }

        // Allocations first, by name, rather than trusting the payment's cascade to
        // reach rows the invoice's nullify would otherwise orphan.
        for payment in now.payments {
            for allocation in payment.allocations { modelContext.delete(allocation) }
            modelContext.delete(payment)
        }
        for invoice in now.invoices { modelContext.delete(invoice) }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        // READ BACK (L127): a revert that reports success over rows still there would
        // let the re-import refuse every number for a reason nobody could see.
        let survivors = try BatchRows(batch, in: modelContext)
        let left = survivors.invoices.count + survivors.payments.count
        guard left == 0 else { throw ImportRevertFailure.rowsSurvived(count: left) }
        return .reverted(invoices: now.invoices.count, payments: now.payments.count, backup: backup)
    }
}

/// The rows one batch wrote, read from the store.
private struct BatchRows {
    let batch: UUID
    let invoices: [Invoice]
    let payments: [Payment]

    init(_ batch: UUID, in context: ModelContext) throws {
        self.batch = batch
        invoices = try context.fetch(FetchDescriptor<Invoice>()).filter { $0.importBatchID == batch }
            .sorted { ($0.number ?? 0, $0.id.uuidString) < ($1.number ?? 0, $1.id.uuidString) }
        payments = try context.fetch(FetchDescriptor<Payment>()).filter { $0.importBatchID == batch }
            .sorted { ($0.receivedOn.dayKey, $0.id.uuidString) < ($1.receivedOn.dayKey, $1.id.uuidString) }
    }

    func blockers(in context: ModelContext) throws -> [ImportRevertBlocker] {
        let spent = Set(try context.fetch(FetchDescriptor<ReferralLedgerEntry>()).compactMap(\.spentOnInvoiceID))
        var found: [ImportRevertBlocker] = []
        for invoice in invoices {
            var reasons: [ImportRevertBlocker.Reason] = []
            if !ImportedState.matches(invoice.importedFingerprint, invoice) { reasons.append(.editedSinceImport) }
            if invoice.allocations.contains(where: { $0.importBatchID != batch }) {
                reasons.append(.paymentRecordedAgainstIt)
            }
            if !invoice.refunds.isEmpty { reasons.append(.refundRecorded) }
            if !invoice.sentMessages.isEmpty { reasons.append(.messageSentAboutIt) }
            if spent.contains(invoice.id) { reasons.append(.referralCreditSpentOnIt) }
            if !reasons.isEmpty { found.append(.init(row: .invoice(number: invoice.number), reasons: reasons)) }
        }
        for payment in payments {
            var reasons: [ImportRevertBlocker.Reason] = []
            if !ImportedState.matches(payment.importedFingerprint, payment) { reasons.append(.editedSinceImport) }
            if payment.allocations.contains(where: { $0.importBatchID != batch }) {
                reasons.append(.paymentPutOnAnotherInvoice)
            }
            if !payment.refunds.isEmpty { reasons.append(.refundRecorded) }
            if !reasons.isEmpty {
                let paid = payment.allocations.first { $0.importBatchID == batch }?.invoice?.number
                found.append(.init(row: .payment(paidInvoice: paid), reasons: reasons))
            }
        }
        return found
    }
}
