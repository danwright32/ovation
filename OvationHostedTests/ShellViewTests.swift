import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#40, PRD 44a. The rail that ships with the first screen, rendered.
///
/// THE RAIL IS WHERE TWO SETTLED RULES LIVE, so it is asserted here rather than
/// only in the presenter: what a rule COMPUTES and what a person SEES are two
/// testable surfaces and a screen can be wrong while the value is right (L442).
@MainActor
struct ShellViewTests {

    private static func noProblems() -> ProblemsStore {
        ProblemsStore(journal: InMemoryProblemsJournal())
    }

    private static func roster(blocking: Int) -> RosterPresenter {
        var clients: [Client] = []
        for i in 0..<blocking {
            let c = Client(name: "Client \(i)", taxStatus: .neverRecorded)
            c.email = "c\(i)@example.example"
            clients.append(c)
        }
        return RosterPresenter(clients: clients, save: {})
    }

    @Test("the rail draws the three destinations that are not built yet")
    func theRailDrawsTheUnbuiltThree() throws {
        let view = ShellView(shell: ShellPresenter(selected: .roster, rosterHasWork: { true }),
                             roster: Self.roster(blocking: 25),
                             problems: Self.noProblems())

        for name in ["Invoices", "Expenses", "Clients"] {
            #expect(throws: Never.self) {
                try view.inspect().find(text: name)
            }
        }
    }

    /// PRD 44a. Present AND marked. A destination present and silent is a dead
    /// control nobody can ask about (L49, L109).
    @Test("each unbuilt destination carries the mark that says so")
    func eachUnbuiltDestinationIsMarked() throws {
        let view = ShellView(shell: ShellPresenter(selected: .roster, rosterHasWork: { true }),
                             roster: Self.roster(blocking: 25),
                             problems: Self.noProblems())

        let marks = try view.inspect().findAll(ViewType.Text.self).filter {
            (try? $0.string()) == ShellView.notBuiltMark
        }
        #expect(marks.count == 3)
    }

    @Test("the roster is in the rail while something blocks")
    func rosterIsInTheRailWhileSomethingBlocks() throws {
        let view = ShellView(shell: ShellPresenter(selected: .invoices, rosterHasWork: { true }),
                             roster: Self.roster(blocking: 25),
                             problems: Self.noProblems())

        #expect(throws: Never.self) {
            try view.inspect().find(text: Destination.roster.title)
        }
    }

    @Test("and it is not drawn once nothing blocks and you are elsewhere")
    func rosterIsNotDrawnWhenEmptyAndElsewhere() throws {
        let view = ShellView(shell: ShellPresenter(selected: .invoices, rosterHasWork: { false }),
                             roster: Self.roster(blocking: 0),
                             problems: Self.noProblems())

        #expect(throws: (any Error).self) {
            try view.inspect().find(text: Destination.roster.title)
        }
        // The rail really is drawn, so the absence above means something (L98).
        #expect(throws: Never.self) {
            try view.inspect().find(text: "Invoices")
        }
    }

    /// PRD 46b. The card's promise is that a number in it means this many things
    /// need you, and on day one nothing does, so it says that rather than
    /// borrowing another screen's fixture counts.
    @Test("the card says nothing is waiting rather than drawing counts nothing can produce")
    func theCardSaysNothingIsWaiting() throws {
        let view = ShellView(shell: ShellPresenter(selected: .roster, rosterHasWork: { true }),
                             roster: Self.roster(blocking: 25),
                             problems: Self.noProblems())

        #expect(throws: Never.self) {
            try view.inspect().find(text: "Nothing waiting")
        }
    }

    // MARK: the status block, which is where a launch notice lands in the shell

    /// THE SHELL REPLACES THE WINDOW, so anything the window used to carry has
    /// to be somewhere here or it is simply gone. `RootView` is where every
    /// launch time condition reaches Dan (ovation#59), and the design puts that
    /// at the foot of the rail. Without this the first screen would silently
    /// swallow a foreign store, a failed backup and a stale export (L242, L98).
    @Test("an open problem is said at the foot of the rail")
    func anOpenProblemIsSaidInTheRail() throws {
        let problems = ProblemsStore(journal: InMemoryProblemsJournal())
        _ = problems.raise(kind: .backupFailed, subject: "b",
                           sentence: "Ovation has not backed up for 3 days.", now: Date())

        let view = ShellView(shell: ShellPresenter(selected: .roster, rosterHasWork: { true }),
                             roster: Self.roster(blocking: 25),
                             problems: problems)

        #expect(throws: Never.self) {
            try view.inspect().find(text: "Ovation has not backed up for 3 days.")
        }
    }

    @Test("the ones behind it are counted, and only when there are some")
    func theOthersAreCountedWhenThereAreSome() throws {
        let problems = ProblemsStore(journal: InMemoryProblemsJournal())
        _ = problems.raise(kind: .backupFailed, subject: "b", sentence: "the first", now: Date())
        _ = problems.raise(kind: .foreignStore, subject: "s", sentence: "the second", now: Date())

        let view = ShellView(shell: ShellPresenter(selected: .roster, rosterHasWork: { true }),
                             roster: Self.roster(blocking: 25),
                             problems: problems)

        #expect(throws: Never.self) {
            try view.inspect().find(text: "1 other problem")
        }
    }

    /// The zero rule again, and the fifth surface it now applies to. `0 other
    /// problems` is noise, and a healthy rail says nothing rather than saying
    /// nothing is wrong in a place reserved for things that are.
    @Test("a rail with nothing wrong says nothing at all about problems")
    func aHealthyRailIsSilent() throws {
        let problems = ProblemsStore(journal: InMemoryProblemsJournal())
        _ = problems.raise(kind: .backupFailed, subject: "b", sentence: "the only one", now: Date())

        let view = ShellView(shell: ShellPresenter(selected: .roster, rosterHasWork: { true }),
                             roster: Self.roster(blocking: 25),
                             problems: problems)

        #expect(throws: (any Error).self) {
            try view.inspect().find(text: "0 other problems")
        }
        // It really did draw the one, so the absence above means something (L98).
        #expect(throws: Never.self) {
            try view.inspect().find(text: "the only one")
        }
    }
}

