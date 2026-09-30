// ovation#568 and ovation#482. The Clients screen, decided here rather than in a
// view: the names down the left, and one client's page on the right.
//
// BUILT FROM THE RECORD, docs/design/clients.html, settled over eight rounds on
// 2026-09-07 and 2026-09-10 (ovation#98, #40, #96) and extended on 2026-09-26 by
// the tax status correction (ovation#482, PRD 51j1). Each rule below names where
// it was settled.
//
// IT READS NO STORE AND NO CLOCK. The clients arrive as an argument, read in the
// same read as the invoice list and the rail's held money line (PRD 46b), so the
// boxes on a client's page and the figure under the rail's card are summed from
// one list and cannot disagree (L107). Everything is turned into VALUES at
// construction, and a model object is never handed to the view (PRD 51l, L443).
//
// A QUANTITY OF NOTHING IS NOT DRAWN (Dan, 2026-09-07). No held money box, no
// referral box and no figure beside a name for a client holding nothing. An
// absence meaning something is MISSING is drawn out loud, which is why a client
// with no tax status reads Not recorded.
import Foundation
import SwiftData

struct ClientsPresenter: Equatable {

    /// One name down the left.
    struct NameRow: Identifiable, Equatable {
        let clientID: UUID
        var id: UUID { clientID }
        let name: String
        /// Money Ovation is holding for this client, or nil where it holds nothing.
        /// The row draws it everywhere EXCEPT beside that client's own open page
        /// (PRD 14n), which `heldFigure(on:selected:)` decides.
        let held: String?
    }

    /// Where one held balance came from (round E, PRD 14l).
    struct Arrival: Equatable {
        let words: String
        let amount: String
    }

    /// One invoice on a client's page.
    struct InvoiceLine: Identifiable, Equatable {
        let invoiceID: PersistentIdentifier
        var id: PersistentIdentifier { invoiceID }
        /// The number the client holds, or empty for a draft, whose status says so.
        let number: String
        let shoot: String
        let date: String
        let amount: String
        let status: String
        /// The tax status it went out under, or nil while it has not gone out
        /// (ovation#482).
        let sentUnder: TaxStatus?
        /// Whether its send is SETTLED as sent, which is what the status column
        /// calls "Sent" (L629): an unsettled send is listed as "Send not settled".
        let isSent: Bool
        /// Whether it carries any sales tax at all, so "charged sales tax" is said
        /// only of one that was.
        let chargedTax: Bool
    }

    /// What pressing one of the two tax answers on a client's page does (PRD 51j1).
    enum TaxPress: Equatable {
        /// The answer given is the one recorded, so there is nothing to change.
        case nothing
        /// Saved at once: nothing can have been sent under a status nobody recorded.
        case record(TaxStatus)
        /// A recorded status would change, so Ovation says what that means first.
        case ask(TaxQuestion)
    }

    /// Asked before a recorded status is changed (Dan, 2026-09-23, ovation#482).
    ///
    /// THE WORDS ARE THE DESIGN RECORD'S DRAFTING (docs/design/clients.html),
    /// approved by Dan on 2026-09-27 (ovation#600) with the zero case said plainly;
    /// see `correction(sent:chargedUnder:becoming:)`.
    struct TaxQuestion: Equatable {
        let from: TaxStatus
        let to: TaxStatus
        let sentence: String
        var change: String { "Change to \(to.exportLabel)" }
        var keep: String { "Keep \(from.exportLabel)" }
    }

    /// Another client on the same address, named so the page can take Dan to it
    /// (ovation#616).
    struct Sharer: Identifiable, Equatable {
        let clientID: UUID
        var id: UUID { clientID }
        let name: String
    }

    /// One name in the shared address notice and the words that follow it.
    struct SharedName: Identifiable, Equatable {
        let sharer: Sharer
        let after: String
        var id: UUID { sharer.clientID }
    }

    /// One client's page.
    struct Page: Identifiable, Equatable {
        let clientID: UUID
        var id: UUID { clientID }
        /// What a write names this client by.
        let storeID: PersistentIdentifier
        let name: String

        /// Where invoices go: one value as written, or nil where there is none.
        let goesTo: String?
        /// Why that value cannot be sent to, or nil where it can.
        let addressProblem: String?
        /// Said where the value holds more than one address, which is a VALUE and
        /// not a fault (Dan, 2026-09-07).
        let recipients: String?
        /// Who booked, named ONLY where invoices go somewhere else (1 of 31).
        let bookedBy: String?

        let taxStatus: TaxStatus
        /// The standing payment terms (PRD 51j): the client's own, or the default.
        let paymentTerm: PaymentTerm
        /// The other clients whose invoices go to the same address, while nobody
        /// has said that is correct for THIS address (PRD 38c), in the names'
        /// order. Empty when there is nothing to ask.
        ///
        /// THE NOTICE AND ITS NAMES ARE ONE ANSWER (ovation#616, L16): the notice
        /// is drawn exactly when this names somebody.
        let sharesAddressWith: [Sharer]

        /// Whether the shared address notice is drawn.
        var sharedAddressAsks: Bool { !sharesAddressWith.isEmpty }

        /// The notice's sentence as each name and the words after it, so the view
        /// can draw every name as a way to that client (L80) and still read as
        /// one sentence: "A uses this address too.", "A and B use this address
        /// too.", "A, B and C use this address too."
        var sharedSaid: [SharedName] {
            let last = sharesAddressWith.count - 1
            return sharesAddressWith.enumerated().map { index, sharer in
                let after: String
                if index == last {
                    after = last == 0 ? " uses this address too." : " use this address too."
                } else {
                    after = index == last - 1 ? " and" : ","
                }
                return SharedName(sharer: sharer, after: after)
            }
        }

        let held: String?
        /// Where held money came from: the sentence for none or one arrival, the
        /// list for more than one (round E).
        let heldSaid: String?
        let arrivals: [Arrival]
        /// Referral credit, in hours, with its unit (PRD 51k1).
        let referral: String?

        let invoices: [InvoiceLine]

        /// What the Sales tax value reads.
        var taxSaid: String { ClientsPresenter.said(taxStatus) }

        /// How many invoices already sent to this client went out under `status`.
        ///
        /// COUNTED FROM THE INVOICES THIS PAGE LISTS, never written beside them, so
        /// the sentence cannot say a number the list does not hold (L180, PRD 51j1).
        ///
        /// ONLY SENDS THE PAGE LISTS AS SENT, and under a taxed status only those
        /// that carried tax, so the sentence says of each one exactly what is true
        /// (review of ovation#600, L629).
        func sentCharged(under status: TaxStatus) -> Int {
            invoices.filter {
                $0.isSent && $0.sentUnder == status && (!status.isTaxed || $0.chargedTax)
            }.count
        }

        /// What pressing `answer` does (PRD 51j1).
        func press(_ answer: TaxStatus) -> TaxPress {
            guard answer != .neverRecorded, answer != taxStatus else { return .nothing }
            guard taxStatus != .neverRecorded else { return .record(answer) }
            return .ask(TaxQuestion(from: taxStatus, to: answer,
                                    sentence: ClientsPresenter.correction(
                                        sent: sentCharged(under: taxStatus),
                                        chargedUnder: taxStatus, becoming: answer)))
        }
    }

    let rows: [NameRow]
    let pages: [UUID: Page]

    var count: Int { rows.count }

    /// The page to show: the one selected, or the first name when nothing is, or
    /// when the selected client is no longer there.
    func page(for selected: UUID?) -> Page? {
        if let selected, let page = pages[selected] { return page }
        return rows.first.flatMap { pages[$0.clientID] }
    }

    /// THE HELD FIGURE IS NOT DRAWN ON THE ROW WHOSE BOX IS OPEN BESIDE IT (Dan,
    /// 2026-09-10, PRD 14n), so the row depends on the SELECTION, and a view that
    /// drew it only where the row is built would be right on load and never again.
    func heldFigure(on row: NameRow, selected: UUID?) -> String? {
        row.clientID == page(for: selected)?.clientID ? nil : row.held
    }

    init(clients: [Client]) {
        // ORDERED BY NAME, declared rather than inherited from the fetch (L343),
        // with the identity breaking a tie so two clients sharing a name keep one
        // order from read to read (L419).
        let ordered = clients.sorted {
            let order = $0.name.compare($1.name, options: [.caseInsensitive, .diacriticInsensitive])
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString
                                         : order == .orderedAscending
        }
        rows = ordered.map {
            NameRow(clientID: $0.id, name: $0.name,
                    held: $0.moneyHeld > .zero ? PDFText.money($0.moneyHeld) : nil)
        }
        var built: [UUID: Page] = [:]
        for client in ordered {
            // In the names' order, so the notice names them the way the list does.
            let others = ordered.filter { $0.id != client.id }
            built[client.id] = Self.page(for: client, sharingWith: others)
        }
        pages = built
    }

    // MARK: the words

    /// A status as the client's page says it. Never recorded reads "Not recorded",
    /// the record's own words for a question nobody has asked yet (PRD 45).
    static func said(_ status: TaxStatus) -> String {
        status == .neverRecorded ? "Not recorded" : status.exportLabel
    }

    /// The design record's drafted sentence, `taxAsk` in docs/design/clients.html,
    /// approved by Dan on 2026-09-27 (ovation#600) with one change: where nothing
    /// went out under the old status it says so plainly rather than "0 invoices ...
    /// were charged". That zero case is Claude's drafting under his instruction.
    static func correction(sent: Int, chargedUnder old: TaxStatus, becoming new: TaxStatus) -> String {
        guard sent > 0 else {
            let what = old.isTaxed ? "was charged sales tax" : "went out without sales tax"
            return "No invoice already sent to this client \(what), so none change. "
                + "Drafts and every invoice from now on will be \(new.exportLabel)."
        }
        let charged = old.isTaxed ? "charged sales tax" : "not charged sales tax"
        return "\(sent)" + (sent == 1 ? " invoice" : " invoices")
            + " already sent to this client " + (sent == 1 ? "was " : "were ") + charged
            + ", and stay as they were sent. Drafts and every invoice from now on will be "
            + new.exportLabel + "."
    }

    // MARK: one page

    private static func page(for client: Client, sharingWith others: [Client]) -> Page {
        let problem = client.contactProblems.isEmpty ? nil : "Not an address"
        let count = client.recipientsForInvoices.count
        let arrivals = arrivals(of: client)
        let heldSaid: String?
        if client.moneyHeld <= .zero {
            heldSaid = nil
        } else if arrivals.isEmpty {
            // Nothing recorded about where it came from is its own state, and it
            // is said rather than left blank: the money is real either way.
            heldSaid = "Received, not yet applied to an invoice"
        } else if arrivals.count == 1 {
            // A SINGLE ARRIVAL IS NEVER BROKEN DOWN: one row restating the figure
            // above it is the same number twice (round E).
            heldSaid = arrivals[0].words
        } else {
            heldSaid = nil
        }
        return Page(
            clientID: client.id, storeID: client.persistentModelID, name: client.name,
            goesTo: client.emailForInvoices, addressProblem: problem,
            recipients: count > 1 ? (count == 2 ? "Two recipients" : "\(count) recipients") : nil,
            bookedBy: client.passedOverForInvoices,
            taxStatus: client.taxStatus,
            paymentTerm: PaymentTerms.standing(days: client.paymentTermDays),
            sharesAddressWith: client.sharersStillAsking(among: others, address: \.emailForInvoices)
                .map { Sharer(clientID: $0.id, name: $0.name) },
            held: client.moneyHeld > .zero ? PDFText.money(client.moneyHeld) : nil,
            heldSaid: heldSaid,
            arrivals: arrivals.count > 1 ? arrivals : [],
            referral: client.referralBalance > .zero ? PDFText.hours(client.referralBalance) : nil,
            invoices: lines(of: client))
    }

    /// Each payment still holding money, named by how it arrived (PRD 14l): money
    /// recorded against an invoice and left over is an overpayment on it, anything
    /// else a deposit. Oldest first.
    private static func arrivals(of client: Client) -> [Arrival] {
        client.payments
            .filter { $0.unallocated > .zero }
            .sorted { $0.receivedOn.dayKey < $1.receivedOn.dayKey }
            .map { payment in
                let against = payment.allocations
                    .filter { !$0.isHeldMoney }
                    .compactMap { allocation -> Int64? in
                        let invoice = allocation.invoice
                        return invoice?.number
                    }
                    .first
                let words = against.map { "Overpaid on invoice \(String($0))" }
                    ?? "Deposit received " + (BusinessCalendar.dayAndMonth(payment.receivedOn) ?? "")
                return Arrival(words: words, amount: PDFText.money(payment.unallocated))
            }
    }

    /// The client's invoices, newest first, undated drafts at the top. A deleted
    /// draft is not one of them.
    private static func lines(of client: Client) -> [InvoiceLine] {
        client.invoices
            .filter {
                if case .deleted = $0.closure { return false }
                return true
            }
            .sorted { a, b in
                let left = a.invoiceDate?.dayKey ?? "9999"
                let right = b.invoiceDate?.dayKey ?? "9999"
                if left != right { return left > right }
                return (a.number ?? Int64.max) > (b.number ?? Int64.max)
            }
            .map { invoice in
                InvoiceLine(
                    invoiceID: invoice.persistentModelID,
                    number: invoice.number.map { String($0) } ?? "",
                    shoot: invoice.orderedShoots.map(\.name)
                        .filter { !$0.isEmpty }.joined(separator: " and "),
                    date: invoice.invoiceDate.flatMap(BusinessCalendar.shortDate) ?? "",
                    amount: PDFText.amount(invoice.total),
                    status: status(of: invoice),
                    sentUnder: invoice.taxStatusWhenSent,
                    isSent: invoice.sentStatus.wasSent,
                    chargedTax: invoice.tax > .zero)
            }
    }

    /// Where an invoice stands, in the words the design record draws ("Sent,
    /// unpaid", "Paid"), each fact once.
    static func status(of invoice: Invoice) -> String {
        if case .cancelled = invoice.closure { return "Cancelled" }
        switch invoice.sentStatus {
        case .notSent: return "Draft"
        case .attempting, .couldNotDetermine: return "Send not settled"
        case .sent:
            switch invoice.paymentState {
            case .paid: return "Paid"
            case .partlyPaid: return "Sent, partly paid"
            case .unpaid: return "Sent, unpaid"
            }
        }
    }
}

/// What is open on one client's page, and what a press does to it (PRD 51j, 51j1).
///
/// A VALUE RATHER THAN STATE SCATTERED THROUGH THE VIEW, so every press can be
/// driven by a test without a window: the view holds one of these and does what it
/// says. It belongs to ONE page, and the view starts a fresh one when the selection
/// moves, so a question asked about one client can never be answered on another.
struct ClientPageInteraction: Equatable {
    /// The two answers are showing beside the Sales tax value.
    var taxIsOpen = false
    /// A recorded status would change, and this is being asked first.
    var asking: ClientsPresenter.TaxQuestion?
    /// The four terms are showing under the Payment terms value.
    var termsAreOpen = false

    /// The Sales tax value was pressed: it opens the answers, or closes them.
    mutating func pressTaxValue() {
        taxIsOpen.toggle()
        asking = nil
    }

    /// One answer was pressed. Returns the status to write NOW, or nil where
    /// nothing is written yet, either because nothing changes or because it asks.
    mutating func pressAnswer(_ answer: TaxStatus, on page: ClientsPresenter.Page) -> TaxStatus? {
        taxIsOpen = false
        switch page.press(answer) {
        case .nothing:
            return nil
        case .record(let status):
            return status
        case .ask(let question):
            asking = question
            return nil
        }
    }

    /// "Change to": the status to write, and the question is closed.
    mutating func change() -> TaxStatus? {
        defer { asking = nil }
        return asking?.to
    }

    /// "Keep": nothing is written.
    mutating func keep() { asking = nil }
}
