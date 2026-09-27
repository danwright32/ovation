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
    /// drive the choice the window actually makes.
    ///
    /// THE SHELL OWNS THE WINDOW WHENEVER THIS LAUNCH HAS ONE (ovation#566): with
    /// the roster in the rail, with it settled, and with a notice unread.
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

    /// ovation#564. THE SETTLED ROSTER IS THE COMMON CASE, and every launch since
    /// ovation#298 is one. The rule above used to be the ONLY way into the shell,
    /// written when the roster was the only screen; once the invoice list existed
    /// it left Dan on the bare problems window with every screen unreachable.
    @Test("the window is the shell when the roster is settled")
    func theWindowIsTheShellWhenSettled() throws {
        let (store, presenter) = make()
        let roster = Self.rosterNeeding(0)
        let shell = ShellPresenter(selected: .invoices, rosterHasWork: { !roster.isSettled })

        let view = RootView(presenter: presenter, store: store, now: { at(11) },
                            roster: roster, shell: shell)

        #expect(throws: Never.self) {
            try view.inspect().find(ShellView.self)
        }
    }

    /// ovation#566. AN UNREAD NOTICE NO LONGER TAKES THE WINDOW, at launch or later
    /// (Dan, 2026-09-26: "Foot, like the rest"). It is named in the rail's foot with
    /// Read, and the shell keeps the window, so an invoice Dan has open stays open.
    /// This reverses the rule ovation#564 added and the test that held it (L252).
    @Test("an unread notice at launch is named in the foot, and the shell owns the window")
    func anUnreadNoticeAtLaunchIsInTheFoot() throws {
        let (store, presenter) = make()
        store.raise(kind: .exportWritten, subject: "year-end-export-2026",
                    sentence: "The 2026 export is written.", now: at(10))
        presenter.refresh()
        #expect(presenter.showing != nil, "the fixture has an unread notice")

        let roster = Self.rosterNeeding(0)
        let shell = ShellPresenter(selected: .invoices, rosterHasWork: { !roster.isSettled })

        let view = RootView(presenter: presenter, store: store, now: { at(11) },
                            roster: roster, shell: shell)

        #expect(throws: Never.self) { try view.inspect().find(ShellView.self) }
        #expect(throws: Never.self) { try view.inspect().find(text: "2026 export written") }
        #expect(throws: (any Error).self) { try view.inspect().find(LaunchNoticeView.self) }
        #expect(throws: (any Error).self) {
            try view.inspect().find(text: "The 2026 export is written.")
        }
    }

    /// And one arriving while the shell is showing, from the year end export or the
    /// booking queue, which used to replace the shell and close the open invoice.
    /// The SAME live view is inspected before and after, so a window that swapped
    /// its content and back cannot pass (L243).
    @Test("a notice arriving mid session goes to the foot and the shell keeps the window")
    func aNoticeMidSessionGoesToTheFoot() throws {
        let (store, presenter) = make()
        let roster = Self.rosterNeeding(0)
        let shell = ShellPresenter(selected: .invoices, rosterHasWork: { !roster.isSettled })
        let view = RootView(presenter: presenter, store: store, now: { at(11) },
                            roster: roster, shell: shell)
        ViewHosting.host(view: view)
        defer { ViewHosting.expel() }
        #expect(throws: Never.self) { try view.inspect().find(ShellView.self) }

        store.raise(kind: .bookingsDrafted, subject: "booking-queue",
                    sentence: "2 booking(s) from the queue are now drafts.", now: at(12))
        presenter.refresh()

        #expect(throws: Never.self) { try view.inspect().find(ShellView.self) }
        #expect(throws: Never.self) { try view.inspect().find(text: "Bookings drafted") }
        #expect(throws: (any Error).self) { try view.inspect().find(LaunchNoticeView.self) }
    }

    /// THE RUNNING EXPORT STAYS ON SCREEN WITH THE SHELL. Its progress lived only in
    /// the problems window, which the shell now always replaces, so a year end
    /// export running for minutes would have shown nothing at all: started, still
    /// alive and finished would look the same. It is a live line at the foot of the
    /// rail while it runs; its outcome then arrives there as a notice.
    @Test("a running export's progress is on screen with the shell")
    func aRunningExportIsOnScreenWithTheShell() throws {
        let (store, presenter) = make()
        let roster = Self.rosterNeeding(0)
        let shell = ShellPresenter(selected: .invoices, rosterHasWork: { !roster.isSettled })
        let command = YearEndExportCommand(directory: nil, runRecord: nil)
        command.began(at: at(10))

        let view = RootView(presenter: presenter, store: store, now: { at(11) },
                            exportCommand: command, roster: roster, shell: shell)

        let shellView = try view.inspect().find(ShellView.self)
        let running = try shellView.find(RunningExportView.self).actualView()
        #expect(running.sentence(at: at(22)) == "Exporting the year. 12s so far.")
        // A quiet day otherwise: nothing open, so no Read, but the export is said.
        #expect(throws: (any Error).self) { try shellView.find(button: RailFoot.readWord) }
    }

    @Test("with no export running, the shell draws no export line")
    func noExportRunningNoLine() throws {
        let (store, presenter) = make()
        let roster = Self.rosterNeeding(0)
        let shell = ShellPresenter(selected: .invoices, rosterHasWork: { !roster.isSettled })
        let command = YearEndExportCommand(directory: nil, runRecord: nil)

        let view = RootView(presenter: presenter, store: store, now: { at(11) },
                            exportCommand: command, roster: roster, shell: shell)

        #expect(throws: Never.self) { try view.inspect().find(ShellView.self) }
        #expect(throws: (any Error).self) { try view.inspect().find(RunningExportView.self) }
    }

    /// The problems window is still what a launch with NO store gets, where there is
    /// no shell to carry anything, or its refusal would reach nobody (ovation#59).
    @Test("with no shell, the notice window is still what shows")
    func noShellStillShowsTheNotice() throws {
        let (store, presenter) = make()
        store.raise(kind: .foreignStore, subject: "s",
                    sentence: "The database belongs to another app.", now: at(10))
        presenter.refresh()

        let view = RootView(presenter: presenter, store: store, now: { at(11) })

        #expect(throws: Never.self) { try view.inspect().find(LaunchNoticeView.self) }
        #expect(throws: (any Error).self) { try view.inspect().find(ShellView.self) }
    }

    private static func rosterNeeding(_ count: Int) -> RosterPresenter {
        var clients: [Client] = []
        for i in 0..<count {
            let c = Client(name: "Client \(i)", taxStatus: .neverRecorded)
            c.email = "c\(i)@example.example"
            clients.append(c)
        }
        return RosterPresenter(clients: clients, write: { _, _ in })
    }
}

