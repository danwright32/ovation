// ovation#49. Building the invoice list at launch, from the store.
//
// IT IS THE SCREEN THE APP OPENS ON. `RosterLaunch` already selects `.invoices`
// whenever the roster has nothing to ask (and since ovation#298 it never has), so
// this is what Dan sees when he opens Ovation, and until this existed that was a
// panel reading "This screen has not been built yet".
//
// A FAILED READ IS ITS OWN PROBLEM, never an empty list. An invoice list drawn
// empty because the fetch threw is indistinguishable from one empty because
// everything is paid, and this screen's empty state says exactly that everything
// is paid (L10, L215). So the read either produces a list or raises a problem and
// produces nothing, and the shell draws the rail's status block for it.
//
// ONE CONTEXT, THE SAME ONE, for the reason `OvationApp` gives where it builds
// these: a fetch and a save through two contexts over one file are two writers
// (ovation#84, ovation#133).
import Foundation
import SwiftData

@MainActor
enum InvoiceListLaunch {

    /// Raised when the store opened but its invoices could not be read out of it.
    ///
    /// ITS OWN KIND rather than the roster's, because the two failures need
    /// different sentences: one means no invoice can be sent, the other means the
    /// screen Dan works from cannot be drawn at all (L11).
    static let invoicesUnreadable = ProblemKind("invoices.unreadable")

    /// The list, or nil when it could not be read.
    ///
    /// - Parameters:
    ///   - fetchInvoices: every invoice in the store.
    ///   - fetchClients: every client, for the money Ovation is holding on each.
    ///     Read here rather than off the invoices, because a client holding money
    ///     with no invoice at all is a real state (PRD 46e) and reading the
    ///     clients through the invoices would silently exclude them.
    ///   - today: the day the list is banded against, injected so the bands can be
    ///     tested at a chosen moment (L74).
    static func present(
        fetchInvoices: () throws -> [Invoice],
        fetchClients: () throws -> [Client],
        problems: ProblemsStore,
        today: BusinessDate,
        now: Date
    ) -> InvoiceListPresenter? {
        let invoices: [Invoice]
        let clients: [Client]
        do {
            invoices = try fetchInvoices()
            clients = try fetchClients()
        } catch {
            _ = problems.raise(
                kind: invoicesUnreadable,
                subject: nil,
                sentence: "Ovation opened its database but could not read the invoices out "
                    + "of it: \(error). The invoice list is the only way to reach an invoice, "
                    + "so until this is fixed nothing can be sent, chased or marked paid.",
                now: now)
            return nil
        }

        // HELD MONEY IS SUMMED FROM THE SAME PLACE THE CLIENTS SCREEN SUMS IT
        // (PRD 46b), never written beside it, because a second copy of a figure a
        // screen computes is a second definition of it (L107).
        var held: [Client: Money] = [:]
        for client in clients where client.moneyHeld > .zero {
            held[client] = client.moneyHeld
        }

        return InvoiceListPresenter(invoices: invoices, heldMoney: held, today: today)
    }

    /// What the rail draws beneath the card: everything Ovation is holding, across
    /// every client (PRD 46b).
    ///
    /// A QUANTITY OF NOTHING IS NOT DRAWN, which is why this is optional rather
    /// than "0.00". PRD 46b makes it a figure rather than one of the card's counts,
    /// and the card's counts are things needing Dan while this is money sitting.
    static func heldMoneyLine(_ clients: [Client]) -> String? {
        let total = Money.sum(of: clients.map(\.moneyHeld))
        return total > .zero ? PDFText.amount(total) : nil
    }
}
