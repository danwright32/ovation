import Foundation
import SwiftData
import Testing

/// ovation#457, PRD 5.8 and 5.4b. Putting a client's referral credit on an
/// invoice and taking it back off.
///
/// HOW MUCH IT SPENDS IS NOT A NUMBER ANYBODY TYPES. PRD 5.51e settles that the
/// credit "keeps its menu entry, having no controls of its own anywhere", so the
/// menu entry is the whole interface and the amount is derived. It is the
/// smaller of what the client has earned and what the invoice is charging, which
/// is both halves of the design record's own rule (`docs/design/rules/money.js`,
/// "A credit may never exceed the balance, nor take an invoice below nothing")
/// and Dan's decision of 2026-09-23, taken over spending the whole balance and
/// refusing the send, and over asking him for a figure.
///
/// THE CAP IS THIS WRITER'S, NEVER THE LEDGER'S. `ReferralLedger`'s own header
/// records that spending more than the balance is allowed there on purpose,
/// because PRD 5.8 asks for a WARNING when a booking is flagged as spending
/// credit the client does not have and a warning is not a refusal. That stays
/// true: this caps what the invoice screen offers to spend, and the log beneath
/// it goes on accepting what it is told (L542, two rules that differ are two
/// decisions until each one's record is read).
@MainActor
struct InvoiceReferralCreditWriterTests {

    private static let dayKey = "2026-11-12"

    private static func day() throws -> BusinessDate {
        try #require(BusinessCalendar.day(forKey: dayKey))
    }

    /// A client, an invoice charging `lines`, and `earned` hours banked.
    ///
    /// THE EARNING GOES THROUGH THE LEDGER rather than being planted, because the
    /// balance is a sum over the log and a fixture that writes the entries itself
    /// would be asserting against a shape only the fixture produces (L48).
    private static func draft(
        earning earned: Hours, charging lines: Money, at rate: Money
    ) async throws -> (ModelContainer, PersistentIdentifier, PersistentIdentifier) {
        let container = try OvationSchema.container(inMemory: true)
        let day = try day()
        let context = ModelContext(container)
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: day, hourlyRate: rate, taxRate: .newYorkCity)
        if lines > .zero {
            invoice.add(LineItem.flat(lines, describedAs: "Photography"))
        }
        context.insert(invoice)
        try context.save()

        if earned > .zero {
            try await ReferralLedger(modelContainer: container)
                .earn(earned, for: client.persistentModelID,
                      fromBooking: "cedar-hill-2026-10-01", on: day)
        }
        return (container, invoice.persistentModelID, client.persistentModelID)
    }

    private static func read(_ id: PersistentIdentifier,
                             in container: ModelContainer) throws -> Invoice {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == id })
    }

    private static func balance(_ id: PersistentIdentifier,
                                in container: ModelContainer) throws -> Hours {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Client>())
            .first { $0.persistentModelID == id }).referralBalance
    }

    // MARK: what it spends

    /// The ordinary shape, and the only one that has ever appeared in the real
    /// data: a balance smaller than the invoice, spent whole.
    @Test("the whole balance lands when the invoice is charging more than it")
    func thewholeBalanceLands() async throws {
        let (container, invoiceID, clientID) = try await Self.draft(
            earning: Hours(whole: 1), charging: Money(dollars: 400), at: Money(dollars: 250))

        try await InvoiceReferralCreditWriter(modelContainer: container)
            .applyReferralCredit(on: invoiceID, on: Self.day())

        let invoice = try Self.read(invoiceID, in: container)
        #expect(invoice.referralCredit?.hours == Hours(whole: 1))
        #expect(invoice.referralCreditAmount == Money(dollars: 250))
        #expect(invoice.subtotal == Money(dollars: 150))
        #expect(try Self.balance(clientID, in: container) == .zero)
    }

    /// DAN'S DECISION, 2026-09-23. A balance larger than the invoice is spent
    /// only as far as the charges, and the rest stays banked. He chose it over
    /// spending the whole balance and letting `Invoice.totalBelowZero` refuse the
    /// send, and over being asked how much to spend.
    @Test("a balance larger than the invoice is spent only as far as the charges")
    func abalanceLargerThanTheInvoice() async throws {
        let (container, invoiceID, clientID) = try await Self.draft(
            earning: Hours(whole: 10), charging: Money(dollars: 400), at: Money(dollars: 250))

        try await InvoiceReferralCreditWriter(modelContainer: container)
            .applyReferralCredit(on: invoiceID, on: Self.day())

        let invoice = try Self.read(invoiceID, in: container)
        #expect(invoice.referralCreditAmount == Money(dollars: 400))
        #expect(invoice.subtotal == .zero)
        // PRD 5.1b: a zero total is an ordinary invoice and no guard may refuse it.
        #expect(!invoice.refusals.contains(.totalBelowZero))
        #expect(invoice.referralCredit?.hours == Hours(hundredths: 160))
        #expect(try Self.balance(clientID, in: container) == Hours(hundredths: 840))
    }

    /// THE CAP IS EXACT RATHER THAN NEAR, and this is the case that tells the two
    /// apart: at $30 an hour no whole hundredth of an hour comes to $100, so the
    /// largest credit that fits is $99.90 and the invoice keeps ten cents. An
    /// implementation that divided and rounded would spend $100.20 here and take
    /// the invoice below nothing, which is the one thing the cap exists to stop.
    @Test("the cap lands exactly where the rate does not divide the charges")
    func thecapLandsExactly() async throws {
        let (container, invoiceID, _) = try await Self.draft(
            earning: Hours(whole: 10), charging: Money(dollars: 100), at: Money(dollars: 30))

        try await InvoiceReferralCreditWriter(modelContainer: container)
            .applyReferralCredit(on: invoiceID, on: Self.day())

        let invoice = try Self.read(invoiceID, in: container)
        #expect(invoice.referralCredit?.hours == Hours(hundredths: 333))
        #expect(invoice.referralCreditAmount == Money(cents: 9_990))
        #expect(invoice.subtotal == Money(cents: 10))
    }

    // MARK: what it refuses

    /// IT REFUSES RATHER THAN WRITING A CREDIT WORTH NOTHING. A zero credit
    /// records no decision, and a silent success here would leave the menu
    /// looking as though it had done something (L109).
    @Test("a client with nothing banked is refused, and nothing is written")
    func aclientWithNothingBanked() async throws {
        let (container, invoiceID, _) = try await Self.draft(
            earning: .zero, charging: Money(dollars: 400), at: Money(dollars: 250))

        await #expect(throws: InvoiceReferralCreditRefusal.noCreditToSpend) {
            try await InvoiceReferralCreditWriter(modelContainer: container)
                .applyReferralCredit(on: invoiceID, on: Self.day())
        }
        #expect(try Self.read(invoiceID, in: container).referralCredit == nil)
    }

    /// An invoice charging nothing has nothing to take a credit off, and spending
    /// one against it would burn the balance for no reduction at all.
    @Test("an invoice charging nothing is refused")
    func aninvoiceChargingNothing() async throws {
        let (container, invoiceID, clientID) = try await Self.draft(
            earning: Hours(whole: 2), charging: .zero, at: Money(dollars: 250))

        await #expect(throws: InvoiceReferralCreditRefusal.nothingIsBeingCharged) {
            try await InvoiceReferralCreditWriter(modelContainer: container)
                .applyReferralCredit(on: invoiceID, on: Self.day())
        }
        #expect(try Self.balance(clientID, in: container) == Hours(whole: 2))
    }

    /// FETCHED AND MATCHED, NEVER SUBSCRIPTED, the same reason the other writers
    /// on this screen record: the screen is a photograph taken at the last write,
    /// and the row may be gone by the time the menu is pressed.
    @Test("an invoice removed since the screen read it is refused by name")
    func aninvoiceRemovedSince() async throws {
        let (container, invoiceID, _) = try await Self.draft(
            earning: Hours(whole: 1), charging: Money(dollars: 400), at: Money(dollars: 250))
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == invoiceID })
        context.delete(invoice)
        try context.save()

        await #expect(throws: InvoiceReferralCreditRefusal.noSuchInvoice) {
            try await InvoiceReferralCreditWriter(modelContainer: container)
                .applyReferralCredit(on: invoiceID, on: Self.day())
        }
    }

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    /// A SENT INVOICE'S FIGURES ARE WHAT THE CLIENT WAS TOLD, the same rule
    /// `InvoiceDiscountWriter` keeps, and a credit moves the total exactly as a
    /// discount does.
    @Test("a sent invoice keeps the credit it was sent with")
    func asentInvoiceIsRefused() async throws {
        let (container, invoiceID, clientID) = try await Self.draft(
            earning: Hours(whole: 1), charging: Money(dollars: 400), at: Money(dollars: 250))
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == invoiceID })
        invoice.number = 1_123
        invoice.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)
        try context.save()

        await #expect(throws: InvoiceReferralCreditRefusal.invoiceWasSent) {
            try await InvoiceReferralCreditWriter(modelContainer: container)
                .applyReferralCredit(on: invoiceID, on: Self.day())
        }
        #expect(try Self.read(invoiceID, in: container).referralCredit == nil)
        #expect(try Self.balance(clientID, in: container) == Hours(whole: 1),
                "and the balance was not touched either")
    }

    @Test("a send that has not settled refuses the credit by its own name")
    func anunsettledSendIsRefused() async throws {
        let (container, invoiceID, _) = try await Self.draft(
            earning: Hours(whole: 1), charging: Money(dollars: 400), at: Money(dollars: 250))
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == invoiceID })
        invoice.sentStatus = .couldNotDetermine(checkedAt: Self.noon)
        try context.save()

        await #expect(throws: InvoiceReferralCreditRefusal.sendIsUnsettled) {
            try await InvoiceReferralCreditWriter(modelContainer: container)
                .applyReferralCredit(on: invoiceID, on: Self.day())
        }
    }

    // MARK: running twice

    /// ASSUME IT RUNS TWICE. The menu can be pressed again, and an edit and
    /// resend re-runs whatever applied the credit, which is the reason the
    /// ledger keys a spend on the invoice at all.
    @Test("applying a second time is refused, and the balance moved only once")
    func applyingTwiceIsRefused() async throws {
        let (container, invoiceID, clientID) = try await Self.draft(
            earning: Hours(whole: 5), charging: Money(dollars: 400), at: Money(dollars: 250))
        let writer = InvoiceReferralCreditWriter(modelContainer: container)
        try await writer.applyReferralCredit(on: invoiceID, on: Self.day())

        await #expect(throws: InvoiceReferralCreditRefusal.creditIsAlreadyApplied) {
            try await writer.applyReferralCredit(on: invoiceID, on: Self.day())
        }
        #expect(try Self.balance(clientID, in: container) == Hours(hundredths: 340))
    }

    /// THE LEDGER IS WRITTEN FIRST SO THAT THIS CASE EXISTS. A crash between the
    /// two writes leaves the spend recorded and the invoice showing nothing, and
    /// the next attempt FINISHES it rather than refusing: the hours come from the
    /// entry that is already there, so the balance moves once in total (L33).
    @Test("a spend recorded with no credit on the invoice is finished, not repeated")
    func ahalfWrittenSpendIsFinished() async throws {
        let (container, invoiceID, clientID) = try await Self.draft(
            earning: Hours(whole: 5), charging: Money(dollars: 400), at: Money(dollars: 250))
        let invoiceUUID = try Self.read(invoiceID, in: container).id
        try await ReferralLedger(modelContainer: container)
            .spend(Hours(hundredths: 60), for: clientID, onInvoice: invoiceUUID, on: Self.day())

        try await InvoiceReferralCreditWriter(modelContainer: container)
            .applyReferralCredit(on: invoiceID, on: Self.day())

        let invoice = try Self.read(invoiceID, in: container)
        #expect(invoice.referralCredit?.hours == Hours(hundredths: 60),
                "the hours come from the entry already in the ledger, never recomputed")
        #expect(invoice.referralCreditAmount == Money(dollars: 150))
        #expect(try Self.balance(clientID, in: container) == Hours(hundredths: 440),
                "and the balance moved once in total, not twice")
    }

    // MARK: taking it back off

    @Test("removing takes the credit off the invoice and gives the hours back")
    func removingGivesTheHoursBack() async throws {
        let (container, invoiceID, clientID) = try await Self.draft(
            earning: Hours(whole: 1), charging: Money(dollars: 400), at: Money(dollars: 250))
        let writer = InvoiceReferralCreditWriter(modelContainer: container)
        try await writer.applyReferralCredit(on: invoiceID, on: Self.day())

        try await writer.removeReferralCredit(on: invoiceID, on: Self.day())

        let invoice = try Self.read(invoiceID, in: container)
        #expect(invoice.referralCredit == nil)
        #expect(invoice.subtotal == Money(dollars: 400))
        #expect(try Self.balance(clientID, in: container) == Hours(whole: 1))
    }

    /// REMOVING AND APPLYING AGAIN HAS TO WORK, because the menu offers both and
    /// a balance that could only ever be spent once per invoice would strand the
    /// hours the moment Dan changed his mind.
    @Test("a credit removed can be applied again")
    func acreditRemovedCanBeAppliedAgain() async throws {
        let (container, invoiceID, clientID) = try await Self.draft(
            earning: Hours(whole: 1), charging: Money(dollars: 400), at: Money(dollars: 250))
        let writer = InvoiceReferralCreditWriter(modelContainer: container)
        try await writer.applyReferralCredit(on: invoiceID, on: Self.day())
        try await writer.removeReferralCredit(on: invoiceID, on: Self.day())

        try await writer.applyReferralCredit(on: invoiceID, on: Self.day())

        #expect(try Self.read(invoiceID, in: container).referralCredit?.hours == Hours(whole: 1))
        #expect(try Self.balance(clientID, in: container) == .zero)
    }

    @Test("removing a credit that is not there is refused by name")
    func removingNothingIsRefused() async throws {
        let (container, invoiceID, clientID) = try await Self.draft(
            earning: Hours(whole: 1), charging: Money(dollars: 400), at: Money(dollars: 250))

        await #expect(throws: InvoiceReferralCreditRefusal.noCreditIsApplied) {
            try await InvoiceReferralCreditWriter(modelContainer: container)
                .removeReferralCredit(on: invoiceID, on: Self.day())
        }
        #expect(try Self.balance(clientID, in: container) == Hours(whole: 1),
                "and nothing was given back that was never spent")
    }

    @Test("a sent invoice keeps its credit when removal is asked for")
    func removingFromASentInvoiceIsRefused() async throws {
        let (container, invoiceID, clientID) = try await Self.draft(
            earning: Hours(whole: 1), charging: Money(dollars: 400), at: Money(dollars: 250))
        let writer = InvoiceReferralCreditWriter(modelContainer: container)
        try await writer.applyReferralCredit(on: invoiceID, on: Self.day())
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == invoiceID })
        invoice.number = 1_124
        invoice.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)
        try context.save()

        await #expect(throws: InvoiceReferralCreditRefusal.invoiceWasSent) {
            try await writer.removeReferralCredit(on: invoiceID, on: Self.day())
        }
        #expect(try Self.read(invoiceID, in: container).referralCredit != nil)
        #expect(try Self.balance(clientID, in: container) == .zero)
    }

    @Test("every refusal carries a sentence, and none of them is empty")
    func everyrefusalSaysSomething() {
        for refusal in InvoiceReferralCreditRefusal.allCases {
            #expect(refusal.sentence.isEmpty == false)
            #expect(refusal.sentence.hasSuffix("."))
        }
    }
}
