import SwiftData
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#489, PRD 51p to 51t. A line being added can be left, and its type
/// changed, driven on the invoice screen the way Dan drives it: Add a line, then
/// Cancel, or Escape twice, or a type chosen and changed, or the field left.
///
/// ON SCREEN, THROUGH `Inspection`, because the line being added is the screen's
/// own `@State`, and a view value inspected off screen reads that as nil for ever
/// and a press on it changes nothing (ovation#485, L718). Each step is its own
/// inspection, so what a press did is read back from the screen after it rather
/// than from the value the press was handed.
///
/// WHAT CANNOT BE DRIVEN HERE IS SAID, NOT IMPLIED. A click away is the field
/// losing focus, which a view tree cannot cause, so it is driven as the change
/// the platform reports; and Escape is the platform's exit command, driven as
/// that command. Both reach exactly the handlers the platform calls.
@MainActor
struct AddingALineTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    /// What the screen asked to write.
    @MainActor
    final class Written {
        var lines: [(type: PersistentIdentifier, amount: Money)] = []
    }

    /// HELD FOR THE WHOLE CASE, because the presenter's types carry identities the
    /// store made and the store has to outlive them.
    private let context: ModelContext
    private let presenter: InvoiceScreenPresenter

    init() throws {
        let store = ModelContext(try OvationSchema.container(inMemory: true))
        for type in [ServiceType(name: "Photography", role: .hourlyPhotography, defaultUnitAmount: nil),
                     ServiceType(name: "Rush turnaround", role: .ordinary,
                                 defaultUnitAmount: Money(dollars: 150)),
                     ServiceType(name: "Preview images", role: .ordinary, defaultUnitAmount: nil)] {
            store.insert(type)
        }
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        client.email = "booker@example.com"
        store.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: Self.today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        invoice.dueDate = .stamping(Self.noon.addingTimeInterval(14 * 86_400))
        store.insert(invoice)
        let shoot = Shoot(name: "Autumn Evensong", when: .dayOnly(Self.today), venue: "St Anne's")
        shoot.shotFrom = ClockTime("19:00")
        shoot.shotUntil = ClockTime("20:30")
        invoice.add(shoot)
        invoice.add(LineItem.hourly(hours: Hours(whole: 1), at: Money(dollars: 250),
                                    describedAs: "Photography", for: shoot))
        let types = try store.fetch(FetchDescriptor<ServiceType>())
        context = store
        presenter = InvoiceScreenPresenter(invoice: invoice, footer: .fixed, today: Self.today,
                                           serviceTypes: types)
    }

    private func screen(_ written: Written) -> InvoiceScreenView {
        InvoiceScreenView(presenter: presenter, close: {}, setTime: { _, _, _ in },
                          addLine: { type, amount in written.lines.append((type, amount)) },
                          createType: { _, _ in })
    }

    private static func words(in view: InspectableView<ViewType.View<InvoiceScreenView>>) -> [String] {
        view.findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    /// Runs one step against the screen as it is on screen now.
    private static func step(_ screen: InvoiceScreenView,
                             _ body: @escaping (InspectableView<ViewType.View<InvoiceScreenView>>) throws -> Void)
        async throws {
        try await screen.inspection.inspect { view in try body(view) }
    }

    /// A row of the type list pressed, once the chooser has opened it.
    ///
    /// THROUGH THE ROW'S OWN `choose`, which is the closure the list is handed
    /// and calls on a press. The list lives in a popover, which is its own window,
    /// and measured here a search of the screen does not reach into it ("Search
    /// did not find a match"), so the press is made one step in from the finger.
    /// The list's rows are covered by `InvoiceScreenView.typeRows`'s own case.
    private static func chooseFromTheList(_ name: String,
                                          on view: InspectableView<ViewType.View<InvoiceScreenView>>) throws {
        let row = try view.find(AddingLineRow.self).actualView()
        #expect(row.line.listIsOpen, "a type was chosen from a list that was not open")
        let choice = try #require(row.types.first { $0.says == name })
        row.choose(choice)
    }

    private static func amount(on view: InspectableView<ViewType.View<InvoiceScreenView>>) throws -> String {
        try view.find(AddingLineRow.self).find(ViewType.TextField.self).input()
    }

    // MARK: Cancel (PRD 51p)

    /// CANCEL TAKES ADD A LINE'S PLACE while a line is being added, and Add a line
    /// comes back once it is cancelled, with nothing written.
    @Test("Cancel replaces Add a line while a line is added, and clears it without writing")
    func cancelReplacesAddALine() async throws {
        let written = Written()
        let screen = screen(written)
        ViewHosting.host(view: screen)
        defer { ViewHosting.expel() }

        try await Self.step(screen) { view in
            #expect(Self.words(in: view).contains("Add a line"))
            #expect(!Self.words(in: view).contains("Cancel"))
            try view.find(button: "Add a line").tap()
        }
        try await Self.step(screen) { view in
            #expect(view.findAll(AddingLineRow.self).count == 1)
            #expect(!Self.words(in: view).contains("Add a line"), "Add a line stayed beside Cancel")
            try view.find(AddingLineRow.self).find(ViewType.Button.self).tap()
        }
        try await Self.step(screen) { view in
            try Self.chooseFromTheList("Rush turnaround", on: view)
        }
        try await Self.step(screen) { view in
            try view.find(button: "Cancel").tap()
        }
        try await Self.step(screen) { view in
            #expect(view.findAll(AddingLineRow.self).isEmpty, "the row survived Cancel")
            #expect(Self.words(in: view).contains("Add a line"))
            #expect(!Self.words(in: view).contains("Cancel"))
        }
        #expect(written.lines.isEmpty, "Cancel wrote the line")
    }

    // MARK: Escape (PRD 51s)

    @Test("Escape with the list open closes the list, and a second Escape cancels the line")
    func escapeTwice() async throws {
        let written = Written()
        let screen = screen(written)
        ViewHosting.host(view: screen)
        defer { ViewHosting.expel() }

        try await Self.step(screen) { view in try view.find(button: "Add a line").tap() }
        try await Self.step(screen) { view in
            try view.find(AddingLineRow.self).find(ViewType.Button.self).tap()
        }
        try await Self.step(screen) { view in
            let opened = try view.find(AddingLineRow.self).actualView().line.listIsOpen
            #expect(opened)
            try view.find(AddingLineRow.self).hStack().callOnExitCommand()
        }
        try await Self.step(screen) { view in
            let row = try view.find(AddingLineRow.self)
            let stillOpen = try row.actualView().line.listIsOpen
            #expect(stillOpen == false, "the first Escape left the list open")
            try row.hStack().callOnExitCommand()
        }
        try await Self.step(screen) { view in
            #expect(view.findAll(AddingLineRow.self).isEmpty, "the second Escape left the line")
            #expect(Self.words(in: view).contains("Add a line"))
        }
        #expect(written.lines.isEmpty)
    }

    // MARK: changing the type (PRD 51r)

    /// AN AMOUNT THAT IS STILL THE OLD TYPE'S USUAL ONE GOES WITH IT.
    @Test("changing the type replaces an amount nobody edited")
    func changingReplacesAnUneditedAmount() async throws {
        let screen = screen(Written())
        ViewHosting.host(view: screen)
        defer { ViewHosting.expel() }

        try await Self.step(screen) { view in try view.find(button: "Add a line").tap() }
        try await Self.step(screen) { view in
            try view.find(AddingLineRow.self).find(ViewType.Button.self).tap()
        }
        try await Self.step(screen) { view in
            try Self.chooseFromTheList("Rush turnaround", on: view)
        }
        try await Self.step(screen) { view in
            let amount = try Self.amount(on: view)
            #expect(amount == "150.00")
            try view.find(AddingLineRow.self).find(ViewType.Button.self).tap()
        }
        try await Self.step(screen) { view in
            try Self.chooseFromTheList("Preview images", on: view)
        }
        try await Self.step(screen) { view in
            let amount = try Self.amount(on: view)
            #expect(amount == "", "Rush's usual amount stayed on Preview images")
            #expect(Self.words(in: view).contains("Preview images"))
        }
    }

    /// AN AMOUNT DAN TYPED IS HIS, and changing the type keeps it.
    @Test("changing the type keeps an amount typed by hand")
    func changingKeepsAnEditedAmount() async throws {
        let screen = screen(Written())
        ViewHosting.host(view: screen)
        defer { ViewHosting.expel() }

        try await Self.step(screen) { view in try view.find(button: "Add a line").tap() }
        try await Self.step(screen) { view in
            try view.find(AddingLineRow.self).find(ViewType.Button.self).tap()
        }
        try await Self.step(screen) { view in
            try Self.chooseFromTheList("Rush turnaround", on: view)
        }
        try await Self.step(screen) { view in
            try view.find(AddingLineRow.self).find(ViewType.TextField.self).setInput("175")
        }
        try await Self.step(screen) { view in
            try view.find(AddingLineRow.self).find(ViewType.Button.self).tap()
        }
        try await Self.step(screen) { view in
            try Self.chooseFromTheList("Preview images", on: view)
        }
        try await Self.step(screen) { view in
            let amount = try Self.amount(on: view)
            #expect(amount == "175", "the typed amount was replaced")
            #expect(Self.words(in: view).contains("Preview images"))
        }
    }

    // MARK: clicking away (PRD 51q)

    /// A READABLE AMOUNT IS WRITTEN WHEN THE FIELD IS LEFT, and the row goes.
    @Test("clicking away from a readable amount writes the line")
    func clickingAwayWritesAReadableAmount() async throws {
        let written = Written()
        let screen = screen(written)
        ViewHosting.host(view: screen)
        defer { ViewHosting.expel() }

        try await Self.step(screen) { view in try view.find(button: "Add a line").tap() }
        try await Self.step(screen) { view in
            try view.find(AddingLineRow.self).find(ViewType.Button.self).tap()
        }
        try await Self.step(screen) { view in
            try Self.chooseFromTheList("Rush turnaround", on: view)
        }
        try await Self.step(screen) { view in
            try view.find(AddingLineRow.self).find(ViewType.TextField.self)
                .callOnChange(oldValue: true, newValue: false)
        }
        try await Self.step(screen) { view in
            #expect(view.findAll(AddingLineRow.self).isEmpty)
            #expect(Self.words(in: view).contains("Add a line"))
        }
        #expect(written.lines.map(\.amount) == [Money(dollars: 150)])
    }

    /// AND AN UNREADABLE ONE LEAVES THE ROW OPEN, with nothing written, rather
    /// than a line worth nothing (PRD 5.1b).
    @Test("clicking away from an amount it cannot read leaves the row open")
    func clickingAwayLeavesAnUnreadableRow() async throws {
        let written = Written()
        let screen = screen(written)
        ViewHosting.host(view: screen)
        defer { ViewHosting.expel() }

        try await Self.step(screen) { view in try view.find(button: "Add a line").tap() }
        try await Self.step(screen) { view in
            try view.find(AddingLineRow.self).find(ViewType.Button.self).tap()
        }
        try await Self.step(screen) { view in
            try Self.chooseFromTheList("Preview images", on: view)
        }
        try await Self.step(screen) { view in
            try view.find(AddingLineRow.self).find(ViewType.TextField.self).setInput("about 90")
        }
        try await Self.step(screen) { view in
            try view.find(AddingLineRow.self).find(ViewType.TextField.self)
                .callOnChange(oldValue: true, newValue: false)
        }
        try await Self.step(screen) { view in
            #expect(view.findAll(AddingLineRow.self).count == 1, "the row closed on an unreadable amount")
            let amount = try Self.amount(on: view)
            #expect(amount == "about 90")
            #expect(Self.words(in: view).contains("Cancel"))
        }
        #expect(written.lines.isEmpty)
    }
}
