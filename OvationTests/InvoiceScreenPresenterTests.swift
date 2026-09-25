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
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
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

    private static func present(_ invoice: Invoice,
                                types: [ServiceType] = []) -> InvoiceScreenPresenter {
        InvoiceScreenPresenter(invoice: invoice, footer: .fixed, today: today,
                               serviceTypes: types)
    }

    /// The three PRD 5.4 seeds, made in the seeder's own order so a test can see
    /// what the screen does to it.
    private static func seeded(_ context: ModelContext) -> [ServiceType] {
        let made = [
            ServiceType(name: "Photography", role: .hourlyPhotography, defaultUnitAmount: nil),
            ServiceType(name: "Rush turnaround", role: .ordinary,
                        defaultUnitAmount: Money(dollars: 150)),
            ServiceType(name: "Preview images", role: .ordinary, defaultUnitAmount: nil),
        ]
        made.forEach { context.insert($0) }
        return made
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

    // MARK: the venue (ovation#95)

    /// THE VENUE IS HOW A SHOOT IS RECOGNISED. Two invoices for one client in one
    /// week are told apart by where they were, not by the name repeated on both,
    /// and every handoff record Downbeat writes carries one.
    @Test("the line names the venue under the shoot")
    func thelineNamesTheVenue() throws {
        let invoice = try Self.invoice(try Self.store())

        let beneath = Self.present(invoice).lines.first?.beneath

        #expect(beneath?.contains("St Anne's") == true, "it says \(beneath ?? "nothing")")
    }

    /// AND A SHOOT WITH NO VENUE SAYS SO RATHER THAN LEAVING A GAP (ovation#95).
    /// A missing required value shown as a blank is indistinguishable from a
    /// value nobody needed, and this one is how the shoot is told from the other
    /// one that week (L67, L626). Every record from Downbeat carries a venue, so
    /// a shoot with none was raised some other way and is exactly the case worth
    /// naming.
    @Test("a shoot with no venue recorded says so, rather than drawing a gap")
    func anovenueShootSaysSo() throws {
        let invoice = try Self.invoice(try Self.store())
        invoice.orderedShoots.first?.venue = nil

        let beneath = try #require(Self.present(invoice).lines.first?.beneath)

        #expect(beneath.hasPrefix("No venue recorded"), "it says \(beneath)")
        // The day is still there, so naming the gap did not cost the fact beside
        // it: the two are one line and both belong on it.
        #expect(beneath.contains("Nov"), "the day went with the venue: \(beneath)")
    }

    @Test("and an empty venue is the same as none, not a gap of its own")
    func anemptyVenueIsTheSame() throws {
        let invoice = try Self.invoice(try Self.store())
        invoice.orderedShoots.first?.venue = "   "

        let beneath = try #require(Self.present(invoice).lines.first?.beneath)

        #expect(beneath.hasPrefix("No venue recorded"), "it says \(beneath)")
    }

    // MARK: when it falls due (ovation#473)

    /// THE FOOT SAYS WHEN IT WAS DATED AS WELL AS WHEN IT IS DUE, which the design
    /// record draws as "Dated 29 Aug 2026, due ...". The app printed only the due
    /// date, so the one number the other is derived from was on the screen nowhere.
    @Test("the foot carries the date the invoice was written as well as the day it falls due")
    func thefootCarriesBothDates() throws {
        let presenter = Self.present(try Self.invoice(try Self.store()))

        #expect(presenter.issued == "12 Nov 2026")
        #expect(presenter.due == "26 Nov 2026")
    }

    /// THE FOUR TERMS, EACH WITH THE DAY IT LANDS ON, which is what the design
    /// record's list shows beside each label rather than leaving the reader to
    /// count. Counted from the INVOICE date, so they do not move with the clock.
    @Test("the due control offers the four terms, each with the day it lands on")
    func theduecontrolOffersTheTerms() throws {
        let presenter = Self.present(try Self.invoice(try Self.store()))

        #expect(presenter.dueChoices.map(\.says) == ["On receipt", "7 days", "14 days", "30 days"])
        #expect(presenter.dueChoices.map(\.lands)
                    == ["12 Nov 2026", "19 Nov 2026", "26 Nov 2026", "12 Dec 2026"])
    }

    /// AND AN INVOICE WITH NO DATE OFFERS NO TERMS, because a term is counted from
    /// the invoice date and there is nothing to count from. An empty list is the
    /// honest answer; four entries all landing on today would be four guesses
    /// (L192).
    @Test("an invoice with no date of its own offers no terms to count from")
    func anundatedInvoiceOffersNoTerms() throws {
        let invoice = try Self.invoice(try Self.store())
        invoice.invoiceDate = nil

        let presenter = Self.present(invoice)

        #expect(presenter.dueChoices.isEmpty)
        #expect(presenter.issued == "")
    }

    /// WHICH TERM THE INVOICE IS ON, so the list can mark it rather than leaving
    /// the reader to compare four dates against the one at the foot (L605).
    @Test("the term the invoice is already on is the one marked")
    func thecurrentTermIsMarked() throws {
        let presenter = Self.present(try Self.invoice(try Self.store()))

        #expect(presenter.dueChoices.filter(\.isCurrent).map(\.says) == ["14 days"])
    }

    /// AND A DUE DATE ON NO TERM MARKS NOTHING, rather than the nearest one. A
    /// date Dan typed is its own answer and marking a term beside it would claim
    /// he had chosen that term (L11).
    @Test("a due date that is on none of the terms marks none of them")
    func adatedOnNoTermMarksNothing() throws {
        let invoice = try Self.invoice(try Self.store())
        invoice.dueDate = BusinessCalendar.day(forKey: "2026-11-20")

        let presenter = Self.present(invoice)

        #expect(presenter.dueChoices.contains { $0.isCurrent } == false)
        #expect(presenter.due == "20 Nov 2026")
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


    // MARK: adding a line (ovation#457, PRD 5.4)

    /// EVERY ACTIVE TYPE IS OFFERED, which is what the design record's own list
    /// draws. The hourly photography type is among them: nothing in the record
    /// takes it out, and removing it would be a change to the list Dan judged.
    @Test("the screen offers every active service type")
    func thescreenOffersEveryActiveType() throws {
        let context = try Self.store()
        let types = Self.seeded(context)
        let invoice = try Self.invoice(context)

        let offered = Self.present(invoice, types: types).serviceTypes

        #expect(offered.count == 3)
        #expect(Set(offered.map(\.name)) == ["Photography", "Rush turnaround", "Preview images"])
    }

    /// IN A DECLARED ORDER. A collection read from a store carries no order
    /// unless the read declares one, so a list rendered straight from a query is
    /// in whatever order came back (L343). The seeder's own order is not
    /// recoverable, because nothing records it.
    @Test("the types are offered in one declared order, by name")
    func thetypesAreInADeclaredOrder() throws {
        let context = try Self.store()
        let types = Self.seeded(context)
        let invoice = try Self.invoice(context)

        let offered = Self.present(invoice, types: types).serviceTypes

        #expect(offered.map(\.name) == ["Photography", "Preview images", "Rush turnaround"])
    }

    /// RETIRED RATHER THAN DELETED (PRD 5.30), so a retired type is still in the
    /// store and must be kept out of the list rather than found not to be there.
    @Test("a retired type is not offered, though it is still in the store")
    func aretiredTypeIsNotOffered() throws {
        let context = try Self.store()
        let types = Self.seeded(context)
        types[1].retiredOn = Self.today
        let invoice = try Self.invoice(context)

        let offered = Self.present(invoice, types: types).serviceTypes

        #expect(offered.map(\.name) == ["Photography", "Preview images"])
    }

    /// WHAT IT USUALLY CHARGES IS CARRIED, because that is what prefills the
    /// amount and is the whole reason the new type panel asks a second question.
    ///
    /// AND A TYPE WITH NO USUAL AMOUNT CARRIES NONE, never a zero: the design
    /// record says in terms that a type charging nothing and a type with no usual
    /// amount are different things, and one of them would prefill every line it
    /// is used on with 0.00 (PRD 5.1b).
    @Test("a type carries what it usually charges, and none is not a zero")
    func atypeCarriesItsUsualAmount() throws {
        let context = try Self.store()
        let types = Self.seeded(context)
        let invoice = try Self.invoice(context)

        let offered = Self.present(invoice, types: types).serviceTypes

        #expect(offered.first { $0.name == "Rush turnaround" }?.usually == Money(dollars: 150))
        #expect(offered.first { $0.name == "Preview images" }?.usually == nil)
    }

    /// A LINE MAY BE ADDED ONLY TO AN ORDINARY DRAFT, the same states the times
    /// and the due date may be typed on, and `InvoiceLineWriter` refuses the same
    /// ones, because a screen gating a write is not the write being guarded
    /// (L196).
    @Test("a sent invoice offers no line to add")
    func asentInvoiceOffersNoLineToAdd() throws {
        let context = try Self.store()
        let types = Self.seeded(context)
        let sent = try Self.invoice(context)
        sent.number = 1_042
        sent.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)

        #expect(Self.present(sent, types: types).mayAddLine(canMakeAType: true) == false)
        #expect(Self.present(try Self.invoice(context), types: types).mayAddLine(canMakeAType: true))
    }

    /// AN EMPTY TYPE LIST STILL OPENS ONTO ITS OWN LAST ENTRY (ovation#490). The
    /// list ends in the word that makes a type, so where the screen can make one
    /// the list is never empty, and hiding `Add a line` there took the only route
    /// to creating a type with it. On the day retiring exists, retiring the last
    /// type would have closed that door with no reason given (L109, L1009).
    @Test("with no type yet, a line may still be added, because the list offers making one")
    func withNoTypesALineCanStillBeAdded() throws {
        let invoice = try Self.invoice(try Self.store())

        #expect(Self.present(invoice).mayAddLine(canMakeAType: true))
    }

    /// AND WHERE NOTHING CAN BE MADE EITHER, the word stays hidden: then the list
    /// really would open onto nothing, the defect ovation#450 named (L109).
    @Test("with no type and no way to make one, there is no line to add")
    func withNoTypesAndNoMakingThereIsNoLine() throws {
        let invoice = try Self.invoice(try Self.store())

        #expect(Self.present(invoice).mayAddLine(canMakeAType: false) == false)
    }

    // MARK: the discount, as a control (ovation#457, PRD 5.4a)

    /// THE FIELD SHOWS THE SHARE, not the figure it comes to, because the share
    /// is what Dan typed and what he would change (PRD 5.4a).
    @Test("a share is offered as the share, with its unit in force")
    func ashareIsOfferedAsAShare() throws {
        let invoice = try Self.invoice(try Self.store())
        invoice.discount = Discount(percentBasisPoints: 1_000)

        let edit = try #require(Self.present(invoice).discountBeingEdited)

        #expect(edit.isPercent)
        #expect(edit.typed == "10")
    }

    /// A FRACTION SURVIVES THE TRIP, which is what basis points are for: 33.33%
    /// is 3,333 and must come back as it went in rather than as 33.
    @Test("a share with a fraction comes back whole")
    func ashareWithAFractionComesBack() throws {
        let invoice = try Self.invoice(try Self.store())
        invoice.discount = Discount(percentBasisPoints: 3_333)

        #expect(Self.present(invoice).discountBeingEdited?.typed == "33.33")
    }

    @Test("an amount is offered as an amount, in the unit money is written in")
    func anamountIsOfferedAsAnAmount() throws {
        let invoice = try Self.invoice(try Self.store())
        invoice.discount = Discount(dollars: Money(dollars: 50))

        let edit = try #require(Self.present(invoice).discountBeingEdited)

        #expect(edit.isPercent == false)
        #expect(edit.typed == "50.00")
    }

    /// NO DISCOUNT IS NO LINE. The design record puts it plainly: it "is not on
    /// the screen at all until there is one", because space is earned by
    /// frequency and 96% of issued invoices carry none.
    @Test("an invoice with no discount offers no line to edit")
    func noDiscountOffersNoLine() throws {
        let invoice = try Self.invoice(try Self.store())

        #expect(Self.present(invoice).discountBeingEdited == nil)
    }

    /// AND A SENT INVOICE OFFERS NO CONTROL EITHER, rather than one that opens
    /// onto a refusal (L651). `InvoiceDiscountWriter` refuses the same state,
    /// because a screen gating a write is not the write being guarded (L196).
    @Test("a sent invoice draws its discount without offering to change it")
    func asentInvoiceOffersNoDiscountControl() throws {
        let context = try Self.store()
        let sent = try Self.invoice(context)
        sent.discount = Discount(percentBasisPoints: 1_000)
        sent.number = 1_042
        sent.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)

        let screen = Self.present(sent)

        #expect(screen.discountBeingEdited == nil)
        // The FIGURE is still drawn: what a client was told is still on the page.
        #expect(screen.money.contains { $0.label.hasPrefix("Discount") })
    }

    // MARK: the status that was never recorded (ovation#457, PRD 5.5)

    /// NEVER RECORDED IS NOT THE SAME AS NOT EXEMPT, which PRD 5.5 states outright
    /// and `docs/design/invoice.html` draws: the tax line is not drawn at all and
    /// neither is the total, because a figure taken off a price nobody has
    /// established asserts something the screen cannot support.
    ///
    /// THIS WAS THE DEFECT (ovation#457, found 2026-09-22). `TaxStatus.isTaxed`
    /// answers true for a status nobody recorded, deliberately, so a return never
    /// under collects. The screen read that as a decision and printed
    /// "Sales tax, 8.875%" with a real figure and a total under it, which is a tax
    /// decision the app does not have, rendered as the recorded one (L192).
    @Test("a tax status nobody recorded draws no tax row and no total")
    func aneverRecordedStatusDrawsNeitherTaxNorTotal() throws {
        let invoice = try Self.invoice(try Self.store(), taxStatus: .neverRecorded)

        let labels = Self.present(invoice).money.map(\.label)

        #expect(labels.contains { $0.hasPrefix("Sales tax") } == false)
        #expect(labels.contains("Total") == false)
        // The subtotal IS known, and stays, so the screen is not left blank.
        #expect(labels.contains("Subtotal"))
    }

    /// AND IT IS ANSWERABLE WHERE IT IS SAID, which is the design record's own
    /// rule for this question: the two answers sit in the block that states the
    /// fact. Until this existed the foot named the one thing stopping the invoice
    /// and the screen offered no way to do it (L80, L111).
    @Test("the screen asks the question, in the design record's own sentence")
    func aneverRecordedStatusAsksTheQuestion() throws {
        let invoice = try Self.invoice(try Self.store(), taxStatus: .neverRecorded)

        let question = try #require(Self.present(invoice).taxQuestion)

        #expect(question.says == "Tax status never recorded for this client.")
    }

    /// A VOCABULARY IN CODE IS A PICKER, NEVER A TEXT BOX (L611), and the answers
    /// come from the one list the roster pass offers rather than a second copy
    /// written here. `neverRecorded` is the ABSENCE of an answer and can never be
    /// chosen, so offering it would let the question be answered with itself.
    @Test("its answers are the enum's own, and recording nothing is not one of them")
    func thetwoAnswersComeFromTheEnum() throws {
        let invoice = try Self.invoice(try Self.store(), taxStatus: .neverRecorded)

        let question = try #require(Self.present(invoice).taxQuestion)

        #expect(question.answers == TaxStatus.answers)
        #expect(question.answers.contains(.neverRecorded) == false)
        #expect(question.answers.isEmpty == false)
    }

    /// AND AN INVOICE WITH NO CLIENT IS THE SAME CASE, found while fixing the one
    /// above rather than separately (L387). `Invoice.tax` charges a clientless
    /// invoice, because its guard reads `client?.taxStatus.isTaxed ?? true`, while
    /// the money block's label read `== true` and so called it exempt: one row
    /// asserting an exemption over a charged figure.
    ///
    /// IT ASKS NOTHING, because the answer is a fact about a client and there is
    /// no client to record it against (L109).
    @Test("an invoice with no client draws no tax row and no total, and asks nothing")
    func aninvoiceWithNoClientDrawsNeitherAndAsksNothing() throws {
        let context = try Self.store()
        let invoice = try Self.invoice(context)
        invoice.client = nil

        let screen = Self.present(invoice)

        #expect(screen.money.map(\.label).contains { $0.hasPrefix("Sales tax") } == false)
        #expect(screen.money.map(\.label).contains("Total") == false)
        #expect(screen.taxQuestion == nil)
    }

    /// EVERY FACT ONCE PER SCREEN (L605). The foot says why Review cannot be
    /// pressed, and the money block now states the same fact with the two answers
    /// beside it. Saying it twice, four inches apart, in two different sentences,
    /// is the composition defect that only shows when the page is read as one
    /// surface, and it was drawn that way until it was looked at.
    ///
    /// THE BODY KEEPS IT, because that is where it can be acted on (L80), and it
    /// is the design record's own arrangement: the record draws this note
    /// permanently and puts the foot's sentence on a hover tip.
    @Test("the foot does not repeat a refusal the money block is already answering")
    func thefootDoesNotRepeatTheQuestion() throws {
        let invoice = try Self.invoice(try Self.store(), taxStatus: .neverRecorded)

        let screen = Self.present(invoice)

        #expect(screen.taxQuestion != nil)
        #expect(screen.refusalAtTheFoot == nil)
        // The gate's own answer is UNCHANGED, because Review is still refused and
        // the word still carries the reason to a screen reader (L53).
        #expect(screen.refusal == ReviewGate.sentence(for: .taxStatusNeverRecorded))
        #expect(screen.mayReview == false)
    }

    /// AND IT ONLY STANDS DOWN FOR THE FACT THE BLOCK IS ACTUALLY STATING. A
    /// missing payment line stops every invoice in the app and is said FIRST by
    /// the gate's own order, so a rule that went quiet whenever the question was
    /// on screen would hide it and send Dan to answer a tax status that is not
    /// what is stopping him (L324, L111).
    @Test("a different reason still reaches the foot while the question is on screen")
    func adifferentReasonStillReachesTheFoot() throws {
        let invoice = try Self.invoice(try Self.store(), taxStatus: .neverRecorded)
        let noPayment = InvoiceFooter(payment: "  ", note: "", contact: "dan@example.com")

        let screen = InvoiceScreenPresenter(invoice: invoice, footer: noPayment,
                                            today: Self.today)

        #expect(screen.taxQuestion != nil)
        #expect(screen.refusalAtTheFoot
                == ReviewGate.sentence(for: .paymentInstructionsNotSet))
    }

    /// AND WITH NO QUESTION ON SCREEN THE FOOT SAYS WHAT IT ALWAYS SAID, which is
    /// the positive control: without it a foot that never speaks would pass both
    /// cases above (L159).
    @Test("with nothing being asked in the body the foot still carries the refusal")
    func thefootStillCarriesAnOrdinaryRefusal() throws {
        let invoice = try Self.invoice(try Self.store(), until: nil, rate: nil)

        let screen = Self.present(invoice)

        #expect(screen.taxQuestion == nil)
        #expect(screen.refusalAtTheFoot == screen.refusal)
        #expect(screen.refusalAtTheFoot == "Waiting on the time the shoot ended.")
    }

    /// One way an invoice can reach the screen, and what its foot says with and
    /// without the tax question on screen beside it.
    private struct FootCase {
        let name: String
        /// The refusal that leads, or nil where the gate says nothing from the
        /// invoice's own vocabulary (no refusal, or a page that cannot be drawn).
        let leads: InvoiceRefusal?
        /// What the gate says with the question absent, or nil where no invoice
        /// without the question can reach this case.
        let refusalAlone: String??
        /// What the gate says with the question present, or nil where no invoice
        /// with the question can reach this case.
        let refusalAsked: String??
        /// What the foot draws with the question present.
        let footAsked: String??
        let footer: InvoiceFooter
        let shape: (ModelContext, TaxStatus) throws -> Invoice
    }

    /// EVERY REFUSAL AGAINST EVERY BODY REMEDY, which is ovation#483's proof that
    /// turning the pairing into data changed nothing anybody sees. It was written
    /// and passed against the condition it replaces, then kept unchanged.
    ///
    /// THE FIXTURE PROVES IT REACHED EACH STATE by asserting the gate's own answer
    /// before the foot's, so a case that fell into a neighbouring refusal fails
    /// rather than passing on the wrong one (L165). And the cases are checked to
    /// cover `ReviewGate.order` whole, so a refusal added to the vocabulary is a
    /// failure here rather than an untested row (L96).
    @Test("the foot stands down only for the refusal a body remedy answers, over every refusal")
    func thefootAgainstEveryRefusalAndRemedy() throws {
        let noPayment = InvoiceFooter(payment: "  ", note: "", contact: "dan@example.com")
        let noContact = InvoiceFooter(payment: "Pay by cheque.", note: "", contact: "")
        let tax = ReviewGate.sentence(for: .taxStatusNeverRecorded)
        func said(_ refusal: InvoiceRefusal) -> String?? { .some(ReviewGate.sentence(for: refusal)) }
        let nobody: String?? = .some(nil)
        let unreachable: String?? = nil

        let cases: [FootCase] = [
            FootCase(name: "nothing refused", leads: nil,
                     refusalAlone: nobody, refusalAsked: .some(tax), footAsked: nobody,
                     footer: .fixed) { try Self.invoice($0, taxStatus: $1) },
            FootCase(name: "no payment line", leads: .paymentInstructionsNotSet,
                     refusalAlone: said(.paymentInstructionsNotSet),
                     refusalAsked: said(.paymentInstructionsNotSet),
                     footAsked: said(.paymentInstructionsNotSet),
                     footer: noPayment) { try Self.invoice($0, taxStatus: $1) },
            FootCase(name: "no contact", leads: .contactDetailsNotSet,
                     refusalAlone: said(.contactDetailsNotSet),
                     refusalAsked: said(.contactDetailsNotSet),
                     footAsked: said(.contactDetailsNotSet),
                     footer: noContact) { try Self.invoice($0, taxStatus: $1) },
            FootCase(name: "no times", leads: .shootTimesNotGiven,
                     refusalAlone: said(.shootTimesNotGiven),
                     refusalAsked: said(.shootTimesNotGiven),
                     footAsked: said(.shootTimesNotGiven), footer: .fixed) {
                try Self.invoice($0, taxStatus: $1, from: nil, until: nil, rate: nil)
            },
            FootCase(name: "no end time", leads: .shootEndTimeNotGiven,
                     refusalAlone: said(.shootEndTimeNotGiven),
                     refusalAsked: said(.shootEndTimeNotGiven),
                     footAsked: said(.shootEndTimeNotGiven), footer: .fixed) {
                try Self.invoice($0, taxStatus: $1, until: nil, rate: nil)
            },
            FootCase(name: "no start time", leads: .shootStartTimeNotGiven,
                     refusalAlone: said(.shootStartTimeNotGiven),
                     refusalAsked: said(.shootStartTimeNotGiven),
                     footAsked: said(.shootStartTimeNotGiven), footer: .fixed) {
                try Self.invoice($0, taxStatus: $1, from: nil, rate: nil)
            },
            // 09:00 to 08:00 is 23 hours, a typo rather than a shoot.
            FootCase(name: "longer than a shoot", leads: .durationLongerThanAShoot,
                     refusalAlone: said(.durationLongerThanAShoot),
                     refusalAsked: said(.durationLongerThanAShoot),
                     footAsked: said(.durationLongerThanAShoot), footer: .fixed) {
                try Self.invoice($0, taxStatus: $1, from: "09:00", until: "08:00", rate: nil)
            },
            // UNREACHABLE WITHOUT THE QUESTION, because the question is asked of
            // exactly the condition that raises this refusal.
            FootCase(name: "tax status never recorded", leads: .taxStatusNeverRecorded,
                     refusalAlone: unreachable, refusalAsked: .some(tax), footAsked: nobody,
                     footer: .fixed) { try Self.invoice($0, taxStatus: $1) },
            FootCase(name: "nothing charged", leads: .nothingIsBeingCharged,
                     refusalAlone: said(.nothingIsBeingCharged),
                     refusalAsked: .some(tax), footAsked: nobody, footer: .fixed) {
                try Self.invoice($0, taxStatus: $1, rate: nil)
            },
            FootCase(name: "discount too large", leads: .discountExceedsSubtotal,
                     refusalAlone: said(.discountExceedsSubtotal),
                     refusalAsked: .some(tax), footAsked: nobody, footer: .fixed) {
                let invoice = try Self.invoice($0, taxStatus: $1)
                invoice.discount = Discount(dollars: Money(dollars: 1_000))
                return invoice
            },
            // $375 of charges and a line of minus $500.
            FootCase(name: "below zero", leads: .totalBelowZero,
                     refusalAlone: said(.totalBelowZero),
                     refusalAsked: .some(tax), footAsked: nobody, footer: .fixed) {
                let invoice = try Self.invoice($0, taxStatus: $1)
                invoice.add(LineItem.flat(Money(dollars: -500), describedAs: "Correction"))
                return invoice
            },
            FootCase(name: "no due date", leads: nil,
                     refusalAlone: .some(ReviewGate.sentence(forCannotBeDrawn: .noDueDate)),
                     refusalAsked: .some(tax), footAsked: nobody, footer: .fixed) {
                let invoice = try Self.invoice($0, taxStatus: $1)
                invoice.dueDate = nil
                return invoice
            },
            // UNREACHABLE WITH THE QUESTION: it is about a client, and there is none.
            FootCase(name: "no client", leads: nil,
                     refusalAlone: .some(ReviewGate.sentence(forCannotBeDrawn: .noClient)),
                     refusalAsked: unreachable, footAsked: unreachable, footer: .fixed) {
                let invoice = try Self.invoice($0, taxStatus: $1)
                invoice.client = nil
                return invoice
            },
        ]

        #expect(Set(cases.compactMap(\.leads)) == Set(ReviewGate.order),
                "every refusal the gate can say has a case here")

        for each in cases {
            if case .some(let expected) = each.refusalAlone {
                let invoice = try each.shape(try Self.store(), .notExempt)
                let screen = InvoiceScreenPresenter(invoice: invoice, footer: each.footer,
                                                    today: Self.today)
                #expect(screen.taxQuestion == nil, "\(each.name), not asked")
                #expect(screen.refusal == expected, "\(each.name), not asked")
                // WITH NOTHING ANSWERED IN THE BODY THE FOOT IS THE GATE, always.
                #expect(screen.refusalAtTheFoot == expected, "\(each.name), not asked")
            }
            if case .some(let expected) = each.refusalAsked,
               case .some(let foot) = each.footAsked {
                let invoice = try each.shape(try Self.store(), .neverRecorded)
                let screen = InvoiceScreenPresenter(invoice: invoice, footer: each.footer,
                                                    today: Self.today)
                #expect(screen.taxQuestion != nil, "\(each.name), asked")
                #expect(screen.refusal == expected, "\(each.name), asked")
                #expect(screen.refusalAtTheFoot == foot, "\(each.name), asked")
            }
        }
    }

    /// THE PAIRING IS DATA (ovation#483). Each control in the body that answers a
    /// refusal declares which, and no refusal is declared by two of them, so a
    /// second control answering the same fact is a failure here rather than a
    /// question of which one the foot believed (L83).
    @Test("every body remedy declares the one refusal it answers, and no two declare the same")
    func everyBodyRemedyDeclaresItsRefusalOnce() {
        let declared = InvoiceScreenPresenter.BodyRemedy.allCases.map(\.answers)

        #expect(declared.isEmpty == false)
        #expect(Set(declared).count == declared.count)
        #expect(InvoiceScreenPresenter.BodyRemedy.taxQuestion.answers == .taxStatusNeverRecorded)
    }

    /// AND WHAT IS ON SCREEN IS READ FROM THE SAME VALUES the view draws, so the
    /// foot can only stand down for a control that is actually there.
    @Test("the remedies on screen are exactly the body controls being drawn")
    func theremediesOnScreenAreTheOnesDrawn() throws {
        let asked = Self.present(try Self.invoice(try Self.store(), taxStatus: .neverRecorded))
        let answered = Self.present(try Self.invoice(try Self.store()))

        #expect(asked.remediesShown == [.taxQuestion])
        #expect(answered.remediesShown.isEmpty)
    }

    /// ASKED ONLY WHILE IT IS OUTSTANDING. A question still on the screen after it
    /// has been answered reads as the answer not having landed (L152).
    @Test("an answered status asks nothing, on either answer")
    func anansweredStatusAsksNothing() throws {
        let context = try Self.store()

        for status in TaxStatus.answers {
            let invoice = try Self.invoice(context, taxStatus: status)

            #expect(Self.present(invoice).taxQuestion == nil)
        }
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
