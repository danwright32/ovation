import Foundation
import Testing

/// ovation#40, PRD 44a and 5a. What is in the rail, and what happens to a place
/// that empties while you are standing in it.
///
/// TWO RULES SETTLED ON 2026-09-07 AND NEITHER IS EXPRESSIBLE WITHOUT A RAIL,
/// which is why PRD 44a ships one with the first screen rather than after it.
/// The roster is a PLACE, it is there only while it has something in it, and it
/// does not vanish underneath somebody who is standing on it. Answering the last
/// question is the moment Dan most deserves to be told he finished and the worst
/// possible moment for the screen to disappear.
///
/// BOTH DIRECTIONS ARE ASSERTED. A rule about something being ABSENT is
/// satisfied by a rail that holds nothing at all (L98, L159), so every test that
/// expects the roster to be gone is paired with one that expects it present.
@MainActor
struct ShellPresenterTests {

    @Test("the roster is in the rail while something blocks a send")
    func rosterIsThereWhileSomethingBlocks() {
        let shell = ShellPresenter(selected: .invoices, rosterHasWork: { true })
        #expect(shell.destinations.contains(.roster))
    }

    @Test("the roster is gone from the rail once nothing blocks and you are elsewhere")
    func rosterLeavesWhenEmptyAndYouAreElsewhere() {
        let shell = ShellPresenter(selected: .invoices, rosterHasWork: { false })
        #expect(!shell.destinations.contains(.roster))
    }

    /// The exception, and it is the whole reason this is a presenter rather than
    /// a filter on a list.
    @Test("the roster stays in the rail when it empties while you are standing on it")
    func rosterStaysUnderYou() {
        var hasWork = true
        let shell = ShellPresenter(selected: .roster, rosterHasWork: { hasWork })
        #expect(shell.destinations.contains(.roster))

        hasWork = false
        #expect(shell.destinations.contains(.roster))
    }

    /// THE RULE IS IMPLEMENTED AND TODAY IT IS DORMANT, which is recorded here
    /// rather than discovered later. `roster` is the only destination that is
    /// BUILT, and `go(to:)` refuses an unbuilt one, so nothing in the running
    /// app can navigate away from the roster and its entry can never actually
    /// leave the rail. The rule still has to be right, because the day a second
    /// screen ships it starts firing.
    ///
    /// **It FIRED, on 2026-09-20 (ovation#49)**, which is what it was for. The
    /// question it made somebody answer, what the window shows once the roster has
    /// settled and gone, turned out to have been answered already:
    /// `RosterLaunch.presenters` opens on `.invoices` whenever the roster has
    /// nothing to ask, and since ovation#298 the live roster never has. So the
    /// window has been opening on the invoice list all along and the list was what
    /// was missing.
    ///
    /// IT IS INVERTED RATHER THAN DELETED OR SOFTENED. The rule it was dormant
    /// about is live now, so what it asserts is that the leaving rule can fire and
    /// that the two screens still unbuilt cannot select (L252, L430).
    @Test("the invoice list is built, so the leaving rule can now actually fire")
    func theLeavingRuleCanNowFire() {
        #expect(Destination.allCases.filter(\.isBuilt) == [.invoices, .roster])

        // The rule firing for real: standing on the list, with nothing blocking,
        // the roster is gone from the rail.
        let shell = ShellPresenter(selected: .invoices, rosterHasWork: { false })
        #expect(!shell.destinations.contains(.roster))
        #expect(shell.selected == .invoices)
    }

    @Test("but the rule itself is right: elsewhere plus nothing blocking means gone")
    func theLeavingRuleIsCorrect() {
        let shell = ShellPresenter(selected: .invoices, rosterHasWork: { false })
        #expect(!shell.destinations.contains(.roster))

        let standing = ShellPresenter(selected: .roster, rosterHasWork: { false })
        #expect(standing.destinations.contains(.roster))
    }

    // MARK: the three that are not built yet

    /// PRD 44a. They are PRESENT and they SAY SO. A destination that is simply
    /// absent teaches nothing, and one that is present and silent is a dead
    /// control nobody can ask about (L49, L109).
    @Test("the two still unbuilt destinations are in the rail and are marked unbuilt")
    func unbuiltDestinationsArePresentAndMarked() {
        let shell = ShellPresenter(selected: .roster, rosterHasWork: { true })

        #expect(shell.destinations.contains(.invoices))
        #expect(shell.destinations.contains(.expenses))
        #expect(shell.destinations.contains(.clients))

        #expect(!Destination.expenses.isBuilt)
        #expect(!Destination.clients.isBuilt)
        #expect(Destination.roster.isBuilt)
        #expect(Destination.invoices.isBuilt)
    }

    /// A rail entry that cannot be reached must not be SELECTABLE, or pressing
    /// it takes Dan to a blank screen and the mark beside it was decoration.
    ///
    /// DRIVEN ON A DESTINATION THAT IS STILL UNBUILT. It used to press `.invoices`,
    /// which is now built, and a test proving a refusal has to be driven on a case
    /// that is actually refused or it proves the opposite by accident (L159).
    @Test("pressing a destination that is not built does not move you")
    func pressingAnUnbuiltDestinationDoesNothing() {
        let shell = ShellPresenter(selected: .roster, rosterHasWork: { true })

        shell.go(to: .expenses)

        #expect(shell.selected == .roster)
    }

    @Test("and pressing one that IS built moves you")
    func pressingABuiltDestinationMoves() {
        // The positive control for the test above: without it, a `go(to:)` that
        // refused everything would pass it (L159).
        let shell = ShellPresenter(selected: .roster, rosterHasWork: { true })

        shell.go(to: .invoices)

        #expect(shell.selected == .invoices)
    }

    @Test("every destination has a name, and no two share one")
    func everyDestinationIsNamedOnce() {
        let names = Destination.allCases.map(\.title)
        #expect(names.count == Destination.allCases.count)
        #expect(Set(names).count == names.count)
        // Computed outside the macro: `#expect` rewrites `contains(where:)`
        // into a rethrowing call and then needs a `try` it cannot have.
        let anyBlank = names.contains { $0.isEmpty }
        #expect(!anyBlank)
    }
}
