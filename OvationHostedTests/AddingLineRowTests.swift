import SwiftData
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#457, PRD 5.4. The row being filled in when a line is being added.
///
/// ITS STATE IS THE SCREEN'S, AND THAT IS WHY IT IS ITS OWN VIEW. A view tree
/// test cannot press a word on the invoice and then see what the screen's
/// `@State` did with it, so a row drawn from that state is a row nothing can
/// check (L442). Every state of it is a case here instead.
@MainActor
struct AddingLineRowTests {

    private static let columns: (hours: CGFloat, rate: CGFloat, amount: CGFloat,
                                 gap: CGFloat, side: CGFloat) = (66, 92, 96, 14, 24)

    private static let types = [
        PopupList.Choice(id: "Photography", says: "Photography"),
        PopupList.Choice(id: "Rush turnaround", says: "Rush turnaround"),
    ]

    private static func chosen(_ name: String, _ usually: Money?)
        -> InvoiceScreenPresenter.ServiceChoice {
        let context = ModelContext(try! OvationSchema.container(inMemory: true))
        let type = ServiceType(name: name, role: .ordinary, defaultUnitAmount: usually)
        context.insert(type)
        return InvoiceScreenPresenter.ServiceChoice(id: type.persistentModelID,
                                                    name: name, usually: usually)
    }

    private static func row(chosen: InvoiceScreenPresenter.ServiceChoice? = nil,
                            amount: Binding<String> = .constant(""),
                            askNewType: (() -> Void)? = {},
                            choose: @escaping (PopupList.Choice) -> Void = { _ in },
                            commit: @escaping () -> Void = {}) -> AddingLineRow {
        AddingLineRow(chosen: chosen, types: Self.types, amount: amount,
                      askNewType: askNewType, choose: choose, commit: commit,
                      columns: Self.columns)
    }

    private static func text(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    // MARK: before a type is chosen

    /// THE TYPE IS ASKED FOR FIRST, in the row's own description cell, which is
    /// the order the design record draws.
    @Test("a row with no type yet asks for one")
    func arowWithNoTypeAsksForOne() throws {
        let drawn = try Self.text(in: Self.row())

        #expect(drawn.contains("Choose a type"))
    }

    /// AND IT IS A CONTROL AT REST rather than on hover only (L49), so it is a
    /// button whether or not anybody is pointing at it.
    @Test("the type is a control, not a label")
    func thetypeIsAControl() throws {
        let pressable = try Self.row().inspect().findAll(ViewType.Button.self)

        #expect(pressable.count == 1)
    }

    // MARK: once it is chosen

    /// THE NAME REPLACES THE CONTROL, because the question has been answered and
    /// a control still asking it reads as the answer not having landed (L152).
    @Test("a row with a type drawn shows its name and asks nothing")
    func arowWithATypeShowsItsName() throws {
        let view = Self.row(chosen: Self.chosen("Rush turnaround", Money(dollars: 150)))

        let drawn = try Self.text(in: view)

        #expect(drawn.contains("Rush turnaround"))
        #expect(!drawn.contains("Choose a type"))
    }

    /// THE HOURS AND THE RATE STAY BLANK. A flat charge has neither, and a
    /// quantity of nothing is not drawn, which is the rule the rows above this
    /// one already keep (PRD 5.1b).
    @Test("the hours and the rate are drawn as nothing, not as zero")
    func thehoursAndRateAreBlank() throws {
        let view = Self.row(chosen: Self.chosen("Rush turnaround", nil))

        let drawn = try Self.text(in: view)

        #expect(!drawn.contains("0"))
        #expect(!drawn.contains("0.00"))
    }

    // MARK: the amount

    /// THE FIELD IS WHAT IT WAS GIVEN, so a prefilled amount is drawn and an
    /// empty one is empty. `InvoiceScreenView.prefill` is what decides which.
    @Test("the amount field shows what it was given")
    func theamountFieldShowsWhatItWasGiven() throws {
        let view = Self.row(chosen: Self.chosen("Rush turnaround", Money(dollars: 150)),
                            amount: .constant("150.00"))

        let field = try view.inspect().find(ViewType.TextField.self)

        #expect(try field.input() == "150.00")
    }

    /// AND IT HAS NO PLACEHOLDER READING 0.00, which the design record states and
    /// PRD 5.1b gives the reason for: a zero total is a legitimate comped invoice,
    /// so a figure the screen has not been given is never drawn as one.
    @Test("an empty amount field offers no zero of its own")
    func anemptyAmountOffersNoZero() throws {
        let view = Self.row(chosen: Self.chosen("Rush turnaround", nil))

        let field = try view.inspect().find(ViewType.TextField.self)

        #expect(try field.input() == "")
        #expect(try Self.text(in: view).allSatisfy { !$0.contains("0.00") })
    }

    /// A FIELD THAT DOES NOTHING ON ENTER IS A FIELD THAT LOST WHAT WAS TYPED, so
    /// the row commits on submit.
    @Test("submitting the amount commits the row")
    func submittingtheAmountCommits() throws {
        var committed = 0
        let view = Self.row(chosen: Self.chosen("Rush turnaround", nil),
                            commit: { committed += 1 })

        try view.inspect().find(ViewType.TextField.self).callOnSubmit()

        #expect(committed == 1)
    }
}
