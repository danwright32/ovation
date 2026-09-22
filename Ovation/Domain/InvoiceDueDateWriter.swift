// ovation#473, PRD 5.7. Writing the day an invoice falls due.
//
// A SCREEN NEVER WRITES, AN ACTOR DOES (PRD 51l, ovation#440), the same shape
// `ShootTimesWriter` uses and for the same reason: a screen holding a model
// object from before an actor wrote to it puts its whole stale snapshot back on
// its next save, so the screen holds no object at all.
//
// IT REFUSES WHAT THE TIMES WRITER REFUSES, and the reasons are the same ones: a
// sent invoice's due date is what a client was told, and an unsettled send's
// render may already be in their inbox. The two writers share the refusal type
// rather than each naming its own, because the question is one question about the
// invoice and two vocabularies for it would drift (L118, L370).
import Foundation
import SwiftData

@ModelActor
actor InvoiceDueDateWriter {

    /// Records the day this invoice falls due.
    func setDueDate(_ due: BusinessDate, on invoiceID: PersistentIdentifier) throws {
        // FETCHED AND MATCHED, NEVER SUBSCRIPTED. `ModelContext`'s subscript traps
        // on a row deleted since the caller read it, and the screen is a
        // photograph taken at the last write.
        guard let invoice = try modelContext.fetch(FetchDescriptor<Invoice>())
            .first(where: { $0.persistentModelID == invoiceID })
        else { throw InvoiceDueDateRefusal.noSuchInvoice }

        switch invoice.sentStatus {
        case .notSent: break
        case .sent: throw InvoiceDueDateRefusal.invoiceWasSent
        case .attempting, .couldNotDetermine: throw InvoiceDueDateRefusal.sendIsUnsettled
        }

        // A DUE DATE BEFORE THE INVOICE DATE IS REFUSED rather than saved and
        // rendered, because it is due before it exists and every reminder counted
        // from it is already late. `On receipt` is the earliest real term and it
        // is the invoice date itself, so equal is allowed and earlier is not.
        if let issued = invoice.invoiceDate, due.dayKey < issued.dayKey {
            throw InvoiceDueDateRefusal.beforeTheInvoiceDate
        }

        invoice.dueDate = due
        try modelContext.save()
    }
}

/// Why a due date was not written.
enum InvoiceDueDateRefusal: Error, Equatable {
    /// The invoice is gone, removed since the screen read it.
    case noSuchInvoice
    /// It has been sent, so its due date is what the client was told.
    case invoiceWasSent
    /// A send is in flight or could not be settled, so the render it would change
    /// may already be in a client's inbox.
    case sendIsUnsettled
    /// Earlier than the day the invoice was written.
    case beforeTheInvoiceDate

    /// What the screen says. Each names what happened rather than only refusing,
    /// because a control that does nothing and gives no reason leaves pressing it
    /// again as the only diagnosis (L109).
    var sentence: String {
        switch self {
        case .noSuchInvoice:
            return "That invoice is no longer there, so the date was not saved."
        case .invoiceWasSent:
            return "This invoice has been sent, so its due date is what the client was told."
        case .sendIsUnsettled:
            return "A send for this invoice has not settled, so its dates cannot change yet."
        case .beforeTheInvoiceDate:
            return "That is before the invoice was written, so it would be due before it exists."
        }
    }
}
