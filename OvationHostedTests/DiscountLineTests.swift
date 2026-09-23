import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#457, PRD 5.4a. The discount's own line on the invoice.
///
/// IT SITS ON ITS OWN LINE BENEATH THE ROW, and that is measured rather than
/// chosen. `docs/design/invoice.html` records that every totals row keeps one
/// width so every figure keeps one right edge, that these controls do not fit
/// that row's label column, and that two earlier attempts widened the row and
/// put the discount's figure off the shared edge, once 24px left and once 24px
/// right, both measured.
///
/// THE RECORD ALSO SAYS THIS LINE'S OWN DESIGN WAS NEVER PUT TO DAN. It was
/// chosen to solve that layout problem with no alternative drawn beside it, and
/// ovation#111 still holds that open. What is built here is what is drawn there.
@MainActor
struct DiscountLineTests {

    private static func line(isPercent: Bool = true,
                             value: Binding<String> = .constant("10"),
                             setUnit: @escaping (Bool) -> Void = { _ in },
                             commit: @escaping () -> Void = {},
                             remove: @escaping () -> Void = {}) -> DiscountLine {
        DiscountLine(isPercent: isPercent, value: value, width: 318,
                     setUnit: setUnit, commit: commit, remove: remove)
    }

    private static func text(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    @Test("the line names itself and offers both units")
    func thelineNamesItselfAndOffersBothUnits() throws {
        let drawn = try Self.text(in: Self.line())

        #expect(drawn.contains("Discount"))
        #expect(drawn.contains("%"))
        #expect(drawn.contains("$"))
    }

    /// WHICH UNIT IS IN FORCE IS DRAWN, not left to be inferred from the figure,
    /// and it is said to a screen reader as well, because a state carried only by
    /// a colour is a state some readers never get (PRD 47, L20).
    @Test("the unit in force is marked, and the other is not", arguments: [true, false])
    func theunitInForceIsMarked(isPercent: Bool) throws {
        let view = Self.line(isPercent: isPercent)

        let marked = try view.inspect().findAll(ViewType.Button.self).filter { button in
            (try? button.accessibilityValue().string()) == "in force"
        }.compactMap { try? $0.labelView().text().string() }

        #expect(marked == [isPercent ? "%" : "$"])
    }

    @Test("pressing a unit asks for that unit", arguments: [true, false])
    func pressingaunitAsksForIt(pressPercent: Bool) throws {
        var asked: [Bool] = []
        let view = Self.line(isPercent: !pressPercent, setUnit: { asked.append($0) })

        try view.inspect().find(ViewType.Button.self, where: { button in
            (try? button.labelView().text().string()) == (pressPercent ? "%" : "$")
        }).tap()

        #expect(asked == [pressPercent])
    }

    @Test("the value field shows what it was given")
    func thevalueFieldShowsWhatItWasGiven() throws {
        let view = Self.line(value: .constant("33.33"))

        #expect(try view.inspect().find(ViewType.TextField.self).input() == "33.33")
    }

    @Test("submitting the value commits it")
    func submittingthevalueCommits() throws {
        var committed = 0
        let view = Self.line(commit: { committed += 1 })

        try view.inspect().find(ViewType.TextField.self).callOnSubmit()

        #expect(committed == 1)
    }

    /// REMOVING IS OFFERED HERE AND NOWHERE ELSE, which is what keeps the menu
    /// from carrying the same action a second time, further from the thing it
    /// acts on (the design record's round 5, L605).
    @Test("the line offers a way to drop the discount")
    func thelineOffersAWayToDropIt() throws {
        var removed = 0
        let view = Self.line(remove: { removed += 1 })

        try view.inspect().find(button: "Remove").tap()

        #expect(removed == 1)
    }
}
