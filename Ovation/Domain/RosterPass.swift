// ovation#40, PRD 5a. The one pass that clears the roster before invoicing goes
// live, as a value rather than as a screen.
//
// WHY IT EXISTS AT ALL. Requirement 5 refuses to send an invoice for a client
// with no recorded tax status, and 25 of 31 clients carry none, so on the day
// invoicing ships 80% of invoices cannot go out. Clearing that one send at a
// time asks the same question 25 times, and each answer belongs to the client
// rather than to the invoice (L126).
//
// IT HOLDS WHAT BLOCKS A SEND AND NOTHING ELSE (Dan, 2026-09-10, PRD 5a). Two
// clients share one address; that WARNS and can be dismissed as correct (PRD
// 38c), it can never stop an invoice going out, and it is answered where the
// client is. Rendered both ways at the real count before it was chosen, as a
// third section counted in this pass's total and as one sitting in it uncounted.
// The cost is real and is stated rather than implied: the one screen built to be
// cleared once does not hold every question about the roster.
//
// THE COUNT AND THE ROWS IT PROMISES COME FROM ONE PLACE (L16). The screen says
// "Started with 25 of 31", and a figure computed beside the sections rather than
// from them reads as a defect in the data the first time the two disagree.
//
// WHAT IT STARTED WITH IS CAPTURED, WHAT IS LEFT IS DERIVED. Saying the number
// is what makes this read as a one time job rather than a standing nag (PRD 5a),
// and a figure that counts down as you answer is the nag. So `startedWith` is
// taken once, when the pass begins.
//
// IT NAMES NOBODY. Every figure here is a count; the clients themselves are
// returned for a screen to draw, and nothing in this type renders a name into
// output (docs/PRIVACY-FLOOR.md).
import Foundation

/// One reading of the roster, taken when the pass begins.
struct RosterPass {
    /// Every client the pass was opened over, in the order it was given them.
    let clients: [Client]

    /// How many clients had something blocking them WHEN THE PASS BEGAN. Held
    /// rather than computed on demand, which is the whole difference between a
    /// one time job and a nag.
    let startedWith: Int

    init(clients: [Client]) {
        self.clients = clients
        self.startedWith = RosterPass.blocking(in: clients).count
    }

    /// The clients whose address cannot be sent to at all. First on the screen,
    /// because it is worse than a missing status: there is nowhere to send.
    var withUnusableAddress: [Client] {
        clients.filter { !$0.contactProblems.isEmpty }
    }

    /// The clients requirement 5 refuses to send for.
    var needingTaxStatus: [Client] {
        clients.filter { $0.taxStatus == .neverRecorded }
    }

    /// How many are still blocked. Derived, so it falls as questions are
    /// answered while `startedWith` does not move.
    var remaining: Int { RosterPass.blocking(in: clients).count }

    /// Nothing is blocked. The screen that shows this pass goes away when it is
    /// true, and says so rather than vanishing under whoever is standing on it.
    var isSettled: Bool { remaining == 0 }

    /// The whole roster, which is the other half of "25 of 31".
    var rosterSize: Int { clients.count }

    /// THE ONE PREDICATE. Both sections and both counts read this, so a client
    /// in both sections is one client here, and the number the screen shows can
    /// never disagree with the rows under it.
    private static func blocking(in clients: [Client]) -> [Client] {
        clients.filter { $0.taxStatus == .neverRecorded || !$0.contactProblems.isEmpty }
    }
}
