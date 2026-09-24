import BackstageGoogle
import Foundation
import SwiftData
import Testing

/// ovation#42. Ovation's own send: everything answerable is answered first, then the
/// attempt is written, then Gmail is asked, then the answer is recorded BY ITS CLASS.
///
/// THE ORDER IS THE SAFETY. The attempt is written before the call because an invoice
/// left `notSent` across it let a timeout hand its number back, and the next review
/// issued that number to an invoice a client may already hold (ovation#460). And every
/// refusal comes BEFORE the write, so an ordinary refusal leaves nothing behind for a
/// person to clear (L667).
///
/// GMAIL IS A STAND IN in every case here, recording what it was handed, so nothing in
/// this suite can reach a real mailbox (L2).
@MainActor
struct InvoiceSenderTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let later = noon.addingTimeInterval(4)
    private static let settings = SendingSettings(fromName: "Dan Wright", fromEmail: "dan@studio.example",
                                                  destination: .clients)
    private static let footer = InvoiceFooter.fixed

    /// A stand in for Gmail: what it was handed, and how it answers.
    final class FakeGmail: MailSender, @unchecked Sendable {
        enum Answer { case accepts, refuses(Error), neverAnswers(Error) }
        var answer: Answer = .accepts
        private(set) var sent: [OutgoingMail] = []
        var limit = GmailSendLimits.maxRequestBytes

        func send(_ mail: OutgoingMail) async throws -> SentReceipt {
            sent.append(mail)
            switch answer {
            case .accepts: return SentReceipt(threadId: "thread-1")
            case .refuses(let error), .neverAnswers(let error): throw error
            }
        }

        func measure(_ mail: OutgoingMail) throws -> MailSizeMeasurement {
            MailSizeMeasurement(encodedBytes: mail.attachments.reduce(0) { $0 + $1.data.count }, limitBytes: limit)
        }
    }

    private static func render() -> RenderedInvoice {
        let bytes = Data("%PDF-1.7 the one render".utf8)
        return RenderedInvoice(bytes: bytes, sha256: DocumentStore.hash(of: bytes), fingerprint: "f")
    }

    /// A numbered draft that nothing refuses, built the way ReviewGate's suite builds one.
    private static func draft(number: Int64? = 1_123) throws -> (ModelContainer, PersistentIdentifier) {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let invoice = try InvoiceFixtures.invoice("Ordinary", in: context)
        invoice.client?.email = "booker@client.example"
        invoice.number = number
        invoice.sentStatus = .notSent
        for shoot in invoice.shoots {
            shoot.shotFrom = ClockTime("19:00")
            shoot.shotUntil = ClockTime("20:00")
        }
        try context.save()
        return (container, invoice.persistentModelID)
    }

    private static func status(_ id: PersistentIdentifier, in container: ModelContainer) throws -> SentStatus {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == id }).sentStatus
    }

    private static func send(_ id: PersistentIdentifier, in container: ModelContainer, gmail: FakeGmail,
                             settings: SendingSettings = settings,
                             message: String = "Hello,\n\nThe invoice is attached.\n\nThank you,\nDan")
    async -> InvoiceSendOutcome {
        let answeredAt = later
        return await InvoiceSender(modelContainer: container).send(
            id, render: render(), message: message, settings: settings, footer: footer,
            through: gmail, clock: { answeredAt })
    }

    // MARK: it goes, and it is recorded as observed

    @Test("an accepted send records the invoice as sent by Ovation, at the moment Gmail answered")
    func anacceptedSendIsRecorded() async throws {
        let (container, id) = try Self.draft()
        let gmail = FakeGmail()

        let outcome = await Self.send(id, in: container, gmail: gmail)

        #expect(outcome == .sent(at: Self.later, to: ["booker@client.example"]))
        #expect(try Self.status(id, in: container) == .sent(route: .ovationSentIt, at: Self.later))
    }

    /// WHAT WAS SENT is the render, attached, under the subject the design settled, to
    /// the client's recipients, from the sending settings (PRD 10c, L64).
    @Test("the message carries the one render as a PDF, the settled subject and the client's recipients")
    func themessageIsTheReviewedOne() async throws {
        let (container, id) = try Self.draft()
        let gmail = FakeGmail()

        _ = await Self.send(id, in: container, gmail: gmail)

        let mail = try #require(gmail.sent.first)
        #expect(mail.to == ["booker@client.example"])
        #expect(mail.subject.hasPrefix("Invoice 1123"))
        #expect(mail.attachments.count == 1)
        #expect(mail.attachments.first?.data == Self.render().bytes)
        #expect(mail.attachments.first?.mimeType == "application/pdf")
        #expect(mail.attachments.first?.filename == "Invoice 1123.pdf")
    }

    @Test("a send to the test address goes there, and the attempt records it as redirected")
    func atestSendIsRedirected() async throws {
        let (container, id) = try Self.draft()
        let gmail = FakeGmail()
        gmail.answer = .neverAnswers(URLError(.timedOut))
        let test = SendingSettings(fromName: "Dan Wright", fromEmail: "dan@studio.example",
                                   destination: .testAddress("second@elsewhere.example"))

        _ = await Self.send(id, in: container, gmail: gmail, settings: test)

        #expect(gmail.sent.first?.to == ["second@elsewhere.example"])
        guard case .attempting(let attempt) = try Self.status(id, in: container) else {
            Issue.record("the unanswered send left no attempt"); return
        }
        #expect(attempt.destination == ["second@elsewhere.example"])
        #expect(attempt.wasRedirected)
        #expect(attempt.renderSHA256 == Self.render().sha256)
    }

    // MARK: Gmail said no, so nothing went

    @Test("a send Gmail refused leaves a draft, and says so")
    func arefusedSendIsStillADraft() async throws {
        let (container, id) = try Self.draft()
        let gmail = FakeGmail()
        gmail.answer = .refuses(GmailSendError.api("invalid recipient"))

        let outcome = await Self.send(id, in: container, gmail: gmail)

        guard case .refused(let sentence) = outcome else { Issue.record("got \(outcome)"); return }
        #expect(sentence.contains("Nothing was sent"))
        #expect(try Self.status(id, in: container) == .notSent)
    }

    @Test("expired Gmail access is a refusal that names reconnecting, and leaves a draft")
    func expiredAccessIsARefusal() async throws {
        let (container, id) = try Self.draft()
        let gmail = FakeGmail()
        gmail.answer = .refuses(GmailSendError.authExpired)

        let outcome = await Self.send(id, in: container, gmail: gmail)

        guard case .refused(let sentence) = outcome else { Issue.record("got \(outcome)"); return }
        #expect(sentence.contains("connect"))
        #expect(try Self.status(id, in: container) == .notSent)
    }

    // MARK: no answer at all, so it stays unsettled and keeps its number

    /// A TIMEOUT IS NOT A REFUSAL. The message may have gone, so the invoice stays
    /// attempting: it cannot be sent again without a person, and its number cannot be
    /// handed back (ovation#460, Dan 2026-09-21).
    @Test("a send Gmail never answered stays unsettled rather than going back to a draft")
    func anunansweredSendStaysUnsettled() async throws {
        let (container, id) = try Self.draft()
        let gmail = FakeGmail()
        gmail.answer = .neverAnswers(URLError(.timedOut))

        let outcome = await Self.send(id, in: container, gmail: gmail)

        guard case .couldNotTell = outcome else { Issue.record("got \(outcome)"); return }
        guard case .attempting = try Self.status(id, in: container) else {
            Issue.record("it went back to a draft, so its number could be reissued"); return
        }
    }

    // MARK: refused before anything is written

    @Test("each refusal is said before anything is written or sent", arguments: [
        "no number", "empty message", "no recipients", "already sent", "too large",
    ])
    func everyRefusalComesFirst(reason: String) async throws {
        let (container, id) = try Self.draft(number: reason == "no number" ? nil : 1_123)
        let gmail = FakeGmail()
        var message = "Hello"
        switch reason {
        case "empty message": message = "  \n "
        case "no recipients":
            let context = ModelContext(container)
            try #require(try context.fetch(FetchDescriptor<Invoice>()).first).client?.email = ""
            try context.save()
        case "already sent":
            let context = ModelContext(container)
            try #require(try context.fetch(FetchDescriptor<Invoice>()).first).sentStatus =
                .sent(route: .ovationSentIt, at: Self.noon)
            try context.save()
        case "too large": gmail.limit = 1
        default: break
        }
        let before = try Self.status(id, in: container)

        let outcome = await Self.send(id, in: container, gmail: gmail, message: message)

        guard case .refused = outcome else { Issue.record("\(reason): got \(outcome)"); return }
        #expect(gmail.sent.isEmpty, "\(reason) reached Gmail")
        #expect(try Self.status(id, in: container) == before, "\(reason) wrote something")
    }

    /// THE GATE IS ASKED AGAIN AT THE PRESS, not trusted from when the sheet opened
    /// (L567): a refusal the invoice acquired meanwhile stops the send.
    @Test("an invoice the review gate refuses is not sent")
    func thegateIsAskedAtThePress() async throws {
        let (container, id) = try Self.draft()
        let context = ModelContext(container)
        try #require(try context.fetch(FetchDescriptor<Invoice>()).first).client?.taxStatus = .neverRecorded
        try context.save()
        let gmail = FakeGmail()

        let outcome = await Self.send(id, in: container, gmail: gmail)

        guard case .refused(let sentence) = outcome else { Issue.record("got \(outcome)"); return }
        #expect(sentence == "Waiting on this client's tax status.")
        #expect(gmail.sent.isEmpty)
    }
}
