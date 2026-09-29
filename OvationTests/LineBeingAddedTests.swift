import Foundation
import SwiftData
import Testing

/// ovation#489, PRD 51p to 51t. A line being added, as one value, so every rule
/// Dan settled on 2026-09-29 is a case rather than a behaviour only a window can
/// show (L442).
@MainActor
struct LineBeingAddedTests {

    /// HELD FOR THE WHOLE CASE, because a choice carries the identity of a type
    /// the store made, and the store has to outlive it.
    private let context: ModelContext

    init() throws {
        context = ModelContext(try OvationSchema.container(inMemory: true))
    }

    private func type(_ name: String, _ usually: Money?) -> InvoiceScreenPresenter.ServiceChoice {
        let made = ServiceType(name: name, role: .ordinary, defaultUnitAmount: usually)
        context.insert(made)
        return InvoiceScreenPresenter.ServiceChoice(id: made.persistentModelID,
                                                    name: name, usually: usually)
    }

    private var rush: InvoiceScreenPresenter.ServiceChoice { type("Rush turnaround", Money(dollars: 150)) }
    private var preview: InvoiceScreenPresenter.ServiceChoice { type("Preview images", nil) }
    private var travel: InvoiceScreenPresenter.ServiceChoice { type("Travel", Money(dollars: 40)) }

    // MARK: choosing, and choosing again (Dan, 2026-09-29, PRD 51r)

    /// A NEW ROW HAS NO TYPE AND NO AMOUNT, and a figure nobody gave it is never
    /// drawn as one (PRD 5.1b).
    @Test("a new line has no type, no amount and no open list")
    func anewLineIsEmpty() {
        let line = LineBeingAdded()

        #expect(line.chosen == nil)
        #expect(line.amount == "")
        #expect(line.listIsOpen == false)
    }

    @Test("the first type chosen fills in its usual amount, and one with none leaves it empty")
    func thefirstTypeFillsItsUsual() {
        var withUsual = LineBeingAdded()
        withUsual.choose(rush)
        var withNone = LineBeingAdded()
        withNone.choose(preview)

        #expect(withUsual.amount == "150.00")
        #expect(withNone.amount == "")
    }

    /// WHILE THE AMOUNT IS STILL THE OLD TYPE'S USUAL ONE, IT GOES WITH THE OLD
    /// TYPE: it was never Dan's figure, and keeping it would price the new line at
    /// the wrong type's rate.
    @Test("changing the type replaces an amount that is still the old type's usual one")
    func changingReplacesAnUntouchedAmount() {
        var line = LineBeingAdded()
        line.choose(rush)
        line.choose(travel)
        #expect(line.amount == "40.00")

        line.choose(preview)
        #expect(line.amount == "", "a type with no usual amount leaves nothing behind")

        line.choose(rush)
        #expect(line.amount == "150.00", "an empty field was the last type's usual, so it is replaced")
        #expect(line.chosen?.name == "Rush turnaround")
    }

    /// AN AMOUNT DAN TYPED HIMSELF IS KEPT, which is the other half of PRD 51r.
    @Test("changing the type keeps an amount typed by hand", arguments: ["175", "175.00", "0", "abc"])
    func changingKeepsATypedAmount(typed: String) {
        var line = LineBeingAdded()
        line.choose(rush)
        line.amount = typed

        line.choose(preview)

        #expect(line.amount == typed)
        #expect(line.chosen?.name == "Preview images")
    }

    /// THE COMPARISON IS OF WHAT THE FIGURES SAY, NOT HOW THEY ARE SPELLED, so
    /// retyping the usual amount as `150` is still the usual amount.
    @Test("the usual amount retyped in another spelling is still the usual amount")
    func theusualRetypedIsStillUsual() {
        var line = LineBeingAdded()
        line.choose(rush)
        line.amount = "$150"

        line.choose(travel)

        #expect(line.amount == "40.00")
    }

    /// AN AMOUNT TYPED BEFORE ANY TYPE WAS CHOSEN IS DAN'S TOO, so choosing the
    /// type does not overwrite it.
    @Test("an amount typed before the type is chosen is kept")
    func anamountTypedFirstIsKept() {
        var line = LineBeingAdded()
        line.amount = "90"

        line.choose(rush)

        #expect(line.amount == "90")
    }

    @Test("choosing a type closes the list")
    func choosingClosesTheList() {
        var line = LineBeingAdded()
        line.listIsOpen = true

        line.choose(rush)

        #expect(line.listIsOpen == false)
    }

    // MARK: Escape (PRD 51s)

    /// THE FIRST PRESS CLOSES THE LIST AND THE SECOND CANCELS THE LINE, which is
    /// the order a person backs out of anything: the innermost thing first.
    @Test("Escape with the list open closes the list, and a second Escape cancels the line")
    func escapeTwice() {
        var line = LineBeingAdded()
        line.choose(rush)
        line.listIsOpen = true

        #expect(line.escape() == .listClosed)
        #expect(line.listIsOpen == false)
        #expect(line.chosen?.name == "Rush turnaround", "closing the list undid the choice")
        #expect(line.escape() == .lineCancelled)
    }

    @Test("Escape with the list shut cancels the line at once")
    func escapeWithTheListShut() {
        var line = LineBeingAdded()

        #expect(line.escape() == .lineCancelled)
    }

    // MARK: what is written (PRD 51q)

    @Test("a chosen type and a readable amount make the line to write")
    func areadableLineIsWritten() throws {
        let chosen = rush
        var line = LineBeingAdded()
        line.choose(chosen)
        line.amount = "175.50"

        let written = try #require(line.written)

        #expect(written.type == chosen.id)
        #expect(written.amount == Money(cents: 17_550))
    }

    /// AN AMOUNT IT CANNOT READ WRITES NOTHING, and a zero it can read is a
    /// legitimate comped line rather than nothing (PRD 5.1b).
    @Test("nothing is written without a type or with an amount it cannot read")
    func nothingUnreadableIsWritten() {
        var noType = LineBeingAdded()
        noType.amount = "175"
        var unreadable = LineBeingAdded()
        unreadable.choose(preview)
        unreadable.amount = "about 90"
        var empty = LineBeingAdded()
        empty.choose(preview)
        var comped = LineBeingAdded()
        comped.choose(preview)
        comped.amount = "0"

        #expect(noType.written == nil)
        #expect(unreadable.written == nil)
        #expect(empty.written == nil)
        #expect(comped.written?.amount == Money.zero)
    }

    /// LEAVING THE FIELD FOR THE ROW'S OWN TYPE LIST IS NOT LEAVING THE LINE. The
    /// list opens from the row, and a blur there that committed would write the
    /// line at the moment Dan was changing its type, which is PRD 51r made
    /// unreachable by PRD 51q.
    @Test("leaving the field commits, except while the row's own list is open")
    func leavingTheFieldCommitsUnlessTheListIsOpen() {
        var line = LineBeingAdded()
        line.choose(rush)
        #expect(line.leavingTheFieldCommits)

        line.listIsOpen = true
        #expect(line.leavingTheFieldCommits == false)
    }
}
