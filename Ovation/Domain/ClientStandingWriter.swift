// ovation#568, PRD 51j and 38c. The two facts about a client that its page on
// the Clients screen records, apart from the tax status (`ClientTaxStatusWriter`).
//
// A SCREEN NEVER WRITES, AN ACTOR DOES (PRD 51l, ovation#440), the shape every
// other writer takes: a screen holding a model object from before an actor wrote
// to it puts its stale snapshot back on its next save, so the screen holds values
// and hands each change here.
//
// THE STANDING PAYMENT TERMS (PRD 51j, Dan 2026-09-10, round D of ovation#98). A
// client's standing terms are set on the Clients screen and never on an invoice
// (PRD 51h). They are one of the four terms the invoice's due date control offers,
// and this refuses anything else rather than trusting the screen to offer only
// those, because a screen gating a write is not the write being guarded (L196).
// `BookingDrafter` reads them when it dates a draft, which is what gives the
// stored field a reader (L46).
//
// A SHARED ADDRESS SAID TO BE CORRECT (PRD 38c, Dan 2026-09-07: "it should give me
// a warning but I should be allowed to dismiss it as correct"). Recorded against
// the ADDRESS it was given for, by `Client.acknowledgeSharedAddress(on:)`, so a
// changed address asks again.
import Foundation
import SwiftData

@ModelActor
actor ClientStandingWriter {

    /// Records this client's standing payment terms.
    func setPaymentTerm(_ term: PaymentTerm, on clientID: PersistentIdentifier) throws {
        guard PaymentTerms.all.contains(term) else { throw ClientStandingRefusal.notATerm }
        let client = try Self.find(clientID, in: modelContext)
        client.paymentTermDays = term.days
        try modelContext.save()
    }

    /// Records that this client's address being shared with another is correct.
    func acknowledgeSharedAddress(on clientID: PersistentIdentifier, day: BusinessDate) throws {
        let client = try Self.find(clientID, in: modelContext)
        client.acknowledgeSharedAddress(on: day)
        try modelContext.save()
    }

    /// FETCHED AND MATCHED, NEVER SUBSCRIPTED: the row may be gone since the screen
    /// read it, and the subscript traps on that.
    private static func find(_ id: PersistentIdentifier, in context: ModelContext) throws -> Client {
        guard let client = try context.fetch(FetchDescriptor<Client>())
            .first(where: { $0.persistentModelID == id })
        else { throw ClientStandingRefusal.noSuchClient }
        return client
    }
}

/// Why a client's standing fact was not written. Each says what happened (L109).
enum ClientStandingRefusal: Error, Equatable, CaseIterable {
    case noSuchClient
    case notATerm

    var sentence: String {
        switch self {
        case .noSuchClient: return "That client is no longer there, so nothing was saved."
        case .notATerm: return "That is not one of the four terms, so nothing was saved."
        }
    }
}
