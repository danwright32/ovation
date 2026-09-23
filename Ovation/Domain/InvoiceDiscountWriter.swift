// ovation#457, PRD 5.4a. Putting a discount on an invoice and taking it off.
//
// A SCREEN NEVER WRITES, AN ACTOR DOES (PRD 51l, ovation#440), the shape every
// other writer on this screen uses.
//
// IT VALIDATES NOTHING ITSELF, and that is the decision rather than an omission.
// `Discount`'s two initialisers are private-formed and are the only ways one is
// made: they refuse a negative amount, which is a surcharge nothing has ever
// asked for, and a share outside nothing to everything. A second set of refusals
// here would be two rules for one question, and the day one moved the other
// would not (L370, L263). What reaches this has already been through them.
//
// NOTHING IS HOW A DISCOUNT IS REMOVED. The invoice's discount is a value it has
// or has not got, so one write over one field reaches both states; a separate
// remove would be two ways to one state and two things to keep in step.
//
// IT TAKES THE STORE'S MONEY GATE. A discount changes the invoice's total, and
// `PaymentAllocator` refuses an allocation larger than `amountOutstanding`,
// which is derived from that total, so a discount written while an allocation is
// deciding leaves that ceiling describing an invoice that no longer exists
// (ovation#175, L157).
import Foundation
import SwiftData

@ModelActor
actor InvoiceDiscountWriter {

    /// Records this invoice's discount, or takes it off when given nothing.
    func setDiscount(_ discount: Discount?, on invoiceID: PersistentIdentifier) async throws {
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }

        // FETCHED AND MATCHED, NEVER SUBSCRIPTED. `ModelContext`'s subscript
        // traps on a row deleted since the caller read it, and the screen is a
        // photograph taken at the last write.
        guard let invoice = try modelContext.fetch(FetchDescriptor<Invoice>())
            .first(where: { $0.persistentModelID == invoiceID })
        else { throw InvoiceDiscountRefusal.noSuchInvoice }

        switch invoice.sentStatus {
        case .notSent: break
        case .sent: throw InvoiceDiscountRefusal.invoiceWasSent
        case .attempting, .couldNotDetermine: throw InvoiceDiscountRefusal.sendIsUnsettled
        }

        invoice.discount = discount
        try modelContext.save()
    }
}

/// Why a discount was not written.
enum InvoiceDiscountRefusal: Error, Equatable, CaseIterable {
    /// The invoice is gone, removed since the screen read it.
    case noSuchInvoice
    /// It has been sent, so its figures are what the client was told.
    case invoiceWasSent
    /// A send is in flight or could not be settled, so the render this would
    /// change may already be in a client's inbox.
    case sendIsUnsettled

    /// What the screen says. Each names what happened rather than only refusing,
    /// because a control that does nothing and gives no reason leaves pressing it
    /// again as the only diagnosis (L109).
    var sentence: String {
        switch self {
        case .noSuchInvoice:
            return "That invoice is no longer there, so the discount was not saved."
        case .invoiceWasSent:
            return "This invoice has been sent, so its discount is what the client was told."
        case .sendIsUnsettled:
            return "A send for this invoice has not settled, so its discount cannot change yet."
        }
    }
}
