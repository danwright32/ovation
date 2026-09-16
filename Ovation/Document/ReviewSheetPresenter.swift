import CoreGraphics
import Foundation

/// What the review sheet says, decided here rather than in a view (ovation#318).
///
/// PRD 52a to 52c. The sheet is the only place Dan sees what ships before it ships
/// (L64), so every choice on it is a value a test can read: which recipients are
/// drawn, whether anybody was passed over, how large the page is. A decision made
/// inside a view body can only be checked by rendering it, and the states that
/// matter here are the ones no ordinary fixture produces.
///
/// IT RENDERS NOTHING AND DECIDES NOTHING ABOUT THE PAGE'S CONTENT. The one render
/// belongs to `ReviewSession`, which is what makes the preview the attachment (PRD
/// 10c); this asks it for the bytes and asks for them again at another scale.
@MainActor
@Observable
final class ReviewSheetPresenter {

    private let session: ReviewSession
    private let document: InvoiceDocument
    private let client: Client
    /// The invoice's due date, as it stood when this review opened. PRD 7's warning
    /// is about a stored date against today, so both ends are held: a fixture that
    /// pins only one walks into another state as real time passes (L130).
    private let dueDate: BusinessDate?
    /// Injected, because a warning computed from the clock at read time can never
    /// age and can never be tested (L74, L290).
    private let now: () -> Date

    /// How large the page is drawn. It starts fitted: the page is taller than the
    /// sheet's visible area, and 47% is what fits (PRD 52b).
    private(set) var scale: InvoicePageScale = .fitted

    init(session: ReviewSession, document: InvoiceDocument, client: Client,
         dueDate: BusinessDate?, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.document = document
        self.client = client
        self.dueDate = dueDate
        self.now = now
    }

    /// What the sheet is about, in the design's words: "Invoice 1123, A Client"
    /// (PRD 52, `docs/design/review-send.html`). Read from the DOCUMENT rather than
    /// from the invoice, so the line names what the page being reviewed says, not
    /// what the record says now; an edit since the render is ovation#42's question
    /// and `ReviewSession.isStale` is what answers it (L443).
    var subtitle: String {
        let number = document.strip.first { $0.first == "Invoice" }?.last ?? ""
        let client = document.strip.first { $0.first == "Bill to" }?.last ?? ""
        return "Invoice \(number), \(client)"
    }

    // MARK: the page

    /// The width the page is drawn at, in points, DERIVED from the page's own size
    /// rather than written down beside it: a review screen may not re-typeset the
    /// page to fit a column, so the only thing that changes is how large it is
    /// (PRD 52b, 10c).
    /// CGFloat, NOT Double, and that is the app's rule rather than a preference:
    /// floating point is forbidden on the money path and CGFloat is deliberately
    /// exempt as a LAYOUT quantity (scripts/check-forbidden-constructs.sh). A page
    /// width is layout.
    var pageWidth: CGFloat { (Self.pagePoints * CGFloat(scale.factor)).rounded() }

    /// A US Letter page, which is what InvoicePDF draws.
    private static let pagePoints: CGFloat = 612

    /// How many times the session has rendered, for the tests that hold this to one
    /// render however many times the page is shown (PRD 10c).
    var renderCount: Int { session.renderCount }

    func show(on page: InvoicePageSink) throws {
        try session.show(on: page)
    }

    /// PRD 52b: the way to open the page is visible at rest and sits above it.
    func open(on page: InvoicePageSink) throws {
        scale = .opened
        try session.zoom(to: .opened, on: page)
    }

    func close(on page: InvoicePageSink) throws {
        scale = .fitted
        try session.zoom(to: .fitted, on: page)
    }

    // MARK: the band about the due date (PRD 7, 52e)

    /// How close to the due date counts as close. Named rather than written into
    /// the sentence, because it is a judgement about when a warning is worth
    /// drawing and PRD 7 says only "close" (L401).
    static let closeWithinDays = 3

    /// The band, or nil on an ordinary send. It is INFORMATION: nothing can answer
    /// it except changing the date, so it carries no control (PRD 52e).
    ///
    /// COUNTED IN DAYS, from the business day each instant falls in, because two
    /// instants on one day are one day whatever the clock says (L39, ovation#64).
    var dueDateWarning: String? {
        guard let dueDate,
              let dueStart = BusinessCalendar.startOfDay(forDayKey: dueDate.dayKey),
              let written = BusinessCalendar.shortDate(dueDate)
        else { return nil }

        let days = BusinessCalendar.dayNumber(for: now()) - BusinessCalendar.dayNumber(for: dueStart)
        if days > 0 {
            let unit = days == 1 ? "day" : "days"
            return "This is already \(days) \(unit) past its due date of \(written)."
        }
        if days == 0 { return "This is due today, \(written)." }
        let ahead = -days
        guard ahead <= Self.closeWithinDays else { return nil }
        let unit = ahead == 1 ? "day" : "days"
        return "This is due in \(ahead) \(unit), on \(written)."
    }

    // MARK: who it goes to (PRD 52c)

    /// Every address this invoice goes to, which is usually one and is sometimes
    /// several. The model decides it, because the same question is asked by the send
    /// (L613).
    var recipients: [String] { client.recipientsForInvoices }

    /// Who was passed over, and nil in the ordinary case.
    ///
    /// SAYING WHY IS SAYING NOTHING when the address is whoever booked the shoot,
    /// which is 30 of the 31 real clients (PRD 52c). It is said only where the
    /// address is genuinely somewhere else AND there is a main address to name: a
    /// sentence reading "not , who booked it" is worse than no sentence at all.
    var passedOver: String? { client.passedOverForInvoices }

    /// The state where the invoice can go nowhere, stated rather than drawn as an
    /// empty list, because an empty list reads as a screen that has not loaded
    /// (L10, L67).
    var noRecipientsSentence: String? {
        recipients.isEmpty ? "This client has no address to send to, so nothing can go out." : nil
    }
}
