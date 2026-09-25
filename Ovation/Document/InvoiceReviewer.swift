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

    /// - Parameters:
    ///   - settingsFile: where the sending settings live, or nil in a build that must never
    ///     send (a Debug build, a disposable launch), which is its own answer at Send.
    ///   - makeSender: Gmail for these settings, or why it cannot be had. Asked only at the
    ///     press, after everything else has been answered.
    init(container: ModelContainer, footer: @escaping () -> InvoiceFooter, settingsFile: URL?,
         makeSender: @escaping @MainActor (SendingSettings) async -> Result<SendingRoute, SenderUnavailable>,
         clock: @escaping @Sendable () -> Date) {
        self.container = container
        self.footer = footer
        self.settingsFile = settingsFile
        self.makeSender = makeSender
        self.clock = clock
    }

    /// The review of this invoice, numbered, rendered once, or why it cannot be opened.
    func open(_ invoiceID: PersistentIdentifier) async -> Result<InvoiceReview, ReviewOpenRefusal> {
        guard let invoice = Self.invoice(invoiceID, in: container.mainContext) else {
            return .failure(.noSuchInvoice)
        }
        var taken: Int64?
        if invoice.number == nil {
            do {
                taken = try await InvoiceNumberAllocator(modelContainer: container).allocate(to: invoiceID)
            } catch {
                return .failure(.couldNotNumber(String(describing: error)))
            }
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
            let presenter = ReviewSheetPresenter(session: session, document: document,
                                                 client: client, dueDate: numbered.dueDate)
            let settings = settingsFile.map { SendingSettings.read(from: $0) }
            let number = numbered.number ?? 0
            return .success(InvoiceReview(
                invoiceID: invoiceID, number: number, numberTakenHere: taken, presenter: presenter,
                subject: InvoiceMail.subject(number: number, shoots: numbered.shoots.map(\.name)),
                message: InvoiceMail.message(amountDue: document.amountDue, dueLine: document.dueLine,
                                             shoots: numbered.shoots.map(\.name),
                                             signedBy: (try? settings?.get())?.fromName),
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
                settle: { review in await self.markNotSent(review.invoiceID) }))
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
        let outcome = await InvoiceSender(modelContainer: container).send(
            review.invoiceID, render: render, message: review.message, settings: settings,
            footer: footer, approvedRecipients: review.goingTo, through: route, clock: clock)
        switch outcome {
        case .sent(let at, let to): review.state = .sent(at: at, to: to)
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

    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(invoiceID: PersistentIdentifier, number: Int64, numberTakenHere: Int64?, presenter: ReviewSheetPresenter,
         subject: String, message: String, destinationWarning: String?, goingTo: [String],
         send: @escaping @MainActor (InvoiceReview) async -> Void,
         settle: @escaping @MainActor (InvoiceReview) async -> String?) {
        self.invoiceID = invoiceID
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
    func markNotSent() async {
        guard case .couldNotTell = state else { return }
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
    case sent(at: Date, to: [String])
    case refused(String)
    case couldNotTell(String)
}

enum ReviewOpenRefusal: Error, Equatable {
    case noSuchInvoice
    case couldNotNumber(String)
    case couldNotRender(String)

    var sentence: String {
        switch self {
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
        let name = signedBy?.split(separator: " ").first.map(String.init)
        return "Hello,\n\n\(what) is attached. It comes to \(amountDue)\(due).\n\nThank you"
            + (name.map { ",\n\($0)" } ?? "")
    }
}
