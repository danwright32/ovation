import Foundation
import SwiftData
import Testing

/// ovation#457, PRD 4, 4a, 5, 7, 8, 51a to 51l. The screen an invoice is built
/// on, decided here rather than in a view.
///
/// EVERY CHOICE IS A VALUE A TEST CAN READ, which is the same rule the invoice
/// list and the review sheet are written to. A decision made inside a view body
/// can only be checked by rendering it, and the states that matter on this screen
/// are the ones no ordinary fixture produces: an invoice waiting on a time, one
/// carrying a credit larger than its charges, one already paid.
///
/// IT READS NO STORE AND NO CLOCK. Everything arrives as an argument, and the
/// screen NEVER holds the store's own context, which is PRD 51l and ovation#440:
/// a screen holding an object from before an actor wrote to it puts its whole
/// stale snapshot back on its next save, silently.
///
/// THE WORDS ARE THE DESIGN RECORD'S OWN, `docs/design/invoice.html`, settled
/// with Dan across nine rounds. Where a label here differs from the PDF's it is
/// because that file settled it differently, not because this one re-decided it.
@MainActor
struct InvoiceScreenPresenterTests {

    /// 2026-11-12, so nothing depends on when the suite runs (L130).
    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    @discardableResult
    private static func invoice(
        _ context: ModelContext,
        client name: String = "Cedar Hill Youth Orchestra",
        taxStatus: TaxStatus = .notExempt,
        shoot: String? = "Autumn Evensong",
        from: String? = "19:00", until: String? = "20:30",
        rate: Int64? = 250
    ) throws -> Invoice {
        let client = Client(name: name, taxStatus: taxStatus)
        client.email = "booker@example.com"
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        invoice.dueDate = .stamping(noon.addingTimeInterval(14 * 86_400))
        context.insert(invoice)
        if let shoot {
            let made = Shoot(name: shoot, when: .dayOnly(today), venue: "St Anne's")
            if let from { made.shotFrom = ClockTime(from) }
            if let until { made.shotUntil = ClockTime(until) }
            invoice.add(made)
            // 19:00 to 20:30 is 1.5 hours at $250, so the line comes to $375.
            if let rate {
                invoice.add(LineItem.hourly(hours: made.billedHours ?? Hours(whole: 1),
                                            at: Money(dollars: rate),
                                            describedAs: "Photography", for: made))
            }
        }
        return invoice
    }

    private static func present(_ invoice: Invoice) -> InvoiceScreenPresenter {
        InvoiceScreenPresenter(invoice: invoice, footer: .fixed, today: today)
    }

    // MARK: the head

    /// THE CLIENT IS THE HEADING AND THE SHOOT SITS UNDER IT, which is the
    /// Clients detail pane's treatment reused rather than a new one (round 1).
    @Test("the head names the client, then the shoot and its date")
    func theheadNamesTheClientAndTheShoot() throws {
        let invoice = try Self.invoice(try Self.store())

        let screen = Self.present(invoice)

        #expect(screen.client == "Cedar Hill Youth Orchestra")
        #expect(screen.shoot.contains("Autumn Evensong"))
    }

    /// A DRAFT WITH NO SHOOT SAYS SO rather than drawing an empty line. An empty
    /// heading reads as a screen still loading (L10).
    @Test("an invoice with no shoot says that, rather than drawing nothing")
    func aninvoiceWithNoShootSaysSo() throws {
        let invoice = try Self.invoice(try Self.store(), shoot: nil)

        #expect(Self.present(invoice).shoot.isEmpty == false)
    }

    // MARK: what the invoice IS (ovation#411)

    /// THE HEAD SAYS WHICH IT IS, which the design record's own `invstate` draws as
    /// "Draft" or "Invoice 1042". An unsent invoice is a draft however far along it
    /// is, which is PRD 46g and ovation#364: the number column means the client has
    /// this number, not that one was reserved.
    @Test("an unsent invoice reads as a draft, and a sent one by its number")
    func theheadSaysWhichItIs() throws {
        let context = try Self.store()
        let draft = try Self.invoice(context)
        let sent = try Self.invoice(context)
        sent.number = 1_042
        sent.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)

        #expect(Self.present(draft).state == "Draft")
        #expect(Self.present(sent).state == "Invoice 1042")
    }

    /// ovation#411, Dan's decision 2026-09-21. A number taken by a review and never
    /// sent is held permanently until the invoice is sent or closed (PRD 10c), and
    /// nothing anywhere said so: the list reads it as a draft by design, so the
    /// held number had no surface at all.
    ///
    /// IT IS SAID WHERE THE NUMBER IS A FACT ABOUT THE THING IN FRONT OF YOU, which
    /// is this screen, chosen over saying nothing and over reporting it only in the
    /// year end reconciliation.
    @Test("a draft holding a number says so, because nothing else does")
    func adraftHoldingANumberSaysSo() throws {
        let context = try Self.store()
        let invoice = try Self.invoice(context)
        invoice.number = 1_123

        #expect(Self.present(invoice).state == "Draft, holding 1123")
    }

    /// AND AN ORDINARY DRAFT SAYS NOTHING EXTRA. Without this, a head that always
    /// mentioned a number would pass the case above (L159), and a number every
    /// draft claimed to hold would be worse than none.
    @Test("and a draft with no number says only that it is a draft")
    func anordinaryDraftSaysOnlyDraft() throws {
        #expect(Self.present(try Self.invoice(try Self.store())).state == "Draft")
    }

    // MARK: the lines

    /// EACH LINE CARRIES ITS OWN FIGURE, and this is the fault the design record's
    /// own guard was written against: the first line's amount was the LINES TOTAL,
    /// which is the same number while an invoice can only carry one line, so a
    /// 375.00 line read as 450.00 the moment a 75.00 line was added beside it
    /// (L101).
    @Test("every line carries its own amount, not the running total")
    func everylineCarriesItsOwnAmount() throws {
        let context = try Self.store()
        let invoice = try Self.invoice(context)
        invoice.add(LineItem.flat(Money(dollars: 75), describedAs: "Rush delivery"))

        let lines = Self.present(invoice).lines

        #expect(lines.count == 2)
        #expect(lines.first?.amount == "375.00")
        #expect(lines.last?.amount == "75.00", "the second line shows its own figure")
    }

    @Test("the columns are the design's four, in its order")
    func thecolumnsAreTheDesignsFour() throws {
        #expect(InvoiceScreenPresenter.columns == ["Description", "Hours", "Rate", "Amount"])
    }

    /// A LINE WITH NO HOURS DRAWS NO HOURS, blank rather than zero. A zero total
    /// is a legitimate comped invoice (PRD 5.1b) and the two must never look alike,
    /// which the design record states in as many words.
    @Test("a flat charge has no hours and no rate, drawn blank rather than as zero")
    func aflatChargeHasNoHours() throws {
        let context = try Self.store()
        let invoice = try Self.invoice(context, rate: nil)
        invoice.add(LineItem.flat(Money(dollars: 75), describedAs: "Rush delivery"))

        // THE LAST ROW, because the shoot's own row comes first: a shoot is a row
        // whether or not it has been priced (round 2, round 3).
        let line = try #require(Self.present(invoice).lines.last)

        #expect(line.hours.isEmpty)
        #expect(line.rate.isEmpty)
        #expect(line.amount == "75.00")
    }

    /// ROUND 2 AND ROUND 3. A shoot is a row whether or not it has been priced,
    /// because the hours are typed into a plain field IN the line, so the line has
    /// to exist before there are any hours to type into it. Where the amount would
    /// be there is a word instead of a number.
    ///
    /// FOUND BY LOOKING AT THE RENDERING. Built from the line items alone, the
    /// commonest screen in the product (an ordinary draft, PRD 3c) was a column
    /// header over an empty space (L606).
    @Test("a shoot with nothing priced against it is still a row, with a word for its amount")
    func anunpricedShootIsStillARow() throws {
        let invoice = try Self.invoice(try Self.store(), until: nil, rate: nil)

        let row = try #require(Self.present(invoice).lines.first)

        #expect(row.describes == "Autumn Evensong")
        #expect(row.amount == "Needs the end time")
        #expect(row.amountIsAWord)
        #expect(row.hours.isEmpty, "there are no hours yet, and a zero would be a figure")
    }

    /// THE REAL DRAFT SHAPE, and the one the case above does not cover. A draft is
    /// a shoot AND its photography line with no hours, which is what
    /// `Invoice.clearTimes(of:)` leaves. A line with no hours reports its RATE as
    /// its amount, so a screen asking "does a line exist" drew `250.00` for an
    /// invoice nobody has priced (L16, L342).
    @Test("a shoot whose line has no hours yet is still the waiting word, never its rate")
    func alineWithNoHoursIsStillWaiting() throws {
        let context = try Self.store()
        let invoice = try Self.invoice(context, until: nil, rate: nil)
        let shoot = try #require(invoice.orderedShoots.first)
        let line = LineItem.hourly(hours: Hours(whole: 1), at: Money(dollars: 250),
                                   describedAs: "Photography", for: shoot)
        invoice.add(line)
        line.hours = nil

        let row = try #require(Self.present(invoice).lines.first)

        #expect(row.amount == "Needs the end time", "it drew \(row.amount)")
        #expect(row.amount != "250.00", "the rate read as the amount")
    }

    /// THE SHORT WORD AND THE LONG SENTENCE COME FROM ONE PLACE, which is
    /// `waiting.js`'s own arrangement and its stated reason: the screen must not
    /// say one thing where the figure is drawn and a different thing under the
    /// main action (L118).
    @Test("the word beside the figure and the sentence under the action are about one thing")
    func thewordAndTheSentenceAgree() throws {
        let invoice = try Self.invoice(try Self.store(), until: nil, rate: nil)

        let screen = Self.present(invoice)

        #expect(screen.lines.first?.amount == "Needs the end time")
        #expect(screen.refusal == "Waiting on the time the shoot ended.")
    }

    // MARK: the times in the head (round 4b)

    /// ROUND 4 SETTLED BOTH SENTENCES, and neither of the two files the design
    /// record was merged from ever drew either: both stopped at "billed as 1.50",
    /// so the reason the figure moved was on the page nowhere. The rounding is
    /// never silent and it says WHICH rule moved it.
    @Test("a rounded duration says so, and says it was the quarter hour")
    func aroundedDurationSaysWhichRuleMovedIt() throws {
        // 19:00 to 20:32 is 1h 32m, which the quarter hour rule takes to 1.75.
        let invoice = try Self.invoice(try Self.store(), until: "20:32", rate: nil)

        let shoot = try #require(Self.present(invoice).shoots.first)

        #expect(shoot.derived == "1h 32m, billed as 1.5 hours, rounded to the nearest quarter")
    }

    /// AND AT THE FLOOR IT NAMES THE MINIMUM INSTEAD, because a reader told the
    /// figure was "rounded to the nearest quarter" when the one hour minimum is
    /// what produced it has been given the wrong reason (L11).
    @Test("a duration at the floor names the one hour minimum, not the quarter")
    func adurationAtTheFloorNamesTheMinimum() throws {
        let invoice = try Self.invoice(try Self.store(), until: "19:20", rate: nil)

        let shoot = try #require(Self.present(invoice).shoots.first)

        #expect(shoot.derived == "20m, billed as 1.0 hours, the one hour minimum")
    }

    /// AND THE RULE IS NAMED EVEN WHERE IT MOVED NOTHING, because the sentence
    /// names the rule that produced the figure rather than claiming a change. 1.5
    /// IS the nearest quarter to 1h 30m.
    @Test("an exact duration still names the rule that produced it")
    func anexactDurationStillNamesTheRule() throws {
        let invoice = try Self.invoice(try Self.store(), until: "20:30", rate: nil)

        let shoot = try #require(Self.present(invoice).shoots.first)

        #expect(shoot.derived == "1h 30m, billed as 1.5 hours, rounded to the nearest quarter")
    }

    /// THE HEAD SAYS NOTHING WHERE THE ROW ALREADY SAYS IT. An untimed shoot's row
    /// carries "Needs the end time", and repeating it in the head states one fact
    /// twice on one screen (L605).
    @Test("an untimed shoot's head says nothing, because its row already says it")
    func anuntimedShootsHeadIsSilent() throws {
        let invoice = try Self.invoice(try Self.store(), until: nil, rate: nil)

        let screen = Self.present(invoice)

        #expect(screen.shoots.first?.derived.isEmpty == true)
        #expect(screen.lines.first?.amount == "Needs the end time")
    }

    /// THE TIMES ARE OFFERED ONLY ON A DRAFT. A sent invoice's times priced a
    /// document a client holds, so the field is not offered rather than offered
    /// and then refused (L651).
    @Test("a sent invoice's times are not offered for typing", arguments: [true, false])
    func asentInvoicesTimesAreNotOffered(sent: Bool) throws {
        let context = try Self.store()
        let invoice = try Self.invoice(context)
        if sent {
            invoice.number = 1_123
            invoice.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)
        }

        #expect(Self.present(invoice).mayEdit == !sent)
    }

    /// THE PICKER SHOWS A `Date` AND THE STORE HOLDS A CLOCK TIME, so the two
    /// conversions have to be each other's inverse or an hour typed is not the hour
    /// saved. It is asserted across the WHOLE day, because the failure it exists to
    /// catch is a zone offset, which shifts some hours past a boundary and leaves
    /// others alone.
    ///
    /// THE FIRST VERSION WAS WRONG THIS WAY. It added the minutes to
    /// `Date(timeIntervalSinceReferenceDate: 0)`, which is midnight UTC and 19:00
    /// the previous day in New York, so every hour drew five off.
    @Test("every minute of the day survives the trip to the picker and back")
    func everyMinuteSurvivesTheRoundTrip() throws {
        for minutes in stride(from: 0, to: 24 * 60, by: 1) {
            let time = try #require(ClockTime(hour: minutes / 60, minute: minutes % 60))
            let back = InvoiceScreenView.clockTime(of: InvoiceScreenView.date(of: time))
            #expect(back == time, "\(minutes) minutes past midnight came back as \(String(describing: back))")
        }
    }

    // MARK: the money

    /// THE SAME ARITHMETIC THE PAGE IS DRAWN FROM, never a second reading of it.
    /// The screen and the PDF show different ROWS, which the design record settled
    /// deliberately, and they must never disagree about a FIGURE (L107).
    @Test("the money rows are the design's, and the total is the invoice's own")
    func themoneyRowsAreTheDesigns() throws {
        let invoice = try Self.invoice(try Self.store())

        let rows = Self.present(invoice).money

        #expect(rows.map(\.label).contains("Subtotal"))
        #expect(rows.map(\.label).contains("Total"))
        #expect(rows.first { $0.label == "Total" }?.value
                == PDFText.amount(invoice.total))
    }

    /// THE DESIGN'S OWN SEPARATOR, which is a comma here and a parenthesis on the
    /// PDF. Both were settled on their own surface and this one is not a second
    /// wording of the other: `docs/design/invoice.html` draws "Sales tax, 8.875%".
    @Test("the tax row names the rate the way this screen's design names it")
    func thetaxRowNamesTheRate() throws {
        let invoice = try Self.invoice(try Self.store())

        let tax = try #require(Self.present(invoice).money.first { $0.label.hasPrefix("Sales tax") })

        #expect(tax.label == "Sales tax, 8.875%")
    }

    @Test("and an exempt client's row says exempt rather than a rate of nothing")
    func anexemptClientsTaxRow() throws {
        let invoice = try Self.invoice(try Self.store(), taxStatus: .exempt)

        let tax = try #require(Self.present(invoice).money.first { $0.label.hasPrefix("Sales tax") })

        #expect(tax.label == "Sales tax, exempt")
    }

    /// PRD 8 AND ROUND 6: the credit is its own block between the lines and the
    /// subtotal, never a line among the charges, and the lines are totalled as
    /// `Services` above it so the subtotal still explains itself.
    @Test("a referral credit is its own row above the subtotal, with Services above that")
    func areferralCreditIsItsOwnRow() throws {
        let context = try Self.store()
        let invoice = try Self.invoice(context)
        invoice.referralCredit = ReferralCredit(hours: Hours(whole: 1),
                                                at: invoice.hourlyRate, earnedFrom: nil)

        let labels = Self.present(invoice).money.map(\.label)

        #expect(labels.prefix(3) == ["Services", "Referral credit", "Subtotal"])
    }

    /// AND WITH NO CREDIT THE TWO ARE ONE NUMBER, so only the subtotal is drawn.
    /// Drawing Services above an identical Subtotal states one fact twice (L605).
    @Test("with no credit there is no Services row, because it would repeat the subtotal")
    func withNoCreditThereIsNoServicesRow() throws {
        let invoice = try Self.invoice(try Self.store())

        #expect(!Self.present(invoice).money.map(\.label).contains("Services"))
    }

    /// PRD 4a. The discount sits BELOW the subtotal and the tax is charged on what
    /// is left, so a Taxable row follows it or the subtotal stops explaining the
    /// tax.
    @Test("a discount sits below the subtotal and is followed by what is taxable")
    func adiscountSitsBelowTheSubtotal() throws {
        let context = try Self.store()
        let invoice = try Self.invoice(context)
        invoice.discount = Discount(dollars: Money(dollars: 50))

        let labels = Self.present(invoice).money.map(\.label)
        let subtotal = try #require(labels.firstIndex(of: "Subtotal"))
        let discount = try #require(labels.firstIndex { $0.hasPrefix("Discount") })

        #expect(discount > subtotal)
        #expect(labels[discount + 1] == "Taxable")
    }

    // MARK: what it is waiting on

    /// THE SCREEN SAYS THE SAME THING THE SEND GATE SAYS, asked of `ReviewGate`
    /// rather than decided again here, so the word under the action and the
    /// sentence beside it cannot name different things about one invoice (L118,
    /// L370).
    @Test("an invoice waiting on a time says so, in the gate's own words")
    func aninvoiceWaitingOnATimeSaysSo() throws {
        let invoice = try Self.invoice(try Self.store(), until: nil, rate: nil)

        let screen = Self.present(invoice)

        #expect(screen.refusal == "Waiting on the time the shoot ended.")
        #expect(screen.mayReview == false)
    }

    @Test("and an invoice with nothing outstanding may be reviewed")
    func aninvoiceWithNothingOutstandingMayBeReviewed() throws {
        // The positive control. Without it a screen that always refused would pass
        // the case above (L159).
        let invoice = try Self.invoice(try Self.store())

        let screen = Self.present(invoice)

        #expect(screen.refusal == nil)
        #expect(screen.mayReview)
    }

    /// BLANK, NEVER ZERO, while the invoice has no number for these yet. The design
    /// record states it exactly, and the reason is PRD 5.1b's: a zero total is a
    /// legitimate comped invoice, so an unpriced one drawing 0.00 is the same page
    /// as a comped one.
    ///
    /// FOUND BY LOOKING AT THE RENDERING rather than by reading the code, which is
    /// what the screenshots are for (L606).
    @Test("an invoice waiting on a time draws no figures at all, rather than zeroes")
    func anunpricedInvoiceDrawsNoFigures() throws {
        let invoice = try Self.invoice(try Self.store(), until: nil, rate: nil)

        let screen = Self.present(invoice)
        let values = screen.money.map(\.value)

        let allBlank = values.allSatisfy { $0.isEmpty }
        #expect(allBlank,
                "an unpriced invoice drew \(values), which is the page a comped one draws")
    }

    /// THE POSITIVE CONTROL, AND IT IS THE PAIR THAT MATTERS. A comped invoice
    /// really does come to nothing and really does draw 0.00, so the case above
    /// cannot be satisfied by a screen that blanks every figure (L159).
    @Test("and a comped invoice does draw its zeroes, because they are its real figures")
    func acompedInvoiceDrawsItsZeroes() throws {
        let context = try Self.store()
        let invoice = try Self.invoice(context, rate: 0)

        let total = try #require(Self.present(invoice).money.first { $0.label == "Total" })

        #expect(total.value == "0.00")
    }

    /// THE SCREEN IS JUDGED AGAINST THE FOOTER IT IS GIVEN, which is the property
    /// the app's wiring depends on. `OvationApp` hands it the footer from Settings
    /// at the moment an invoice is opened (ovation#319), because two of the reasons
    /// an invoice may not go out live there. If the screen ignored its footer and
    /// judged against the shipped text, passing Settings' footer would change
    /// nothing, and `check-invoice-footer-source.sh`'s refusal of the shipped text
    /// would be protecting a value nothing reads.
    @Test("with no payment instructions in Settings, the screen refuses Review and says why")
    func thescreenIsJudgedAgainstTheFooterItIsGiven() throws {
        let invoice = try Self.invoice(try Self.store())
        var footer = InvoiceFooter.fixed
        footer.payment = ""

        let screen = InvoiceScreenPresenter(invoice: invoice, footer: footer, today: Self.today)

        #expect(screen.refusal == "Settings has no payment instructions, so no invoice can be sent.")
        #expect(screen.mayReview == false)
    }

    // MARK: the foot

    /// PRD 7 AND ROUND 8. The due date is in the foot and it is the date, not a
    /// count of days: the terms panel behind it names the date each term lands on.
    @Test("the foot carries the due date as a date")
    func thefootCarriesTheDueDate() throws {
        let invoice = try Self.invoice(try Self.store())

        #expect(Self.present(invoice).due == "26 Nov 2026")
    }

    /// A VALUE THE INVOICE HAS NO NUMBER FOR YET IS BLANK, NEVER ZERO, which the
    /// design record states for exactly the reason PRD 5.1b gives: a zero total is
    /// a legitimate comped invoice and the two must never look alike.
    @Test("an invoice with no due date draws nothing there rather than a placeholder date")
    func aninvoiceWithNoDueDateDrawsNothing() throws {
        let context = try Self.store()
        let invoice = try Self.invoice(context)
        invoice.dueDate = nil

        #expect(Self.present(invoice).due.isEmpty)
    }
}
