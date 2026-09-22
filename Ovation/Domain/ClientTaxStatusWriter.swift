// ovation#457, PRD 5.5. Recording a client's sales tax status.
//
// A SCREEN NEVER WRITES, AN ACTOR DOES (PRD 51l, ovation#440), the same shape
// `ShootTimesWriter` and `InvoiceDueDateWriter` use and for the same reason: a
// screen holding a model object from before an actor wrote to it puts its whole
// stale snapshot back on its next save, so the screen holds no object at all.
//
// IT REFUSES NOTHING ABOUT THE INVOICE, and that is a decision rather than an
// omission. The status is a fact about the CLIENT, and `Invoice.tax` reads it at
// render time deliberately: put to Dan on 2026-09-19 with the measurement that
// his own history has three clients taxed on some invoices and untaxed on
// others, he answered that the tax was applied by hand and sometimes missed, so
// the history contains mistakes and the status stays a fact about the client.
// PRD 5a1 records what that costs if a client ever does become exempt. A refusal
// here on the grounds that an invoice has been sent would quietly reverse it.
//
// WHAT IT DOES REFUSE is writing the ABSENCE of an answer as an answer. The two
// screens that ask offer `TaxStatus.answers`, which cannot contain it, and this
// refuses it as well, because a screen gating a write is not the write being
// guarded (L196).
import Foundation
import SwiftData

@ModelActor
actor ClientTaxStatusWriter {

    /// Records this client's sales tax status.
    func setTaxStatus(_ status: TaxStatus, on clientID: PersistentIdentifier) throws {
        // REFUSED BEFORE THE FETCH, so a status that could never be written does
        // not depend on the client still being there to be refused: one wrong
        // call must give one answer, whatever else is true of the store (L11).
        guard status != .neverRecorded else { throw ClientTaxStatusRefusal.notAnAnswer }

        // FETCHED AND MATCHED, NEVER SUBSCRIPTED. `ModelContext`'s subscript traps
        // on a row deleted since the caller read it, and the screen is a
        // photograph taken at the last write.
        guard let client = try modelContext.fetch(FetchDescriptor<Client>())
            .first(where: { $0.persistentModelID == clientID })
        else { throw ClientTaxStatusRefusal.noSuchClient }

        client.taxStatus = status
        try modelContext.save()
    }
}

/// Why a tax status was not written.
enum ClientTaxStatusRefusal: Error, Equatable, CaseIterable {
    /// The client is gone, removed since the screen read them.
    case noSuchClient
    /// `neverRecorded` was handed in, which is the absence of an answer rather
    /// than one of them. Writing it would turn an answered client back into an
    /// unanswered one and stop every invoice they have.
    case notAnAnswer

    /// What the screen says. Each names what happened rather than only refusing,
    /// because a control that does nothing and gives no reason leaves pressing it
    /// again as the only diagnosis (L109).
    var sentence: String {
        switch self {
        case .noSuchClient:
            return "That client is no longer there, so the tax status was not saved."
        case .notAnAnswer:
            return "That is not one of the two answers, so nothing was saved."
        }
    }
}
