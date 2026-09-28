import Foundation
import SwiftData
import Testing

/// ovation#556, PRD 51d and 51o. The invoice's history, built from what is recorded.
///
/// EVERY ENTRY IS SOMETHING THE STORE HOLDS. The pane names what the system did, one
/// sentence a line, and a fact that was never recorded is said to be missing rather
/// than drawn from a neighbouring one (L192): the creation day on an invoice written
/// before schema version 4, and who a send went to, which a settled send does not keep.
@MainActor
struct InvoiceHistoryTests {

    /// 2026-11-12 at noon in New York, pinned (L130).
    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static func day(_ offset: Int) -> BusinessDate {
        .stamping(noon.addingTimeInterval(TimeInterval(offset) * 86_400))
    }

    private static func context() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    /// A sent invoice for 375.00, created ten days before noon.
    private static func invoice(_ context: ModelContext, createdOn: BusinessDate? = day(-10),
                                sent: Bool = true) -> Invoice {
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        client.email = "booker@example.com"
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: day(-10),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: createdOn)
        context.insert(invoice)
        invoice.add(LineItem.flat(Money(dollars: 375), describedAs: "Photography"))
        invoice.number = 1_123
        if sent { invoice.recordSendState(.sent(route: .ovationSentIt, at: noon.addingTimeInterval(-5 * 86_400))) }
        return invoice
    }

    private static func pay(_ invoice: Invoice, _ amount: Money, by method: PaymentMethod,
                            on day: BusinessDate, in context: ModelContext,
                            source: AllocationSource = .recordedWithThePayment) -> Payment {
        let payment = Payment(client: invoice.client, amount: amount, method: method, receivedOn: day)
        context.insert(payment)
        context.insert(PaymentAllocation(payment: payment, invoice: invoice, amount: amount,
                                         allocatedOn: day, source: source))
        return payment
    }

    private static func said(_ entries: [InvoiceHistory.Entry]) -> [String] {
        entries.map { [$0.when, $0.what, $0.more].compactMap { $0 }.joined(separator: " | ") }
    }

    @Test("a draft made from a booking says so, on the day it was created")
    func adraftFromABooking() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context, sent: false)
        let shoot = Shoot(name: "Autumn Evensong", when: .dayOnly(Self.day(-10)), venue: "St Anne's")
        shoot.bookingKey = "booking-1"
        invoice.add(shoot)

        let history = InvoiceHistory(invoice)

        #expect(Self.said(history.entries) == ["2 Nov | Draft created | from a Downbeat booking"])
        #expect(history.unrecorded.isEmpty)
    }

    @Test("a draft made by hand says it was created and nothing about where from")
    func adraftByHand() throws {
        let context = try Self.context()
        let history = InvoiceHistory(Self.invoice(context, sent: false))
        #expect(Self.said(history.entries) == ["2 Nov | Draft created"])
    }

    /// Issue #556: `createdOn` is nil on every invoice written before version 4, and
    /// the pane leaves it out rather than guesses. It says the day is missing instead.
    @Test("an invoice with no recorded creation day leaves the entry out and says the day was not recorded")
    func nocreationDay() throws {
        let context = try Self.context()
        let history = InvoiceHistory(Self.invoice(context, createdOn: nil))

        #expect(!history.entries.contains { $0.what == "Draft created" })
        #expect(history.entries.map(\.what) == ["Sent"])
        #expect(history.unrecorded.contains(InvoiceHistory.creationNotRecorded))
    }

    @Test("a send with no record is Sent on its day, with no address rather than the client's")
    func sentByOvation() throws {
        let context = try Self.context()
        let entries = InvoiceHistory(Self.invoice(context)).entries
        #expect(Self.said(entries) == ["2 Nov | Draft created", "7 Nov | Sent"])
    }

    @Test("a send found in the mailbox says where it was found")
    func sentFromTheMailbox() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context)
        invoice.recordSendState(.sent(route: .foundInTheMailbox, at: Self.noon))
        #expect(Self.said(InvoiceHistory(invoice).entries).last
                    == "12 Nov | Sent | found in Gmail's Sent folder")
    }

    @Test("a send Gmail never answered is a send started, and says it is not known whether it went")
    func anunsettledSend() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context)
        invoice.recordSendState(.attempting(SendAttempt(destination: ["booker@example.com"],
                                                     wasRedirected: false, renderSHA256: "x",
                                                     startedAt: Self.noon)))
        #expect(Self.said(InvoiceHistory(invoice).entries).last
                    == "12 Nov | Send started | Gmail has not said whether it went")
    }

    @Test("each payment is its own entry naming its amount and method, oldest first")
    func payments() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context)
        _ = Self.pay(invoice, Money(dollars: 100), by: .zelle, on: Self.day(-1), in: context)
        _ = Self.pay(invoice, Money(dollars: 200), by: .check, on: Self.day(-3), in: context)

        let said = Self.said(InvoiceHistory(invoice).entries)

        #expect(Array(said.suffix(2)) == ["9 Nov | Payment recorded | $200.00 by check",
                                          "11 Nov | Payment recorded | $100.00 by Zelle"])
    }

    @Test("a check that cleared is its own entry on the day it cleared, after the payment")
    func acheckThatCleared() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context)
        let check = Self.pay(invoice, Money(dollars: 375), by: .check, on: Self.day(-3), in: context)
        check.markCleared(on: Self.day(-1))

        let said = Self.said(InvoiceHistory(invoice).entries)

        #expect(Array(said.suffix(2)) == ["9 Nov | Payment recorded | $375.00 by check",
                                          "11 Nov | Cleared"])
    }

    @Test("held money put on the invoice is not called a payment, and taking it off is its own entry")
    func heldMoney() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context)
        let deposit = Payment(client: invoice.client, amount: Money(dollars: 100), method: .zelle,
                              receivedOn: Self.day(-20))
        context.insert(deposit)
        let applied = PaymentAllocation(payment: deposit, invoice: invoice, amount: Money(dollars: 100),
                                        allocatedOn: Self.day(-4), source: .heldMoney)
        context.insert(applied)
        applied.releasedOn = Self.day(-2)

        let said = Self.said(InvoiceHistory(invoice).entries)

        #expect(Array(said.suffix(2)) == ["8 Nov | Held money applied | $100.00",
                                          "10 Nov | Held money removed | $100.00"])
        #expect(!said.contains { $0.contains("Payment recorded") })
    }

    @Test("a cancelled invoice ends with Cancelled")
    func cancelled() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context)
        invoice.closure = .cancelled(on: Self.day(0), reason: "")
        #expect(Self.said(InvoiceHistory(invoice).entries).last == "12 Nov | Cancelled")
    }

    // MARK: where the pane goes (ovation#597)

    /// Dan, 2026-09-28: at the full 1064 window the screen is 856 wide and the pane
    /// pushes, leaving the invoice its 556; at the 860 half screen window the screen
    /// is 652 and it covers the right of the invoice instead of squeezing it to 352.
    @Test("the pane pushes at the full window and covers at half screen, decided by the width left to the invoice")
    func thepaneCoversAtHalfScreen() {
        typealias Layout = InvoiceScreenView.HistoryLayout
        #expect(Layout.forWidth(OvationWindow.minimumWidth - OvationWindow.railWidth) == .cover)
        #expect(Layout.forWidth(652) == .cover)
        #expect(Layout.forWidth(856) == .push, "556 left beside the pane is PRD 51d's width, so it pushes")
        #expect(Layout.forWidth(855.5) == .cover, "half a point short of 556 left is too narrow")
        #expect(Layout.forWidth(1_200) == .push)
    }

    // MARK: the messages sent (ovation#596)

    /// A message Gmail accepted, recorded against the invoice as the sender records one.
    @discardableResult
    private static func record(_ kind: SentMessageKind, on invoice: Invoice, dayOffset: Int,
                               to recipients: [String] = ["booker@example.com"],
                               in context: ModelContext) -> SentMessage {
        let message = SentMessage(kind: kind, recipients: recipients,
                                  sentAt: noon.addingTimeInterval(TimeInterval(dayOffset) * 86_400),
                                  gmailThreadID: "thread-1", messageID: "<m1@mail.gmail.com>")
        context.insert(message)
        message.invoice = invoice
        return message
    }

    @Test("a send Ovation recorded says who it went to, as it went, not the client's address today")
    func sentSaysWhoItWentTo() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context)
        Self.record(.invoice, on: invoice, dayOffset: -5, to: ["booker@example.com", "office@example.com"],
                    in: context)
        invoice.client?.email = "someone.new@example.com"

        let history = InvoiceHistory(invoice)

        #expect(Self.said(history.entries)
                    == ["2 Nov | Draft created", "7 Nov | Sent | to booker@example.com, office@example.com"])
        #expect(history.unrecorded.isEmpty, "nothing is missing once the first send was recorded")
    }

    @Test("each reminder and copy is its own entry, on its day, saying who it went to")
    func remindersAndCopiesAreListed() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context)
        Self.record(.invoice, on: invoice, dayOffset: -5, in: context)
        Self.record(.copy, on: invoice, dayOffset: -1, to: ["accounts@example.com"], in: context)
        Self.record(.reminder, on: invoice, dayOffset: -3, in: context)
        Self.record(.reminder, on: invoice, dayOffset: 0, in: context)

        #expect(Self.said(InvoiceHistory(invoice).entries) == [
            "2 Nov | Draft created",
            "7 Nov | Sent | to booker@example.com",
            "9 Nov | Reminder sent | to booker@example.com",
            "11 Nov | Copy sent | to accounts@example.com",
            "12 Nov | Reminder sent | to booker@example.com",
        ])
    }

    /// An invoice sent before schema version 7, or found in the mailbox, has no record
    /// of who its first send went to, and the pane says so rather than drawing it
    /// from the client (L192). A reminder recorded since is still listed.
    @Test("an invoice sent before sends were recorded says who it first went to was not recorded")
    func anEarlierSendSaysItWasNotRecorded() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context)
        Self.record(.reminder, on: invoice, dayOffset: 0, in: context)

        let history = InvoiceHistory(invoice)

        #expect(Self.said(history.entries).suffix(2) == ["7 Nov | Sent", "12 Nov | Reminder sent | to booker@example.com"])
        #expect(history.unrecorded == [InvoiceHistory.firstSendNotRecorded])
        #expect(InvoiceHistory.firstSendNotRecorded
                    == "Who this invoice first went to was not recorded, and neither was any reminder or copy sent before Ovation began recording them.")
        #expect(InvoiceHistory(Self.invoice(context, sent: false)).unrecorded.isEmpty,
                "a draft has not gone anywhere, so nothing about a send is missing")
    }

    /// PRD 51o. After Record, the history opens with the new payment marked, and the
    /// new payment is found by comparing the entries before and after, never by
    /// position, which a second payment on the same day would make ambiguous (L237).
    @Test("the payment just recorded is the payment entry that was not there before")
    func theNewPaymentIsFound() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context)
        _ = Self.pay(invoice, Money(dollars: 100), by: .zelle, on: Self.day(0), in: context)
        let before = InvoiceHistory(invoice).entries
        _ = Self.pay(invoice, Money(dollars: 100), by: .zelle, on: Self.day(0), in: context)
        let after = InvoiceHistory(invoice).entries

        let marked = InvoiceHistory.newlyRecorded(before: before, after: after)

        #expect(marked.count == 1)
        let entry = try #require(after.first { marked.contains($0.id) })
        #expect(entry.what == "Payment recorded")
        #expect(!before.contains { $0.id == entry.id })
    }

    @Test("nothing new, nothing marked, and a new entry that is not a payment is not marked")
    func onlyPaymentsAreMarked() throws {
        let context = try Self.context()
        let invoice = Self.invoice(context, sent: false)
        let before = InvoiceHistory(invoice).entries
        invoice.recordSendState(.sent(route: .ovationSentIt, at: Self.noon))
        let after = InvoiceHistory(invoice).entries

        #expect(InvoiceHistory.newlyRecorded(before: before, after: before).isEmpty)
        #expect(InvoiceHistory.newlyRecorded(before: before, after: after).isEmpty)
    }

    // MARK: paid in full, one predicate (L16)

    @Test("paid in full is money covering a priced total, never a comp and never an unpriced draft")
    func paidInFull() throws {
        let context = try Self.context()
        let owed = Self.invoice(context)
        #expect(!owed.isPaidInFull)
        _ = Self.pay(owed, owed.total, by: .zelle, on: Self.day(0), in: context)
        #expect(owed.isPaidInFull)

        let part = Self.invoice(context)
        _ = Self.pay(part, Money(dollars: 100), by: .zelle, on: Self.day(0), in: context)
        #expect(!part.isPaidInFull)

        // A PRICED COMP OWES NOTHING AND WAS NOT PAID (PRD 5.1b): no receipt, no Paid in full.
        let comp = Self.invoice(context)
        comp.lineItems.forEach { $0.unitAmount = .zero }
        #expect(!comp.isPaidInFull)

        // ovation#582. An unpriced draft with money on it is not paid, whatever it totals.
        let unpriced = Invoice(client: owed.client, kind: .photography, invoiceDate: Self.day(0),
                               hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        context.insert(unpriced)
        unpriced.add(Shoot(name: "Autumn Evensong", when: .dayOnly(Self.day(0)), venue: nil))
        _ = Self.pay(unpriced, Money(dollars: 50), by: .zelle, on: Self.day(0), in: context)
        #expect(unpriced.isUnpriced)
        #expect(!unpriced.isPaidInFull)
    }
}
