// ovation#49, PRD section 6, 46, 46a, 46d, 46f, 46g. The invoice list, decided
// here rather than in a view.
//
// THE BANDS ARE NOT DRAWN (PRD 46). They decide the ORDER and nothing else: a
// heading reading "Send it today" over a row whose action word reads Send labels
// one fact three times, and with one to three invoices per band nearly every
// other line on screen would be a heading.
//
// THE CARD IS COUNTED FROM THE ROWS' OWN ACTIONS, which is the design record's
// derivation rather than a second one invented here (`docs/design/invoice-list.html`).
// Counting from the BANDS instead would be wrong twice over: a blocked draft sits
// in a band and must not be counted (PRD 46f), and a row the held money band moved
// must be counted where it is drawn rather than in the band it was taken out of
// (PRD 46d). Both fall out of reading the action, and neither falls out of reading
// the band. PRD 46a says in its own words that its mapping is unenforceable
// without this, and the fault it exists to prevent is one Dan found on 2026-09-10:
// a band saying 2 above a list that did not hold 2 (L107).
//
// IT READS NO STORE AND NO CLOCK. Everything arrives as an argument, which is what
// lets the whole surface be driven by a test without a window or a container, and
// what stops a row being right today and wrong tomorrow (L74, L130).
import Foundation
import SwiftData

@MainActor
@Observable
final class InvoiceListPresenter {

    /// One invoice, as one line (PRD 47).
    struct Row: Identifiable, Equatable {
        let invoiceID: PersistentIdentifier
        var id: PersistentIdentifier { invoiceID }

        /// The client, drawn lighter than the shoot beside it.
        let client: String
        /// THE SHOOT CARRIES THE WEIGHT, NOT THE CLIENT (Dan, 2026-09-09, settled
        /// against three alternatives and shown to him on a client holding three
        /// separate invoices for three shoots). Two invoices for one client in one
        /// week are told apart by what they were, not by the name repeated on both.
        /// On a combined invoice this is the LAST shoot, with `otherShoots` beside
        /// it, because the run reads forward to the one that closed it.
        let shoot: String
        /// How many shoots are on this invoice BESIDES the one named. Zero on an
        /// ordinary invoice, and PRD 5.1a's combined drafts are why it is not.
        let otherShoots: Int
        /// The shoot's date, a span across a combined invoice's shoots, or the
        /// words for having no date at all.
        let shootDate: String
        /// The number, or `draft`. PRD 46g: an invoice that took a number and was
        /// never sent says `draft` too, because this column means the client has
        /// this number, not that one was reserved.
        let number: String
        /// What it comes to, and on a part paid invoice what is left of it.
        let amount: String
        /// The exact thing to do, or nil where the band means there is nothing.
        let action: String?
        /// How long it has been overdue, and nil where it is not.
        let age: String?

        /// Whether the card counts this row, which is decided by the ACTION and
        /// therefore cannot disagree with what the row offers.
        var isCountedOnCard: Bool { InvoiceListPresenter.cardLine(for: action) != nil }
    }

    /// One band and the rows in it. A band holding nothing is not here at all:
    /// PRD 46 draws no headings, so an empty band would be a gap in the list with
    /// nothing on screen saying what it is.
    struct BandRows: Equatable {
        let band: InvoiceBand
        let rows: [Row]
    }

    /// One line of the sidebar card (PRD 46a).
    struct CardLine: Equatable {
        let label: String
        let count: Int
    }

    private(set) var bands: [BandRows] = []
    private(set) var card: [CardLine] = []

    /// - Parameters:
    ///   - invoices: every invoice in the store, in whatever order it came back.
    ///     The order is declared here and never inherited (L343).
    ///   - heldMoney: what Ovation is holding for each client, which PRD 46d needs
    ///     and no single invoice can answer about itself.
    ///   - today: the day the list is being read on, injected.
    init(invoices: [Invoice], heldMoney: [Client: Money], today: BusinessDate) {
        // TWO PASSES, AND THE FIRST ONE CANNOT BE SKIPPED. Whether an invoice
        // belongs in the held money band is a fact about its client's WHOLE set of
        // open invoices, so every invoice has to be read before any of them can be
        // banded (PRD 14j, 46d).
        let first = invoices.map {
            (invoice: $0, standing: InvoiceStanding(of: $0, today: today,
                                                    couldSettleMoreThanOne: false))
        }
        let waiting = Self.clientsWhoseMoneyCouldSettleMoreThanOne(first, heldMoney: heldMoney)

        var byBand: [InvoiceBand: [(Row, sortKey: Int)]] = [:]
        for (invoice, read) in first {
            // THE CLIENT QUALIFIES, THE INVOICE MOVES, and those are two different
            // questions. Held money waiting on a decision is a fact about a CLIENT,
            // so the set above is a set of clients; applying it to every invoice
            // that client has would sweep up their drafts and their settled
            // invoices too. Only the invoices the money could actually settle
            // move, which is the same predicate the set was counted over (L16).
            let moves = read.isOpen && read.sent.wasSent
                && (invoice.client.map { waiting.contains($0) } ?? false)
            let standing = InvoiceStanding(of: invoice, today: today,
                                           couldSettleMoreThanOne: moves)
            // TOTAL BY CONSTRUCTION. `InvoiceBandTests` proves that exactly one
            // band claims every drawn state, so `first` here is the only one, and
            // a state claimed by nothing is a deleted invoice and nothing else.
            guard let band = InvoiceBand.allCases.first(where: { $0.claims(standing) }) else {
                continue
            }
            let row = Self.row(for: invoice, standing: standing, band: band, today: today)
            // SORTED ON THE SAME NUMBER THE BAND WAS DECIDED FROM, so a row cannot
            // sit in a band on one reading of its date and be ordered by another
            // (L545). A dateless draft is banded as long ago and sorts that way.
            byBand[band, default: []].append((row, standing.shootDay ?? Int.min))
        }

        // OLDEST FIRST WITHIN EACH BAND (PRD section 6), with the invoice's own id
        // breaking a tie so two invoices on one day come back in the same order on
        // every run rather than in whatever order the store returned (L343, L419).
        bands = InvoiceBand.allCases.compactMap { band in
            guard let rows = byBand[band], !rows.isEmpty else { return nil }
            let ordered = rows.sorted {
                $0.sortKey != $1.sortKey ? $0.sortKey < $1.sortKey
                                         : ($0.0.client, $0.0.shoot) < ($1.0.client, $1.0.shoot)
            }
            return BandRows(band: band, rows: ordered.map(\.0))
        }

        card = Self.card(over: bands)
    }

    // MARK: the card

    /// Which card line rolls up that action, and nil for an action no line counts.
    ///
    /// NIL IS A REAL ANSWER AND NOT A GAP. A blocked draft's action is the thing it
    /// is waiting for, and the card's lines count what Dan can act on from the list
    /// (PRD 46f). `Receipts to file` counts the other half of the product, which
    /// has no rows here at all.
    nonisolated static func cardLine(for action: String?) -> String? {
        switch action {
        case Action.send: return "To send"
        case Action.remind: return "To chase"
        case Action.markCleared, Action.markSent: return "To confirm"
        case Action.useItHere: return "To place"
        default: return nil
        }
    }

    /// The card's lines, in the order it draws them, counted from the rows.
    ///
    /// A LINE WITH NOTHING BEHIND IT IS NOT DRAWN, because the card's promise is
    /// that a number in it means this many things need you, and a row of zeroes is
    /// noise on the screen Dan works from every day.
    private static func card(over bands: [BandRows]) -> [CardLine] {
        var counts: [String: Int] = [:]
        for row in bands.flatMap(\.rows) {
            guard let line = cardLine(for: row.action) else { continue }
            counts[line, default: 0] += 1
        }
        return ["To place", "To send", "To chase", "To confirm"]
            .compactMap { label in
                counts[label].map { CardLine(label: label, count: $0) }
            }
    }

    // MARK: who the held money band moves

    /// The clients whose held money could settle more than one open invoice.
    ///
    /// PRD 14h and 14j are two halves of one rule and both are applied here. With
    /// exactly ONE open invoice Ovation applies the money itself and there is
    /// nothing to ask, so nothing moves. With more than one it applies it to none
    /// of them and asks on each, which is what this band is.
    ///
    /// ZERO IS NOT SOME. A client holding nothing has nothing to place, and a
    /// presence check that accepts any value would move every one of their invoices
    /// into a band asking a question about no money (L706).
    ///
    /// A DRAFT IS NOT AN OPEN INVOICE HERE, and that is read off the design record
    /// rather than decided in this file. `docs/design/invoice-list.html` draws
    /// Cedar Hill Youth Orchestra with TWO invoices in the waiting band and a THIRD
    /// Cedar Hill row, a draft, sitting outside it in the drafts to send. That
    /// arrangement was rendered and settled, so a draft stays where its dates put
    /// it and only an issued invoice can be one of the several this money could
    /// settle.
    ///
    /// IT IS DELIBERATELY NOT THE WHOLE QUESTION. Whether money can be recorded
    /// against a draft at all, and where a deposit sits before the booking even
    /// reaches Ovation, is ovation#96, which records in terms that it has no
    /// answer yet. This reads the one arrangement that HAS been settled and leaves
    /// that issue everything else (L61, L542).
    private static func clientsWhoseMoneyCouldSettleMoreThanOne(
        _ read: [(invoice: Invoice, standing: InvoiceStanding)],
        heldMoney: [Client: Money]
    ) -> Set<Client> {
        var open: [Client: Int] = [:]
        for (invoice, standing) in read where standing.isOpen && standing.sent.wasSent {
            guard let client = invoice.client else { continue }
            open[client, default: 0] += 1
        }
        return Set(open.compactMap { client, count in
            count > 1 && (heldMoney[client] ?? .zero) > .zero ? client : nil
        })
    }

    // MARK: what a row says

    /// The exact words a row's action can carry. Named rather than written at each
    /// site, because the card counts them and a typo in one place would silently
    /// stop a row being counted anywhere (L113, L611).
    enum Action {
        static let send = "Send"
        static let remind = "Remind"
        static let markCleared = "Mark cleared"
        static let markSent = "Mark sent"
        static let useItHere = "Use it here"
        static let addDate = "Add date"
        static let addHours = "Add hours"
        static let addTaxStatus = "Add tax status"
    }

    private static func row(for invoice: Invoice, standing: InvoiceStanding,
                            band: InvoiceBand, today: BusinessDate) -> Row {
        let shoots = invoice.orderedShoots
        return Row(
            invoiceID: invoice.persistentModelID,
            client: invoice.client?.name ?? "",
            shoot: shoots.last?.name ?? "",
            otherShoots: max(shoots.count - 1, 0),
            shootDate: span(of: shoots)
                ?? invoice.invoiceDate.flatMap(BusinessCalendar.shortDate) ?? "no date",
            // PRD 46g: `draft` whether or not a number is being held.
            number: invoice.sentStatus.wasSent
                ? invoice.number.map(String.init) ?? "draft"
                : "draft",
            amount: amount(invoice),
            action: action(for: invoice, band: band),
            age: age(of: standing))
    }

    /// The dates a combined invoice covers, as one span, and nil where there is
    /// nothing to span.
    ///
    /// PRD 5.1a lets Dan combine several drafts onto one invoice, each shoot its
    /// own line, so the date column has several dates to show in one cell. It
    /// collapses what the two ends share, which is the design record's own rule
    /// (`docs/design/invoice-list.html`): a run inside one month reads
    /// "2 to 6 Sep 2026" rather than repeating the month twice.
    private static func span(of shoots: [Shoot]) -> String? {
        let days = shoots.compactMap(\.day)
        guard let first = days.first, let last = days.last, days.count > 1,
              let from = BusinessCalendar.shortDate(first),
              let to = BusinessCalendar.shortDate(last)
        else { return nil }
        guard from != to else { return to }
        let start = from.split(separator: " "), end = to.split(separator: " ")
        guard start.count == 3, end.count == 3 else { return from + " to " + to }
        if start[1] == end[1] && start[2] == end[2] { return "\(start[0]) to \(to)" }
        return "\(start[0]) \(start[1]) to \(to)"
    }

    /// What the row shows in the amount column.
    ///
    /// A PART PAID ROW SAYS WHICH FIGURE IT IS SHOWING (PRD section 6), and that is
    /// not decoration: under the accrual basis the year end export carries the
    /// invoice's FULL value in the year it was issued, so the same invoice is two
    /// different numbers in two places on purpose, and an unlabelled pair reads as
    /// a defect in one of them.
    ///
    /// AN UNPRICED DRAFT SAYS SO RATHER THAN SHOWING A ZERO (ovation#117, PRD 3c).
    /// A comped invoice really does come to nothing, and a surface inferring one
    /// from the other would draw two states that need opposite actions the same way.
    private static func amount(_ invoice: Invoice) -> String {
        if invoice.isUnpriced { return "no price" }
        // A COMPED SHOOT SAYS SO RATHER THAN SHOWING 0.00 (PRD 1b). A zero invoice
        // is an ordinary invoice that happens to total nothing, occasionally
        // drafted because a corporate client's accounts payable needs the
        // paperwork, and a bare 0.00 in a column of money reads as a fault.
        if invoice.total == .zero { return "comped" }
        guard invoice.paymentState == .partlyPaid else {
            return PDFText.amount(invoice.total)
        }
        return PDFText.amount(invoice.amountOutstanding)
            + " owed of " + PDFText.amount(invoice.total)
    }

    /// The exact thing to do about this row, or nil where the band means there is
    /// nothing to do yet.
    ///
    /// A BLOCKED DRAFT'S ACTION NAMES THE MISSING THING (PRD 46f, Dan 2026-09-19),
    /// even where that thing is a fact about the CLIENT and is answered elsewhere.
    /// `Open client` was drawn beside it and rejected: naming the destination makes
    /// one row read as a different kind of row when for the reader it is the same
    /// situation three times.
    private static func action(for invoice: Invoice, band: InvoiceBand) -> String? {
        switch band {
        case .toPlace: return Action.useItHere
        case .overdue: return Action.remind
        case .checkNotCleared: return Action.markCleared
        case .sayWhetherItWasSent: return Action.markSent
        case .draftShootToday, .draftNeedsSending:
            return blocker(of: invoice) ?? Action.send
        // NOTHING TO DO YET, and that is the band's whole meaning. An ahead draft
        // offering Send would put every future shoot in the card's To send count,
        // which is the view PRD section 6 says the ordering exists to replace.
        case .draftShootAhead: return blocker(of: invoice)
        // WAITING ON THEM, NOT ON DAN. Chasing is what the overdue band offers, and
        // offering it here would make every sent invoice a task the day it went.
        case .sentAwaitingPayment, .paidOrCleared, .cancelled: return nil
        }
    }

    /// What this draft is waiting for, or nil when it is ready to go.
    ///
    /// ASKED IN `ReviewGate`'S OWN ORDER, never a second ranking written here, so
    /// the word on the row and the sentence on the send gate cannot name different
    /// things about one invoice (L118, L370). The footer's two reasons are
    /// deliberately not consulted: they stop every invoice in the app at once, and
    /// a list saying `Add date` on one row and a Settings problem on the rest would
    /// send Dan to the wrong screen (L111).
    private static func blocker(of invoice: Invoice) -> String? {
        if invoice.invoiceDate == nil { return Action.addDate }
        let refusals = invoice.refusals
        for refusal in ReviewGate.order where refusals.contains(refusal) {
            switch refusal {
            case .shootTimesNotGiven, .shootEndTimeNotGiven, .shootStartTimeNotGiven:
                return Action.addHours
            case .taxStatusNeverRecorded:
                return Action.addTaxStatus
            // THE REST ARE NOT MISSING FACTS, they are numbers already typed that
            // come to something the invoice cannot be sent as. The row cannot name
            // a thing to add, so it offers Send and the gate refuses with the
            // sentence that explains it, which is where that reasoning already
            // lives (ovation#136, ovation#384).
            case .durationLongerThanAShoot, .discountExceedsSubtotal, .totalBelowZero,
                 .paymentInstructionsNotSet, .contactDetailsNotSet:
                continue
            // ovation#458. A MISSING FACT, unlike the five above, and still no word
            // here. The words in this column are PRD 46a's vocabulary and the
            // sidebar card counts by them, so an eighth is a change to a settled
            // screen rather than a line in this switch, and ovation#450 owns that
            // question for all of them at once. Until it is answered the row offers
            // Send and the gate refuses by name, which is what the five above
            // already do. Nothing in the app can reach this state today: the only
            // code that creates an invoice outside tests is the Debug sample world.
            case .nothingIsBeingCharged:
                continue
            }
        }
        return nil
    }

    /// How long it has been overdue, as an age rather than an alarm (PRD 45).
    ///
    /// NO RED ANYWHERE (Dan, 2026-09-06: red "feels like something is wrong"). An
    /// overdue invoice is not an error: nothing failed, the money has not arrived.
    private static func age(of standing: InvoiceStanding) -> String? {
        guard let dueDay = standing.dueDay, dueDay < InvoiceBand.today else { return nil }
        return "\(InvoiceBand.today - dueDay)d"
    }
}
