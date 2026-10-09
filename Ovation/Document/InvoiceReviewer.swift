// ovation#42, PRD 10c. Opening the review of a real invoice, sending it, and closing it.
//
// ONE OBJECT, PASSED DOWN AS ONE VALUE. The invoice screen's writes each travel from
// OvationApp through RootView and ShellView as a closure named at every layer, and a
// layer that forgets one produces the same screen as a launch that cannot write
// (ovation#485). The review is one value instead, so it cannot arrive in part.
//
// REVIEW TAKES THE NUMBER, AND CLOSING UNSENT GIVES IT BACK (Dan, 2026-09-14). The
// render made at Review carries that number and the send attaches that same render.
// `InvoiceNumberAllocator.release` refuses an invoice whose send was accepted or is
// unsettled, so closing after either keeps the number: a client may already hold it.
// Since ovation#362 it also refuses any number a send was ever attempted with, which
// the send records by letting go of the review's hold before Gmail is called.
//
// THE PRESENTER AND SESSION ARE BUILT HERE, ONCE, never inside a sheet's content, which
// re-runs on every body evaluation and would re-render the PDF, and "the preview is the
// attachment" would quietly stop being true.
import BackstageGoogle
import Foundation
import Observation
import SwiftData

@MainActor
final class InvoiceReviewer {

    private let container: ModelContainer
    private let footer: () -> InvoiceFooter
    private let settingsFile: URL?
    private let makeSender: @MainActor (SendingSettings) async -> Result<SendingRoute, SenderUnavailable>
    private let clock: @Sendable () -> Date
    private let saveRecord: InvoiceSender.RecordSave

    /// - Parameters:
    ///   - settingsFile: where the sending settings live, or nil in a build that must never
    ///     send (a Debug build, a disposable launch), which is its own answer at Send.
    ///   - makeSender: Gmail for these settings, or why it cannot be had. Asked only at the
    ///     press, after everything else has been answered.
    ///   - saveRecord: how a reminder's or a copy's record is saved, which only a test
    ///     replaces, to make that save fail (ovation#608).
    init(container: ModelContainer, footer: @escaping () -> InvoiceFooter, settingsFile: URL?,
         makeSender: @escaping @MainActor (SendingSettings) async -> Result<SendingRoute, SenderUnavailable>,
         clock: @escaping @Sendable () -> Date,
         saveRecord: @escaping InvoiceSender.RecordSave = InvoiceSender.savingRecord) {
        self.container = container
        self.footer = footer
        self.settingsFile = settingsFile
        self.makeSender = makeSender
        self.clock = clock
        self.saveRecord = saveRecord
    }

    /// The review of this invoice, numbered, rendered once, or why it cannot be opened.
    ///
    /// ovation#548. `kind` is nil for the first send, which issues the invoice, and
    /// names a reminder or a copy of an invoice already sent. Either way it is THIS
    /// sheet and THIS route to Gmail, so what goes to whom is shown before it goes
    /// whichever word opened it (L64, L263). A reminder or a copy takes no number, since
    /// a sent invoice has one, and is refused here if the invoice cannot be sent again.
    func open(_ invoiceID: PersistentIdentifier,
              as kind: InvoiceMailKind? = nil) async -> Result<InvoiceReview, ReviewOpenRefusal> {
        guard let invoice = Self.invoice(invoiceID, in: container.mainContext) else {
            return .failure(.noSuchInvoice)
        }
        if let kind, let refusal = kind.refusal(for: invoice) {
            return .failure(.cannotSendAgain(refusal))
        }
        var taken: Int64?
        if kind == nil, invoice.number == nil {
            do {
                taken = try await InvoiceNumberAllocator(modelContainer: container).allocate(to: invoiceID)
            } catch {
                return .failure(.couldNotNumber(String(describing: error)))
            }
        } else if kind == nil, invoice.numberHeldByAReview, let left = invoice.number {
            // A NUMBER AN EARLIER REVIEW LEFT, still held because nothing was ever sent
            // with it and the launch could not give it back (ovation#362). This review
            // takes it up as its own, so closing unsent hands it back through the same
            // refusals, rather than the invoice being stuck with a number no review
            // will ever return.
            taken = left
        }
        // READ AGAIN AFTER THE ALLOCATOR'S WRITE, from the context the page is built in,
        // so the page carries the number that was just taken rather than none.
        guard let numbered = Self.invoice(invoiceID, in: container.mainContext) else {
            return .failure(.noSuchInvoice)
        }
        do {
            let footer = footer()
            let document = try InvoiceDocument(invoice: numbered, footer: footer)
            let session = ReviewSession(document: document, resources: try InvoicePDFResources.bundled())
            guard let client = numbered.client else {
                if let taken { try? await InvoiceNumberAllocator(modelContainer: container).release(taken, from: invoiceID) }
                return .failure(.couldNotRender("it has no client"))
            }
            // A PAID INVOICE IS NOT LATE, so a copy of one carries no due date band:
            // "already 20 days past its due date" over an invoice paid in full would be
            // a warning about nothing (L11).
            let isPaid = numbered.isPaidInFull
            let presenter = ReviewSheetPresenter(session: session, document: document, client: client,
                                                 dueDate: isPaid ? nil : numbered.dueDate)
            let settings = settingsFile.map { SendingSettings.read(from: $0) }
            let number = numbered.number ?? 0
            let shoots = numbered.shoots.map(\.name)
            let signedBy = (try? settings?.get())?.fromName
            let subject: String
            let message: String
            switch kind {
            case nil:
                subject = InvoiceMail.subject(number: number, shoots: shoots)
                message = InvoiceMail.message(amountDue: document.amountDue, dueLine: document.dueLine,
                                              shoots: shoots, signedBy: signedBy)
            case .reminder:
                subject = InvoiceMailKind.reminder.subject(number: number, shoots: shoots,
                                                           onto: numbered.issuingMessage)
                message = InvoiceMail.reminderMessage(amountDue: document.amountDue,
                                                      dueLine: document.dueLine,
                                                      shoots: shoots, signedBy: signedBy)
            case .copy:
                subject = InvoiceMailKind.copy.subject(number: number, shoots: shoots,
                                                       onto: numbered.issuingMessage)
                message = InvoiceMail.copyMessage(amountDue: document.amountDue, dueLine: document.dueLine,
                                                  paidInFull: isPaid, shoots: shoots, signedBy: signedBy)
            }
            return .success(InvoiceReview(
                invoiceID: invoiceID, number: number, numberTakenHere: taken, presenter: presenter,
                subject: subject,
                message: message,
                destinationWarning: (try? settings?.get())?.destination.warning,
                // WHO IT GOES TO, from the same settings the send reads (L64, L455): the
                // test address when redirected, the client's recipients otherwise, and the
                // client's where no settings can be read, since Send refuses then anyway.
                goingTo: (try? settings?.get())?.destination.recipients(forClient: presenter.recipients)
                    ?? presenter.recipients,
                // HELD STRONGLY, deliberately: the reviewer never holds a review, so this
                // makes no cycle, and a weak reference let a review outlive the reviewer
                // that made it and turned Send into a silent no-op.
                send: { review in await self.send(review, footer: footer) },
                settle: { review in await self.markNotSent(review.invoiceID) },
                kind: kind))
        } catch {
            if let taken { try? await InvoiceNumberAllocator(modelContainer: container).release(taken, from: invoiceID) }
            return .failure(.couldNotRender(String(describing: error)))
        }
    }

    /// Puts an unsettled send back to a draft that keeps its number, or says why not
    /// (ovation#471). Nil when it was done.
    func markNotSent(_ invoiceID: PersistentIdentifier) async -> String? {
        do {
            try await SendSettler(modelContainer: container).markNotSent(invoiceID)
            return nil
        } catch let refusal as SendSettleRefusal {
            return refusal.sentence
        } catch {
            return "The invoice could not be changed, so it is still unsettled: \(error.localizedDescription)"
        }
    }

    /// What Dan is asked before marking this invoice as not sent, or nil where it has
    /// no number to name (L180).
    func confirmation(forSettling invoiceID: PersistentIdentifier) -> String? {
        Self.invoice(invoiceID, in: container.mainContext)?.number.map(SendSettler.confirmation(number:))
    }

    /// Closes a review. A number taken HERE is handed back only while nothing has been sent
    /// or is in flight, which the allocator itself refuses otherwise.
    func close(_ review: InvoiceReview) async {
        guard let taken = review.numberTakenHere else { return }
        try? await InvoiceNumberAllocator(modelContainer: container).release(taken, from: review.invoiceID)
    }

    /// Said when the invoice settings changed between opening the review and pressing Send.
    static let footerChanged = "The invoice settings changed after this was opened, so nothing was sent. Close it and review it again."

    private func send(_ review: InvoiceReview, footer opened: InvoiceFooter) async {
        // THE FOOTER IS ASKED AGAIN AT THE PRESS (L567). The page was drawn with the one
        // read at the open, so any change since, complete or not, means what would go
        // out is not what the settings now say; the gate below then judges that footer.
        let footer = self.footer()
        guard footer == opened else {
            review.state = .refused(Self.footerChanged)
            return
        }
        // THE SETTINGS ARE READ AGAIN AT THE PRESS, never trusted from the open (L567).
        guard let settingsFile else {
            review.state = .refused("This build of Ovation does not send, so nothing was sent.")
            return
        }
        let settings: SendingSettings
        switch SendingSettings.read(from: settingsFile) {
        case .success(let read): settings = read
        case .failure(let refusal):
            review.state = .refused(refusal.sentence)
            return
        }
        let render: RenderedInvoice
        do {
            render = try review.presenter.rendered()
        } catch {
            review.state = .refused("This invoice could not be drawn, so nothing was sent.")
            return
        }
        review.state = .working(since: clock())
        // BUILT, NOT CONNECTED: the send makes it ready only after its own refusals.
        let route: SendingRoute
        switch await makeSender(settings) {
        case .success(let made): route = made
        case .failure(let unavailable):
            review.state = .refused(unavailable.sentence)
            return
        }
        // ONE PRESS, ONE ROUTE: the first send and a reminder or a copy differ only in
        // which of the sender's two entries is asked, never in how Gmail is reached.
        let sender = InvoiceSender(modelContainer: container)
        let outcome: InvoiceSendOutcome
        if let kind = review.kind {
            outcome = await sender.resend(
                review.invoiceID, as: kind, render: render, message: review.message, settings: settings,
                footer: footer, approvedRecipients: review.goingTo, through: route, clock: clock,
                saveRecord: saveRecord)
        } else {
            outcome = await sender.send(
                review.invoiceID, render: render, message: review.message, settings: settings,
                footer: footer, approvedRecipients: review.goingTo, through: route, clock: clock)
        }
        switch outcome {
        case .sent(let at, let to, let notRecorded):
            review.state = .sent(at: at, to: to, notRecorded: notRecorded)
        case .refused(let sentence): review.state = .refused(sentence)
        case .couldNotTell(let sentence): review.state = .couldNotTell(sentence)
        }
    }

    private static func invoice(_ id: PersistentIdentifier, in context: ModelContext) -> Invoice? {
        try? context.fetch(FetchDescriptor<Invoice>()).first { $0.persistentModelID == id }
    }
}

/// One open review: what the sheet shows, and where the send has got to.
@MainActor
@Observable
final class InvoiceReview: Identifiable {
    let invoiceID: PersistentIdentifier
    /// Nil for the first send, which issues the invoice; a reminder or a copy of one
    /// already sent otherwise (ovation#548), which writes nothing to the invoice.
    let kind: InvoiceMailKind?
    /// The invoice's number, which the outcome names.
    let number: Int64
    /// The number this review took, which closing hands back while nothing went. Nil
    /// where the invoice already had one, and cleared once Dan settles an unsettled send
    /// here, because a settled send keeps its number whatever happens next (ovation#471).
    private(set) var numberTakenHere: Int64?
    let presenter: ReviewSheetPresenter
    let subject: String
    var message: String
    /// What the sheet says when the send will not reach the client, or nil.
    let destinationWarning: String?
    /// Where the message will actually go, which the sheet lists (L64).
    let goingTo: [String]
    var state: ReviewSendState = .ready
    private let performSend: @MainActor (InvoiceReview) async -> Void
    private let performSettle: @MainActor (InvoiceReview) async -> String?

    /// STORED, NOT THE REVIEW'S ADDRESS (ovation#685, L1019): an address is handed
    /// to the next object once this one is freed, so anything keyed on it, a
    /// sheet presented by item included, would take a new review for the old one.
    nonisolated let id = UUID()

    init(invoiceID: PersistentIdentifier, number: Int64, numberTakenHere: Int64?, presenter: ReviewSheetPresenter,
         subject: String, message: String, destinationWarning: String?, goingTo: [String],
         send: @escaping @MainActor (InvoiceReview) async -> Void,
         settle: @escaping @MainActor (InvoiceReview) async -> String?,
         kind: InvoiceMailKind? = nil) {
        self.invoiceID = invoiceID
        self.kind = kind
        self.number = number
        self.numberTakenHere = numberTakenHere
        self.presenter = presenter
        self.subject = subject
        self.message = message
        self.destinationWarning = destinationWarning
        self.goingTo = goingTo
        self.performSend = send
        self.performSettle = settle
    }

    /// The one thing Send is waiting on, or nil when it may be pressed.
    var whySendIsWaiting: String? {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? InvoiceMail.emptyMessage : nil
    }

    func send() async {
        if case .working = state { return }
        await performSend(self)
    }

    /// Back to the sheet after a refusal, for another try. Only a refusal: an accepted or
    /// unsettled send is never offered again from here, because sending it again is how a
    /// client gets the invoice twice.
    func tryAgain() {
        if case .refused = state { state = .ready }
    }

    /// Dan saying a send Gmail never answered did not go (ovation#471). Only from
    /// that state. The invoice goes back to a draft that KEEPS its number, so this
    /// review stops holding the number as its own to hand back, and the sheet is
    /// ready again; a refusal is said in place of the outcome.
    /// Whether Mark unsent is offered once Gmail never answered. Only on the FIRST
    /// send: it says the invoice was not issued, and a reminder or a copy that may not
    /// have gone says nothing about whether the invoice was (ovation#548).
    var offersMarkUnsent: Bool {
        guard kind == nil, case .couldNotTell = state else { return false }
        return true
    }

    func markNotSent() async {
        guard offersMarkUnsent else { return }
        // LET GO OF THE NUMBER BEFORE THE WRITE, not after it. A Close landing while
        // the settle saves would otherwise find the invoice a draft again and this
        // review still claiming the number, and hand it back (L157). A refused settle
        // loses nothing by it: the invoice is still sent or unsettled, and the
        // allocator refuses to release either.
        numberTakenHere = nil
        if let refusal = await performSettle(self) {
            state = .couldNotTell(refusal)
            return
        }
        state = .ready
    }
}

/// Where the send has got to. Working, sent, refused and unsettled are visibly different
/// states, and working carries when it started so the sheet can count the seconds and it
/// can never look stalled (PRD 33, the design record's sending states).
enum ReviewSendState: Equatable {
    case ready
    case working(since: Date)
    /// `notRecorded` is why the history will not show a reminder or a copy that went.
    case sent(at: Date, to: [String], notRecorded: String? = nil)
    case refused(String)
    case couldNotTell(String)
}

enum ReviewOpenRefusal: Error, Equatable {
    case noSuchInvoice
    case couldNotNumber(String)
    case couldNotRender(String)
    /// ovation#548. A reminder or a copy asked of an invoice that cannot be sent again.
    case cannotSendAgain(String)

    var sentence: String {
        switch self {
        case .cannotSendAgain(let sentence): return sentence
        case .noSuchInvoice: return "That invoice is no longer there."
        case .couldNotNumber(let detail): return "This invoice could not be given a number, so it cannot be reviewed: \(detail)"
        case .couldNotRender(let detail): return "This invoice could not be drawn, so there is nothing to review: \(detail)"
        }
    }
}

/// Why Gmail cannot be had for a send, said at the press.
struct SenderUnavailable: Error, Equatable {
    let sentence: String
}

extension InvoiceMail {
    /// The message the sheet starts from, which Dan edits in place and which owes its cold
    /// read (PRD 41a, ovation#50). Built from the page's own wording of the amount and the
    /// due date, so the message and the attachment cannot state two different figures.
    static func message(amountDue: String, dueLine: String, shoots: [String], signedBy: String?) -> String {
        let named = shoots.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let what = named.isEmpty ? "The invoice" : "The invoice for " + named.joined(separator: " and ")
        let due = dueLine.isEmpty ? "" : " and is due \(dueLine)"
        return "Hello,\n\n\(what) is attached. It comes to \(amountDue)\(due).\n\nThank you"
            + signature(signedBy)
    }

    /// ovation#548. The reminder the sheet starts from, which Dan edits in place and
    /// which owes its cold read like every outbound sentence (PRD 41a). Built from the
    /// page's own wording of what is outstanding and when it was due, so the message
    /// and the attachment cannot state two different figures.
    static func reminderMessage(amountDue: String, dueLine: String, shoots: [String],
                                signedBy: String?) -> String {
        let named = shoots.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let what = named.isEmpty ? "the invoice" : "the invoice for " + named.joined(separator: " and ")
        let due = dueLine.isEmpty ? "" : ", and was due \(dueLine)"
        return "Hello,\n\nA reminder about \(what), attached again here. "
            + "\(amountDue) is still outstanding\(due).\n\nThank you" + signature(signedBy)
    }

    /// ovation#548. The copy the sheet starts from. A paid invoice says it was paid,
    /// in the page's own words; anything else says what it comes to and when it is
    /// due, which is the first send's sentence.
    static func copyMessage(amountDue: String, dueLine: String, paidInFull: Bool, shoots: [String],
                            signedBy: String?) -> String {
        let named = shoots.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let what = named.isEmpty ? "the invoice" : "the invoice for " + named.joined(separator: " and ")
        let figure: String
        if dueLine.isEmpty {
            figure = paidInFull ? "It came to \(amountDue)." : "It comes to \(amountDue)."
        } else {
            figure = paidInFull ? "It came to \(amountDue) and was \(dueLine)."
                                : "It comes to \(amountDue) and is due \(dueLine)."
        }
        return "Hello,\n\nA copy of \(what) is attached. \(figure)\n\nThank you" + signature(signedBy)
    }

    /// ",\nDan", from the first word of the sending name, or nothing where there is none.
    private static func signature(_ signedBy: String?) -> String {
        signedBy?.split(separator: " ").first.map { ",\n\($0)" } ?? ""
    }
}
