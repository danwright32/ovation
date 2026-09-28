import BackstageGoogle
import Foundation
import SwiftData
import Testing

/// ovation#548. Remind and Send a copy: a sent invoice going out again, through the
/// same review sheet and the same Gmail route as the first send (L263).
///
/// WHAT IS DIFFERENT FROM THE FIRST SEND IS THE WHOLE POINT OF THIS SUITE. A reminder
/// or a copy is sent AFTER the invoice was established as sent, so it must never write
/// the invoice's sent state, never take or hand back a number, and never offer Mark
/// unsent, which is a statement about the FIRST send. Everything else is the first
/// send's: every refusal answered before Gmail is made ready, who it goes to approved
/// on the sheet and checked again at the press (L64, L567), and the answer by its class.
///
/// GMAIL IS A STAND IN in every case here, so nothing in this suite can reach a real
/// mailbox or Google (L2).
@MainActor
struct InvoiceResendTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let firstSent = noon.addingTimeInterval(-20 * 86_400)
    private static let later = noon.addingTimeInterval(4)
    private static let settings = SendingSettings(fromName: "Dan Wright", fromEmail: "dan@studio.example",
                                                  destination: .clients)

    private static func settingsFile() throws -> URL {
        let folder = URL.temporaryDirectory
            .appending(path: "ovation-resend-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "sending.json")
        try Data(#"{"fromName":"Dan Wright","fromEmail":"dan@studio.example","destination":"clients"}"#.utf8)
            .write(to: url)
        return url
    }

    /// A sent, numbered invoice, owed in full unless `paid`.
    private static func sent(paid: Bool = false, sent: Bool = true) throws -> (ModelContainer, PersistentIdentifier) {
        let container = try OvationSchema.container(inMemory: true)
        let context = container.mainContext
        let invoice = try InvoiceFixtures.invoice("Ordinary", in: context)
        invoice.client?.email = "booker@client.example"
        invoice.number = 1_123
        for shoot in invoice.shoots {
            shoot.shotFrom = ClockTime("19:00")
            shoot.shotUntil = ClockTime("20:00")
        }
        if sent { invoice.sentStatus = .sent(route: .ovationSentIt, at: firstSent) }
        if paid {
            let day = BusinessDate.stamping(noon.addingTimeInterval(-86_400))
            let payment = Payment(client: invoice.client, amount: invoice.total, method: .zelle, receivedOn: day)
            context.insert(payment)
            context.insert(PaymentAllocation(payment: payment, invoice: invoice, amount: invoice.total,
                                             allocatedOn: day, source: .recordedWithThePayment))
        }
        try context.save()
        return (container, invoice.persistentModelID)
    }

    private static func invoice(_ id: PersistentIdentifier, in container: ModelContainer) throws -> Invoice {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == id })
    }

    private static func render() -> RenderedInvoice {
        let bytes = Data("%PDF-1.7 the one render".utf8)
        return RenderedInvoice(bytes: bytes, sha256: DocumentStore.hash(of: bytes), fingerprint: "f")
    }

    private static func resend(_ kind: InvoiceMailKind, _ id: PersistentIdentifier,
                               in container: ModelContainer,
                               gmail: InvoiceSenderTests.FakeGmail,
                               approved: [String] = ["booker@client.example"],
                               readiness: InvoiceSenderTests.Readiness = .init()) async -> InvoiceSendOutcome {
        let answeredAt = later
        return await InvoiceSender(modelContainer: container).resend(
            id, as: kind, render: render(), message: "Hello,\n\nA reminder.\n\nThank you,\nDan",
            settings: settings, footer: .fixed, approvedRecipients: approved,
            through: readiness.route(gmail), clock: { answeredAt })
    }

    // MARK: the sender

    @Test("a reminder goes to the client with its own subject and the invoice attached, and the sent state is untouched")
    func areminderGoes() async throws {
        let (container, id) = try Self.sent()
        let gmail = InvoiceSenderTests.FakeGmail()

        let outcome = await Self.resend(.reminder, id, in: container, gmail: gmail)

        #expect(outcome == .sent(at: Self.later, to: ["booker@client.example"]))
        let mail = try #require(gmail.sent.first)
        #expect(mail.subject.hasPrefix("Reminder: Invoice 1123"))
        #expect(mail.attachments.first?.filename == "Invoice 1123.pdf")
        #expect(try Self.invoice(id, in: container).sentStatus == .sent(route: .ovationSentIt, at: Self.firstSent))
    }

    @Test("a copy of a paid invoice goes with its own subject")
    func acopyGoes() async throws {
        let (container, id) = try Self.sent(paid: true)
        let gmail = InvoiceSenderTests.FakeGmail()

        let outcome = await Self.resend(.copy, id, in: container, gmail: gmail)

        #expect(outcome == .sent(at: Self.later, to: ["booker@client.example"]))
        #expect(gmail.sent.first?.subject.hasPrefix("Copy: Invoice 1123") == true)
    }

    @Test("an invoice that was never sent is refused before Gmail is made ready", arguments: [
        InvoiceMailKind.reminder, .copy,
    ])
    func adraftIsRefused(kind: InvoiceMailKind) async throws {
        let (container, id) = try Self.sent(sent: false)
        let gmail = InvoiceSenderTests.FakeGmail()
        let readiness = InvoiceSenderTests.Readiness()

        let outcome = await Self.resend(kind, id, in: container, gmail: gmail, readiness: readiness)

        guard case .refused(let sentence) = outcome else { Issue.record("got \(outcome)"); return }
        #expect(sentence.contains("has not been sent"))
        #expect(gmail.sent.isEmpty)
        #expect(readiness.calls == 0, "a refusal made Gmail ready, which can open a browser")
        #expect(try Self.invoice(id, in: container).sentStatus == .notSent)
    }

    @Test("a reminder about an invoice paid in full is refused")
    func noreminderForAPaidInvoice() async throws {
        let (container, id) = try Self.sent(paid: true)
        let gmail = InvoiceSenderTests.FakeGmail()

        let outcome = await Self.resend(.reminder, id, in: container, gmail: gmail)

        #expect(outcome == .refused(InvoiceMailKind.reminderPaidInFull))
        #expect(gmail.sent.isEmpty)
    }

    @Test("who it goes to changed after the sheet opened, so nothing goes")
    func achangedRecipientRefuses() async throws {
        let (container, id) = try Self.sent()
        let gmail = InvoiceSenderTests.FakeGmail()

        let outcome = await Self.resend(.reminder, id, in: container, gmail: gmail,
                                        approved: ["someone@else.example"])

        #expect(outcome == .refused(InvoiceMail.recipientsChanged))
        #expect(gmail.sent.isEmpty)
    }

    @Test("Gmail refusing says nothing went, and the invoice is still sent rather than a draft")
    func gmailRefuses() async throws {
        let (container, id) = try Self.sent()
        let gmail = InvoiceSenderTests.FakeGmail()
        gmail.answer = .refuses(GmailSendError.api("invalid recipient"))

        let outcome = await Self.resend(.reminder, id, in: container, gmail: gmail)

        guard case .refused(let sentence) = outcome else { Issue.record("got \(outcome)"); return }
        #expect(sentence.contains("Nothing was sent"))
        #expect(!sentence.contains("draft"), "a sent invoice is not a draft: \(sentence)")
        #expect(try Self.invoice(id, in: container).sentStatus == .sent(route: .ovationSentIt, at: Self.firstSent))
    }

    @Test("Gmail never answering cannot tell whether it went, and writes nothing")
    func gmailNeverAnswers() async throws {
        let (container, id) = try Self.sent()
        let gmail = InvoiceSenderTests.FakeGmail()
        gmail.answer = .neverAnswers(URLError(.timedOut))

        let outcome = await Self.resend(.reminder, id, in: container, gmail: gmail)

        guard case .couldNotTell(let sentence) = outcome else { Issue.record("got \(outcome)"); return }
        #expect(sentence.contains("Sent folder"))
        #expect(try Self.invoice(id, in: container).sentStatus == .sent(route: .ovationSentIt, at: Self.firstSent))
    }

    // MARK: the reviewer and the sheet

    private static func reviewer(_ container: ModelContainer, gmail: InvoiceSenderTests.FakeGmail = .init(),
                                 settings: URL?) -> InvoiceReviewer {
        let noon = Self.noon
        return InvoiceReviewer(container: container, footer: { .fixed }, settingsFile: settings,
                               makeSender: { _ in .success(SendingRoute(sender: gmail, ready: { nil })) },
                               clock: { noon })
    }

    @Test("Remind opens the sheet on a reminder: its subject and message, no number taken")
    func remindOpensAReminder() async throws {
        let (container, id) = try Self.sent()

        let review = try await Self.reviewer(container, settings: try Self.settingsFile())
            .open(id, as: .reminder).get()

        #expect(review.kind == .reminder)
        #expect(review.subject.hasPrefix("Reminder: Invoice 1123"))
        #expect(review.message.contains("$272.19"))
        #expect(review.message.contains("still outstanding"))
        #expect(review.numberTakenHere == nil)
        #expect(review.goingTo == ["booker@client.example"])
    }

    @Test("sending the reminder from the sheet says sent, to whom, and leaves the invoice as it was")
    func thesheetSendsTheReminder() async throws {
        let (container, id) = try Self.sent()
        let gmail = InvoiceSenderTests.FakeGmail()
        let reviewer = Self.reviewer(container, gmail: gmail, settings: try Self.settingsFile())
        let review = try await reviewer.open(id, as: .reminder).get()

        await review.send()
        await reviewer.close(review)

        #expect(review.state == .sent(at: Self.noon, to: ["booker@client.example"]))
        #expect(gmail.sent.first?.body == review.message)
        let after = try Self.invoice(id, in: container)
        #expect(after.number == 1_123)
        #expect(after.sentStatus == .sent(route: .ovationSentIt, at: Self.firstSent))
    }

    @Test("Remind on an invoice that was never sent does not open, and says why", arguments: [
        InvoiceMailKind.reminder, .copy,
    ])
    func resendingADraftDoesNotOpen(kind: InvoiceMailKind) async throws {
        let (container, id) = try Self.sent(sent: false)

        let opened = await Self.reviewer(container, settings: try Self.settingsFile()).open(id, as: kind)

        guard case .failure(let refusal) = opened else { Issue.record("it opened"); return }
        #expect(refusal.sentence.contains("has not been sent"))
        #expect(try Self.invoice(id, in: container).number == 1_123)
    }

    @Test("a copy of a paid invoice says it was paid and carries no due date warning")
    func acopySaysPaid() async throws {
        let (container, id) = try Self.sent(paid: true)

        let review = try await Self.reviewer(container, settings: try Self.settingsFile())
            .open(id, as: .copy).get()

        #expect(review.subject.hasPrefix("Copy: Invoice 1123"))
        #expect(review.message.contains("was paid"))
        #expect(review.presenter.dueDateWarning == nil, "a paid invoice is not late")
    }

    @Test("a reminder Gmail never answered offers no Mark unsent, because the first send is not in question")
    func noMarkUnsentOnAReminder() async throws {
        let (container, id) = try Self.sent()
        let gmail = InvoiceSenderTests.FakeGmail()
        gmail.answer = .neverAnswers(URLError(.timedOut))
        let review = try await Self.reviewer(container, gmail: gmail, settings: try Self.settingsFile())
            .open(id, as: .reminder).get()
        await review.send()
        guard case .couldNotTell = review.state else { Issue.record("got \(review.state)"); return }

        #expect(!review.offersMarkUnsent)
        await review.markNotSent()

        guard case .couldNotTell = review.state else { Issue.record("Mark unsent acted on a reminder"); return }
        #expect(try Self.invoice(id, in: container).sentStatus == .sent(route: .ovationSentIt, at: Self.firstSent))
    }

    // MARK: the words

    @Test("the reminder and the copy say what was sent, never that it was recorded against the invoice")
    func theoutcomeLines() {
        #expect(InvoiceMailKind.reminder.sentLine(time: "3:04 PM", to: ["a@b.example"])
                    == "Reminder sent at 3:04 PM to a@b.example.")
        #expect(InvoiceMailKind.copy.sentLine(time: "3:04 PM", to: ["a@b.example"])
                    == "Copy sent at 3:04 PM to a@b.example.")
    }

    @Test("the reminder's and the copy's messages, word for word, owed their cold read (PRD 41a)")
    func themessages() {
        #expect(InvoiceMail.reminderMessage(amountDue: "$272.19", dueLine: "by November 8, 2026",
                                            shoots: ["Autumn Evensong"], signedBy: "Dan Wright")
                    == "Hello,\n\nA reminder about the invoice for Autumn Evensong, attached again here. "
                    + "$272.19 is still outstanding, and was due by November 8, 2026.\n\nThank you,\nDan")
        #expect(InvoiceMail.copyMessage(amountDue: "$272.19", dueLine: "paid November 11, 2026",
                                        paidInFull: true, shoots: ["Autumn Evensong"], signedBy: "Dan Wright")
                    == "Hello,\n\nA copy of the invoice for Autumn Evensong is attached. "
                    + "It came to $272.19 and was paid November 11, 2026.\n\nThank you,\nDan")
    }

    // MARK: the foot

    @Test("the foot offers Remind beside Record a payment, and Send a copy beside Paid in full")
    func thefoot() throws {
        let today = BusinessDate.stamping(Self.noon)
        let (owedContainer, owedID) = try Self.sent()
        let owed = InvoiceScreenPresenter(invoice: try Self.invoice(owedID, in: owedContainer),
                                          footer: .fixed, today: today)
        #expect(owed.footAction == .recordPayment)
        #expect(owed.footSecond == .reminder)

        let (paidContainer, paidID) = try Self.sent(paid: true)
        let paid = InvoiceScreenPresenter(invoice: try Self.invoice(paidID, in: paidContainer),
                                          footer: .fixed, today: today)
        #expect(paid.footAction == .paidInFull)
        #expect(paid.footSecond == .copy)

        let (draftContainer, draftID) = try Self.sent(sent: false)
        let draft = InvoiceScreenPresenter(invoice: try Self.invoice(draftID, in: draftContainer),
                                           footer: .fixed, today: today)
        #expect(draft.footSecond == nil)
    }

    @Test("the words on the foot are the design record's")
    func thewords() {
        #expect(InvoiceMailKind.reminder.footWord == "Remind")
        #expect(InvoiceMailKind.copy.footWord == "Send a copy")
    }
}
