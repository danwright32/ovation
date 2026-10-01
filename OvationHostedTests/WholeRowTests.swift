import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Ovation

/// ovation#615. A row answers a click anywhere on it, not only on its words.
///
/// Dan, 2026-09-28: the rail's rows only responded with the pointer over the
/// words. A plain style button hit tests only what its label paints, and a row
/// whose background is clear paints nothing to the right of its title, so a click
/// there went nowhere and said nothing.
///
/// EVERY CASE PRESSES WHERE THE WORDS ARE NOT, through a real window (`RealClick`),
/// because a view tree `tap()` calls the action directly and passes whether the
/// click would have landed or not. And the harness is shown to tell the two apart
/// before any row is judged by it: a plain button's empty end must NOT answer, or
/// a green here would mean only that every click lands (L1, L159).
///
/// EVERY CASE HAS A TIME LIMIT. On the CI runner this branch's macOS job went
/// silent for its whole hour in the hosted suite, twice, and this is the only
/// suite that sends mouse events. A real click that is never answered waits with
/// no deadline (L110), and a suite that hangs says nothing about which case did.
/// One minute is the smallest limit Swift Testing allows, and every case here
/// takes well under a second.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WholeRowTests {

    /// A value a binding can write into and a test can read back.
    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    /// A row the way the defect drew one: words at the leading edge, the rest of
    /// its width clear.
    private static func row(_ words: String) -> some View {
        Text(words)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The one row's words and its clear end, in a 240 by 40 window.
    private static let onTheWords = NSPoint(x: 14, y: 20)
    private static let atTheClearEnd = NSPoint(x: 234, y: 20)

    private static func hostRow(_ button: some View) -> NSWindow {
        RealClick.host(button, size: CGSize(width: 240, height: 40))
    }

    // MARK: the harness can see the defect

    @Test("a plain button's words answer a real click, so the harness delivers one")
    func aplainButtonsWordsAnswer() {
        var pressed = 0
        let window = Self.hostRow(Button { pressed += 1 } label: { Self.row("Invoices") }
            .buttonStyle(.plain))
        defer { window.close() }

        RealClick.click(at: Self.onTheWords, in: window)

        #expect(pressed == 1, "a click on the words did nothing, so no case below can be believed")
    }

    @Test("and its clear end does not, which is the defect this suite exists to catch")
    func aplainButtonsClearEndDoesNotAnswer() {
        var pressed = 0
        let window = Self.hostRow(Button { pressed += 1 } label: { Self.row("Invoices") }
            .buttonStyle(.plain))
        defer { window.close() }

        RealClick.click(at: Self.atTheClearEnd, in: window)

        #expect(pressed == 0, "the clear end answered, so this harness cannot see the defect")
    }

    // MARK: the component

    @Test("a button styled WholeTarget answers on its clear end")
    func wholeTargetAnswersOnItsClearEnd() {
        var pressed = 0
        let window = Self.hostRow(Button { pressed += 1 } label: { Self.row("Invoices") }
            .buttonStyle(WholeTarget(RoundedRectangle(cornerRadius: 5))))
        defer { window.close() }

        RealClick.click(at: Self.atTheClearEnd, in: window)

        #expect(pressed == 1)
    }

    /// WHAT THE ROW ALLOWS IS UNCHANGED (ovation#615): a disabled row takes a click
    /// anywhere on it and does nothing, as it did on its words before.
    @Test("and a disabled one still does nothing, wherever it is pressed")
    func aDisabledWholeTargetDoesNothing() {
        var pressed = 0
        let window = Self.hostRow(Button { pressed += 1 } label: { Self.row("Expenses") }
            .buttonStyle(WholeTarget()).disabled(true))
        defer { window.close() }

        RealClick.click(at: Self.atTheClearEnd, in: window)
        RealClick.click(at: Self.onTheWords, in: window)

        #expect(pressed == 0)
    }

    // MARK: the rows in the app

    /// Where the rail's words start and where its rows end, from the rail's own
    /// width and inset, so a change to either moves these with it.
    private static let railWords = RailFoot.railInset + 16
    private static let railRowEnd = OvationWindow.railWidth - RailFoot.railInset - 4

    /// Every destination the rail's rows reach from clicks down one line.
    private static func railReached(atX x: CGFloat) -> Set<Destination> {
        let shell = ShellPresenter(selected: .roster, rosterHasWork: { true })
        let roster = RosterPresenter(clients: [Client(name: "Client 0", taxStatus: .neverRecorded)],
                                     write: { _, _ in })
        let view = ShellView(shell: shell, roster: roster,
                             problems: ProblemsStore(journal: InMemoryProblemsJournal()))
        let window = RealClick.host(view, size: CGSize(width: 1100, height: 720))
        defer { window.close() }
        var reached: Set<Destination> = []
        // The title bar, the card and the rows, and not the foot, whose words
        // are controls of their own.
        RealClick.sweep(x: x, in: window, toTop: 360) { reached.insert(shell.selected) }
        return reached
    }

    /// The case Dan reported: a row that is not the current destination has a
    /// clear background, and it did not answer beside its title.
    @Test("the rail's rows answer a click at their far end")
    func theRailRowsAnswerAtTheirFarEnd() {
        let reached = Self.railReached(atX: Self.railRowEnd)

        #expect(reached.isSuperset(of: [.invoices, .clients]), "reached only \(reached)")
    }

    @Test("and on their words, so the line the far end is swept on is the rows' line")
    func theRailRowsAnswerOnTheirWords() {
        let reached = Self.railReached(atX: Self.railWords)

        #expect(reached.isSuperset(of: [.invoices, .clients]), "reached only \(reached)")
    }

    @Test("a name on the Clients screen answers a click at the far end of its row")
    func aclientNameAnswersAtItsFarEnd() throws {
        let (clients, _) = try ClientsViewTests.population()
        let chosen = Box<UUID?>(try ClientsViewTests.id(of: "Harborlight Ballet", in: clients))
        let view = ClientsView(presenter: ClientsPresenter(clients: clients),
                               selected: chosen.binding)
        let window = RealClick.host(view, size: CGSize(width: 1100, height: 1000))
        defer { window.close() }

        var reached: Set<UUID> = []
        let sent = RealClick.sweep(x: ClientsView.namesWidth - 8, in: window, step: 4) {
            if let id = chosen.value { reached.insert(id) }
        }

        // Three of the 31 draw a held figure at that end, and a click on a figure
        // answered even before; the rest are the rows whose far end was dead.
        // THE MESSAGE SAYS WHAT THE CLICKS MET (review of #644): on the CI runner
        // not one landed while every other sweep did, and this is the only one
        // through a scroll view, so a failure reports how many releases something
        // else took and the size the window was really given.
        #expect(reached.count >= 20, """
            only \(reached.count) names answered at the far end; \(sent.releasesTaken) of \
            \(sent.clicks) releases were taken before the click could deliver them, in a \
            content area of \(window.contentView?.bounds.size ?? .zero)
            """)
    }

    /// The list is as wide as its widest entry or its minimum, and a short entry
    /// is a row of that list: a click to the right of its words is on it.
    @Test("a popup list's short entries answer a click at the list's far edge")
    func apopupsEntriesAnswerAtTheListsEdge() {
        var taken: Set<String> = []
        var asked = 0
        let list = PopupList(choices: [PopupList.Choice(id: "rush", says: "Rush")],
                             asks: "New type...", ask: { asked += 1 },
                             choose: { taken.insert($0.id) })
        let window = RealClick.host(list, size: CGSize(width: 186, height: 120))
        defer { window.close() }

        RealClick.sweep(x: 180, in: window, step: 2) {}

        #expect(taken == ["rush"], "the choice did not answer at the list's edge")
        #expect(asked > 0, "the trailing entry did not answer at the list's edge")
    }

    @Test("and on their words, so the edge is swept across the entries")
    func apopupsEntriesAnswerOnTheirWords() {
        var taken: Set<String> = []
        var asked = 0
        let list = PopupList(choices: [PopupList.Choice(id: "rush", says: "Rush")],
                             asks: "New type...", ask: { asked += 1 },
                             choose: { taken.insert($0.id) })
        let window = RealClick.host(list, size: CGSize(width: 186, height: 120))
        defer { window.close() }

        RealClick.sweep(x: 22, in: window, step: 2) {}

        #expect(taken == ["rush"])
        #expect(asked > 0)
    }
}
