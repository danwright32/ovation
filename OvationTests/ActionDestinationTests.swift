import Foundation
import Testing

/// ovation#450. Which of the invoice list's action words has somewhere to go.
///
/// EIGHT WORDS WERE DRAWN AS CONTROLS AND NONE OF THEM DID WHAT THE WORD SAID.
/// That is worse than a greyed control, because it does not look disabled: it
/// looks exactly like the live control it will become, and a dead control with
/// no reason beside it is one somebody presses repeatedly and then works around
/// (L109, L148). The list is also the first screen the app opens on.
///
/// THE ANSWER IS ONE DERIVATION, read both by whether the word is drawn as a
/// control and by what pressing it does, so the two cannot disagree (L70).
struct ActionDestinationTests {

    /// THE ONE THAT IS LIVE, and it is live for a reason that can be checked:
    /// the invoice screen is what the list already opens on a tap, and typing
    /// the shoot's times is what that screen offers (ovation#467).
    @Test("Add hours goes to the invoice screen, which is the screen that types them")
    func addhoursGoesToTheInvoiceScreen() {
        #expect(InvoiceListPresenter.Action.destination(of: InvoiceListPresenter.Action.addHours)
                    == .theInvoiceScreen)
    }

    /// ovation#471. THE WORD FOR A SEND OVATION COULD NOT SETTLE is the one thing
    /// Dan may do about it, clear it, and pressing it settles the send in place
    /// after he confirms, rather than going to a screen.
    @Test("Mark unsent settles the send in place, and counts under To confirm")
    func markunsentSettlesTheSend() {
        let word = InvoiceListPresenter.Action.markUnsent
        #expect(word == "Mark unsent")
        #expect(InvoiceListPresenter.Action.destination(of: word) == .settleTheSend)
        #expect(InvoiceListPresenter.cardLine(for: word) == "To confirm")
    }

    /// AND EVERY OTHER WORD HAS NOWHERE TO GO TODAY. Enumerated from the same
    /// list the words themselves come from, so a word added later is answered
    /// here rather than taking a default that reads as a considered decision
    /// (L41, L113).
    @Test("every other word has nowhere to go, and is enumerated rather than assumed")
    func everyotherWordHasNowhereToGo() {
        let live = [InvoiceListPresenter.Action.addHours, InvoiceListPresenter.Action.markUnsent]
        let expected = Set(InvoiceListPresenter.Action.all).subtracting(live)

        let nowhere = Set(InvoiceListPresenter.Action.all
            .filter { InvoiceListPresenter.Action.destination(of: $0) == nil })

        #expect(nowhere == expected, "\(nowhere.symmetricDifference(expected)) disagrees")
    }

    /// AND THE WORDS THEMSELVES ARE UNCHANGED, which is the constraint ovation#450
    /// names in as many words. PRD 46a counts the list's rows BY their action, so
    /// the sidebar card's five counts come off exactly these strings: a word
    /// softened into "Add hours when you can" would silently move a count (L683).
    @Test("the eight words are exactly the eight the sidebar card counts by")
    func thewordsAreUnchanged() {
        #expect(InvoiceListPresenter.Action.all == [
            "Send", "Remind", "Mark cleared", "Mark unsent",
            "Use it here", "Add date", "Add hours", "Add tax status",
        ])
    }

    /// A WORD NOBODY DEFINED IS NOT LIVE. The lookup is over strings, so a typo
    /// at a call site must read as nowhere to go rather than as the live case,
    /// which would put back the dead control this exists to remove (L42).
    @Test("a word that is not one of the eight has nowhere to go", arguments: [
        "", "add hours", "Add Hours", "Add hours ", "Open",
    ])
    func anunknownWordIsNotLive(word: String) {
        #expect(InvoiceListPresenter.Action.destination(of: word) == nil)
    }
}
