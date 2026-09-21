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
    /// Why this invoice cannot be reviewed, or nil when it can.
    let refusal: String?

    var mayReview: Bool { refusal == nil }

    init(invoice: Invoice, footer: InvoiceFooter, today: BusinessDate) {
        client = invoice.client?.name ?? "No client"
        shoot = Self.shootLine(invoice)
        lines = Self.rows(of: invoice)
        money = Self.moneyRows(invoice)
        due = invoice.dueDate.flatMap(BusinessCalendar.shortDate) ?? ""
        // ASKED OF THE SEND GATE, never decided again here, so the sentence on this
        // screen and the one the review refuses with cannot name different things
        // about one invoice (L118, L370). It is the whole question including the
        // footer's two reasons, because a screen offering Review must refuse
        // exactly what Review refuses (L651).
        refusal = ReviewGate.refusal(for: invoice, footer: footer)
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
            if let priced = byShoot[shoot.persistentModelID], !priced.isEmpty {
                rows += priced.map(Self.line)
            } else {
                rows.append(Self.waitingRow(for: shoot, on: invoice))
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
        var beneath: [String] = []
        if let venue = shoot.venue, !venue.isEmpty { beneath.append(venue) }
        if let day = shoot.day, let written = BusinessCalendar.shortDate(day) {
            beneath.append(written)
        }
        // THE SHORT FORM THE GATE OWNS, never a second wording written here, so
        // the word beside the figure and the sentence under the action come from
        // one place (L118, L370).
        let word = ReviewGate.order
            .first { invoice.refusals.contains($0) && ReviewGate.says(for: $0) != nil }
            .flatMap(ReviewGate.says)
        return Line(id: shoot.persistentModelID,
                    describes: shoot.name,
                    beneath: beneath.joined(separator: ", "),
                    hours: "", rate: "",
                    amount: word ?? "",
                    amountIsAWord: word != nil)
    }

    /// One line's four columns.
    ///
    /// DERIVED THE SAME WAY THE PAGE DERIVES THEM (`InvoiceDocument.row`), because
    /// the figure a client reads and the figure Dan approves are one fact. What
    /// differs is only the formatting helper each surface uses.
    private static func line(_ item: LineItem) -> Line {
        var beneath: [String] = []
        if let shoot = item.shoot {
            if let venue = shoot.venue, !venue.isEmpty { beneath.append(venue) }
            if let day = shoot.day, let written = BusinessCalendar.shortDate(day) {
                beneath.append(written)
            }
        }
        return Line(
            id: item.persistentModelID,
            describes: item.shoot?.name ?? item.summary,
            beneath: beneath.joined(separator: ", "),
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
                                 isTotal: false))
            rows.append(MoneyRow(label: "Taxable", value: figure(invoice.taxableAmount),
                                 isTotal: false))
        }
        // THE DESIGN'S OWN SEPARATOR, a comma rather than the PDF's parenthesis.
        // Both were settled on the surface they are drawn on.
        let rate = invoice.client?.taxStatus.isTaxed == true ? invoice.taxRate.description : "exempt"
        rows.append(MoneyRow(label: "Sales tax, \(rate)", value: figure(invoice.tax),
                             isTotal: false))
        rows.append(MoneyRow(label: "Total", value: figure(invoice.total), isTotal: true))
        return rows
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
