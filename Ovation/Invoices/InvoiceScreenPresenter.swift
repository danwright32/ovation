// ovation#457, PRD 4, 4a, 5, 7, 8, 51a to 51l. The screen an invoice is actually
// built on, decided here rather than in a view.
//
// THE DESIGN WAS SETTLED FIRST AND THIS IS IT IN SWIFT. `docs/design/invoice.html`
// is nine rounds agreed with Dan, and every treatment below is that file's rather
// than a fresh judgement. Where a label differs from the PDF's it is because the
// two surfaces settled it separately: the PDF writes "Sales tax (8.875%)" and this
// screen writes "Sales tax, 8.875%", each chosen where it was drawn.
//
// EVERY CHOICE IS A VALUE A TEST CAN READ, which is how the invoice list and the
// review sheet are written too. The states that matter here are the ones no
// ordinary fixture produces: waiting on a time, a credit larger than the charges,
// an invoice already paid. A decision made in a view body can only be checked by
// rendering it.
//
// IT HOLDS NO CONTEXT AND WRITES NOTHING, which is PRD 51l and ovation#440 rather
// than tidiness. A screen holding an object from before an actor wrote to it puts
// its whole stale snapshot back on its next save: the allocated number is
// overwritten, nothing throws, and the surface reports success.
// `scripts/check-forbidden-constructs.sh` refuses a view that holds one.
//
// IT READS NO CLOCK. `today` arrives as an argument, so a screen cannot be right
// this morning and wrong tonight and no case has to wait for a date to pass (L74).
import Foundation
import SwiftData

@MainActor
@Observable
final class InvoiceScreenPresenter {

    /// One charge, as the four columns the design draws.
    struct Line: Identifiable, Equatable {
        let id: PersistentIdentifier
        /// What the line is for: the shoot's name, or the charge's own summary.
        let describes: String
        /// The venue and the day, beneath the description.
        let beneath: String
        /// Blank on a flat charge, which has no hours and must not read as zero.
        let hours: String
        /// Blank on a flat charge for the same reason.
        let rate: String
        let amount: String
        /// Whether `amount` is a word saying what is missing rather than a figure
        /// (round 3). Drawn quieter, and never red: an unpriced draft is work
        /// waiting, not something that has gone wrong (PRD 5.45).
        let amountIsAWord: Bool
    }

    /// One row of the money block, label and figure.
    struct MoneyRow: Equatable {
        let label: String
        let value: String
        /// Whether it is drawn as the closing figure rather than a step toward it.
        let isTotal: Bool
        /// Whether this is the discount's row, so the screen can put its
        /// controls directly beneath it.
        ///
        /// A FLAG RATHER THAN THE LABEL. The design record puts that line
        /// "beneath it", meaning beneath the discount row and above the tax and
        /// the total, and a view finding the row by matching its words would
        /// break on the first refinement of them, which already differ between
        /// a share and an amount (L103).
        var isDiscount = false
    }

    /// One shoot in the head, with the times Dan types and what they produce
    /// (round 4b: "beside the shoot", chosen by Dan and then re-drawn at the
    /// multiple event case he was worried about).
    struct TimedShoot: Identifiable, Equatable {
        let id: PersistentIdentifier
        let name: String
        let start: ClockTime?
        let end: ClockTime?
        /// What the times produce, or what is missing. Empty when there is
        /// nothing to say.
        let derived: String
    }

    /// The four columns, in the design's order.
    static let columns = ["Description", "Hours", "Rate", "Amount"]

    let client: String
    /// The shoot and its date, under the client. Never empty: an invoice with no
    /// shoot says so, because an empty line reads as a screen still loading (L10).
    let shoot: String
    let lines: [Line]
    let money: [MoneyRow]
    /// The due date as a date, or empty where there is none. BLANK RATHER THAN A
    /// PLACEHOLDER, which the design record states for the reason PRD 5.1b gives:
    /// a zero is a legitimate comped invoice and a missing value must not look
    /// like one.
    let due: String
    /// The date the invoice was written, rendered, or empty where it has none.
    ///
    /// THE FOOT SAYS BOTH (ovation#473). The design record draws "Dated 29 Aug
    /// 2026, due ...", and the app printed only the second, so the number every
    /// term is counted from appeared on the screen nowhere.
    let issued: String
    /// What the due control offers.
    let dueChoices: [DueChoice]
    /// Which the invoice IS, drawn at the top right: "Draft", "Invoice 1042", or a
    /// draft that is holding a number (ovation#411).
    let state: String
    /// Why this invoice cannot be reviewed, or nil when it can.
    let refusal: String?
    /// The refusal the FOOT draws, which is the gate's answer except where the
    /// money block is already stating that same fact with the two answers beside
    /// it. ovation#457.
    ///
    /// EVERY FACT ONCE PER SCREEN (L605). `refusal` is unchanged and still governs
    /// whether Review may be pressed and what it says to a screen reader; this is
    /// only what is DRAWN at the foot, and it exists because the tax question is
    /// the first refusal on this screen with a remedy in the body. Saying it in
    /// both places is the composition defect that shows only when the page is read
    /// as one surface, and it shipped that way until the screen was looked at.
    ///
    /// IT STANDS DOWN ONLY FOR A FACT A CONTROL ON SCREEN IS ANSWERING (L324). A
    /// missing payment line stops every invoice in the app and the gate says it
    /// FIRST, so a rule that went quiet whenever the question was on screen would
    /// hide it and send Dan to answer a tax status that is not what is stopping
    /// him.
    ///
    /// DERIVED FROM `remediesShown` RATHER THAN WRITTEN AS ONE CONDITION PER
    /// CONTROL (ovation#483). The tax question was the first remedy in the body
    /// and is not the last, and a rule each new control has to remember to join is
    /// one the next control forgets, with nothing but a screen that reads slightly
    /// wrong to show for it (L621).
    ///
    /// COMPARED AGAINST THE GATE'S OWN SENTENCE rather than a second copy of those
    /// words here, so the two cannot drift into disagreeing (L118, L370).
    let refusalAtTheFoot: String?

    /// A control in the body that answers a refusal where its fact is stated.
    /// ovation#483.
    ///
    /// EACH ONE DECLARES THE REFUSAL IT ANSWERS, through a switch with no default,
    /// so a control added here cannot be added without saying which fact the foot
    /// should then leave to it (L113). A control that answers no refusal is not a
    /// member at all.
    enum BodyRemedy: CaseIterable, Equatable {
        /// The tax status question in the money block, with its two answers.
        case taxQuestion

        /// The refusal this control answers.
        var answers: InvoiceRefusal {
            switch self {
            case .taxQuestion: return .taxStatusNeverRecorded
            }
        }
    }

    /// The body remedies this screen is drawing, in the order they are listed in
    /// `BodyRemedy`.
    ///
    /// READ FROM THE SAME VALUES THE VIEW DRAWS, so the foot stands down only for
    /// a control that is actually on screen (L16).
    let remediesShown: [BodyRemedy]

    /// The shoots, with their times, in the head.
    let shoots: [TimedShoot]
    /// The one question this screen asks about the CLIENT rather than the invoice,
    /// or nil once it has been answered. ovation#457, PRD 5.5.
    ///
    /// IT IS ANSWERABLE WHERE IT IS SAID, which is the design record's own rule:
    /// the two answers sit in the block that states the fact. Until this existed
    /// the foot named the one thing stopping the invoice and offered no way to do
    /// it, and the only place the status could be set was the roster pass, which
    /// is a different screen reached from a different place (L80, L111).
    let taxQuestion: TaxQuestion?

    /// The tax status question, as the design record draws it.
    struct TaxQuestion: Equatable {
        /// The design record's own sentence. It STATES THE FACT AND EXPLAINS NO
        /// INTERFACE (L604): the record settled deliberately that no sentence here
        /// says the answer is recorded on the client, because that was the
        /// interface being explained rather than the domain.
        let says: String
        /// The answers, from `TaxStatus.answers` rather than two strings written
        /// here, so this screen and the roster pass offer one list (L611, L89).
        let answers: [TaxStatus]
        /// WHO IT IS ABOUT, carried by the question rather than looked up again
        /// when it is answered. The answer is a fact about this client, so the
        /// action is addressed by the same thing the question was asked about and
        /// cannot land on another (L166).
        let about: PersistentIdentifier
    }

    /// One service type a line may be added as.
    ///
    /// THE IDENTIFIER IS CARRIED so the write is addressed by the same thing the
    /// choice was made about, rather than looked up again by name when it is
    /// used (L166).
    struct ServiceChoice: Identifiable, Equatable {
        let id: PersistentIdentifier
        let name: String
        /// What it usually charges, which prefills the amount, or nil where it
        /// has none. NIL RATHER THAN ZERO: the design record says in terms that a
        /// type charging nothing and a type with no usual amount are different
        /// things, and one of them would prefill every line with 0.00 (PRD 5.1b).
        let usually: Money?
    }

    /// The types a line may be added as.
    ///
    /// EVERY ACTIVE ONE, including the hourly photography type. Nothing in the
    /// design record takes it out of this list, and leaving it out would be a
    /// change to the list Dan judged rather than an implementation detail.
    ///
    /// IN A DECLARED ORDER, because a collection read from a store carries none
    /// unless the read declares one (L343). It is by name: the seeder's own order
    /// is not recoverable, since nothing records it.
    let serviceTypes: [ServiceChoice]

    /// Whether a line may be added at all.
    ///
    /// AN ORDINARY DRAFT WITH SOMETHING TO CHOOSE, and making a type counts. A word
    /// that opens a list with nothing in it is a control that does nothing, which
    /// is the defect ovation#450 named (L109), and `InvoiceLineWriter` refuses the
    /// same states this hides the word for, because a screen gating a write is not
    /// the write being guarded (L196).
    ///
    /// TWO CONDITIONS, AND THE SECOND HAS TWO WAYS TO HOLD (ovation#490). The list
    /// ends in the word that makes a type, so where the screen can make one it is
    /// never empty; requiring a type to exist hid the only route to creating the
    /// first one. Whether the screen CAN make one is the view's to say, since it
    /// holds the control, so it is asked rather than assumed.
    func mayAddLine(canMakeAType: Bool) -> Bool {
        mayEdit && (!serviceTypes.isEmpty || canMakeAType)
    }

    /// The discount as its own controls need it, or nil where there is none to
    /// edit or no editing it. ovation#457, PRD 5.4a.
    ///
    /// NO DISCOUNT IS NO LINE. The design record puts it plainly: it "is not on
    /// the screen at all until there is one", because space is earned by
    /// frequency and 96% of issued invoices carry none.
    struct DiscountEdit: Equatable {
        /// A share of the pre tax subtotal, or an amount off it.
        let isPercent: Bool
        /// The value as a person would type it, which is what the field shows.
        let typed: String
    }

    let discountBeingEdited: DiscountEdit?

    /// What the Edit menu needs to know about this invoice. ovation#457.
    ///
    /// BUILT HERE BECAUSE THIS IS WHERE THE INVOICE IS. The menu is declared on
    /// the app, outside every view, and the shell holds only this presenter, so
    /// turning the invoice into the values the menu reads is this type's own job
    /// and is done in the one place that already does it (PRD 51l).
    let editMenuFacts: InvoiceEditCommand.Open

    /// Whether the times may be typed at all.
    ///
    /// AN ORDINARY DRAFT ONLY. A sent invoice's times priced a document a client
    /// holds, and an unsettled send's may already be in their inbox, so the field
    /// is not offered rather than offered and then refused: a control that opens
    /// onto a refusal is a dead control (L651, L109). `ShootTimesWriter` refuses
    /// the same states, because a screen gating a write is not the write being
    /// guarded (L196).
    let mayEdit: Bool

    var mayReview: Bool { refusal == nil }

    init(invoice: Invoice, footer: InvoiceFooter, today: BusinessDate,
         serviceTypes: [ServiceType] = []) {
        // RETIRED RATHER THAN DELETED (PRD 5.30), so a retired type is still in
        // the store and is kept out here rather than found not to be there.
        self.serviceTypes = serviceTypes
            .filter { $0.retiredOn == nil }
            .map { ServiceChoice(id: $0.persistentModelID, name: $0.name,
                                 usually: $0.defaultUnitAmount) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        client = invoice.client?.name ?? "No client"
        shoot = Self.shootLine(invoice)
        lines = Self.rows(of: invoice)
        money = Self.moneyRows(invoice)
        due = invoice.dueDate.flatMap(BusinessCalendar.shortDate) ?? ""
        issued = invoice.invoiceDate.flatMap(BusinessCalendar.shortDate) ?? ""
        dueChoices = Self.dueChoices(for: invoice)
        state = Self.state(of: invoice)
        // ASKED OF THE SEND GATE, never decided again here, so the sentence on this
        // screen and the one the review refuses with cannot name different things
        // about one invoice (L118, L370). It is the whole question including the
        // footer's two reasons, because a screen offering Review must refuse
        // exactly what Review refuses (L651).
        refusal = ReviewGate.refusal(for: invoice, footer: footer)
        // ONE READING, used by the question itself and by the foot's decision
        // about whether to repeat it, so the two cannot disagree (L16).
        // THE FIGURE IS DRAWN ON A SENT INVOICE AND THE CONTROLS ARE NOT, which
        // is the rule the times and the due date already keep: what a client was
        // told stays on the page, and a control that opens onto a refusal is a
        // dead control (L651).
        discountBeingEdited = invoice.sentStatus == .notSent
            ? Self.discountEdit(invoice.discount) : nil
        editMenuFacts = InvoiceEditCommand.Open(invoice)
        let asking = Self.taxQuestion(for: invoice)
        taxQuestion = asking
        let shown = BodyRemedy.allCases.filter { remedy in
            switch remedy {
            case .taxQuestion: return asking != nil
            }
        }
        remediesShown = shown
        let answered = shown.map { ReviewGate.sentence(for: $0.answers) }
        refusalAtTheFoot = refusal.map(answered.contains) == true ? nil : refusal
        shoots = invoice.orderedShoots.map { Self.timed($0, on: invoice) }
        mayEdit = invoice.sentStatus == .notSent
    }

    /// One term the due control offers.
    struct DueChoice: Identifiable, Equatable, Sendable {
        var id: String { says }
        /// What the list calls it, from `PaymentTerms` rather than written again.
        let says: String
        /// The day it lands on, said beside the label rather than left to be
        /// counted, which is what the design record's own list draws.
        let lands: String
        let day: BusinessDate
        /// Whether the invoice is already on this term.
        let isCurrent: Bool
    }

    /// The terms, each counted from the INVOICE date.
    ///
    /// FROM THE INVOICE DATE, NEVER FROM TODAY, so the four dates in the list are
    /// the same ones tomorrow. A term computed at read time from the clock can
    /// never age, because every evaluation moves it forward (L74).
    ///
    /// AN INVOICE WITH NO DATE OFFERS NOTHING, because there is nothing to count
    /// from. Four entries all landing on today would be four guesses presented as
    /// the recorded answer (L192).
    ///
    /// AND A DUE DATE ON NO TERM MARKS NONE OF THEM rather than the nearest: a
    /// date Dan typed is its own answer, and marking a term beside it would claim
    /// he had chosen that term (L11).
    private static func dueChoices(for invoice: Invoice) -> [DueChoice] {
        guard let issued = invoice.invoiceDate else { return [] }
        return PaymentTerms.all.compactMap { term in
            guard let day = term.from(issued),
                  let lands = BusinessCalendar.shortDate(day) else { return nil }
            return DueChoice(says: term.says, lands: lands, day: day,
                             isCurrent: invoice.dueDate?.dayKey == day.dayKey)
        }
    }

    /// One shoot's times and what they produce.
    private static func timed(_ shoot: Shoot, on invoice: Invoice) -> TimedShoot {
        TimedShoot(id: shoot.persistentModelID, name: shoot.name,
                   start: shoot.shotFrom, end: shoot.shotUntil,
                   derived: derived(of: shoot, on: invoice))
    }

    /// THE ROUNDING IS NEVER SILENT, AND IT SAYS WHICH RULE MOVED THE FIGURE, which
    /// round 4 settled and neither of the two files the design record was merged
    /// from ever drew: both stopped at "billed as 1.50", so the reason the figure
    /// moved was on the page nowhere. `ShootDuration.Priced.atMinimum` has existed
    /// since it was written and nothing had read it (L46).
    private static func derived(of shoot: Shoot, on invoice: Invoice) -> String {
        guard let start = shoot.shotFrom, let end = shoot.shotUntil else {
            // Nothing to derive yet, and the row already carries the waiting word,
            // so the head says nothing rather than saying it twice (L605).
            return ""
        }
        switch ShootDuration.between(start, and: end) {
        case .priced(let priced):
            // THE REASON IS ALWAYS GIVEN, which is what round 4 settled, and it is
            // not a claim that the figure moved: it names the rule that produced
            // it. An earlier version here gave it only when the figure had moved
            // UP, which left the design's own worked example ("1h 32m, billed as
            // 1.50 hours, rounded to the nearest quarter") unexplained, because
            // 1.53 hours rounds DOWN to the quarter.
            let why = priced.atMinimum
                ? "the one hour minimum"
                : "rounded to the nearest quarter"
            return "\(elapsed(priced.elapsedMinutes)), billed as "
                + "\(PDFText.hoursFigure(priced.billed)) hours, \(why)"
        case .longerThanAShoot:
            // The gate's own short word, never a second wording of it (L118).
            return ReviewGate.says(for: .durationLongerThanAShoot) ?? ""
        }
    }

    /// What the head's state word says.
    ///
    /// AN UNSENT INVOICE IS A DRAFT HOWEVER FAR ALONG IT IS, which is PRD 46g and
    /// ovation#364: a number means the client has it, not that one was reserved.
    ///
    /// AND A DRAFT HOLDING A NUMBER SAYS SO (ovation#411, Dan 2026-09-21). PRD 10c
    /// gives a number back only while nothing was numbered after it, so an invoice
    /// that took one at Review and was never sent holds it permanently until it is
    /// sent or closed, and NOTHING anywhere said so: the list reads it as a draft
    /// by design, which is right there and left the number with no surface at all.
    /// Dan chose this screen over saying nothing and over reporting it only in the
    /// year end reconciliation, because here the number is a fact about the thing
    /// in front of him.
    private static func state(of invoice: Invoice) -> String {
        guard !invoice.sentStatus.wasSent else {
            return invoice.number.map { "Invoice \($0)" } ?? "Draft"
        }
        return invoice.number.map { "Draft, holding \($0)" } ?? "Draft"
    }

    /// The shoot and its day, or what the invoice has instead.
    private static func shootLine(_ invoice: Invoice) -> String {
        let shoots = invoice.orderedShoots
        guard let first = shoots.first else {
            // PRD 4 puts rush turnaround and preview images on the invoice rather
            // than on a shoot, so an invoice can legitimately have none. It says so
            // rather than drawing a blank where a name belongs.
            return "No shoot on this invoice"
        }
        var parts = [first.name]
        if shoots.count > 1 {
            // PRD 5.1a puts more than one shoot on a combined invoice, and the head
            // names the first with a count rather than a list that would not fit.
            parts.append("and \(shoots.count - 1) more")
        }
        if let day = first.day, let written = BusinessCalendar.shortDate(day) {
            parts.append(written)
        }
        return parts.joined(separator: ", ")
    }

    /// Every row the table draws.
    ///
    /// A SHOOT IS A ROW WHETHER OR NOT IT HAS BEEN PRICED, which is round 2 and
    /// round 3 of the design: the hours are typed into a plain field in the line,
    /// so the line has to exist before there are any hours to type into it. A
    /// table built from the LINE ITEMS alone draws nothing at all for the ordinary
    /// draft, which is the state every invoice starts in (PRD 3c).
    ///
    /// FOUND BY LOOKING AT THE RENDERING. Built from line items, the commonest
    /// screen in the product was a column header over an empty space (L606).
    private static func rows(of invoice: Invoice) -> [Line] {
        let byShoot = Dictionary(grouping: invoice.orderedLineItems) { $0.shoot?.persistentModelID }
        var rows: [Line] = []
        for shoot in invoice.orderedShoots {
            // PRICED MEANS A LINE CARRIES HOURS, which is the domain's own predicate
            // (`Invoice.shootsWithNoHours`) and not "a line exists". A real draft is
            // a shoot AND its photography line with no hours, because that is what
            // `Invoice.clearTimes(of:)` leaves and it is the shape that does not
            // dead end on `nothingIsBeingCharged`. Asked as "a line exists", that
            // draft drew the line, and a line with no hours reports its RATE as its
            // amount, so an unpriced draft read `250.00` (L16, L342).
            let priced = (byShoot[shoot.persistentModelID] ?? []).filter { $0.billedHours != nil }
            if priced.isEmpty {
                rows.append(Self.waitingRow(for: shoot, on: invoice))
            } else {
                rows += priced.map(Self.line)
            }
        }
        // PRD 4: rush turnaround and preview images belong to the INVOICE rather
        // than to a shoot, so they follow the shoots rather than being lost.
        rows += (byShoot[nil] ?? []).map(Self.line)
        return rows
    }

    /// A shoot with nothing priced against it yet: a word where the amount would
    /// be, in the design record's own short form.
    private static func waitingRow(for shoot: Shoot, on invoice: Invoice) -> Line {
        // THE SHORT FORM THE GATE OWNS, never a second wording written here, so
        // the word beside the figure and the sentence under the action come from
        // one place (L118, L370).
        let word = ReviewGate.order
            .first { invoice.refusals.contains($0) && ReviewGate.says(for: $0) != nil }
            .flatMap(ReviewGate.says)
        return Line(id: shoot.persistentModelID,
                    describes: shoot.name,
                    beneath: Self.beneath(shoot),
                    hours: "", rate: "",
                    amount: word ?? "",
                    amountIsAWord: word != nil)
    }

    /// Where the shoot was and when, under its description.
    ///
    /// ovation#95. THE VENUE IS HOW A SHOOT IS RECOGNISED: two invoices for one
    /// client in one week are told apart by where they were, not by the name
    /// repeated on both, and every handoff record Downbeat writes carries one.
    ///
    /// A MISSING ONE IS NAMED RATHER THAN LEFT AS A GAP. A required value shown
    /// as a blank is indistinguishable from one nobody needed (L67), and an
    /// omitted element does not remove the space it occupied, so the line simply
    /// read as a date sitting where a place should be (L626). A venue of
    /// whitespace drew a leading comma, which reads as a layout fault.
    ///
    /// ONE DERIVATION FOR BOTH LINES, the priced one and the one still waiting on
    /// a time, because they are two renderings of one fact and written twice they
    /// drift (L370).
    private static func beneath(_ shoot: Shoot) -> String {
        let venue = (shoot.venue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = [venue.isEmpty ? "No venue recorded" : venue]
        if let day = shoot.day, let written = BusinessCalendar.shortDate(day) {
            parts.append(written)
        }
        return parts.joined(separator: ", ")
    }

    /// One line's four columns.
    ///
    /// DERIVED THE SAME WAY THE PAGE DERIVES THEM (`InvoiceDocument.row`), because
    /// the figure a client reads and the figure Dan approves are one fact. What
    /// differs is only the formatting helper each surface uses.
    private static func line(_ item: LineItem) -> Line {
        return Line(
            id: item.persistentModelID,
            describes: item.shoot?.name ?? item.summary,
            beneath: item.shoot.map(Self.beneath) ?? "",
            // A FLAT CHARGE DRAWS NEITHER, blank rather than zero. The design
            // record says it in as many words: a value the invoice has no number
            // for yet is blank, never zero, because a zero is legitimate.
            hours: item.billedHours.map(PDFText.hours) ?? "",
            rate: item.billedHours == nil ? "" : PDFText.amount(item.unitAmount),
            amount: PDFText.amount(item.amount),
            amountIsAWord: false)
    }

    /// The money block, in the design's order.
    ///
    /// THE FIGURES ARE THE INVOICE'S OWN, never recomputed here, so this screen and
    /// the PDF cannot come to disagree about what an invoice comes to (L107).
    private static func moneyRows(_ invoice: Invoice) -> [MoneyRow] {
        // BLANK, NEVER ZERO, while the invoice has no number for these yet. The
        // design record states it exactly: "A value the invoice has no number for
        // yet. Blank, never zero: a zero total is a legitimate comped invoice (PRD
        // 5.1b) and the two must never look alike."
        //
        // FOUND BY LOOKING AT THE RENDERING (ovation#457). A draft waiting on the
        // time its shoot ended drew `Subtotal 0.00`, `Sales tax 0.00`, `Total 0.00`,
        // which is the same page a comped invoice draws, and is ovation#458's
        // defect class arriving on the screen instead of in the gate.
        let pending = invoice.isUnpriced
        func figure(_ amount: Money) -> String { pending ? "" : PDFText.amount(amount) }
        var rows: [MoneyRow] = []
        // PRD 8, round 6: the credit is its OWN block between the lines and the
        // subtotal, never a line among the charges, and the lines are totalled as
        // `Services` above it so the subtotal still explains itself.
        //
        // WITH NO CREDIT THE TWO ARE ONE NUMBER, so only the subtotal is drawn. A
        // `Services` row above an identical `Subtotal` states one fact twice (L605).
        if invoice.referralCreditAmount > .zero {
            rows.append(MoneyRow(label: "Services",
                                 value: figure(invoice.subtotal + invoice.referralCreditAmount),
                                 isTotal: false))
            rows.append(MoneyRow(label: "Referral credit",
                                 value: pending ? "" : "-" + PDFText.amount(invoice.referralCreditAmount),
                                 isTotal: false))
        }
        rows.append(MoneyRow(label: "Subtotal", value: figure(invoice.subtotal), isTotal: false))
        // PRD 4a: below the subtotal, and the tax is charged on what is left, so
        // `Taxable` follows or the subtotal stops explaining the tax.
        if let discount = invoice.discount {
            let share = discount.percentBasisPoints.map { ", \(percent($0))" } ?? ""
            rows.append(MoneyRow(label: "Discount" + share,
                                 value: pending ? "" : "-" + PDFText.amount(invoice.discountAmount),
                                 isTotal: false, isDiscount: true))
            rows.append(MoneyRow(label: "Taxable", value: figure(invoice.taxableAmount),
                                 isTotal: false))
        }
        // NEVER RECORDED IS NOT THE SAME AS NOT EXEMPT, which PRD 5.5 states
        // outright, and neither the tax nor the total is drawn until it has been
        // answered. The design record draws exactly this: "a figure taken off a
        // price nobody has established asserts something the screen cannot
        // support."
        //
        // THE DEFECT THIS FIXES (ovation#457, found 2026-09-22). `isTaxed` answers
        // TRUE for a status nobody recorded, deliberately, so a tax return can
        // never under collect on an unknown. The screen read that as a decision
        // and printed "Sales tax, 8.875%" with a real figure and a total beneath
        // it, which is a tax decision the app does not have rendered as the
        // recorded one (L192). The two zeroes on this screen are different things
        // and so are the two taxed states: an exempt client's $0.00 is a MEASURED
        // value, and an unanswered status has no value at all.
        //
        // AND A CLIENTLESS INVOICE IS THE SAME CASE, found in this diff rather than
        // separately (L387). `invoice.tax` charges it, because its own guard reads
        // `client?.taxStatus.isTaxed ?? true`, while the label here read `== true`
        // and so called it exempt: one row asserting an exemption over a charged
        // figure. Nothing recorded a status for a client that does not exist, so
        // neither row is drawn, and `ReviewGate` already refuses the invoice
        // through `InvoiceDocument.refusalToRender`.
        //
        // ONE READING OF THE STATUS decides both the label and whether the row is
        // there, so the word and the figure beside it cannot disagree again (L544).
        guard let status = invoice.client?.taxStatus, status != .neverRecorded else {
            return rows
        }
        // THE DESIGN'S OWN SEPARATOR, a comma rather than the PDF's parenthesis.
        // Both were settled on the surface they are drawn on.
        let rate = status.isTaxed ? invoice.taxRate.description : "exempt"
        rows.append(MoneyRow(label: "Sales tax, \(rate)", value: figure(invoice.tax),
                             isTotal: false))
        rows.append(MoneyRow(label: "Total", value: figure(invoice.total), isTotal: true))
        return rows
    }

    /// What a value typed into the discount's field asks for. ovation#495.
    ///
    /// AN UNREADABLE VALUE IS A ZERO OF THE UNIT IN FORCE, which is how
    /// `docs/design/invoice.html` handles it: its field reads `isFinite(n) ? n :
    /// 0` and keeps `DISCOUNT.kind`. Dan decided on 2026-09-23 that the app
    /// follows the record here, which retired an earlier version that left the
    /// discount alone.
    ///
    /// WHAT IS READABLE IS `Hundredths`'s answer, the one parser every typed
    /// figure goes through (L370), each unit stripping only its own sign so a
    /// figure typed into one cannot be read as the other's (L118).
    ///
    /// READABLE BUT REFUSED IS NIL, and the discount is left where it is. A share
    /// outside nothing to everything and a negative amount are what `Discount`'s
    /// own initialisers refuse, and the decision is about a value that cannot be
    /// read, not about one that can.
    static func discountAsked(typed: String, isPercent: Bool) -> Discount? {
        let read = Hundredths.read(typed, stripping: isPercent ? "%" : "$") ?? 0
        return isPercent
            ? Discount(percentBasisPoints: read)
            : Discount(dollars: Money(cents: read))
    }

    /// What committing a typed discount saves, and what the field then shows.
    /// ovation#495.
    ///
    /// THE FIELD SHOWS WHAT WAS SAVED, as the design record's redraw does. The
    /// store's own reseed fires only when the discount CHANGES, so an unreadable
    /// value typed over a discount already at zero would otherwise stay in the
    /// field while the invoice carried the zero, and the field would say
    /// something the invoice does not. Nil where the discount refuses the value
    /// and nothing is saved.
    struct DiscountCommit: Equatable {
        let discount: Discount
        let fieldShows: String
    }

    static func discountCommitted(typed: String, isPercent: Bool) -> DiscountCommit? {
        guard let discount = discountAsked(typed: typed, isPercent: isPercent),
              let shown = discountEdit(discount) else { return nil }
        return DiscountCommit(discount: discount, fieldShows: shown.typed)
    }

    /// The discount as the field shows it.
    ///
    /// THE SHARE, NOT THE FIGURE IT COMES TO, because the share is what Dan
    /// typed and what he would change (PRD 5.4a). It goes out through the same
    /// `Hundredths` that reads it back, so editing a discount cannot change it
    /// by looking at it (L317).
    static func discountEdit(_ discount: Discount?) -> DiscountEdit? {
        guard let discount else { return nil }
        if let points = discount.percentBasisPoints {
            return DiscountEdit(isPercent: true, typed: Hundredths.text(points))
        }
        guard let dollars = discount.dollarsOff else { return nil }
        return DiscountEdit(isPercent: false, typed: PDFText.amount(dollars))
    }

    /// The tax status question, asked only while it is outstanding.
    ///
    /// AND ONLY WHERE THERE IS SOMEBODY TO ANSWER ABOUT. A clientless invoice has
    /// no recorded status either, but the answer is a fact about a client, so a
    /// question with nowhere to put its answer is not asked (L109).
    private static func taxQuestion(for invoice: Invoice) -> TaxQuestion? {
        guard let client = invoice.client, client.taxStatus == .neverRecorded else { return nil }
        return TaxQuestion(says: "Tax status never recorded for this client.",
                           answers: TaxStatus.answers,
                           about: client.persistentModelID)
    }

    /// "20m", "1h", "1h 32m": the design record's own `elapsedText`. A zero hour
    /// and a zero minute are each left out rather than written, because "0h 20m"
    /// and "1h 0m" are both a quantity of nothing drawn.
    private static func elapsed(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        guard hours > 0 else { return "\(rest)m" }
        return rest > 0 ? "\(hours)h \(rest)m" : "\(hours)h"
    }

    /// A percentage as the design writes it, from basis points.
    private static func percent(_ basisPoints: Int64) -> String {
        let whole = basisPoints / 100
        let fraction = abs(basisPoints % 100)
        guard fraction != 0 else { return "\(whole)%" }
        var digits = String(format: "%02d", fraction)
        while digits.hasSuffix("0") { digits.removeLast() }
        return "\(whole).\(digits)%"
    }
}
