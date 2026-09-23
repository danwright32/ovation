import SwiftData
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#473, PRD 5.7. When this invoice is due, drawn.
///
/// THE APP PRINTED THE DUE DATE AS TEXT, so the one thing PRD 5.7 says is
/// overridable per invoice could not be overridden. The design record draws a
/// control: a button showing the date, a list of four terms each with the day it
/// lands on, and an "Another date..." entry that opens a panel.
///
/// WHAT A RULE DECIDES AND WHAT A PERSON SEES ARE TWO TESTABLE SURFACES (L442):
/// the presenter's terms are covered in `InvoiceScreenPresenterTests`, and this
/// is the other half.
@MainActor
struct DueDateControlTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    private static func choices(_ issued: String = "2026-11-12",
                                due: String? = "2026-11-26") throws
        -> [InvoiceScreenPresenter.DueChoice] {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: BusinessCalendar.day(forKey: issued),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        invoice.dueDate = due.flatMap(BusinessCalendar.day(forKey:))
        context.insert(invoice)
        return InvoiceScreenPresenter(invoice: invoice, footer: .fixed, today: today).dueChoices
    }

    private static func text(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    @Test("the foot says when it was written and when it is due")
    func thefootSaysBoth() throws {
        let view = DueDateControl(issued: "12 Nov 2026", due: "26 Nov 2026",
                                  choices: try Self.choices(), save: { _ in })

        let drawn = try Self.text(in: view)

        #expect(drawn.contains("Dated 12 Nov 2026, due "))
        #expect(drawn.contains("26 Nov 2026"))
    }

    /// THE DATE IS A CONTROL when the invoice may be edited, which is what makes
    /// the requirement's "overridable per invoice" true rather than recorded.
    @Test("the due date is pressable on a draft")
    func theduedateIsPressable() throws {
        let view = DueDateControl(issued: "12 Nov 2026", due: "26 Nov 2026",
                                  choices: try Self.choices(), save: { _ in })

        let pressable = try view.inspect().findAll(ViewType.Button.self)
            .compactMap { try? $0.labelView().text().string() }

        #expect(pressable == ["26 Nov 2026"])
    }

    /// AND IT IS NOT OFFERED ON AN INVOICE THAT MAY NOT BE EDITED, rather than
    /// offered and then refused, because a control that opens onto a refusal is a
    /// dead control (L651, L109). The positive control above is what makes this
    /// absence mean something (L159).
    @Test("a sent invoice draws the date as a word, with nothing to press")
    func asentInvoiceHasNoControl() throws {
        let view = DueDateControl(issued: "12 Nov 2026", due: "26 Nov 2026",
                                  choices: try Self.choices())

        let pressable = try view.inspect().findAll(ViewType.Button.self)

        #expect(pressable.isEmpty)
        #expect(try Self.text(in: view).contains("26 Nov 2026"))
    }

    /// AND AN INVOICE WITH NO DATE OF ITS OWN OFFERS NO CONTROL EITHER, because
    /// there is nothing to count a term from, and it says which of the two
    /// reasons it is rather than sharing one silence (L11).
    @Test("an invoice with no date says why the due date cannot be set")
    func anundatedInvoiceSaysWhy() throws {
        let view = DueDateControl(issued: "", due: "", choices: [], save: { _ in })

        let pressable = try view.inspect().findAll(ViewType.Button.self)
        let spoken = try view.inspect().find(ViewType.Text.self, where: { text in
            (try? text.accessibilityLabel().string())?.contains("not yet") == true
        })

        #expect(pressable.isEmpty)
        #expect(try spoken.accessibilityLabel().string().contains("no date to count a term from"))
    }

    /// EVERY TERM CARRIES THE DAY IT LANDS ON, which is what the design record
    /// shows rather than leaving the reader to count fourteen days in their head.
    @Test("the four terms each name the day they land on")
    func thetermsNameTheirDays() throws {
        let choices = try Self.choices()

        #expect(choices.map(\.says) == ["On receipt", "7 days", "14 days", "30 days"])
        #expect(choices.map(\.lands)
                    == ["12 Nov 2026", "19 Nov 2026", "26 Nov 2026", "12 Dec 2026"])
    }

    // MARK: the terms as the one list draws them (ovation#457)

    /// THE TERMS AND THE SERVICE TYPES ARE ONE LIST, which the design record
    /// states and which this half of the conversion has to keep true. The
    /// popover the list is presented in is its own window, so no view tree test
    /// can reach it, and the translation into that list is therefore the only
    /// part of this that a test can hold (L442).
    @Test("each term becomes a row carrying its words and the day it lands on")
    func eachtermBecomesARow() throws {
        let choices = try Self.choices()

        let rows = DueDateControl.rows(for: choices)

        #expect(rows.map(\.says) == choices.map(\.says))
        #expect(rows.map(\.beside) == choices.map(\.lands))
        #expect(rows.contains { $0.isCurrent })
    }

    /// AND EVERY ROW FINDS ITS OWN TERM BACK. The row hands back an identity and
    /// the control looks the term up by it, so a row whose identity does not
    /// round trip saves a date the person did not pick, and every date on the
    /// screen still looks right (L15, L237).
    @Test("every row finds its way back to exactly one term")
    func everyrowFindsItsTermBack() throws {
        let choices = try Self.choices()

        let rows = DueDateControl.rows(for: choices)

        #expect(Set(rows.map(\.id)).count == choices.count, "two rows share an identity")
        for (row, term) in zip(rows, choices) {
            let found = choices.filter { $0.says == row.id }
            #expect(found.count == 1)
            #expect(found.first?.day.dayKey == term.day.dayKey)
        }
    }
}
