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
    /// The three PRD 5.4 seeds, so a case about adding a line has something to
    /// choose from.
    private static func types(_ context: ModelContext) -> [ServiceType] {
        let made = [
            ServiceType(name: "Photography", role: .hourlyPhotography, defaultUnitAmount: nil),
            ServiceType(name: "Rush turnaround", role: .ordinary,
                        defaultUnitAmount: Money(dollars: 150)),
            ServiceType(name: "Preview images", role: .ordinary, defaultUnitAmount: nil),
        ]
        made.forEach { context.insert($0) }
        return made
    }

    private static func draft(sent: Bool = false, end: String? = nil,
                              number: Int64? = nil,
                              taxStatus: TaxStatus = .notExempt,
                              offering: Bool = false) throws -> InvoiceScreenPresenter {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: taxStatus)
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
        if let number { invoice.number = number }
        return InvoiceScreenPresenter(invoice: invoice, footer: .fixed, today: today,
                                      serviceTypes: offering ? Self.types(context) : [])
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

    /// THE HELD NUMBER REACHES THE WINDOW (ovation#411). The presenter can compose
    /// the sentence perfectly and the head can fail to draw it, which is the second
    /// of the two testable surfaces (L442), and this one is the whole point of the
    /// issue: a number held by a draft had no surface anywhere in the app.
    @Test("a draft holding a number says so in the window, and an ordinary one does not")
    func theheldNumberIsDrawn() throws {
        let holding = InvoiceScreenView(presenter: try Self.draft(number: 1_123),
                                        close: {}, setTime: { _, _, _ in })
        let ordinary = InvoiceScreenView(presenter: try Self.draft(), close: {},
                                         setTime: { _, _, _ in })

        let held = try Self.text(in: holding)
        let plain = try Self.text(in: ordinary)

        #expect(held.contains("Draft, holding 1123"))
        // The positive control, without which a head drawing that sentence always
        // would pass the line above (L159).
        #expect(plain.contains("Draft"))
        #expect(!plain.contains { $0.contains("holding") },
                "an ordinary draft claimed to be holding a number")
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

    // MARK: the tax status, answered where it is said (ovation#457, PRD 5.5)

    /// THE THING STOPPING THE INVOICE IS ANSWERABLE WHERE IT IS SAID, which is the
    /// design record's own rule for this question. Until this existed the foot
    /// named the one thing outstanding and the screen offered no way to do it, and
    /// the only place the status could be set was a different screen reached from
    /// a different place (L80, L111).
    @Test("the question and its two answers reach the window")
    func thetaxQuestionIsDrawn() throws {
        let view = InvoiceScreenView(presenter: try Self.draft(taxStatus: .neverRecorded),
                                     close: {}, setTime: { _, _, _ in },
                                     answerTax: { _, _ in })

        let drawn = try Self.text(in: view)
        let pressable = try view.inspect().findAll(ViewType.Button.self)
            .compactMap { try? $0.labelView().text().string() }

        #expect(drawn.contains("Tax status never recorded for this client."))
        #expect(TaxStatus.answers.allSatisfy { pressable.contains($0.exportLabel) },
                "the window offered \(pressable)")
    }

    /// THE POSITIVE CONTROL, without which a screen that never asks would pass the
    /// case above (L159).
    @Test("and a client whose status is recorded is asked nothing")
    func anansweredClientIsAskedNothing() throws {
        let view = InvoiceScreenView(presenter: try Self.draft(), close: {},
                                     setTime: { _, _, _ in }, answerTax: { _, _ in })

        let drawn = try Self.text(in: view)

        #expect(!drawn.contains { $0.contains("Tax status never recorded") })
        #expect(drawn.contains { $0.hasPrefix("Sales tax") },
                "an answered client should still be drawing a tax row")
    }

    /// AND PRESSING ONE HANDS BACK THE ANSWER IT NAMES. A control wired to the
    /// wrong value is the defect no rendering can show: both answers draw
    /// identically and only the press tells them apart (L442).
    @Test("pressing an answer hands back the status that answer names", arguments: TaxStatus.answers)
    func pressinganAnswerHandsItBack(_ answer: TaxStatus) throws {
        let presenter = try Self.draft(taxStatus: .neverRecorded)
        var given: [TaxStatus] = []
        var about: [PersistentIdentifier] = []
        let view = InvoiceScreenView(presenter: presenter,
                                     close: {}, setTime: { _, _, _ in },
                                     answerTax: { about.append($0); given.append($1) })

        try view.inspect().find(ViewType.Button.self, where: { button in
            (try? button.labelView().text().string()) == answer.exportLabel
        }).tap()

        #expect(given == [answer])
        // ADDRESSED BY THE CLIENT THE QUESTION WAS ASKED ABOUT, never looked up
        // again when it is answered (L166).
        #expect(about == [presenter.taxQuestion?.about])
    }

    /// A REFUSED ANSWER IS SAID, never swallowed, for the reason every other write
    /// on this screen says its refusal: a control that does nothing and gives no
    /// reason leaves pressing it again as the only diagnosis (L109, L148).
    @Test("a refused answer reaches the window, in the writer's own words")
    func arefusedAnswerIsDrawn() throws {
        let view = InvoiceScreenView(presenter: try Self.draft(taxStatus: .neverRecorded),
                                     close: {}, setTime: { _, _, _ in },
                                     answerTax: { _, _ in },
                                     refusedTax: ClientTaxStatusRefusal.noSuchClient.sentence)

        let drawn = try Self.text(in: view)

        #expect(drawn.contains(ClientTaxStatusRefusal.noSuchClient.sentence))
    }

    /// NOTHING TO WRITE WITH DRAWS NO ANSWERS, rather than two words that look
    /// pressable and are not, which is the defect ovation#450 named and this
    /// screen's own header says it must not ship (L109).
    @Test("with nowhere to put the answer the question is stated and not offered")
    func nowritePathOffersNoAnswers() throws {
        let view = InvoiceScreenView(presenter: try Self.draft(taxStatus: .neverRecorded),
                                     close: {}, setTime: { _, _, _ in })

        let drawn = try Self.text(in: view)
        let pressable = try view.inspect().findAll(ViewType.Button.self)
            .compactMap { try? $0.labelView().text().string() }

        #expect(drawn.contains("Tax status never recorded for this client."))
        #expect(!pressable.contains { TaxStatus.answers.map(\.exportLabel).contains($0) })
    }

    /// EVERY FACT ONCE PER SCREEN (L605), read as one surface rather than as two
    /// components each correct on its own. The foot said "Waiting on this client's
    /// tax status." while the money block said "Tax status never recorded for this
    /// client." four inches above it, and both were right.
    @Test("the window states the tax status once, in the block that can answer it")
    func thewindowStatesTheTaxStatusOnce() throws {
        let view = InvoiceScreenView(presenter: try Self.draft(taxStatus: .neverRecorded),
                                     close: {}, setTime: { _, _, _ in },
                                     answerTax: { _, _ in })

        let drawn = try Self.text(in: view)

        #expect(drawn.contains("Tax status never recorded for this client."))
        #expect(!drawn.contains(ReviewGate.sentence(for: .taxStatusNeverRecorded)),
                "the foot repeated what the money block was already answering")
    }

    // MARK: adding a line (ovation#457, PRD 5.4)

    /// THE WORD APPENDS A ROW AND THE TYPE IS CHOSEN INSIDE IT, so the line is
    /// built where it is going to live, which the design record settled on
    /// 2026-09-08 against three alternatives including putting it in the Edit
    /// menu. That one was rejected on measurement rather than taste: 26 of 130
    /// issued invoices carry more than one line, against 5 carrying a discount.
    @Test("a draft with something to choose from offers a line to add")
    func adraftOffersALineToAdd() throws {
        let view = InvoiceScreenView(presenter: try Self.draft(offering: true),
                                     close: {}, setTime: { _, _, _ in },
                                     addLine: { _, _ in })

        #expect(try Self.text(in: view).contains("Add a line"))
    }

    /// AND IT IS NOT OFFERED WHERE IT CANNOT BE DONE, rather than offered and
    /// then refused: a control that opens onto a refusal is a dead control, and a
    /// word that looks pressable and is not is the defect this screen must not
    /// ship (L651, L109, ovation#450).
    @Test("a sent invoice offers no line to add", arguments: [true, false])
    func asentInvoiceOffersNoLineToAdd(sent: Bool) throws {
        let view = InvoiceScreenView(presenter: try Self.draft(sent: sent, end: "20:30",
                                                               offering: true),
                                     close: {}, setTime: { _, _, _ in },
                                     addLine: { _, _ in })

        #expect(try Self.text(in: view).contains("Add a line") == !sent)
    }

    /// NOR WHERE THERE IS NOTHING TO WRITE WITH. Nil means this launch has no
    /// store, and a word with nothing behind it is the same dead control (L3).
    @Test("with nowhere to put a line the word is not drawn")
    func nowritePathDrawsNoWord() throws {
        let view = InvoiceScreenView(presenter: try Self.draft(offering: true),
                                     close: {}, setTime: { _, _, _ in })

        #expect(try !Self.text(in: view).contains("Add a line"))
    }

    // MARK: what the list and the panel decide

    /// THE TYPES BECOME ROWS OF THE ONE LIST. The list is presented in a popover,
    /// which is its own window and beyond any view tree test, so this translation
    /// is the part a test can hold, and it is the part that decides which type a
    /// press writes (L442, L237).
    @Test("every offered type becomes a row that finds its own type back")
    func everytypeBecomesARow() throws {
        let presenter = try Self.draft(offering: true)

        let rows = InvoiceScreenView.typeRows(for: presenter.serviceTypes)

        #expect(rows.map(\.says) == presenter.serviceTypes.map(\.name))
        // NOTHING BESIDE THE NAME, which is what the design record's own type
        // list draws: its rows carry a label and no second column.
        #expect(rows.allSatisfy { $0.beside.isEmpty })
        #expect(Set(rows.map(\.id)).count == rows.count, "two rows share an identity")
    }

    /// THE TYPE'S USUAL AMOUNT PREFILLS THE FIELD, which the design record says
    /// is what makes the new type panel's second question worth asking.
    ///
    /// AND A TYPE WITH NONE LEAVES IT EMPTY, never a zero: a figure the screen
    /// has not been given is never drawn as one, which is the rule the hours
    /// column already keeps (PRD 5.1b).
    @Test("choosing a type prefills its usual amount, and none leaves it empty")
    func choosingatypePrefillsItsAmount() throws {
        let presenter = try Self.draft(offering: true)
        let rush = try #require(presenter.serviceTypes.first { $0.name == "Rush turnaround" })
        let preview = try #require(presenter.serviceTypes.first { $0.name == "Preview images" })

        #expect(InvoiceScreenView.prefill(for: rush) == "150.00")
        #expect(InvoiceScreenView.prefill(for: preview) == "")
    }

    /// A TYPE WITH NO NAME CANNOT BE CREATED, and the control says so by looking
    /// inert rather than by refusing after the press, which is the design
    /// record's own reasoning: a control that does nothing and gives no reason
    /// leaves pressing it again as the only diagnosis (L109).
    @Test("a name of nothing cannot create a type", arguments: ["", "   ", "\t"])
    func anemptyNameCannotCreate(typed: String) {
        #expect(InvoiceScreenView.canCreate(typed) == false)
    }

    @Test("and a real name can")
    func arealNameCanCreate() {
        #expect(InvoiceScreenView.canCreate("Travel"))
        #expect(InvoiceScreenView.canCreate("  Travel  "))
    }

    /// A REFUSED LINE IS SAID, never swallowed, the same as every other write on
    /// this screen (L109, L148).
    @Test("a refused line reaches the window, in the writer's own words")
    func arefusedLineIsDrawn() throws {
        let view = InvoiceScreenView(presenter: try Self.draft(offering: true),
                                     close: {}, setTime: { _, _, _ in },
                                     addLine: { _, _ in },
                                     refusedLine: InvoiceLineRefusal.serviceTypeIsRetired.sentence)

        #expect(try Self.text(in: view)
            .contains(InvoiceLineRefusal.serviceTypeIsRetired.sentence))
    }

    /// A TYPE MADE FROM THE PANEL BECOMES THE ROW'S TYPE, which the design record
    /// settles. The list comes back from the store after the write, so the row
    /// finds it by the name that was typed, trimmed the way the writer stores it
    /// (L185).
    @Test("a type just made is found by the name that was typed")
    func atypeJustMadeIsFound() throws {
        let presenter = try Self.draft(offering: true)

        let found = InvoiceScreenView.newlyMade(named: "  Rush turnaround ",
                                                in: presenter.serviceTypes)

        #expect(found?.name == "Rush turnaround")
    }

    /// AND A NAME THAT IS NOT THERE YET FINDS NOTHING, which is what makes the
    /// row wait rather than select whatever is nearest (L75).
    @Test("a name that is not in the list yet finds nothing")
    func anameNotThereFindsNothing() throws {
        let presenter = try Self.draft(offering: true)

        #expect(InvoiceScreenView.newlyMade(named: "Travel",
                                            in: presenter.serviceTypes) == nil)
    }
}
