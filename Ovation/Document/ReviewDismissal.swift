// ovation#42. Every way the review sheet closes settles the review exactly once.
//
// The sheet closes by its own Close and Done and by the Escape key, and all three reach
// the one close in ShellView, which settles here first, so whichever arrives second
// finds nothing to settle. Escape once cleared only the binding a system sheet was
// presented from and never handed back a number the review had taken; since the sheet
// floats (ovation#547) Escape calls the same close as Close does.
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
