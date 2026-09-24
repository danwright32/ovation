import Foundation
import Testing

/// ovation#42. Every way the review sheet closes settles the review exactly once, and
/// a send in flight cannot be closed away.
///
/// WHY A TRACKER. The sheet closes by its own Close and Done, which settle the review
/// directly, and by the Escape key, which only clears the binding. The one thing both
/// reach is the sheet's dismissal, so the review is settled there too, and this makes
/// the second arrival a no-op rather than a second hand back of a number.
struct ReviewDismissalTests {

    final class Review {}

    @Test("closing by a control settles the review, and the dismissal after it settles nothing")
    func acontrolCloseSettlesOnce() {
        var screen = ReviewOnScreen<Review>()
        let review = Review()
        screen.opened(review)

        #expect(screen.settle() === review)
        #expect(screen.settle() == nil)
    }

    @Test("a dismissal no control saw, the Escape key, still settles the review")
    func adismissalAloneSettles() {
        var screen = ReviewOnScreen<Review>()
        let review = Review()
        screen.opened(review)

        #expect(screen.settle() === review)
    }

    @Test("with nothing on screen, a dismissal settles nothing")
    func nothingOpenSettlesNothing() {
        var screen = ReviewOnScreen<Review>()
        #expect(screen.settle() == nil)
    }

    @Test("a second review opened settles itself, never the first")
    func thenextReviewIsItsOwn() {
        var screen = ReviewOnScreen<Review>()
        let first = Review()
        let second = Review()
        screen.opened(first)
        _ = screen.settle()
        screen.opened(second)

        #expect(screen.settle() === second)
    }

    @Test("only a send in flight holds the sheet open", arguments: [
        (ReviewSendState.working(since: Date(timeIntervalSince1970: 0)), true),
        (.ready, false),
        (.sent(at: Date(timeIntervalSince1970: 0), to: ["a@example.com"]), false),
        (.refused("no"), false),
        (.couldNotTell("unknown"), false),
    ])
    func onlyAsendInFlightHoldsTheSheet(state: ReviewSendState, holds: Bool) {
        #expect(state.holdsTheSheetOpen == holds)
    }
}
