import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#450. The product's one word that is a control, drawn.
///
/// WHAT A RULE DECIDES AND WHAT A PERSON SEES ARE TWO TESTABLE SURFACES (L442),
/// and this is the second: `Action.destination` can be perfectly right while the
/// row still draws every word as a control. The whole defect was in the drawing.
@MainActor
struct ActionWordTests {

    private static func buttons(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Button.self)
            .compactMap { try? $0.labelView().text().string() }
    }

    private static func text(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    @Test("a word with somewhere to go is a control, and pressing it does that thing")
    func alivewordIsAControl() throws {
        var pressed = 0
        let view = ActionWord(word: "Add hours", size: 12.5, press: { pressed += 1 })

        #expect(try Self.buttons(in: view) == ["Add hours"])

        try view.inspect().find(ViewType.Button.self).tap()
        #expect(pressed == 1)
    }

    /// THE POSITIVE CONTROL'S OPPOSITE, and the case the issue is actually about:
    /// a word with nowhere to go is not a button at all, so it cannot be pressed
    /// and it does not read as pressable.
    @Test("a word with nowhere to go is not a control, and still says the word")
    func aquietWordIsNotAControl() throws {
        let view = ActionWord(word: "Mark cleared", size: 12.5)

        #expect(try Self.buttons(in: view).isEmpty, "a word with nowhere to go was a button")
        #expect(try Self.text(in: view) == ["Mark cleared"],
                "the word itself changed, which would move a count on the sidebar card")
    }

    /// AND A SCREEN READER IS TOLD WHY, because a refusal only sighted readers
    /// can infer from a colour is not a refusal (PRD 47, L111, L577).
    @Test("the quiet word tells a screen reader it is not yet, and why")
    func thequietWordSaysWhyToAScreenReader() throws {
        let view = ActionWord(word: "Review", size: 14, notYet: "Waiting on the shoot's times.")

        let spoken = try view.inspect().find(ViewType.Text.self).accessibilityLabel().string()

        #expect(spoken == "Review, not yet: Waiting on the shoot's times.")
    }

    /// AND WITH NO REASON TO GIVE IT SAYS THE WORD, rather than an empty label or
    /// the phrase "not yet" trailing off into nothing (L440).
    @Test("a quiet word with no reason recorded is spoken as itself")
    func aquietWordWithNoReasonIsSpokenAsItself() throws {
        let view = ActionWord(word: "Remind", size: 12.5)

        let spoken = try view.inspect().find(ViewType.Text.self).accessibilityLabel().string()

        #expect(spoken == "Remind")
    }
}
