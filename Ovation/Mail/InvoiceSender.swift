// ovation#42, PRD 5.10, 10c. Ovation's own send of one invoice.
//
// EVERYTHING ANSWERABLE IS ANSWERED FIRST, THEN ONE WRITE, THEN GMAIL, THEN ONE WRITE.
//
// First the refusals, all of them, before anything is written: the invoice still a
// draft, numbered, the review gate asked again AT THE PRESS rather than trusted from
// when the sheet opened (L567), somebody to send to, a message, and a request under
// Gmail's size limit. A refusal placed after the write would leave the in-flight state
// behind on every ordinary refusal, for a person to clear (L667).
//
// Then Gmail is made ready, which is where a browser can ask Dan to sign in, so no
// refusal above ever opens one (L667).
//
// Then the attempt is written, BEFORE the call. An invoice left `notSent` across the
// call let a timeout hand its number back, and the next review issued that number to an
// invoice a client may already hold (ovation#460).
//
// Then Gmail, and the answer is recorded BY ITS CLASS rather than by its cause (L35):
//
//   accepted            sent, observed, at the moment Gmail answered
//   Gmail said no       back to a draft: an answer came, and it was that nothing went
//   no answer at all    left attempting: the message may have gone, so it can neither
//                       be sent again nor have its number handed back without a person
//                       (Dan, 2026-09-21: he may clear it, never assert it)
import BackstageGoogle
import Foundation
import SwiftData

@ModelActor
actor InvoiceSender {

    /// How a reminder's or a copy's record is saved once Gmail accepted it.
    ///
    /// A SEAM SO THAT SAVE CAN BE MADE TO FAIL (ovation#608). An in-memory store never
    /// refuses a save, so without it the path that says a reminder went but could not
    /// be recorded had a tested sentence and had never once run (L1, L151). Every
    /// caller but a test takes `savingRecord`.
    typealias RecordSave = @Sendable (ModelContext) throws -> Void
    static let savingRecord: RecordSave = { try $0.save() }

    func send(_ invoiceID: PersistentIdentifier, render: RenderedInvoice, message: String,
              settings: SendingSettings, footer: InvoiceFooter, approvedRecipients: [String],
              through route: SendingRoute, clock: @Sendable () -> Date) async -> InvoiceSendOutcome {
        let sender = route.sender
        guard let invoice = try? modelContext.fetch(FetchDescriptor<Invoice>())
            .first(where: { $0.persistentModelID == invoiceID }) else {
            return .refused("That invoice is no longer there, so nothing was sent.")
        }

        // 1. THE REFUSALS, every one before anything is written.
        switch invoice.sentStatus {
        case .notSent: break
        case .sent: return .refused("This invoice has already been sent, so it was not sent again.")
        case .attempting, .couldNotDetermine:
            return .refused("A send for this invoice has not settled, so it was not sent again.")
        }
        guard let number = invoice.number else {
            return .refused("This invoice has no number yet, so nothing was sent.")
        }
        if let waiting = ReviewGate.refusal(for: invoice, footer: footer) {
            return .refused(waiting)
        }
        // Bound first rather than read as `invoice.client?.member`: that form trips a
        // compiler fault that depends on how files are batched (ovation#497).
        let client = invoice.client
        let recipients = settings.destination.recipients(forClient: client?.recipientsForInvoices ?? [])
        guard !recipients.isEmpty else {
            return .refused("This client has no address to send to, so nothing was sent.")
        }
        // WHO IT GOES TO IS WHO THE SHEET SHOWED (L64): a settings file or a client
        // address changed since the sheet opened would send somewhere never approved.
        guard recipients == approvedRecipients else {
            return .refused(InvoiceMail.recipientsChanged)
        }
        // AND THE TAX STATUS IS THE ONE THE PAGE WAS RENDERED UNDER (review of
        // ovation#600, L567). The attempt below records the status the invoice is
        // charged under now; a correction on the client's page since the sheet
        // opened would record a status the attached page does not show.
        guard render.chargedUnder == invoice.taxStatusCharged else {
            return .refused(InvoiceMail.taxStatusChanged)
        }
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .refused(InvoiceMail.emptyMessage)
        }
        guard let attachment = MailAttachment(filename: InvoiceMail.filename(number: number),
                                              mimeType: "application/pdf", data: render.bytes),
              let mail = OutgoingMail(to: recipients,
                                      subject: InvoiceMail.subject(number: number,
                                                                   shoots: invoice.shoots.map(\.name)),
                                      body: message, attachments: [attachment])
        else {
            return .refused("The message could not be put together, so nothing was sent.")
        }
        do {
            let size = try sender.measure(mail)
            guard size.fits else {
                return .refused("The invoice is too large for Gmail to send (\(size.encodedBytes) bytes of \(size.limitBytes)), so nothing was sent.")
            }
        } catch {
            return .refused("The message could not be measured for sending, so nothing was sent: \(error.localizedDescription)")
        }

        // GMAIL IS MADE READY LAST, after every refusal and before anything is written,
        // because making it ready is where a browser can ask Dan to sign in, and an
        // ordinary refusal must never open one (L667). A failure here sends nothing.
        if let unavailable = await route.ready() {
            return .refused(unavailable.sentence)
        }

        // 2. THE ATTEMPT, written before the call.
        // RECORDED THROUGH THE INVOICE, so the attempt also records the tax status
        // the render was taken under (ovation#482, PRD 51j1): what went out is what
        // it says, whatever the client's page later corrects.
        invoice.recordSendState(.attempting(SendAttempt(destination: recipients,
                                                        wasRedirected: settings.destination.isRedirected,
                                                        renderSHA256: render.sha256,
                                                        startedAt: clock())))
        do {
            try modelContext.save()
        } catch {
            invoice.recordSendState(.notSent)
            return .refused("The send could not be recorded before it started, so nothing was sent: \(error.localizedDescription)")
        }

        // 3. GMAIL, and the answer by its class.
        let receipt: SentReceipt
        do {
            receipt = try await sender.send(mail)
        } catch let refusal as GmailSendError {
            return settle(invoice, as: .notSent, then: .refused(Self.sentence(for: refusal)))
        } catch let refusal as MailSenderError {
            return settle(invoice, as: .notSent,
                          then: .refused("\(refusal.localizedDescription) Nothing was sent, and this is still a draft."))
        } catch {
            // NO ANSWER. Left attempting, deliberately: the message may have gone.
            return .couldNotTell("Gmail did not answer (\(error.localizedDescription)), so Ovation cannot tell whether it went. It will not be sent again until that is settled.")
        }

        let sentAt = clock()
        // THE MESSAGE IS RECORDED IN THE SAME SAVE AS THE SENT STATE (ovation#596), so
        // an invoice cannot be recorded as sent without who it went to, or the other
        // way round; a save that fails loses both, and says so.
        return settle(invoice, as: .sent(route: .ovationSentIt, at: sentAt),
                      recording: Self.message(.invoice, to: recipients, at: sentAt, subject: mail.subject,
                                              receipt: receipt),
                      then: .sent(at: sentAt, to: recipients))
    }

    /// The record of one message Gmail accepted, with the identifiers AS GMAIL
    /// REPORTED THEM (L127): a degraded one is nil, never the empty stand in the
    /// receipt carries, because a thread id of "" would be replied onto.
    private static func message(_ kind: SentMessageKind, to recipients: [String], at sentAt: Date,
                                subject: String, receipt: SentReceipt) -> SentMessage {
        let thread = receipt.threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageID = receipt.messageID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SentMessage(kind: kind, recipients: recipients, sentAt: sentAt, subject: subject,
                           gmailThreadID: receipt.threadIdDegraded || thread.isEmpty ? nil : thread,
                           messageID: receipt.messageIDDegraded || (messageID ?? "").isEmpty ? nil : messageID)
    }

    /// What a reminder is threaded with: the send that issued the invoice, where
    /// Ovation recorded both its thread and its Message-ID (ovation#596). An invoice
    /// sent before version 7 has neither, and its reminder starts a thread of its own
    /// rather than replying onto a guess.
    static func threading(_ kind: InvoiceMailKind,
                          onto issuing: SentMessage?) -> (threadId: String, inReplyTo: String, references: String?)? {
        guard kind == .reminder, let issuing,
              let thread = issuing.gmailThreadID, let parent = issuing.messageID else { return nil }
        return (thread, parent, MailThreading.references(parentReferences: nil, parentMessageID: parent))
    }

    /// ovation#548. A sent invoice going out again, as a reminder or a copy, through the
    /// same Gmail route as the first send.
    ///
    /// THE FIRST SEND'S REFUSALS, IN THE FIRST SEND'S ORDER, and then NOTHING WRITTEN
    /// until Gmail has accepted it. The invoice's sent state records the send that
    /// ISSUED it, which is what the accrual basis and the number sequence rest on
    /// (PRD 24, 10c); a reminder is a second message about a document the client
    /// already holds, so it must never move that state, take or hand back a number,
    /// or leave an attempt behind. So nothing is written before the call, and an
    /// unanswered reminder is said and left: Ovation cannot tell whether it went, and
    /// Gmail's Sent folder can. Once Gmail accepts, ONE row is written, the
    /// `SentMessage` the history lists (ovation#596), and nothing else.
    func resend(_ invoiceID: PersistentIdentifier, as kind: InvoiceMailKind, render: RenderedInvoice,
                message: String, settings: SendingSettings, footer: InvoiceFooter,
                approvedRecipients: [String], through route: SendingRoute,
                clock: @Sendable () -> Date,
                saveRecord: RecordSave = InvoiceSender.savingRecord) async -> InvoiceSendOutcome {
        let sender = route.sender
        guard let invoice = try? modelContext.fetch(FetchDescriptor<Invoice>())
            .first(where: { $0.persistentModelID == invoiceID }) else {
            return .refused("That invoice is no longer there, so nothing was sent.")
        }
        if let refusal = kind.refusal(for: invoice) { return .refused(refusal) }
        guard let number = invoice.number else {
            return .refused("This invoice has no number, so nothing was sent.")
        }
        if let waiting = ReviewGate.refusal(for: invoice, footer: footer) {
            return .refused(waiting)
        }
        let client = invoice.client
        let recipients = settings.destination.recipients(forClient: client?.recipientsForInvoices ?? [])
        guard !recipients.isEmpty else {
            return .refused("This client has no address to send to, so nothing was sent.")
        }
        guard recipients == approvedRecipients else {
            return .refused(InvoiceMail.recipientsChanged)
        }
        // THE PAGE IS THE ONE THE INVOICE WAS CHARGED UNDER, the first send's rule
        // (ovation#600): a page drawn under another status is a different bill.
        guard render.chargedUnder == invoice.taxStatusCharged else {
            return .refused(InvoiceMail.taxStatusChanged)
        }
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .refused(InvoiceMail.emptyMessage)
        }
        // A REMINDER REPLIES ONTO THE SEND THAT ISSUED THE INVOICE, where Ovation
        // recorded it (ovation#596); a copy starts its own thread.
        let thread = Self.threading(kind, onto: invoice.issuingMessage)
        guard let attachment = MailAttachment(filename: InvoiceMail.filename(number: number),
                                              mimeType: "application/pdf", data: render.bytes),
              let mail = OutgoingMail(to: recipients,
                                      subject: kind.subject(number: number,
                                                            shoots: invoice.shoots.map(\.name),
                                                            onto: invoice.issuingMessage),
                                      body: message, attachments: [attachment],
                                      inReplyTo: thread?.inReplyTo, references: thread?.references,
                                      threadId: thread?.threadId)
        else {
            return .refused("The message could not be put together, so nothing was sent.")
        }
        do {
            let size = try sender.measure(mail)
            guard size.fits else {
                return .refused("The invoice is too large for Gmail to send (\(size.encodedBytes) bytes of \(size.limitBytes)), so nothing was sent.")
            }
        } catch {
            return .refused("The message could not be measured for sending, so nothing was sent: \(error.localizedDescription)")
        }
        if let unavailable = await route.ready() {
            return .refused(unavailable.sentence)
        }
        let receipt: SentReceipt
        do {
            receipt = try await sender.send(mail)
        } catch let refusal as GmailSendError {
            return .refused(Self.resentSentence(for: refusal))
        } catch let refusal as MailSenderError {
            return .refused("\(refusal.localizedDescription) Nothing was sent.")
        } catch {
            return .couldNotTell("Gmail did not answer (\(error.localizedDescription)), so Ovation cannot tell whether the \(kind.noun) went. Look in Gmail's Sent folder before sending it again.")
        }
        // RECORDED ONLY NOW, once Gmail accepted it (ovation#596, PRD 10c): the
        // history lists what went, never what was tried. Nothing else is written, so
        // the invoice's sent state is untouched whatever happens here.
        let sentAt = clock()
        let record = Self.message(SentMessageKind(kind), to: recipients, at: sentAt, subject: mail.subject,
                                  receipt: receipt)
        modelContext.insert(record)
        record.invoice = invoice
        do {
            try saveRecord(modelContext)
        } catch {
            // IT WENT, and that is said first; what failed is only the record of it
            // (L12). Rolled back so a half written record is not saved by the next
            // write.
            modelContext.rollback()
            return .sent(at: sentAt, to: recipients,
                         notRecorded: InvoiceMail.notRecorded(kind.noun, error.localizedDescription))
        }
        return .sent(at: sentAt, to: recipients)
    }

    /// Gmail's refusals of a reminder or a copy, which say nothing about a draft: the
    /// invoice is sent and stays sent.
    private static func resentSentence(for refusal: GmailSendError) -> String {
        switch refusal {
        case .authExpired:
            return "Gmail access has expired, so connect Gmail again. Nothing was sent."
        case .tooLarge(let encoded, let limit):
            return "The invoice is too large for Gmail to send (\(encoded) bytes of \(limit)). Nothing was sent."
        case .api(let detail):
            return "Gmail refused it: \(detail). Nothing was sent."
        }
    }

    /// Records how the attempt ended. A save that fails AFTER Gmail accepted leaves the
    /// invoice attempting, which is the honest state: it went, and Ovation could not write
    /// that down, so it needs a person rather than a guess (L12).
    private func settle(_ invoice: Invoice, as status: SentStatus, recording message: SentMessage? = nil,
                        then outcome: InvoiceSendOutcome) -> InvoiceSendOutcome {
        invoice.recordSendState(status)
        if let message {
            modelContext.insert(message)
            message.invoice = invoice
        }
        do {
            try modelContext.save()
            return outcome
        } catch {
            modelContext.rollback()
            return .couldNotTell("Gmail answered, and Ovation could not record the answer: \(error.localizedDescription). It will not be sent again until that is settled.")
        }
    }

    private static func sentence(for refusal: GmailSendError) -> String {
        switch refusal {
        case .authExpired:
            return "Gmail access has expired, so connect Gmail again. Nothing was sent, and this is still a draft."
        case .tooLarge(let encoded, let limit):
            return "The invoice is too large for Gmail to send (\(encoded) bytes of \(limit)). Nothing was sent, and this is still a draft."
        case .api(let detail):
            return "Gmail refused it: \(detail). Nothing was sent, and this is still a draft."
        }
    }
}

/// Gmail for one send, in two steps. Building it opens nothing, so the sender can
/// measure the message while the refusals are asked; `ready` is the step that may open
/// a browser, and the send calls it only once every refusal has been answered.
struct SendingRoute: Sendable {
    let sender: any MailSender
    /// Nil once Gmail is ready to send, or why it cannot be.
    let ready: @Sendable @MainActor () async -> SenderUnavailable?
}

/// How one press of Send ended. Three answers, because they need three different things
/// from Dan (L11): nothing, nothing but a retry, and a decision only he can make.
enum InvoiceSendOutcome: Equatable, Sendable {
    /// It went. `notRecorded` says why the history will not show it, where a reminder
    /// or a copy went and its record could not be saved (ovation#596).
    case sent(at: Date, to: [String], notRecorded: String? = nil)
    /// Nothing was sent, and the invoice is still a draft.
    case refused(String)
    /// It may have gone. The invoice is left attempting.
    case couldNotTell(String)
}

/// ovation#548. The two ways a SENT invoice goes out again: `Remind` beside Record a
/// payment, and `Send a copy` beside Paid in full (the design record's `footFor`).
///
/// NOT A THIRD CASE BESIDE THE FIRST SEND, deliberately. The first send issues the
/// invoice and writes its sent state; these write nothing, so a review carrying no
/// kind is the first send and one carrying a kind never touches that state.
enum InvoiceMailKind: Equatable, Hashable, Sendable, CaseIterable {
    case reminder
    case copy

    /// The design record's own word for the foot.
    var footWord: String {
        switch self {
        case .reminder: return "Remind"
        case .copy: return "Send a copy"
        }
    }

    /// What it is called inside a sentence.
    var noun: String {
        switch self {
        case .reminder: return "reminder"
        case .copy: return "copy"
        }
    }

    /// The subject this message goes under, asked by the review sheet and by the send
    /// alike, so the sheet shows exactly what is sent (L64).
    ///
    /// A REMINDER REPLIES: "Re: " and the issuing send's subject exactly as it went,
    /// read from its record rather than composed again (Dan, 2026-09-28), because Gmail
    /// joins a message to a thread only when the subjects match, and an invoice's
    /// shoots can be renamed after it went. Where no issuing send was recorded (an
    /// invoice sent before schema version 7) there is no thread to join, so it keeps
    /// its own "Reminder: Invoice 1123, Autumn Evensong".
    ///
    /// A COPY KEEPS ITS OWN, "Copy: Invoice 1123, Autumn Evensong", since it may go to
    /// someone who was not on the first message.
    ///
    /// `issuing` HAS NO DEFAULT, so a caller cannot forget it and silently send a
    /// reminder outside the thread (L168).
    func subject(number: Int64, shoots: [String], onto issuing: SentMessage?) -> String {
        switch self {
        case .reminder:
            if let sent = issuing?.subject, !sent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Re: " + sent
            }
            return "Reminder: " + InvoiceMail.subject(number: number, shoots: shoots)
        case .copy:
            return "Copy: " + InvoiceMail.subject(number: number, shoots: shoots)
        }
    }

    /// What the sheet says once Gmail accepted. It names no invoice number, which the
    /// first send's line does ("recorded against invoice N"), because a reminder
    /// issues nothing; it is recorded in the invoice's history instead (ovation#596).
    func sentLine(time: String, to recipients: [String]) -> String {
        let heading = self == .reminder ? "Reminder" : "Copy"
        return "\(heading) sent at \(time) to \(recipients.joined(separator: ", "))."
    }

    /// What the sheet's outcome is headed once Gmail accepted.
    var sentHeading: String {
        switch self {
        case .reminder: return "Reminder sent"
        case .copy: return "Copy sent"
        }
    }

    static let reminderPaidInFull = "This invoice is paid in full, so there is nothing to remind anyone about. Nothing was sent."

    /// Why this invoice cannot be sent again as this kind, or nil when it can.
    ///
    /// ASKED AT OPENING AND AGAIN AT THE PRESS (L567): the invoice can be paid or
    /// cancelled between the two.
    ///
    /// CANCELLED AND DELETED ARE TWO CAUSES, SO TWO SENTENCES (ovation#601, L11). How
    /// it closed is asked before whether it was sent, because a deleted invoice was a
    /// draft and would otherwise be refused as never sent; a cancelled one was sent, so
    /// the order changes nothing for it.
    func refusal(for invoice: Invoice) -> String? {
        switch invoice.closure {
        case .cancelled: return "This invoice was cancelled, so no \(noun) was sent."
        case .deleted: return "This invoice was deleted, so no \(noun) was sent."
        case nil: break
        }
        guard invoice.sentStatus.wasSent else {
            return "This invoice has not been sent, so there is no \(noun) to send. Nothing was sent."
        }
        if self == .reminder, invoice.amountOutstanding <= .zero {
            return Self.reminderPaidInFull
        }
        return nil
    }
}

/// The message's own words and names, in one place, so the sheet shows what the send uses.
enum InvoiceMail {
    /// "Invoice 1123, Autumn Evensong", the design record's subject (review-send.html).
    static func subject(number: Int64, shoots: [String]) -> String {
        let named = shoots.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return named.isEmpty ? "Invoice \(number)" : "Invoice \(number), " + named.joined(separator: " and ")
    }

    static func filename(number: Int64) -> String { "Invoice \(number).pdf" }

    /// Said when the send would go to anyone other than who the review sheet showed.
    static let recipientsChanged = "Who this would go to changed after it was opened, so nothing was sent. Close it and review it again."

    /// Said when the client's sales tax status changed after the page was rendered, so
    /// the attached page no longer says what the invoice would record (ovation#600).
    static let taxStatusChanged = "This client's sales tax status changed after this was opened, so nothing was sent. Close it and review it again."

    /// What the sheet says once Gmail accepted. Built as a String, because a SwiftUI
    /// Text interpolating an integer groups it, and "invoice 1,123" names nothing issued.
    static func sentLine(time: String, to recipients: [String], number: Int64) -> String {
        "Sent at \(time) to \(recipients.joined(separator: ", ")), and recorded against invoice \(String(number))."
    }

    /// Said beneath a reminder or a copy that went when its record could not be saved,
    /// so the history's silence about it is explained rather than believed (L12).
    static func notRecorded(_ noun: String, _ reason: String) -> String {
        "Ovation could not add this \(noun) to the invoice's history (\(reason)), so the history will not show it."
    }

    /// The design record's one sentence for an empty message (Dan, 2026-09-09).
    static let emptyMessage = "The message is empty. Nothing is sent without one."
}
