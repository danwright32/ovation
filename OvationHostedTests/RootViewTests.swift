import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// Plan 1.13, ovation#59. The half that model level tests cannot see.
///
/// The precedent this whole design comes from is postroll#846 and #855, where
/// several presenters shared one surface, one heading landed over another's
/// buttons, and EVERY MODEL LEVEL TEST PASSED while it was happening. These
/// render the real view and read what is on it.
@MainActor
struct RootViewTests {

    @Test("the notice shows the sentence of the condition the presenter is showing")
    func theNoticeRendersTheCurrentCondition() throws {
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s",
                    sentence: "The database belongs to another app.", now: at(10))
        presenter.refresh()

        let view = RootView(presenter: presenter, store: store, now: { at(11) })

        #expect(throws: Never.self) {
            try view.inspect().find(text: "The database belongs to another app.")
        }
    }

    @Test("with two conditions, the notice says one more is waiting")
    func theNoticeCountsWhatIsBehindIt() throws {
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s", sentence: "the first", now: at(10))
        store.raise(kind: .backupFailed, subject: "b", sentence: "the second", now: at(11))
        presenter.refresh()

        let view = RootView(presenter: presenter, store: store, now: { at(12) })

        #expect(throws: Never.self) {
            try view.inspect().find(text: "1 more to read")
        }
    }

    @Test("dismissing replaces the notice's CONTENT in the SAME live view")
    func dismissingChangesWhatIsOnScreen() throws {
        // L243, rendered, and rendered in the view that was already on screen.
        //
        // An earlier version of this test built a SECOND RootView after tapping
        // and inspected that. It passed, and it proved nothing about the defect
        // it names: a freshly constructed view reads the presenter again anyway,
        // so a surface that never updates in place would have passed too. The
        // view is hosted once and inspected again after the tap.
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s", sentence: "the first", now: at(10))
        store.raise(kind: .backupFailed, subject: "b", sentence: "the second", now: at(11))
        presenter.refresh()

        let view = RootView(presenter: presenter, store: store, now: { at(12) })
        ViewHosting.host(view: view)
        defer { ViewHosting.expel() }

        // Scoped to the NOTICE, not the whole window. Both sentences are on
        // screen after the tap, because the durable list keeps everything open
        // (L126), so an assertion over the whole view cannot tell "the notice
        // moved on" from "the list still lists it". The first version of this
        // test could not, and said so by failing.
        let before = try view.inspect().find(LaunchNoticeView.self)
        #expect(throws: Never.self) { try before.find(text: "the first") }

        try view.inspect().find(button: "I have read this").tap()

        let after = try view.inspect().find(LaunchNoticeView.self)
        #expect(throws: Never.self) { try after.find(text: "the second") }
        #expect(throws: (any Error).self) { try after.find(text: "the first") }
        #expect(presenter.showing?.sentence == "the second")
    }

    @Test("a dismissed condition is still in the durable list, not gone from the screen")
    func theListOutlivesTheNotice() throws {
        // A condition that persists in the data must not be reachable only from a
        // notice that clears (L126).
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s", sentence: "the only one", now: at(10))
        presenter.refresh()

        let view = RootView(presenter: presenter, store: store, now: { at(11) })
        try view.inspect().find(button: "I have read this").tap()

        let after = RootView(presenter: presenter, store: store, now: { at(12) })
        #expect(presenter.showing == nil)
        #expect(throws: Never.self) {
            try after.inspect().find(text: "the only one")
        }
    }

    @Test("with nothing wrong, the list says so rather than showing an empty box")
    func theEmptyStateIsItsOwnSentence() throws {
        let (store, presenter) = make()
        let view = RootView(presenter: presenter, store: store, now: { at(10) })

        #expect(throws: Never.self) {
            try view.inspect().find(text: ProblemsListView.nothingWrong)
        }
    }

    // MARK: fixtures

    private func make() -> (ProblemsStore, LaunchPresenter) {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        return (store, LaunchPresenter(store: store))
    }

    private func at(_ second: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(second))
    }

    // MARK: which window Dan actually gets (ovation#40, PRD 44a)

    /// L3: built is not wired. Every test above this point renders `ShellView`
    /// directly, which says nothing about whether the app ever SHOWS it. These
    /// two drive the choice the window actually makes.
    ///
    /// THE SHELL OWNS THE WINDOW ONLY WHILE THE ROSTER IS IN THE RAIL, which is
    /// the same predicate the rail itself uses rather than a second one beside
    /// it (L70). So the roster cannot be in the rail with the shell not showing,
    /// nor the shell showing with nothing to stand on.
    @Test("the window is the shell while something blocks a send")
    func theWindowIsTheShellWhenTheRosterHasWork() throws {
        let (store, presenter) = make()
        let roster = Self.rosterNeeding(3)
        let shell = ShellPresenter(selected: .roster, rosterHasWork: { !roster.isSettled })

        let view = RootView(presenter: presenter, store: store, now: { at(11) },
                            roster: roster, shell: shell)

        #expect(throws: Never.self) {
            try view.inspect().find(text: Destination.roster.title)
        }
        #expect(throws: Never.self) {
            try view.inspect().find(text: "Invoices")
        }
    }

    /// And the other direction, or the assertion above is satisfied by a window
    /// that shows the shell unconditionally (L98, L159). With nothing blocking,
    /// the window is what it has always been, so the launch notices and the
    /// durable list are not quietly replaced by a screen with nothing on it.
    @Test("the window is the problems surface when nothing blocks a send")
    func theWindowIsTheProblemsSurfaceWhenSettled() throws {
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s",
                    sentence: "The database belongs to another app.", now: at(10))
        presenter.refresh()

        let roster = Self.rosterNeeding(0)
        let shell = ShellPresenter(selected: .invoices, rosterHasWork: { !roster.isSettled })

        let view = RootView(presenter: presenter, store: store, now: { at(11) },
                            roster: roster, shell: shell)

        #expect(throws: Never.self) {
            try view.inspect().find(text: "The database belongs to another app.")
        }
        #expect(throws: (any Error).self) {
            try view.inspect().find(text: "Invoices")
        }
    }

    private static func rosterNeeding(_ count: Int) -> RosterPresenter {
        var clients: [Client] = []
        for i in 0..<count {
            let c = Client(name: "Client \(i)", taxStatus: .neverRecorded)
            c.email = "c\(i)@example.example"
            clients.append(c)
        }
        return RosterPresenter(clients: clients, save: {})
    }
}

