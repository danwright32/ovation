// ovation#457, PRD 5.4. Adding a line to an invoice.
//
// A SCREEN NEVER WRITES, AN ACTOR DOES (PRD 51l, ovation#440), the shape the
// other three writers on this screen use and for the same reason: a screen
// holding a model object from before an actor wrote to it puts its whole stale
// snapshot back on its next save.
//
// IT TAKES THE STORE'S MONEY GATE, and that is the part worth reading twice.
// `PaymentAllocator` refuses an allocation larger than `invoice.amountOutstanding`,
// which is derived from the invoice's TOTAL, and a line changes that total. A
// line written while an allocation is deciding leaves the allocation's ceiling
// describing an invoice that no longer exists, so the invoice can end up holding
// more money than it asks for with every individual step correct (ovation#175,
// L157). The gate's own header says it serializes "every writer of money against
// an invoice", and this is one.
//
// THE LINE IS FLAT, WITH NO SHOOT. PRD 4 puts rush turnaround and preview images
// on the invoice rather than on a shoot, and `LineItem.flat` takes no shoot so
// that none can be assigned afterwards: a flat charge that reached a shoot was
// priced as hours times its amount, and $150 of rush turnaround on a three hour
// shoot came to $450 on an invoice that totalled correctly against its own parts
// (ovation#431).
//
// IT REFUSES NO AMOUNT IT IS GIVEN, including zero, which is a comped line and a
// legitimate one (PRD 5.1b), and including a negative, which `LineItem.flat`
// records as allowed. What refuses an amount is the control, and only for one
// it cannot READ.
import Foundation
import SwiftData

@ModelActor
actor InvoiceLineWriter {

    /// Adds one flat line of this service type, charged at this amount.
    func addLine(ofType typeID: PersistentIdentifier,
                 amount: Money,
                 to invoiceID: PersistentIdentifier) async throws {
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }

        // FETCHED AND MATCHED, NEVER SUBSCRIPTED. `ModelContext`'s subscript traps
        // on a row deleted since the caller read it, and the screen is a
        // photograph taken at the last write.
        guard let invoice = try modelContext.fetch(FetchDescriptor<Invoice>())
            .first(where: { $0.persistentModelID == invoiceID })
        else { throw InvoiceLineRefusal.noSuchInvoice }

        switch invoice.sentStatus {
        case .notSent: break
        case .sent: throw InvoiceLineRefusal.invoiceWasSent
        case .attempting, .couldNotDetermine: throw InvoiceLineRefusal.sendIsUnsettled
        }

        guard let type = try modelContext.fetch(FetchDescriptor<ServiceType>())
            .first(where: { $0.persistentModelID == typeID })
        else { throw InvoiceLineRefusal.noSuchServiceType }

        // RETIRED RATHER THAN DELETED (PRD 5.30), so a retired type is still
        // there to be asked for and is refused BY NAME rather than reported
        // missing: the two are different facts and a person reading "no such
        // type" about one they can see in their own history is being told
        // something untrue (L11).
        guard type.retiredOn == nil else { throw InvoiceLineRefusal.serviceTypeIsRetired }

        let line = LineItem.flat(amount, describedAs: type.name)
        line.serviceType = type
        invoice.add(line)
        modelContext.insert(line)
        try modelContext.save()
    }
}

/// Why a line was not added.
enum InvoiceLineRefusal: Error, Equatable, CaseIterable {
    /// The invoice is gone, removed since the screen read it.
    case noSuchInvoice
    /// It has been sent, so its charges are what the client was told.
    case invoiceWasSent
    /// A send is in flight or could not be settled, so the render this would
    /// change may already be in a client's inbox.
    case sendIsUnsettled
    /// The service type is gone.
    case noSuchServiceType
    /// The service type is retired, so it names work no longer offered.
    case serviceTypeIsRetired

    /// What the screen says. Each names what happened rather than only refusing,
    /// because a control that does nothing and gives no reason leaves pressing it
    /// again as the only diagnosis (L109).
    var sentence: String {
        switch self {
        case .noSuchInvoice:
            return "That invoice is no longer there, so the line was not added."
        case .invoiceWasSent:
            return "This invoice has been sent, so its charges are what the client was told."
        case .sendIsUnsettled:
            return "A send for this invoice has not settled, so its charges cannot change yet."
        case .noSuchServiceType:
            return "That service type is no longer there, so the line was not added."
        case .serviceTypeIsRetired:
            return "That service type has been retired, so it cannot be charged for."
        }
    }
}
