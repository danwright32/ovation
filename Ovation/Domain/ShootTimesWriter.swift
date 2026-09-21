// ovation#457, PRD 3, 3a, 3c, 51l. Writing the times Dan types onto a shoot.
//
// THIS IS WHAT MAKES A DRAFT SENDABLE. PRD 3a says a booking's times are a
// placeholder nothing may be priced from, and 3c that a draft carries no duration
// and cannot be sent until Dan supplies one. He supplies it on the invoice screen,
// through this, and ovation#42's send waits on it: nothing else in the app writes a
// shoot's times at all.
//
// A SCREEN NEVER WRITES, AN ACTOR DOES (PRD 51l, ovation#440). The invoice screen
// holds what Dan is typing as values and hands each field here as he leaves it,
// which Dan chose on 2026-09-20 against an explicit Save and against writing every
// keystroke. A screen holding an object from before an actor wrote to it puts its
// whole stale snapshot back on its next save, so the screen holds no object at all.
//
// CLEARING A TIME CLEARS THE HOURS BESIDE IT, in the same save. A shoot linked line
// whose shoot has no times falls back to its OWN stored hours, which is right for an
// imported QuickBooks row and wrong for a shoot Dan has just cleared, and the reader
// cannot tell the two apart, so the writer settles it. That is Dan's decision of
// 2026-09-19 and the reason `Invoice.clearTimes(of:)` exists (L46, L544).
import Foundation
import SwiftData

/// Why a time was not written.
enum ShootTimesRefusal: Error, Equatable {
    /// The shoot is gone, removed since the screen read it.
    case noSuchShoot
    /// Its invoice has been sent, so its times priced a document a client holds.
    case invoiceWasSent
    /// A send is in flight or could not be settled, so the render it would change
    /// may already be in a client's inbox.
    case sendIsUnsettled

    /// What the screen says. Each names what happened rather than only refusing,
    /// because a control that does nothing and gives no reason leaves pressing it
    /// again as the only diagnosis (L109).
    var sentence: String {
        switch self {
        case .noSuchShoot:
            return "That shoot is no longer on this invoice, so the time was not saved."
        case .invoiceWasSent:
            return "This invoice has been sent, so its times are what the client was billed."
        case .sendIsUnsettled:
            return "A send for this invoice has not settled, so its times cannot change yet."
        }
    }
}

@ModelActor
actor ShootTimesWriter {

    /// Records when the shoot started, or clears it.
    func setStart(_ time: ClockTime?, on shootID: PersistentIdentifier) throws {
        try write(shootID) { $0.shotFrom = time }
    }

    /// Records when the shoot ended, or clears it.
    func setEnd(_ time: ClockTime?, on shootID: PersistentIdentifier) throws {
        try write(shootID) { $0.shotUntil = time }
    }

    /// Finds the shoot, refuses what may not change, applies the edit, and settles
    /// the hours beside it, all in one save.
    private func write(_ shootID: PersistentIdentifier, _ edit: (Shoot) -> Void) throws {
        // FETCHED AND MATCHED, NEVER SUBSCRIPTED. `ModelContext`'s subscript traps
        // on a row deleted since the caller read it, and the screen is a photograph
        // taken at the last write, so the shoot Dan is typing into can be gone.
        guard let shoot = try modelContext.fetch(FetchDescriptor<Shoot>())
            .first(where: { $0.persistentModelID == shootID })
        else { throw ShootTimesRefusal.noSuchShoot }

        // A SENT INVOICE'S TIMES PRICED A DOCUMENT A CLIENT ALREADY HOLDS. Changing
        // them would make Ovation's copy disagree with the client's, and an edit to
        // something sent is a new version, never an overwrite (ovation#46).
        //
        // AN UNSETTLED SEND IS REFUSED TOO, for ovation#460's reason: the message
        // may already be with the client, so the render it would change is not
        // Ovation's to rewrite until the send is resolved.
        switch shoot.invoice?.sentStatus ?? .notSent {
        case .notSent: break
        case .sent: throw ShootTimesRefusal.invoiceWasSent
        case .attempting, .couldNotDetermine: throw ShootTimesRefusal.sendIsUnsettled
        }

        edit(shoot)

        // A SHOOT MISSING EITHER TIME HAS NO DURATION, so the line beside it must
        // have no stored hours to fall back to. Clearing only when BOTH are gone
        // would leave a shoot with a start and no end pricing from a figure no
        // screen shows.
        if shoot.shotFrom == nil || shoot.shotUntil == nil {
            for line in shoot.invoice?.lineItems ?? [] where line.shoot?.id == shoot.id {
                line.hours = nil
            }
        }
        try modelContext.save()
    }
}
