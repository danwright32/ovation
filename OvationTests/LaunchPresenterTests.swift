import Foundation
import Testing

/// Plan 1.13, ovation#59. ONE surface, holding the identity of what is showing.
///
/// The measured precedent is postroll#846 and #855: several independent
/// presenters attached to one surface, where a surface that shows one thing at a
/// time silently ignores every request past the first, and a boolean driven
/// alert cannot notice that WHICH condition is showing has changed. Every model
/// level test passed while it was happening.
@MainActor
struct LaunchPresenterTests {

    @Test("with nothing to say, nothing is presented")
    func silenceWhenThereIsNothing() {
        let (_, presenter) = make()
        presenter.refresh()

        #expect(presenter.showing == nil)
        #expect(presenter.waiting == 0)
    }

    @Test("two conditions raised in one launch are BOTH reachable, one at a time")
    func bothConditionsAreReachable() {
        // The case the issue names. A surface that can show one thing at a time
        // silently ignores every request past the first (L242), so the second
        // condition has to be counted and then shown, never dropped.
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s", sentence: "the store is not ours",
                    now: at(10))
        store.raise(kind: .backupFailed, subject: "b", sentence: "the backup did not verify",
                    now: at(11))
        presenter.refresh()

        #expect(presenter.showing?.kind == .foreignStore)
        #expect(presenter.waiting == 1)

        presenter.dismiss(now: at(12))

        #expect(presenter.showing?.kind == .backupFailed)
        #expect(presenter.waiting == 0)

        presenter.dismiss(now: at(13))

        #expect(presenter.showing == nil)
        #expect(presenter.waiting == 0)
    }

    @Test("what is showing carries an identity, so a change of content is a change of identity")
    func theShowingIdentityChanges() {
        // L243: a surface driven by a boolean cannot notice that WHICH thing is
        // showing has changed, so replacing one notice with another leaves the
        // previous content on screen. The view keys on this.
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(10))
        store.raise(kind: .backupFailed, subject: "b", sentence: "two", now: at(11))
        presenter.refresh()

        let first = presenter.showing?.id
        presenter.dismiss(now: at(12))
        let second = presenter.showing?.id

        #expect(first != nil)
        #expect(second != nil)
        #expect(first != second)
    }

    @Test("a condition arriving while one is on screen queues rather than replacing it")
    func anArrivalDoesNotYankTheScreen() {
        // A decision the code makes, rather than whichever one SwiftUI happens to
        // honour. Replacing what somebody is reading mid sentence is how a
        // refusal gets dismissed unread.
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(10))
        presenter.refresh()
        let showingBefore = presenter.showing?.id

        store.raise(kind: .backupFailed, subject: "b", sentence: "two", now: at(11))
        presenter.refresh()

        #expect(presenter.showing?.id == showingBefore)
        #expect(presenter.waiting == 1)
    }

    @Test("an OLDER condition coming back does not push aside what is being read")
    func aRecurrenceDoesNotYankTheScreenEither() {
        // The case that actually tells the two policies apart, and the one the
        // test above could NOT: planting "always show the head of the queue"
        // left every other case passing, because a newly raised condition is
        // never at the head. It gets there by RECURRING. Dan dismisses the store
        // refusal, the backup failure comes up, and then the store refusal
        // happens again on the next check. Without this rule the backup notice
        // is yanked away mid sentence by something he has already read once.
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s", sentence: "the older one", now: at(10))
        presenter.refresh()
        presenter.dismiss(now: at(11))

        store.raise(kind: .backupFailed, subject: "b", sentence: "the newer one", now: at(12))
        presenter.refresh()
        #expect(presenter.showing?.sentence == "the newer one")

        // The older condition recurs. It is earlier in raise order, so a
        // presenter that simply took the head of the queue would switch to it.
        store.raise(kind: .foreignStore, subject: "s", sentence: "the older one", now: at(13))
        presenter.refresh()

        #expect(presenter.showing?.sentence == "the newer one")
        #expect(presenter.waiting == 1)
    }

    @Test("but if what is showing stops needing to be shown, the surface moves on")
    func aResolvedNoticeIsReplaced() {
        // The other half of L243. Something else resolved this condition, so the
        // presenter must not keep displaying it, and what replaces it is a
        // different identity rather than new text in the same box.
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(10))
        store.raise(kind: .backupFailed, subject: "b", sentence: "two", now: at(11))
        presenter.refresh()
        let first = try! #require(presenter.showing?.id)

        store.resolve(first, because: "Dan moved the file aside", now: at(12))
        presenter.refresh()

        #expect(presenter.showing?.kind == .backupFailed)
        #expect(presenter.showing?.id != first)
    }

    @Test("dismissing takes it off the surface and leaves it in the durable list")
    func dismissingIsNotDeleting() {
        // A condition that persists in the data must not be reachable only from a
        // notice that clears (L126). The modal is a shortcut into the list, never
        // the only place the condition is visible.
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(10))
        presenter.refresh()

        presenter.dismiss(now: at(11))

        #expect(presenter.showing == nil)
        #expect(store.open.count == 1)
        #expect(store.open.first?.acknowledgedAt == at(11))
    }

    @Test("dismissing nothing is refused rather than pretending it worked")
    func dismissingNothingIsRefused() {
        let (_, presenter) = make()
        #expect(!presenter.dismiss(now: at(10)))
    }

    @Test("the oldest condition is shown first, so the order is the order they happened")
    func theOrderIsRaiseOrder() {
        let (store, presenter) = make()
        store.raise(kind: .backupFailed, subject: "b", sentence: "two", now: at(10))
        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(11))
        presenter.refresh()

        #expect(presenter.showing?.kind == .backupFailed)
    }

    // MARK: fixtures

    private func make() -> (ProblemsStore, LaunchPresenter) {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        return (store, LaunchPresenter(store: store))
    }

    private func at(_ second: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(second))
    }
}
