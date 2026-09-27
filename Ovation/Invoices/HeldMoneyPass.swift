// ovation#185, PRD 14h. What makes Ovation apply a client's held money BY ITSELF.
//
// WHY IT LISTENS RATHER THAN BEING CALLED. The pass has to follow every write
// that can change its answer: a payment recorded for more than was owed, a
// cancellation that releases money to the client, a draft priced by its times, a
// discount that shrinks a draft under the held money already on it, a send that
// settles. Asking each writer to call it is a behaviour every present and future
// writer must opt into, and the one that forgets leaves money sitting beside an
// invoice it should be on with nothing saying so (L621). `StoreWriteNotices` is
// posted by every save, so this follows all of them, including its own, which
// is why `PaymentAllocator.placeHeldMoney` is a fixed point that saves nothing
// when it has nothing to do.
//
// AND ONCE WHEN THE STORE OPENS, so money held when the app was last closed, or
// by a version from before this one, is placed without waiting for a write.
//
// A PASS THAT FAILS IS SAID (L10, L13). It raises a problem naming what went
// wrong, and the next pass that works resolves it, because the pass re-checks the
// whole condition anyway and a notice about a condition that has cleared is noise
// (the problems list resolves itself).
import Foundation
import SwiftData

extension ProblemKind {
    /// A held money pass failed, so money may be sitting on a client that PRD 14h
    /// says Ovation would have put on their one open invoice.
    static let heldMoneyNotPlaced = ProblemKind("held-money.not-placed")
}

@MainActor
final class HeldMoneyPass {

    /// One pass, over the day it is run on.
    typealias Place = @Sendable (BusinessDate) async throws -> Void

    private let place: Place
    private let problems: ProblemsStore
    private let now: () -> Date
    private var notices: StoreWriteNotices?

    /// A pass with its placement supplied, which is how the suite makes one fail.
    init(place: @escaping Place, problems: ProblemsStore, now: @escaping () -> Date) {
        self.place = place
        self.problems = problems
        self.now = now
    }

    /// Over a real store: one pass now, and one after every write committed to it.
    ///
    /// THE LISTENING IS NOT THE CALLER'S TO ARRANGE, so there is no way to make one
    /// over a store that does not follow its writes (L621).
    convenience init(over container: ModelContainer, problems: ProblemsStore,
                     now: @escaping () -> Date) {
        self.init(place: { day in
                      _ = try await PaymentAllocator(modelContainer: container)
                          .placeHeldMoney(on: day)
                  },
                  problems: problems, now: now)
        notices = StoreWriteNotices(container: container) { [weak self] in
            self?.run()
        }
        run()
    }

    /// Starts a pass without waiting for it.
    func run() {
        Task { await pass() }
    }

    /// One pass, and what it says about itself.
    func pass() async {
        let moment = now()
        let id = Problem.identity(kind: .heldMoneyNotPlaced, subject: nil)
        do {
            try await place(.stamping(moment))
            if problems.open.contains(where: { $0.id == id }) {
                _ = problems.resolve(id, because: "a later pass placed held money without error",
                                     now: moment)
            }
        } catch {
            _ = problems.raise(
                kind: .heldMoneyNotPlaced, subject: nil,
                sentence: "Ovation could not check whether a client's held money belongs on "
                    + "their one open invoice: \(error). Nothing was moved, so each invoice "
                    + "still shows what it owes, and Ovation tries again after the next change.",
                now: moment)
        }
    }
}
