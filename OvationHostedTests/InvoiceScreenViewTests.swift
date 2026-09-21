import SwiftData
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#457. The invoice screen RENDERED, as against what its presenter decides.
///
/// WHAT A RULE COMPUTES AND WHAT A PERSON SEES ARE TWO TESTABLE SURFACES, and a
/// screen can be wrong while the value is right (L442). Everything here is about
/// the second: that a sentence reaches the window, that a missing time is not drawn
/// as a time, and that a control which cannot be pressed is not drawn as one.
@MainActor
struct InvoiceScreenViewTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    /// A draft: a shoot with a start and no end, and its line with no hours, which
    /// is the ordinary state of every invoice (PRD 3c).
    private static func draft(sent: Bool = false, end: String? = nil) throws -> InvoiceScreenPresenter {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        client.email = "booker@example.com"
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        invoice.dueDate = .stamping(noon.addingTimeInterval(14 * 86_400))
        context.insert(invoice)
        let shoot = Shoot(name: "Autumn Evensong", when: .dayOnly(today), venue: "St Anne's")
        shoot.shotFrom = ClockTime("19:00")
        shoot.shotUntil = end.flatMap(ClockTime.init)
        invoice.add(shoot)
        let line = LineItem.hourly(hours: Hours(whole: 1), at: Money(dollars: 250),
                                   describedAs: "Photography", for: shoot)
        invoice.add(line)
        if end == nil { line.hours = nil }
        if sent {
            invoice.number = 1_123
            invoice.sentStatus = .sent(route: .ovationSentIt, at: noon)
        }
        return InvoiceScreenPresenter(invoice: invoice, footer: .fixed, today: today)
    }

    private static func text(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    /// A REFUSED WRITE IS SAID, never swallowed. It can only be a race here, because
    /// the field is not offered on an invoice that may not be edited, and a write
    /// that silently does nothing leaves typing it again as the only diagnosis
    /// (L109, L148).
    @Test("a refused write reaches the window, in its own words")
    func arefusedWriteIsDrawn() throws {
        let view = InvoiceScreenView(presenter: try Self.draft(), close: {},
                                     setTime: { _, _, _ in },
                                     refused: ShootTimesRefusal.invoiceWasSent.sentence)

        let drawn = try Self.text(in: view)

        #expect(drawn.contains(ShootTimesRefusal.invoiceWasSent.sentence))
    }

    @Test("and with nothing refused the window says nothing about it")
    func nothingRefusedSaysNothing() throws {
        // The positive control: without it a screen drawing that sentence always
        // would pass the case above (L159).
        let view = InvoiceScreenView(presenter: try Self.draft(), close: {},
                                     setTime: { _, _, _ in })

        let drawn = try Self.text(in: view)

        #expect(!drawn.contains { $0.contains("could not be saved") })
        #expect(!drawn.contains(ShootTimesRefusal.invoiceWasSent.sentence))
    }

    /// A TIME THAT IS NOT GIVEN IS NOT DRAWN AS A TIME. `DatePicker` has no empty
    /// state, so handed a placeholder it renders one as a real time and a draft
    /// read "Ran 7:00 PM to 12:00 AM", a plausible shoot ending at midnight. A
    /// placeholder for a missing required value is a detection, not a label (L67).
    @Test("a shoot with no end time says so rather than drawing midnight")
    func amissingEndTimeSaysSo() throws {
        let view = InvoiceScreenView(presenter: try Self.draft(), close: {},
                                     setTime: { _, _, _ in })

        let drawn = try Self.text(in: view)

        #expect(drawn.contains("Not given"))
        #expect(!drawn.contains { $0.contains("12:00") }, "a missing time was drawn as midnight")
    }

    /// THE TIMES ARE NOT OFFERED ON A SENT INVOICE, drawn rather than offered and
    /// then refused: a control that opens onto a refusal is a dead control (L651).
    @Test("a sent invoice draws its times as text, with no field to type into")
    func asentInvoiceHasNoField() throws {
        let sent = InvoiceScreenView(presenter: try Self.draft(sent: true, end: "20:30"),
                                     close: {}, setTime: { _, _, _ in })
        let draft = InvoiceScreenView(presenter: try Self.draft(end: "20:30"),
                                      close: {}, setTime: { _, _, _ in })

        let sentPickers = try sent.inspect().findAll(ViewType.DatePicker.self).count
        let draftPickers = try draft.inspect().findAll(ViewType.DatePicker.self).count

        #expect(sentPickers == 0, "a sent invoice offered \\(sentPickers) time field(s)")
        #expect(draftPickers == 2, "a draft should offer both times, and offered \\(draftPickers)")
    }
}
