// ovation#40, PRD 44a. The rail, and what is in it.
//
// THE RAIL SHIPS WITH THE FIRST SCREEN, chosen by Dan on 2026-09-11 in a round
// that drew all three options at the real count: the pass alone in the window,
// the rail with three placeholders, and the rail with the Clients screen
// finished beside it. He took the middle one. Three of the four entries lead
// nowhere for months, which is the stated cost.
//
// WHAT IT BUYS IS THAT TWO SETTLED RULES HAVE SOMEWHERE TO BE TRUE. PRD 5a says
// the roster is a PLACE, there only while it has something in it, and that it
// does not vanish underneath somebody standing on it. Neither is expressible in
// a window with no rail, so building the pass without one would have quietly
// dropped both.
import Foundation

/// Where Ovation can put you. One case per rail entry, and the rail is derived
/// from this rather than written beside it, so an entry cannot exist without a
/// destination behind it (L41).
enum Destination: String, CaseIterable, Hashable, Sendable {
    case invoices
    case expenses
    case clients
    case roster

    /// What the rail calls it. One vocabulary, read by the rail and by the
    /// screen's own heading, so the two cannot drift apart.
    var title: String {
        switch self {
        case .invoices: return "Invoices"
        case .expenses: return "Expenses"
        case .clients: return "Clients"
        case .roster: return "Settle the roster"
        }
    }

    /// Whether there is a screen behind it yet.
    ///
    /// THE UNBUILT ONES ARE PRESENT AND SAY SO (PRD 44a), rather than absent. A
    /// destination that is simply missing teaches nothing about what is coming,
    /// and one that is present and silent is a dead control nobody can ask about
    /// (L49, L109). The mark beside it in the rail is the reason, which is why
    /// pressing one is allowed to do nothing: the answer is already on screen.
    ///
    /// MOVING A CASE TO `true` IS A DECISION, NOT A LINE. `ShellPresenterTests`
    /// asserts that `roster` is still the only one, and it fails the day that
    /// stops being true, on purpose: the roster leaving the rail is unreachable
    /// while nothing else is built, so whoever builds the second screen is the
    /// first person who has to answer what the window shows once the roster has
    /// settled and gone.
    var isBuilt: Bool {
        switch self {
        case .roster: return true
        case .invoices, .expenses, .clients: return false
        }
    }
}

@MainActor
@Observable
final class ShellPresenter {
    /// Where you are. Private to set, because the only way to move is `go(to:)`,
    /// which is where the refusal lives.
    private(set) var selected: Destination

    /// Whether anything is blocking a send. A closure rather than a stored flag
    /// so it is re-read every time the rail is drawn: a value copied in at init
    /// would be true at init and never again (L175).
    private let rosterHasWork: () -> Bool

    init(selected: Destination, rosterHasWork: @escaping () -> Bool) {
        self.selected = selected
        self.rosterHasWork = rosterHasWork
    }

    /// What the rail draws, in order.
    ///
    /// THE ROSTER IS HERE WHILE IT HAS WORK, **OR** WHILE YOU ARE STANDING ON
    /// IT. The second half is Dan's, 2026-09-07: answering the last question is
    /// the moment you most deserve to be told you finished, and the worst
    /// possible moment for the screen to disappear from under you.
    var destinations: [Destination] {
        var items: [Destination] = [.invoices, .expenses, .clients]
        if rosterHasWork() || selected == .roster { items.append(.roster) }
        return items
    }

    /// Move, if there is anywhere to move to.
    ///
    /// A DESTINATION WITH NO SCREEN REFUSES RATHER THAN TAKING YOU TO A BLANK
    /// ONE. It is silent because it does not need to speak: the entry carries
    /// its own reason in the rail beside it.
    func go(to destination: Destination) {
        guard destination.isBuilt else { return }
        selected = destination
    }
}
