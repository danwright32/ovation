// ovation#49 and ovation#451. Where the invoice list comes from, and how it stays
// true.
//
// IT IS THE SCREEN THE APP OPENS ON. `RosterLaunch` already selects `.invoices`
// whenever the roster has nothing to ask (and since ovation#298 it never has), so
// this is what Dan sees when he opens Ovation.
//
// WHY THE BUILD AND THE RE-READ ARE ONE THING. This began as `InvoiceListLaunch`,
// which built the list once inside the launch and had no way to be asked again.
// Adding a second entry point for re-reading would have been two pieces of code
// deriving one screen, which is the shape where a change lands in one of them and
// the other goes on answering (L370, L107). So there is one derivation, run at
// launch and run again on every write, and the launch is simply its first read.
//
// A FAILED READ IS ITS OWN PROBLEM, never an empty list. An invoice list drawn
// empty because the fetch threw is indistinguishable from one empty because
// everything is paid, and this screen's empty state says exactly that everything
// is paid (L10, L215). So a read either produces a list or raises a problem and
// produces nothing.
//
// AND A FAILED RE-READ DOES NOT KEEP THE LAST GOOD ANSWER EITHER. A stale list of
// rows that may no longer exist, drawn exactly like a current one, is ovation#451
// wearing a different hat.
//
// BOTH DERIVED FIGURES COME OUT OF ONE READ, by construction rather than by
// anybody remembering. The list and PRD 46b's held money line used to be two
// separate pieces of state on `OvationApp` built from two separate fetches, which
// is precisely the shape where one is rebuilt and the other is left behind,
// reading correctly formed and wrong.
//
// A FRESH CONTEXT EVERY READ, and that is measured rather than preferred.
// `SwiftDataBehaviourTests` records that two contexts over one container do not
// merge, that a settled context CAN see another's write by fetching again, and
// that a DIRTY one CANNOT: a context with one unsaved edit on it reads the old
// value. The launch's context is shared with the roster, which saves through it,
// so re-reading there would be correct only while nobody was working. A context
// made for one read and thrown away has nothing unsaved by construction, and the
// probe confirms it sees the write at the instant the notice arrives.
//
// IT NEVER WRITES, which is what makes a second context safe here at all. The
// rule the shared context exists for (ovation#84, ovation#133) is about a fetch
// and a SAVE through two contexts being two writers. This one only ever fetches.
import Foundation
import SwiftData

@MainActor
@Observable
final class InvoiceListSource {

    /// Every invoice and every client, read together.
    ///
    /// ONE CLOSURE RATHER THAN TWO, so both halves necessarily come from one read
    /// at one instant. Two closures would let a caller give each its own context
    /// and read the store at two different moments, and the held money band is a
    /// fact about a client's whole set of invoices (PRD 14j, 46d), so the two
    /// disagreeing is a band with the wrong rows in it.
    typealias Read = () throws -> (invoices: [Invoice], clients: [Client])

    /// Raised when the store opened but its invoices could not be read out of it.
    ///
    /// ITS OWN KIND rather than the roster's, because the two failures need
    /// different sentences: one means no invoice can be sent, the other means the
    /// screen Dan works from cannot be drawn at all (L11).
    static let invoicesUnreadable = ProblemKind("invoices.unreadable")

    /// The list, or nil where it could not be read. Never an empty list standing
    /// for a failure.
    private(set) var list: InvoiceListPresenter?

    /// What Ovation is holding across every client, or nil where it holds nothing
    /// (PRD 46b: a quantity of nothing is not drawn).
    private(set) var heldMoney: String?

    private let read: Read
    /// How to make a read only context, where there is a store at all. Nil under
    /// the closure based initialiser, which a test drives without one.
    private let makeReader: (() -> ModelContext)?
    private let problems: ProblemsStore
    private let now: () -> Date
    private var notices: StoreWriteNotices?

    /// - Parameters:
    ///   - read: the store, read whole.
    ///   - problems: where a failed read is reported.
    ///   - now: read at EVERY read rather than captured once. The bands are
    ///     decided against a day (PRD 46), so an app left open overnight would go
    ///     on banding against the day it was opened and an invoice would fall due
    ///     with the screen never saying so (L175, L74).
    init(read: @escaping Read, problems: ProblemsStore, now: @escaping () -> Date,
         makeReader: (() -> ModelContext)? = nil) {
        self.read = read
        self.makeReader = makeReader
        self.problems = problems
        self.now = now
        reread()
    }

    /// Over a real store, listening for its writes.
    ///
    /// THE LISTENING IS NOT OPTIONAL AND NOT THE CALLER'S JOB. A source over a
    /// store that did not re-read is the defect ovation#451 is, so there is no way
    /// to make one (L621).
    convenience init(
        over container: ModelContainer,
        problems: ProblemsStore,
        now: @escaping () -> Date
    ) {
        self.init(
            read: {
                let reader = ModelContext(container)
                return (invoices: try reader.fetch(FetchDescriptor<Invoice>()),
                        clients: try reader.fetch(FetchDescriptor<Client>()))
            },
            problems: problems,
            now: now,
            makeReader: { ModelContext(container) })
        notices = StoreWriteNotices(container: container) { [weak self] in
            self?.reread()
        }
    }

    /// Reads the store and derives both figures again.
    func reread() {
        let moment = now()
        let store: (invoices: [Invoice], clients: [Client])
        do {
            store = try read()
        } catch {
            // BOTH FIGURES GO, and the held money one cannot be read as "holds
            // nothing" although nil is also what that means (L10, L11). `ShellView`
            // draws the held money line only INSIDE the list, so a nil list replaces
            // the whole surface with the could-not-be-read state and the figure is
            // not on screen at all to be misread.
            list = nil
            heldMoney = nil
            _ = problems.raise(
                kind: Self.invoicesUnreadable,
                subject: nil,
                sentence: "Ovation opened its database but could not read the invoices out "
                    + "of it: \(error). The invoice list is the only way to reach an invoice, "
                    + "so until this is fixed nothing can be sent, chased or marked paid.",
                now: moment)
            return
        }

        // HELD MONEY IS SUMMED FROM THE SAME PLACE THE CLIENTS SCREEN SUMS IT
        // (PRD 46b), never written beside it, because a second copy of a figure a
        // screen computes is a second definition of it (L107).
        //
        // READ OFF THE CLIENTS rather than off the invoices, because a client
        // holding money with no invoice at all is a real state (PRD 46e) and
        // reading the clients through the invoices would silently exclude them.
        var held: [Client: Money] = [:]
        for client in store.clients where client.moneyHeld > .zero {
            held[client] = client.moneyHeld
        }

        list = InvoiceListPresenter(invoices: store.invoices, heldMoney: held,
                                    today: .stamping(moment))
        heldMoney = Self.heldMoneyLine(store.clients)

        // A READ THAT WORKED IS PROOF THE INVOICES ARE READABLE, which is the whole
        // of what the notice claimed. It is settled here for the same reason the
        // launch sequence settles the backup folder notice when a backup happens:
        // nothing else retracts it, `ProblemsStore` never retracts on its own, and
        // a standing notice about a condition that has passed is one Dan learns to
        // click past (L36).
        for standing in problems.open where standing.kind == Self.invoicesUnreadable {
            _ = problems.resolve(standing.id,
                                 because: "the invoices were read",
                                 now: moment)
        }
    }

    /// The screen for one invoice, or nil where that row is no longer there.
    ///
    /// THE SOURCE RESOLVES IT BECAUSE A VIEW MAY NOT (PRD 51l, ovation#440). The
    /// list's rows carry a `PersistentIdentifier` and nothing else useful, and a
    /// screen needs the invoice, its client and its lines. `check-forbidden-constructs.sh`
    /// refuses a view that makes a `ModelContext`, so the resolution lives here,
    /// where the container already does.
    ///
    /// NIL RATHER THAN A TRAP. `ModelContext`'s subscript traps on a row deleted
    /// since the caller read it, and the list is a photograph taken at the last
    /// write, so a row Dan presses can be gone. It is fetched and matched rather
    /// than subscripted, and an absent row is an answer (L10).
    ///
    /// A FRESH CONTEXT, for the reason the read above gives: it only ever fetches,
    /// so it cannot be the second writer ovation#84 forbids.
    func screen(for id: PersistentIdentifier, footer: InvoiceFooter) -> InvoiceScreenPresenter? {
        guard let makeReader else { return nil }
        let reader = makeReader()
        guard let invoice = try? reader.fetch(FetchDescriptor<Invoice>())
            .first(where: { $0.persistentModelID == id })
        else { return nil }
        return InvoiceScreenPresenter(invoice: invoice, footer: footer,
                                      today: .stamping(now()))
    }

    /// Stops listening for writes. Idempotent.
    func stop() {
        notices?.stop()
        notices = nil
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
