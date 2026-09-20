// ovation#167, PRD 50 to 50f. WHAT THE INVOICE PDF SAYS, as text, before anything is drawn.
//
// THE PAGE'S WORDS ARE DECIDED HERE AND NOWHERE ELSE. The renderer lays these
// strings out and the review sheet shows that rendering, so a label or a figure
// is chosen once and the preview cannot say something the attachment does not.
//
// THE SHAPE IS THE DESIGN RECORD'S. docs/design/invoice-pdf.html builds its page
// from the same sections in the same order, and OvationTests/InvoiceDocumentTests
// holds this to what that page draws for its seven fixtures, read from
// docs/design/invoice-pdf.expected.json rather than restated (L638).
import Foundation

/// The text in the page's footer.
///
/// PRD 9: these come from settings, and ovation#319 gave them a place there. The
/// values live in `InvoiceFooterSetting`; `fixed` below is only what a field Dan
/// has never written falls back to.
///
/// THE PAYMENT TERMS ARE NOT HERE. They count the invoice's own days (Dan,
/// 2026-09-14), so they belong to the invoice rather than to a sentence fixed in
/// advance; `PDFText.terms(days:)` writes them.
struct InvoiceFooter: Equatable, Sendable {
    // VAR, BECAUSE THIS IS ALSO WHAT SETTINGS EDITS (ovation#319). The type the
    // page is built from and the type Dan types into are ONE type: a second
    // struct beside it would be two vocabularies for one fact, and the copy
    // between them is where a field added to one stops reaching the other (L317).
    var payment: String
    var note: String
    var contact: String

    /// What a field Dan has never written falls back to, and nothing else. It is
    /// no longer what any page is built from: `scripts/check-invoice-footer-source.sh`
    /// refuses a reference to it from anything that draws or sends (ovation#319).
    static let fixed = InvoiceFooter(
        payment: "Payment instructions available upon request.",
        note: "Thank you for having me at your performance. Galleries are delivered within two weeks after the shoot.",
        contact: "dan@danwrightphotography.com")

    /// Why this footer stops an invoice going out, each as its own reason.
    ///
    /// THE PAYMENT LINE AND THE CONTACT ARE REQUIRED, THE NOTE IS NOT (Dan,
    /// 2026-09-17). A page asking somebody for money that does not say how to pay
    /// it, or how to reach the person asking, is not worth sending. A note is a
    /// pleasantry, and its absence is simply a shorter page.
    ///
    /// THESE ARE NOT PROPERTIES OF AN INVOICE, which is why they are computed here
    /// and not in `Invoice.refusals`: they are identical for every invoice in the
    /// app, and an invoice cannot see a setting. `ReviewGate` puts the two
    /// together and is the only thing that should be asked whether an invoice may
    /// go out.
    var refusals: Set<InvoiceRefusal> {
        var found: Set<InvoiceRefusal> = []
        if payment.isBlankOnThePage { found.insert(.paymentInstructionsNotSet) }
        if contact.isBlankOnThePage { found.insert(.contactDetailsNotSet) }
        return found
    }
}

extension String {
    /// Whether this would print as nothing.
    ///
    /// ONE PREDICATE, because the page and the refusal have to agree about what
    /// empty means (L70, L16): a footer that refuses the send and a page that
    /// draws the block anyway would be two answers to one question. A line of
    /// spaces is empty, because it draws a blank gap under a heading, which is the
    /// fault rather than the remedy.
    var isBlankOnThePage: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct InvoiceDocument: Equatable, Sendable {

    /// Why an invoice cannot be written as a page. Each is its own case, so what
    /// Dan is told names the one thing that is missing (L11).
    ///
    /// AN UNRECORDED TAX STATUS IS NOT ONE OF THESE. PRD 5b charges the tax and
    /// shows it like any other invoice; the refusal to SEND belongs to
    /// `Invoice.refusals`, and the page Dan reviews before that refusal is the same
    /// page as always.
    enum Refusal: Error, Equatable, Sendable {
        case noNumber
        case noInvoiceDate
        case noDueDate
        case noClient
        case discountExceedsSubtotal
        /// A stored day key that is not a calendar day. Refused rather than printed
        /// as something plausible (L50).
        case unreadableDate
        /// The terms would be a negative number of days, which is a mistake in the
        /// dates rather than a term to print.
        case dueBeforeInvoiceDate
    }

    struct FootBlock: Equatable, Sendable {
        let label: String
        let lines: [String]
    }

    let amountDueLabel: String
    let amountDue: String
    let dueLine: String
    /// Label and value pairs: Bill to, Invoice, Issued.
    let strip: [[String]]
    let title: String
    let columns: [String]
    /// One row per line item, in the invoice's order: description, the line
    /// beneath it, hours, rate, amount. An empty string is an empty cell.
    let items: [[String]]
    /// Label and figure pairs, top to bottom.
    let money: [[String]]
    let foot: [FootBlock]

    init(invoice: Invoice, footer: InvoiceFooter) throws {
        guard let number = invoice.number else { throw Refusal.noNumber }
        guard let invoiceDate = invoice.invoiceDate else { throw Refusal.noInvoiceDate }
        guard let dueDate = invoice.dueDate else { throw Refusal.noDueDate }
        guard let client = invoice.client else { throw Refusal.noClient }
        // The invoice's own predicate, so the page and the send cannot disagree
        // about what an oversized discount is (L16).
        if invoice.refusals.contains(.discountExceedsSubtotal) { throw Refusal.discountExceedsSubtotal }
        guard let issued = PDFText.date(invoiceDate), let due = PDFText.date(dueDate),
              let issuedStart = BusinessCalendar.startOfDay(forDayKey: invoiceDate.dayKey),
              let dueStart = BusinessCalendar.startOfDay(forDayKey: dueDate.dayKey)
        else { throw Refusal.unreadableDate }
        // Counted by business day from the recorded day keys, through the one
        // calendar that decides what a day is (L39). Signed, because the clamped
        // `wholeDays` would read a due date before the invoice date as due that day.
        let days = BusinessCalendar.dayNumber(for: dueStart) - BusinessCalendar.dayNumber(for: issuedStart)
        guard let terms = PDFText.terms(days: days) else { throw Refusal.dueBeforeInvoiceDate }

        amountDueLabel = "Amount due"
        // What is still owed, which is the total unless money is already applied
        // (Dan, 2026-09-14, ovation#167).
        amountDue = PDFText.money(invoice.amountOutstanding)
        dueLine = "by " + due
        strip = [["Bill to", client.name], ["Invoice", String(number)], ["Issued", issued]]
        title = "Invoice"
        columns = ["Description", "Hours", "Rate", "Amount"]
        items = try invoice.orderedLineItems.map(Self.row)
        money = Self.moneyRows(invoice, taxed: client.taxStatus.isTaxed)
        // A BLOCK WITH NOTHING TO SAY IS LEFT OFF, rather than drawn as a heading
        // over a gap (ovation#319). The page is still BUILT when a required line is
        // missing, and that is deliberate: Dan reviews this page before sending,
        // and a page that refused to draw would leave him unable to see what is
        // wrong with it. The refusal belongs to `ReviewGate`, which stops the send.
        //
        // THE TERMS KEEP THE PAYMENT BLOCK ALIVE. They are the invoice's own, never
        // blank, so an unwritten payment line shortens that block rather than
        // removing it, and "Payment due within 14 days" still reaches the client.
        foot = [
            FootBlock(label: "Payment", lines: [footer.payment, terms]),
            FootBlock(label: "Note", lines: [footer.note]),
            FootBlock(label: "Contact", lines: [footer.contact]),
        ]
        .map { FootBlock(label: $0.label, lines: $0.lines.filter { !$0.isBlankOnThePage }) }
        .filter { !$0.lines.isEmpty }
    }

    /// A shoot's line is named for the shoot, with its venue and day beneath. An
    /// extra is a type and an amount (PRD 51f), and the app holds no field for a
    /// line of detail beneath it, so none is written.
    private static func row(_ item: LineItem) throws -> [String] {
        var beneath: [String] = []
        if let shoot = item.shoot {
            if let venue = shoot.venue, !venue.isEmpty { beneath.append(venue) }
            if let day = shoot.day {
                guard let written = PDFText.date(day) else { throw Refusal.unreadableDate }
                beneath.append(written)
            }
        }
        return [
            item.shoot?.name ?? item.summary,
            beneath.joined(separator: ", "),
            // THE HOURS THE LINE ACTUALLY CHARGES (ovation#43). A shoot that has
            // been timed decides them, so the figure the client reads and the times
            // Dan typed are one fact rather than two that can be made to disagree.
            item.billedHours.map(PDFText.hours) ?? "",
            item.billedHours == nil ? "" : PDFText.money(item.unitAmount),
            PDFText.money(item.amount),
        ]
    }

    /// PRD 8 and 5.4a. The referral credit is its own block above the subtotal, the
    /// lines totalled as Services above it (Dan, 2026-09-14, ovation#131 and
    /// ovation#167); with no credit the two are one number and it is written once.
    /// A discount sits below the subtotal and the tax is charged on what is left.
    private static func moneyRows(_ invoice: Invoice, taxed: Bool) -> [[String]] {
        var rows: [[String]] = []
        if invoice.referralCreditAmount > .zero {
            rows.append(["Services", PDFText.money(invoice.subtotal + invoice.referralCreditAmount)])
            rows.append(["Referral credit", PDFText.money(-invoice.referralCreditAmount)])
        }
        rows.append(["Subtotal", PDFText.money(invoice.subtotal)])
        if let discount = invoice.discount {
            let share = discount.percentBasisPoints.map { " (\(percent($0)))" } ?? ""
            rows.append(["Discount" + share, PDFText.money(-invoice.discountAmount)])
            rows.append(["Taxable", PDFText.money(invoice.taxableAmount)])
        }
        let rate = taxed ? invoice.taxRate.description : "exempt"
        rows.append(["Sales tax (\(rate))", PDFText.money(invoice.tax)])
        // Money already applied sits BELOW the total (PRD 14k), and the page then
        // ends on what is still owed: Total, Payments received, Balance due (Dan,
        // 2026-09-14, ovation#167, chosen by looking at four wordings).
        if invoice.amountPaid > .zero {
            rows.append(["Total", PDFText.money(invoice.total)])
            rows.append(["Payments received", PDFText.money(-invoice.amountPaid)])
            rows.append(["Balance due", PDFText.money(invoice.amountOutstanding)])
        } else {
            rows.append(["Total due", PDFText.money(invoice.total)])
        }
        return rows
    }

    /// 1,000 basis points is "10%", 1,250 is "12.5%", 3,333 is "33.33%": to the
    /// precision it was given, and no further.
    private static func percent(_ basisPoints: Int64) -> String {
        let whole = basisPoints / 100
        let part = basisPoints % 100
        guard part != 0 else { return "\(whole)%" }
        return part % 10 == 0 ? "\(whole).\(part / 10)%" : "\(whole).\(part < 10 ? "0" : "")\(part)%"
    }
}
