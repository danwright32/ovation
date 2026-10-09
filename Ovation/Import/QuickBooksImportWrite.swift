// ovation#68, ovation#69 and ovation#71. What the QuickBooks import writes, and
// what it says it wrote.
//
// AN INVOICE IS WRITTEN ONLY WHERE THE EXPORTS AGREE ABOUT IT: its lines sum to its
// total (`QuickBooksReconciliation`) and the payments under it add up to what the
// invoice list says was paid (`QuickBooksPaymentReconciliation`). Every other
// invoice is already refused by name in the report, and writing it anyway would
// put an invoice in the store whose lines or whose payment state nobody could
// vouch for (L340).
//
// THE WRITE ITSELF IS `InvoiceNumberAllocator.importInvoices`, because the import
// is the second writer of the invoice number field and both writers have to read
// one ceiling inside one serialized writer (plan 1.10, L280). This file holds what
// that writer is handed and what it answers, and how one invoice's rows become
// models, so the rule for each lives in one place.
//
// FOUR OUTCOMES PER INVOICE, NEVER FEWER (ovation#72): written, already imported,
// refused here with a reason, or refused before it got here by the reader or the
// reconciliations. Folding already imported into written makes a re-run look like
// it did work; folding it into refused makes a harmless re-run look like a failure.
import Foundation
import SwiftData

/// One invoice the import would write, with every row it came from.
struct QuickBooksImportCandidate: Equatable, Sendable {

    /// One payment QuickBooks recorded against the invoice, keyed on its own row.
    struct Payment: Equatable, Sendable {
        let key: QuickBooksImportKey
        let row: QuickBooksLedgerRow
    }

    /// Over the invoice list row, every sales line row and every payment row, in
    /// that order (`QuickBooksImportKey`).
    let key: QuickBooksImportKey
    let invoice: QuickBooksInvoiceRow
    let lines: [QuickBooksLineRow]
    let payments: [Payment]
}

/// What one import run wrote, and why it wrote nothing for the rest.
struct QuickBooksImportWrite: Equatable, Sendable {

    struct Refusal: Equatable, Sendable {
        /// The invoice's row in the invoice list.
        let invoiceRow: Int
        let reason: Reason
    }

    enum Reason: Equatable, Sendable {
        /// Another invoice in the store already holds this number, whichever writer
        /// put it there (ovation#71). The number is carried for Dan's own screen and
        /// never printed (docs/PRIVACY-FLOOR.md).
        case numberAlreadyHeld(number: Int64)
        case numberIsNotPositive
        /// No client in Ovation carries the name QuickBooks billed.
        case clientNotInOvation
        /// Several do, so which one this invoice belongs to is not settled (L521).
        case clientNameHeldBySeveral(count: Int)
        /// A payment row under it was already written by an earlier import.
        case paymentAlreadyImported(ledgerRow: Int)
        /// Ovation's own arithmetic over the lines and the client's tax status does
        /// not arrive at QuickBooks' total, so the invoice would read as owing a
        /// figure QuickBooks never billed (L150).
        case totalDiffers(ovation: Money, quickBooks: Money)
    }

    /// The run that wrote these, which every row it wrote carries (ovation#69).
    let batch: UUID
    /// Invoice list rows written, in file order.
    let written: [Int]
    let paymentsWritten: Int
    /// Invoice list rows whose key the store already holds.
    let alreadyImported: [Int]
    let refused: [Refusal]
}

/// The write went in and the store did not hold what was written.
enum QuickBooksImportWriteFailure: Error, Equatable {
    case readBackDisagreed(wrote: Int, found: Int)
}

extension QuickBooksImportRun {

    /// Every invoice the exports agree about, in invoice list order, keyed at
    /// `version`. Empty where either reconciliation could not run.
    func candidates(version: Int = QuickBooksImportKey.importerVersion) -> [QuickBooksImportCandidate] {
        guard let reconciliation, let paymentReconciliation else { return [] }
        let tied = Dictionary(paymentReconciliation.tied.map { ($0.invoice.number, $0) },
                              uniquingKeysWith: { first, _ in first })
        return reconciliation.agreed.compactMap { agreed -> QuickBooksImportCandidate? in
            guard let payments = tied[agreed.invoice.number], payments.invoice == agreed.invoice else { return nil }
            let paymentKeys = payments.payments.map { row in
                QuickBooksImportCandidate.Payment(
                    key: QuickBooksImportKey(version: version, sources: [
                        .init(fileSHA256: invoicesAndPayments.fileSHA256, row: row.row, rawRowSHA256: row.rawRowSHA256),
                    ]),
                    row: row)
            }
            let sources = [QuickBooksImportKey.Source(fileSHA256: invoiceList.fileSHA256, row: agreed.invoice.row,
                                                      rawRowSHA256: agreed.invoice.rawRowSHA256)]
                + agreed.lines.map { .init(fileSHA256: salesLines.fileSHA256, row: $0.row, rawRowSHA256: $0.rawRowSHA256) }
                + payments.payments.map { .init(fileSHA256: invoicesAndPayments.fileSHA256, row: $0.row,
                                                rawRowSHA256: $0.rawRowSHA256) }
            return QuickBooksImportCandidate(key: QuickBooksImportKey(version: version, sources: sources),
                                             invoice: agreed.invoice, lines: agreed.lines, payments: paymentKeys)
        }
        .sorted { $0.invoice.row < $1.invoice.row }
    }
}

/// How one candidate's rows become models. No store decisions here: the allocator
/// has already settled the number, the client and the key before it calls this.
enum QuickBooksImportBuilder {

    /// Inserts the invoice and its lines into `context`, billed in QuickBooks on its
    /// own date. The caller deletes it again if it refuses it.
    static func invoice(_ candidate: QuickBooksImportCandidate, client: Client, batch: UUID,
                        in context: ModelContext) -> Invoice {
        let row = candidate.invoice
        let invoice = Invoice.imported(number: row.number, key: candidate.key, batch: batch, client: client,
                                       invoiceDate: row.date, dueDate: row.dueDate)
        context.insert(invoice)
        for line in candidate.lines {
            let summary = line.description.isEmpty ? (line.product ?? "") : line.description
            let item: LineItem
            if let hundredths = line.quantityHundredths, let price = line.salesPrice {
                item = .hourly(hours: Hours(hundredths: hundredths), at: price, describedAs: summary)
            } else {
                item = .flat(line.amount, describedAs: summary)
            }
            context.insert(item)
            invoice.add(item)
        }
        invoice.recordSendState(.sent(route: .billedInQuickBooks, at: row.date.instant))
        return invoice
    }

    /// Inserts each payment and the allocation putting all of it on `invoice`.
    static func payments(_ candidate: QuickBooksImportCandidate, onto invoice: Invoice, client: Client,
                         batch: UUID, in context: ModelContext) -> [Payment] {
        candidate.payments.map { imported in
            let payment = Payment.imported(key: imported.key, batch: batch, client: client,
                                           amount: imported.row.amount, receivedOn: imported.row.date)
            context.insert(payment)
            let allocation = PaymentAllocation.imported(payment: payment, invoice: invoice,
                                                        amount: imported.row.amount,
                                                        allocatedOn: imported.row.date, batch: batch)
            context.insert(allocation)
            return payment
        }
    }
}
