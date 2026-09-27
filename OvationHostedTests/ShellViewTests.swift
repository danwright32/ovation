import AppKit
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
        return RosterPresenter(clients: clients, write: { _, _ in })
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
    ///
    /// TWO, NOT THREE, SINCE ovation#49. The invoice list is built, so it no
    /// longer carries the mark, and the count is asserted against the destinations
    /// that are actually unbuilt rather than against a number typed here, which
    /// would have to be edited again for every screen and says nothing about which
    /// ones it counted (L41, L96).
    @Test("each unbuilt destination carries the mark that says so")
    func eachUnbuiltDestinationIsMarked() throws {
        let view = ShellView(shell: ShellPresenter(selected: .roster, rosterHasWork: { true }),
                             roster: Self.roster(blocking: 25),
                             problems: Self.noProblems())

        let marks = try view.inspect().findAll(ViewType.Text.self).filter {
            (try? $0.string()) == ShellView.notBuiltMark
        }
        let unbuilt = ShellPresenter(selected: .roster, rosterHasWork: { true })
            .destinations.filter { !$0.isBuilt }
        #expect(marks.count == unbuilt.count)
        #expect(unbuilt == [.expenses, .clients])
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

    // MARK: the foot of the rail, where every notice and problem is named (ovation#99, #566)

    /// THE SHELL IS THE WINDOW, so anything the old notice window carried has to be
    /// here or it is simply gone (L242, L98). Dan settled its form on 2026-09-26: each
    /// open thing on its own line, a short name with Read beside it, newest first, at
    /// most two, then "and N more". The whole sentence is behind Read.
    private static func shell(_ problems: ProblemsStore,
                              presenter: ShellPresenter = ShellPresenter(
                                  selected: .roster, rosterHasWork: { true })) -> ShellView {
        ShellView(shell: presenter, roster: Self.roster(blocking: 25), problems: problems,
                  now: { Date(timeIntervalSinceReferenceDate: 99) })
    }

    private static func at(_ second: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(second))
    }

    private static func texts(in view: ShellView) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    @Test("an open problem is named at the foot by its short name, with Read beside it")
    func anOpenProblemIsNamedWithRead() throws {
        let problems = Self.noProblems()
        _ = problems.raise(kind: .backupsAreStale, subject: "b",
                           sentence: "Your work on 2026-09-23 is in no backup.", now: Self.at(1))

        let view = Self.shell(problems)

        #expect(throws: Never.self) { try view.inspect().find(text: "Backups are behind") }
        #expect(try view.inspect().findAll(ViewType.Button.self)
                    .filter { (try? $0.labelView().text().string()) == RailFoot.readWord }.count == 1)
        // The sentence is behind Read, not in the rail: that is the decision.
        #expect(throws: (any Error).self) {
            try view.inspect().find(text: "Your work on 2026-09-23 is in no backup.")
        }
    }

    @Test("two open things are each named with their own Read, newest first, and nothing counts them")
    func twoAreEachNamed() throws {
        let problems = Self.noProblems()
        _ = problems.raise(kind: .backupsAreStale, subject: "b", sentence: "older", now: Self.at(1))
        _ = problems.raise(kind: .exportWritten, subject: "year-end-export-2026",
                           sentence: "newer", now: Self.at(2))

        let view = Self.shell(problems)
        let words = try Self.texts(in: view)

        let newer = try #require(words.firstIndex(of: "2026 export written"))
        let older = try #require(words.firstIndex(of: "Backups are behind"))
        #expect(newer < older, "newest first")
        #expect(words.filter { $0 == RailFoot.readWord }.count == 2)
        // The retired counts (Dan, 2026-09-26): neither vocabulary survives.
        #expect(!words.contains { $0.contains("other problem") || $0.contains("more to read") })
    }

    @Test("a third open thing is not named, and the foot says and 1 more")
    func aThirdIsCountedAsMore() throws {
        let problems = Self.noProblems()
        _ = problems.raise(kind: .backupsAreStale, subject: "b", sentence: "one", now: Self.at(1))
        _ = problems.raise(kind: .rosterUnreadable, subject: "r", sentence: "two", now: Self.at(2))
        _ = problems.raise(kind: .exportFailed, subject: "year-end-export-2026",
                           sentence: "three", now: Self.at(3))

        let words = try Self.texts(in: Self.shell(problems))

        #expect(words.contains("2026 export failed"))
        #expect(words.contains("Clients unreadable"))
        #expect(!words.contains("Backups are behind"))
        #expect(words.contains("and 1 more"))
        #expect(words.filter { $0 == RailFoot.readWord }.count == 2)
    }

    /// The zero rule. A rail with nothing open says nothing at all, not even the line
    /// about when Ovation looks, rather than saying nothing is wrong in the one place
    /// reserved for things that are.
    @Test("with nothing open there is no foot at all")
    func nothingOpenNoFoot() throws {
        let problems = Self.noProblems()
        let read = problems.raise(kind: .exportWritten, subject: "year-end-export-2026",
                                  sentence: "done", now: Self.at(1))
        problems.acknowledge(read.id, now: Self.at(2))

        let words = try Self.texts(in: Self.shell(problems))

        #expect(!words.contains(RailFoot.readWord))
        #expect(!words.contains(RailFoot.onlyWhileOpen))
        // It really did draw the rail, so the absence above means something (L98).
        #expect(words.contains("Nothing waiting"))
    }

    @Test("pressing Read opens that thing's sentence, and only that one")
    func pressingReadOpensThatOne() throws {
        let problems = Self.noProblems()
        let older = problems.raise(kind: .backupsAreStale, subject: "b", sentence: "older",
                                   now: Self.at(1))
        _ = problems.raise(kind: .exportWritten, subject: "year-end-export-2026",
                           sentence: "newer", now: Self.at(2))
        let presenter = ShellPresenter(selected: .invoices, rosterHasWork: { false })
        let view = Self.shell(problems, presenter: presenter)

        let reads = try view.inspect().findAll(ViewType.Button.self)
            .filter { (try? $0.labelView().text().string()) == RailFoot.readWord }
        try #require(reads.count == 2)
        try reads[1].tap()

        #expect(presenter.reading == older.id)
        // Nothing else moved: still on the invoice list.
        #expect(presenter.selected == .invoices)
    }

    @Test("what Read opens holds the whole sentence and I have read this, looking like a control")
    func theReadingHoldsTheSentence() throws {
        var done = 0
        let reading = FootReading(sentence: "The 2026 export is written.", done: { done += 1 })

        #expect(throws: Never.self) { try reading.inspect().find(text: "The 2026 export is written.") }
        // Drawn by the product's one control word, so it is underlined at rest (L49).
        let control = try reading.inspect().find(ActionWord.self).actualView()
        #expect(control.word == RailFoot.readIt)
        try reading.inspect().find(button: RailFoot.readIt).tap()
        #expect(done == 1)
    }

    /// The popover is its own window, so the reading it shows is taken from the one
    /// function the popover itself is built from, and its done is pressed.
    @Test("I have read this marks it read and closes the popover; a notice leaves the foot")
    func readingANoticeClosesIt() throws {
        let problems = Self.noProblems()
        let notice = problems.raise(kind: .exportWritten, subject: "year-end-export-2026",
                                    sentence: "The 2026 export is written.", now: Self.at(1))
        let presenter = ShellPresenter(selected: .invoices, rosterHasWork: { false })
        presenter.read(notice.id)
        let view = Self.shell(problems, presenter: presenter)

        let reading = view.reading(for: notice)
        #expect(reading.sentence == "The 2026 export is written.")
        reading.done()

        #expect(presenter.reading == nil)
        #expect(problems.all.first?.acknowledgedAt == Date(timeIntervalSinceReferenceDate: 99))
        #expect(!(try Self.texts(in: Self.shell(problems))).contains("2026 export written"))
    }

    @Test("a standing problem, once read, is still named with its Read")
    func aReadStandingProblemStays() throws {
        let problems = Self.noProblems()
        let standing = problems.raise(kind: .backupsAreStale, subject: "b", sentence: "behind",
                                      now: Self.at(1))
        let presenter = ShellPresenter(selected: .invoices, rosterHasWork: { false })
        presenter.read(standing.id)
        let view = Self.shell(problems, presenter: presenter)

        view.reading(for: standing).done()

        let words = try Self.texts(in: Self.shell(problems))
        #expect(words.contains("Backups are behind"))
        #expect(words.contains(RailFoot.readWord))
    }

    /// ARITHMETIC OVER THE NAME'S WIDTH IS NOT THE LINE'S WIDTH. The first build
    /// passed `RailFootTests`' sum and still cut "2026 export written" short on
    /// screen, because the line spent its gap twice. So each name is laid out in the
    /// line the foot really draws, at its natural width, and held to the column.
    @Test("every short name, laid out in its own line with Read, fits the foot's column")
    func everyLineFitsTheColumn() throws {
        var names = Array(ProblemKind.shortNames.values)
        for yearly in ProblemKind.yearlyShortNames.values {
            names += (2000...2099).map(yearly)
        }
        #expect(names.count > 400)
        let reading = FootReading(sentence: "", done: {})
        let tooWide = names.filter { name in
            let line = RailFootLine(name: name, read: {}, isReading: .constant(false),
                                    reading: reading)
            return NSHostingView(rootView: line.fixedSize()).fittingSize.width > RailFoot.column
        }
        #expect(tooWide.isEmpty, "wider than the \(Int(RailFoot.column)) point column: \(tooWide.sorted())")
    }
}
