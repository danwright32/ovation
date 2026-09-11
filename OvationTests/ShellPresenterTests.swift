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
    /// **This test FAILS the day a second destination is built**, on purpose. It
    /// is the only thing that makes whoever builds it answer the question this
    /// round did not: what the window shows once the roster has settled and
    /// gone. A rule that is correct and unreachable is exactly the kind that
    /// ships wrong (L535).
    @Test("the roster is still the only built destination, so the leaving rule cannot yet fire")
    func theLeavingRuleIsDormantBecauseNothingElseIsBuilt() {
        #expect(Destination.allCases.filter(\.isBuilt) == [.roster])
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
    @Test("the three unbuilt destinations are in the rail and are marked unbuilt")
    func unbuiltDestinationsArePresentAndMarked() {
        let shell = ShellPresenter(selected: .roster, rosterHasWork: { true })

        #expect(shell.destinations.contains(.invoices))
        #expect(shell.destinations.contains(.expenses))
        #expect(shell.destinations.contains(.clients))

        #expect(!Destination.invoices.isBuilt)
        #expect(!Destination.expenses.isBuilt)
        #expect(!Destination.clients.isBuilt)
        #expect(Destination.roster.isBuilt)
    }

    /// A rail entry that cannot be reached must not be SELECTABLE, or pressing
    /// it takes Dan to a blank screen and the mark beside it was decoration.
    @Test("pressing a destination that is not built does not move you")
    func pressingAnUnbuiltDestinationDoesNothing() {
        let shell = ShellPresenter(selected: .roster, rosterHasWork: { true })

        shell.go(to: .invoices)

        #expect(shell.selected == .roster)
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
