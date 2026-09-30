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
@MainActor
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

    // MARK: the harness can see the defect

    @Test("a plain button's words answer a real click, so the harness delivers one")
    func aplainButtonsWordsAnswer() throws {
        var pressed = 0
        let window = RealClick.host(Button { pressed += 1 } label: { Self.row("Invoices") }
            .buttonStyle(.plain), size: CGSize(width: 240, height: 40))
        defer { window.close() }

        let frame = try RealClick.frame(ofButton: "Invoices", in: window)
        RealClick.click(at: RealClick.nearLeadingEnd(of: frame), in: window)

        #expect(pressed == 1, "a click on the words did nothing, so no case below can be believed")
    }

    @Test("and its clear end does not, which is the defect this suite exists to catch")
    func aplainButtonsClearEndDoesNotAnswer() throws {
        var pressed = 0
        let window = RealClick.host(Button { pressed += 1 } label: { Self.row("Invoices") }
            .buttonStyle(.plain), size: CGSize(width: 240, height: 40))
        defer { window.close() }

        let frame = try RealClick.frame(ofButton: "Invoices", in: window)
        #expect(frame.width > 200, "the row was not laid out across the window")
        RealClick.click(at: RealClick.nearTrailingEnd(of: frame), in: window)

        #expect(pressed == 0, "the clear end answered, so this harness cannot see the defect")
    }

    // MARK: the component

    @Test("a button styled WholeTarget answers on its clear end")
    func wholeTargetAnswersOnItsClearEnd() throws {
        var pressed = 0
        let window = RealClick.host(Button { pressed += 1 } label: { Self.row("Invoices") }
            .buttonStyle(WholeTarget(RoundedRectangle(cornerRadius: 5))),
                                    size: CGSize(width: 240, height: 40))
        defer { window.close() }

        let frame = try RealClick.frame(ofButton: "Invoices", in: window)
        RealClick.click(at: RealClick.nearTrailingEnd(of: frame), in: window)

        #expect(pressed == 1)
    }

    /// WHAT THE ROW ALLOWS IS UNCHANGED (ovation#615): a disabled row takes a click
    /// anywhere on it and does nothing, as it did on its words before.
    @Test("and a disabled one still does nothing, wherever it is pressed")
    func aDisabledWholeTargetDoesNothing() throws {
        var pressed = 0
        let window = RealClick.host(Button { pressed += 1 } label: { Self.row("Expenses") }
            .buttonStyle(WholeTarget()).disabled(true), size: CGSize(width: 240, height: 40))
        defer { window.close() }

        let frame = try RealClick.frame(ofButton: "Expenses", in: window)
        RealClick.click(at: RealClick.nearTrailingEnd(of: frame), in: window)
        RealClick.click(at: RealClick.nearLeadingEnd(of: frame), in: window)

        #expect(pressed == 0)
    }

    // MARK: the rows in the app

    /// The case Dan reported. Invoices is not the current destination, so its
    /// background is clear, which is exactly the row that did not answer.
    @Test("the rail's row answers a click on its clear end")
    func theRailRowAnswersOnItsClearEnd() throws {
        let shell = ShellPresenter(selected: .roster, rosterHasWork: { true })
        let roster = RosterPresenter(clients: [Client(name: "Client 0", taxStatus: .neverRecorded)],
                                     write: { _, _ in })
        let view = ShellView(shell: shell, roster: roster,
                             problems: ProblemsStore(journal: InMemoryProblemsJournal()))
        let window = RealClick.host(view, size: CGSize(width: 1100, height: 720))
        defer { window.close() }

        let frame = try RealClick.frame(ofButton: Destination.invoices.title, in: window)
        RealClick.click(at: RealClick.nearTrailingEnd(of: frame), in: window)

        #expect(shell.selected == .invoices)
    }

    @Test("a name on the Clients screen answers a click beside it")
    func aclientNameAnswersBesideIt() throws {
        let (clients, _) = try ClientsViewTests.population()
        let chosen = Box<UUID?>(try ClientsViewTests.id(of: "Harborlight Ballet", in: clients))
        let view = ClientsView(presenter: ClientsPresenter(clients: clients),
                               selected: chosen.binding)
        let window = RealClick.host(view, size: CGSize(width: 1100, height: 1000))
        defer { window.close() }

        // A client holding nothing, so nothing is drawn at the row's far end.
        let frame = try RealClick.frame(ofButton: "Kestrel Lane Quartet", in: window)
        RealClick.click(at: RealClick.nearTrailingEnd(of: frame), in: window)

        #expect(chosen.value == (try ClientsViewTests.id(of: "Kestrel Lane Quartet", in: clients)))
    }

    /// The list is as wide as its widest entry or its minimum, and a short entry
    /// is a row of that list: a click to the right of its words is on it.
    @Test("a popup list's short entry answers a click at the list's far edge")
    func apopupEntryAnswersAtTheListsEdge() throws {
        var taken: [String] = []
        let list = PopupList(choices: [PopupList.Choice(id: "rush", says: "Rush")],
                             asks: "New type...", ask: {}, choose: { taken.append($0.id) })
        let window = RealClick.host(list, size: CGSize(width: 186, height: 120))
        defer { window.close() }

        let frame = try RealClick.frame(ofButton: "Rush", in: window)
        let edge = try #require(window.contentView).bounds.width - 6
        RealClick.click(at: NSPoint(x: edge, y: frame.midY), in: window)

        #expect(taken == ["rush"])
    }

    @Test("and so does its trailing entry, which asks rather than chooses")
    func apopupsTrailingEntryAnswersAtTheListsEdge() throws {
        var asked = 0
        let list = PopupList(choices: [PopupList.Choice(id: "rush", says: "Rush")],
                             asks: "New type...", ask: { asked += 1 }, choose: { _ in })
        let window = RealClick.host(list, size: CGSize(width: 186, height: 120))
        defer { window.close() }

        let frame = try RealClick.frame(ofButton: "New type...", in: window)
        let edge = try #require(window.contentView).bounds.width - 6
        RealClick.click(at: NSPoint(x: edge, y: frame.midY), in: window)

        #expect(asked == 1)
    }
}
