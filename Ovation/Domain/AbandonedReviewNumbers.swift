// ovation#362. The launch's one call into the sweep that gives back the numbers
// reviews still held when the app last stopped.
//
// AWAITED BEFORE ANY SCREEN HAS THE STORE, so no review can hold a number the sweep
// would mistake for an abandoned one.
//
// A SWEEP THAT FAILS IS SAID IN THE PROBLEMS LIST (Dan, 2026-09-29, in his words),
// whether it threw or kept a number the store would not let go of. Only the next
// launch whose sweep released, or kept by rule, every held number resolves it,
// because every launch re-checks the whole condition anyway and a notice about a
// condition that has cleared is noise (the problems list resolves itself, as
// `HeldMoneyPass` does). Failing
// leaves every hold where it was, which is the safe side: the invoice keeps its
// number and its next review takes it up.
import Foundation
import SwiftData

extension ProblemKind {
    /// The launch could not give back the numbers reviews left at the last quit.
    static let reviewNumbersNotReleased = ProblemKind("invoice-numbers.review-holds-not-released")
}

@MainActor
enum AbandonedReviewNumbers {

    /// Dan's sentence, 2026-09-29, word for word.
    static let couldNotRelease = "Unused invoice numbers could not be released. Ovation will try again next launch."

    /// One sweep with its work supplied, which is how the suite makes one fail.
    static func giveBack(sweep: () async throws -> AbandonedReviewSweep,
                         problems: ProblemsStore, now: Date) async {
        let id = Problem.identity(kind: .reviewNumbersNotReleased, subject: nil)
        do {
            // A SWEEP THAT RAN IS NOT A SWEEP THAT WORKED (review of fb781b4). A number
            // kept because the store would not let go of it is this same failure, and
            // the sentence is still true of it: the next launch tries that hold again.
            let swept = try await sweep()
            guard swept.kept.values.allSatisfy(\.keptByRule) else {
                _ = problems.raise(kind: .reviewNumbersNotReleased, subject: nil,
                                   sentence: couldNotRelease, now: now)
                return
            }
            if problems.open.contains(where: { $0.id == id }) {
                _ = problems.resolve(id, because: "a later launch gave back the numbers reviews left",
                                     now: now)
            }
        } catch {
            _ = problems.raise(kind: .reviewNumbersNotReleased, subject: nil,
                               sentence: couldNotRelease, now: now)
        }
    }

    /// Over the store that has just opened.
    static func giveBack(over container: ModelContainer, problems: ProblemsStore, now: Date) async {
        await giveBack(sweep: {
            try await InvoiceNumberAllocator(modelContainer: container).releaseNumbersAbandonedReviewsHeld()
        }, problems: problems, now: now)
    }
}
