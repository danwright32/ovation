import BackstageGoogle
import Foundation
import SwiftData
import Testing

/// ovation#42, PRD 10c. Opening the review of a REAL invoice, sending it, and closing it.
///
/// REVIEW TAKES THE NUMBER, AND CLOSING UNSENT GIVES IT BACK (Dan, 2026-09-14, the
/// numbering rule on ovation#42). The render made at Review carries that number, and the
/// send attaches that same render. A number is never handed back from an invoice whose
/// send was accepted or is unsettled, because a client may already hold it (ovation#460).
///
/// THE PRESENTER AND SESSION ARE BUILT ONCE, here, never inside a sheet's content, which
/// re-runs on every body evaluation and would re-render the PDF, so "the preview is the
/// attachment" would quietly stop being true (ovation#42's plan).
@MainActor
struct InvoiceReviewerTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    private static func settingsFile(_ json: String?) throws -> URL {
        let folder = URL.temporaryDirectory
            .appending(path: "ovation-review-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "sending.json")
        if let json { try Data(json.utf8).write(to: url) }
        return url
    }

    private static let clients = #"{"fromName":"Dan Wright","fromEmail":"dan@studio.example","destination":"clients"}"#
    private static let test = #"{"fromName":"Dan Wright","fromEmail":"dan@studio.example","destination":"test","testAddress":"second@elsewhere.example"}"#

    /// A reviewable draft with no number yet, the way a real draft reaches Review.
    private static func draft(numbered: Int64? = nil) throws -> (ModelContainer, PersistentIdentifier) {
        let container = try OvationSchema.container(inMemory: true)
        let context = container.mainContext
        let invoice = try InvoiceFixtures.invoice("Ordinary", in: context)
        invoice.client?.email = "booker@client.example"
        invoice.number = numbered
        for shoot in invoice.shoots {
            shoot.shotFrom = ClockTime("19:00")
            shoot.shotUntil = ClockTime("20:00")
        }
        try context.save()
        return (container, invoice.persistentModelID)
    }

    private static func reviewer(_ container: ModelContainer, settings: URL?,
                                 gmail: InvoiceSenderTests.FakeGmail = .init(),
                                 senderCalls: SenderCalls = .init(),
                                 footer: @escaping () -> InvoiceFooter = { .fixed }) -> InvoiceReviewer {
        let noon = Self.noon
        return InvoiceReviewer(container: container, footer: footer, settingsFile: settings,
                               makeSender: { _ in
                                   senderCalls.count += 1
                                   return .success(SendingRoute(sender: gmail, ready: {
                                       senderCalls.readies += 1
                                       return nil
                                   }))
                               },
                               clock: { noon })
    }

    final class SenderCalls: @unchecked Sendable {
        var count = 0
        /// How often Gmail was made ready, the moment a browser can open.
        var readies = 0
    }

    private static func invoice(_ id: PersistentIdentifier, in container: ModelContainer) throws -> Invoice {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == id })
    }

    // MARK: the number

    @Test("opening the review of an unnumbered draft takes the next number, and the page carries it")
    func openingTakesTheNumber() async throws {
        let (container, id) = try Self.draft()

        let review = try await Self.reviewer(container, settings: nil).open(id).get()

        let number = try #require(try Self.invoice(id, in: container).number)
        #expect(review.presenter.subtitle.contains("\(number)"))
        #expect(review.numberTakenHere == number)
    }

    @Test("closing the review without sending gives the number back")
    func closingUnsentGivesItBack() async throws {
        let (container, id) = try Self.draft()
        let reviewer = Self.reviewer(container, settings: nil)
        let review = try await reviewer.open(id).get()

        await reviewer.close(review)

        #expect(try Self.invoice(id, in: container).number == nil)
    }

    @Test("an invoice that already had a number keeps it, and closing does not touch it")
    func anumberedInvoiceKeepsItsNumber() async throws {
        let (container, id) = try Self.draft(numbered: 1_123)
        let reviewer = Self.reviewer(container, settings: nil)

        let review = try await reviewer.open(id).get()
        await reviewer.close(review)

        #expect(review.numberTakenHere == nil)
        #expect(try Self.invoice(id, in: container).number == 1_123)
    }

    @Test("closing after a send Gmail accepted keeps the number")
    func closingAfterASendKeepsIt() async throws {
        let (container, id) = try Self.draft()
        let reviewer = Self.reviewer(container, settings: try Self.settingsFile(Self.clients))
        let review = try await reviewer.open(id).get()
        await review.send()

        await reviewer.close(review)

        #expect(try Self.invoice(id, in: container).number != nil)
        #expect(try Self.invoice(id, in: container).sentStatus.wasSent)
    }

    @Test("closing after a send Gmail never answered keeps the number too")
    func closingAfterAnUnsettledSendKeepsIt() async throws {
        let (container, id) = try Self.draft()
        let gmail = InvoiceSenderTests.FakeGmail()
        gmail.answer = .neverAnswers(URLError(.timedOut))
        let reviewer = Self.reviewer(container, settings: try Self.settingsFile(Self.clients), gmail: gmail)
        let review = try await reviewer.open(id).get()
        await review.send()

        await reviewer.close(review)

        #expect(try Self.invoice(id, in: container).number != nil)
    }

    // MARK: the send, from the sheet

    @Test("with no sending settings, Send refuses by name and never asks for Gmail")
    func nosettingsRefusesBeforeGmail() async throws {
        let (container, id) = try Self.draft()
        let calls = SenderCalls()
        let missing = try Self.settingsFile(nil)
        let review = try await Self.reviewer(container, settings: missing, senderCalls: calls).open(id).get()

        await review.send()

        #expect(review.state == .refused(SendingSettingsRefusal.noFile(path: missing.path).sentence))
        #expect(calls.count == 0)
    }

    @Test("a build with no sending settings at all says it does not send")
    func abuildThatDoesNotSendSaysSo() async throws {
        let (container, id) = try Self.draft()
        let review = try await Self.reviewer(container, settings: nil).open(id).get()

        await review.send()

        guard case .refused(let sentence) = review.state else { Issue.record("got \(review.state)"); return }
        #expect(sentence.contains("does not send"))
    }

    @Test("an accepted send leaves the sheet saying sent, to whom")
    func anacceptedSendIsSaid() async throws {
        let (container, id) = try Self.draft()
        let review = try await Self.reviewer(container, settings: try Self.settingsFile(Self.clients)).open(id).get()

        await review.send()

        #expect(review.state == .sent(at: Self.noon, to: ["booker@client.example"]))
    }

    /// THE FOOTER IS ASKED AGAIN AT THE PRESS (L567). A footer changed after the sheet
    /// opened is refused whether or not the new one is complete: an incomplete one must
    /// not go out, and a complete one is not what the page Dan approved carries.
    @Test("a footer changed after the sheet opened stops the send before Gmail", arguments: [
        "payment cleared", "payment reworded",
    ])
    func achangedFooterStopsTheSend(change: String) async throws {
        let (container, id) = try Self.draft()
        let gmail = InvoiceSenderTests.FakeGmail()
        let calls = SenderCalls()
        let current = FooterBox()
        let review = try await Self.reviewer(container, settings: try Self.settingsFile(Self.clients),
                                             gmail: gmail, senderCalls: calls,
                                             footer: { current.footer }).open(id).get()
        let fixed = InvoiceFooter.fixed
        current.footer = InvoiceFooter(payment: change == "payment cleared" ? "" : "Pay by bank transfer.",
                                       note: fixed.note, contact: fixed.contact)

        await review.send()

        guard case .refused(let sentence) = review.state else { Issue.record("\(change): \(review.state)"); return }
        #expect(sentence == InvoiceReviewer.footerChanged)
        #expect(calls.count == 0, "\(change) asked for Gmail")
        #expect(gmail.sent.isEmpty)
        #expect(try Self.invoice(id, in: container).sentStatus == .notSent)
    }

    final class FooterBox { var footer = InvoiceFooter.fixed }

    /// THE SHEET SAID CLIENT, THE FILE NOW SAYS TEST (or the reverse): the send
    /// refuses rather than going somewhere the sheet never showed.
    @Test("a destination changed after the sheet opened stops the send")
    func achangedDestinationStopsTheSend() async throws {
        let (container, id) = try Self.draft()
        let gmail = InvoiceSenderTests.FakeGmail()
        let calls = SenderCalls()
        let file = try Self.settingsFile(Self.clients)
        let review = try await Self.reviewer(container, settings: file, gmail: gmail,
                                             senderCalls: calls).open(id).get()
        try Data(Self.test.utf8).write(to: file)

        await review.send()

        #expect(review.state == .refused(InvoiceMail.recipientsChanged))
        #expect(gmail.sent.isEmpty)
        #expect(calls.readies == 0, "a refused send made Gmail ready, which can open a browser")
    }

    /// THE PREVIEW IS THE ATTACHMENT (PRD 10c): the bytes sent are the bytes the
    /// session rendered for the page, and the session rendered once.
    @Test("what is attached is the one render the page shows")
    func theattachmentIsTheRender() async throws {
        let (container, id) = try Self.draft()
        let gmail = InvoiceSenderTests.FakeGmail()
        let review = try await Self.reviewer(container, settings: try Self.settingsFile(Self.clients),
                                             gmail: gmail).open(id).get()

        await review.send()

        #expect(gmail.sent.first?.attachments.first?.data == (try review.presenter.renderedBytes()))
        #expect(review.presenter.renderCount == 1)
    }

    // MARK: what the sheet says

    @Test("the message starts from a sentence naming the shoot, the amount and when it is due")
    func thedefaultMessageNamesTheFacts() async throws {
        let (container, id) = try Self.draft()
        let review = try await Self.reviewer(container, settings: try Self.settingsFile(Self.clients)).open(id).get()

        #expect(review.message.contains("$272.19"))
        #expect(review.message.contains("November 8, 2026"))
        #expect(review.message.hasSuffix("Dan"))
    }

    @Test("an emptied message refuses the send with the settled sentence")
    func anemptyMessageRefuses() async throws {
        let (container, id) = try Self.draft()
        let review = try await Self.reviewer(container, settings: try Self.settingsFile(Self.clients)).open(id).get()
        review.message = "   "

        #expect(review.whySendIsWaiting == InvoiceMail.emptyMessage)
    }

    @Test("a test destination is said on the sheet before anything is pressed")
    func atestDestinationIsSaid() async throws {
        let (container, id) = try Self.draft()
        let review = try await Self.reviewer(container, settings: try Self.settingsFile(Self.test)).open(id).get()

        #expect(review.destinationWarning?.contains("second@elsewhere.example") == true)
        #expect(review.subject.hasPrefix("Invoice "))
    }

    /// WHO IT GOES TO IS PART OF WHAT IS APPROVED (L64). With sends redirected, the sheet
    /// lists the test address the message will reach, never the client it will not.
    @Test("the sheet lists where the message actually goes, the test address when redirected")
    func thesheetListsTheRealDestination() async throws {
        let (container, id) = try Self.draft()

        let redirected = try await Self.reviewer(container, settings: try Self.settingsFile(Self.test)).open(id).get()
        #expect(redirected.goingTo == ["second@elsewhere.example"])

        let (container2, id2) = try Self.draft()
        let ordinary = try await Self.reviewer(container2, settings: try Self.settingsFile(Self.clients)).open(id2).get()
        #expect(ordinary.goingTo == ["booker@client.example"])
    }
}
