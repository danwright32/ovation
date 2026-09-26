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
        invoice.sentStatus = .attempting(SendAttempt(destination: recipients,
                                                     wasRedirected: settings.destination.isRedirected,
                                                     renderSHA256: render.sha256,
                                                     startedAt: clock()))
        do {
            try modelContext.save()
        } catch {
            invoice.sentStatus = .notSent
            return .refused("The send could not be recorded before it started, so nothing was sent: \(error.localizedDescription)")
        }

        // 3. GMAIL, and the answer by its class.
        do {
            _ = try await sender.send(mail)
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
        return settle(invoice, as: .sent(route: .ovationSentIt, at: sentAt),
                      then: .sent(at: sentAt, to: recipients))
    }

    /// Records how the attempt ended. A save that fails AFTER Gmail accepted leaves the
    /// invoice attempting, which is the honest state: it went, and Ovation could not write
    /// that down, so it needs a person rather than a guess (L12).
    private func settle(_ invoice: Invoice, as status: SentStatus,
                        then outcome: InvoiceSendOutcome) -> InvoiceSendOutcome {
        invoice.sentStatus = status
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
    case sent(at: Date, to: [String])
    /// Nothing was sent, and the invoice is still a draft.
    case refused(String)
    /// It may have gone. The invoice is left attempting.
    case couldNotTell(String)
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

    /// What the sheet says once Gmail accepted. Built as a String, because a SwiftUI
    /// Text interpolating an integer groups it, and "invoice 1,123" names nothing issued.
    static func sentLine(time: String, to recipients: [String], number: Int64) -> String {
        "Sent at \(time) to \(recipients.joined(separator: ", ")), and recorded against invoice \(String(number))."
    }

    /// The design record's one sentence for an empty message (Dan, 2026-09-09).
    static let emptyMessage = "The message is empty. Nothing is sent without one."
}
