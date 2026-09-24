// ovation#42. Every way the review sheet closes settles the review exactly once.
//
// The sheet closes by its own Close and Done, which settle the review directly, and by
// the Escape key, which only clears the binding the sheet is presented from. Both reach
// the sheet's dismissal, so the review is settled there as well, and whichever arrives
// second finds nothing to settle. Without this, Escape closed the sheet and never handed
// back a number the review had taken.
import Foundation

struct ReviewOnScreen<Review: AnyObject> {
    private var current: Review?

    mutating func opened(_ review: Review) { current = review }

    /// The review to settle now, once: the first caller gets it and every later one nil.
    mutating func settle() -> Review? {
        defer { current = nil }
        return current
    }
}

extension ReviewSendState {
    /// A send in flight cannot be closed away: its answer is what the sheet is for, and
    /// closing it would hand back a number while Gmail may still be sending under it.
    var holdsTheSheetOpen: Bool {
        if case .working = self { return true }
        return false
    }
}
