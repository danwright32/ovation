// ovation#471. Dan saying an invoice whose send Ovation could not settle did not go.
//
// HE MAY CLEAR ONE, NEVER ASSERT ONE (Dan, 2026-09-21). `SentStatus` offers no way
// to say an invoice was sent by hand, and this adds none: it writes exactly one
// transition, an unsettled send back to a draft, and refuses every other.
//
// THE NUMBER STAYS. Dan can be wrong about whether it went, and a kept number turns
// a wrong answer into a duplicate of one document rather than two invoices sharing
// one number. `InvoiceNumberAllocator.release` is not called here, deliberately.
//
// A SCREEN NEVER WRITES, AN ACTOR DOES (PRD 51l, ovation#440), the shape every
// other invoice writer takes.
import Foundation
import SwiftData

@ModelActor
actor SendSettler {

    /// Puts an unsettled send back to a draft, keeping its number.
    func markNotSent(_ invoiceID: PersistentIdentifier) throws {
        // FETCHED AND MATCHED, NEVER SUBSCRIPTED: the row may be gone since the
        // screen read it.
        guard let invoice = try modelContext.fetch(FetchDescriptor<Invoice>())
            .first(where: { $0.persistentModelID == invoiceID })
        else { throw SendSettleRefusal.noSuchInvoice }

        switch invoice.sentStatus {
        case .attempting, .couldNotDetermine: break
        case .sent: throw SendSettleRefusal.invoiceWasSent
        case .notSent: throw SendSettleRefusal.nothingToSettle
        }
        invoice.sentStatus = .notSent
        try modelContext.save()
    }

    /// What Dan is asked before it happens, derived from the invoice it acts on
    /// (L180): what changes, and the risk he is taking.
    nonisolated static func confirmation(number: Int64) -> String {
        "Invoice \(String(number)) goes back to being a draft and keeps its number. If it did reach the client, sending it again sends the same invoice twice."
    }
}

/// Why an invoice was not marked as not sent. Each needs something different (L11).
enum SendSettleRefusal: Error, Equatable {
    case noSuchInvoice
    case invoiceWasSent
    case nothingToSettle

    var sentence: String {
        switch self {
        case .noSuchInvoice: return "That invoice is no longer there, so nothing changed."
        case .invoiceWasSent: return "This invoice was sent, so it cannot be marked unsent."
        case .nothingToSettle: return "This invoice is already a draft, so there is nothing to settle."
        }
    }
}
