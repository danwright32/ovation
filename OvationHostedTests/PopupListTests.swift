import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#457. The one popup list, used twice.
///
/// THE DESIGN RECORD SAYS IT IS ONE OBJECT. `docs/design/invoice.html` builds the
/// service types that hang off a line's description cell and the payment terms
/// that hang off the foot from a single `popList`, and records why: they were
/// built as two and merged in the same change rather than left as a cleanup,
/// because the second copy is what makes the first stop being the single site
/// (L370, L613).
///
/// IT IS TESTED DIRECTLY, WHICH THE TERM LIST NEVER WAS. Both call sites present
/// it inside a popover, and a popover is its own window that a view tree test
/// cannot reach, so until this existed the list's rendering was checked nowhere
/// and only the values behind it were (L442).
@MainActor
struct PopupListTests {

    private static let terms = [
        PopupList.Choice(id: "on-receipt", says: "On receipt", beside: "12 Nov 2026",
                         isCurrent: false),
        PopupList.Choice(id: "net-14", says: "Net 14", beside: "26 Nov 2026",
                         isCurrent: true),
    ]

    private static let types = [
        PopupList.Choice(id: "photography", says: "Concert photography"),
        PopupList.Choice(id: "rush", says: "Rush turnaround"),
    ]

    private static func words(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    // MARK: the choices

    @Test("every choice is drawn, in the order it was given")
    func everychoiceIsDrawn() throws {
        let view = PopupList(choices: Self.terms, choose: { _ in })

        let drawn = try Self.words(in: view)

        #expect(drawn.firstIndex(of: "On receipt") ?? 99 < drawn.firstIndex(of: "Net 14") ?? 0)
        #expect(drawn.contains("On receipt"))
        #expect(drawn.contains("Net 14"))
    }

    /// WHAT A CHOICE LANDS ON IS SAID BESIDE IT, which the design record draws
    /// rather than leaving the reader to count fourteen days in their head.
    @Test("a choice carrying a figure draws it beside the words")
    func afigureIsDrawnBesideTheWords() throws {
        let view = PopupList(choices: Self.terms, choose: { _ in })

        let drawn = try Self.words(in: view)

        #expect(drawn.contains("26 Nov 2026"))
    }

    /// AND A CHOICE THAT IS ONLY ITS NAME DRAWS NOTHING BESIDE IT, rather than an
    /// empty cell holding the space open (L626). The service types have no figure.
    @Test("a choice that is only a name draws no second column")
    func anameOnlyChoiceDrawsNothingBeside() throws {
        let view = PopupList(choices: Self.types, choose: { _ in })

        let drawn = try Self.words(in: view)

        #expect(drawn == ["Concert photography", "Rush turnaround"])
    }

    @Test("pressing a choice hands back that choice and no other")
    func pressingachoiceHandsItBack() throws {
        var taken: [String] = []
        let view = PopupList(choices: Self.types, choose: { taken.append($0.id) })

        try view.inspect().find(ViewType.Button.self, where: { button in
            (try? button.find(text: "Rush turnaround")) != nil
        }).tap()

        #expect(taken == ["rush"])
    }

    // MARK: the trailing question

    /// THE THREE DOTS SAY A QUESTION IS COMING, which is the macOS convention and
    /// is true at both call sites: each trailing entry opens a panel.
    @Test("the trailing entry is drawn when there is one")
    func thetrailingEntryIsDrawn() throws {
        let view = PopupList(choices: Self.types, asks: "New type...",
                             ask: {}, choose: { _ in })

        #expect(try Self.words(in: view).contains("New type..."))
    }

    /// THE POSITIVE CONTROL. Without it a list that always drew an entry would
    /// pass the case above (L159).
    @Test("and no trailing entry is drawn when there is none")
    func nottrailingEntryWhenThereIsNone() throws {
        let view = PopupList(choices: Self.types, choose: { _ in })

        let pressable = try view.inspect().findAll(ViewType.Button.self).count

        #expect(pressable == Self.types.count)
    }

    @Test("pressing the trailing entry asks its question rather than choosing")
    func pressingthetrailingEntryAsks() throws {
        var asked = 0
        var taken: [String] = []
        let view = PopupList(choices: Self.types, asks: "New type...",
                             ask: { asked += 1 }, choose: { taken.append($0.id) })

        try view.inspect().find(ViewType.Button.self, where: { button in
            (try? button.find(text: "New type...")) != nil
        }).tap()

        #expect(asked == 1)
        #expect(taken.isEmpty, "the trailing entry chose a service type")
    }
}
