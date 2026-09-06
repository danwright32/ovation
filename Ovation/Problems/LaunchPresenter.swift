// Plan 1.13, ovation#59. The ONE surface every launch time condition reaches Dan
// through, and it holds the identity of what is showing.
//
// WHY IT HOLDS AN IDENTITY RATHER THAN A BOOLEAN. A surface driven by a boolean
// cannot notice that WHICH thing is showing has changed, so replacing one notice
// with another while it is open leaves the previous content on screen (L243).
// And a surface that can show only one thing at a time silently ignores every
// request past the first, so all but one condition can vanish with nothing said
// (L242). Measured in this estate: postroll#846 and #855, where one heading
// landed over another's buttons and every model level test passed throughout.
//
// THE ARRIVAL POLICY IS A DECISION, made here rather than left to whichever
// request SwiftUI happens to honour:
//
//   A condition arriving while one is on screen QUEUES. Replacing what somebody
//   is reading mid sentence is how a refusal gets dismissed unread. If what IS
//   showing stops needing to be shown, because something else resolved it, the
//   surface moves on, and what replaces it is a different identity.
//
// THIS IS A SHORTCUT INTO THE DURABLE LIST, never the only place a condition is
// visible. Dismissing acknowledges; it does not delete (L126).
import Foundation

@MainActor
@Observable
final class LaunchPresenter {
    private let store: ProblemsStore

    /// What is on screen, or nil. The view keys on `showing?.id`, so a change of
    /// content is a change of identity.
    private(set) var showing: Problem?

    /// How many more are waiting behind it. Shown, so a person can tell one
    /// refusal from four.
    private(set) var waiting: Int = 0

    init(store: ProblemsStore) {
        self.store = store
    }

    /// Recompute from the store. Called at launch and whenever the store changes.
    func refresh() {
        let queue = store.needingPresentation

        if let current = showing, queue.contains(where: { $0.id == current.id }) {
            // Keep it. An arrival does not yank the screen out from under a
            // reader; it waits its turn.
            showing = queue.first { $0.id == current.id }
            waiting = queue.count - 1
        } else {
            showing = queue.first
            waiting = max(queue.count - 1, 0)
        }
    }

    /// Dan has read it. Acknowledged in the store, taken off the surface, still
    /// in the list.
    @discardableResult
    func dismiss(now: Date) -> Bool {
        guard let current = showing else { return false }
        let acknowledged = store.acknowledge(current.id, now: now)
        refresh()
        return acknowledged
    }
}
