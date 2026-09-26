import Foundation
import SwiftData
import Testing

/// ovation#461, PRD 1, 3, 3a, 3c, 5.7, 42c. One queued booking becomes one draft.
///
/// NOTHING IN OVATION CREATED AN INVOICE BEFORE THIS. Measured 2026-09-21: the
/// only `context.insert(invoice)` outside tests was `ReviewSampleWorld`, which is
/// Debug only. So ovation#42 had nothing to send, and every screen in the
/// Invoicing and sending milestone was built against a population nothing put
/// there.
///
/// IT IS A SHORTCUT AND THE SHORTCUT IS NAMED: ovation#32's drain replaces this,
/// and ovation#31's ledger is what this deliberately does not write.
///
/// THE DRAFT IS UNPRICED, WHICH IS THE POINT RATHER THAN AN OMISSION. PRD 3a
/// makes the booking's times a placeholder nothing may be priced from, and PRD 3c
/// says a drafted invoice carries no duration and cannot be sent until Dan
/// supplies one. So the shoot arrives with its DAY and no times, and Dan types
/// them on the invoice screen (ovation#457). A drafter that copied `startsAt` and
/// `endsAt` onto the shoot would price every invoice from Downbeat's placeholder,
/// which is the one thing both requirements forbid.
///
/// ON THE MAIN ACTOR, because `ReviewGate.refusal` is: one case asserts what the
/// SCREEN would say about a fresh draft, and the screen is main actor isolated.
/// The drafter is an actor of its own and is awaited across that boundary, which
/// is exactly how the app calls it.
@MainActor
struct BookingDrafterTests {

    // MARK: fixtures

    private static func fixtureData(_ file: StaticString = #filePath) throws -> Data {
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appending(path: "Fixtures/handoff-record-v3-2026-09-06.json"))
    }

    /// The measured record, optionally with named fields replaced. Built by
    /// editing the real bytes rather than by constructing a value, so a fixture
    /// cannot drift into a shape Downbeat never writes (L48).
    private static func record(booking edits: [String: Any] = [:],
                               client clientEdits: [String: Any] = [:]) throws -> HandoffRecord {
        var object = try #require(try JSONSerialization.jsonObject(with: try fixtureData())
                                    as? [String: Any])
        var booking = try #require(object["booking"] as? [String: Any])
        for (key, value) in edits { booking[key] = value }
        object["booking"] = booking
        var client = try #require(object["client"] as? [String: Any])
        for (key, value) in clientEdits { client[key] = value }
        object["client"] = client
        let data = try JSONSerialization.data(withJSONObject: object)
        guard case .read(let record) = HandoffRecord.read(data) else {
            throw DraftFixtureProblem.theRecordDidNotDecode
        }
        return record
    }

    private enum DraftFixtureProblem: Error { case theRecordDidNotDecode }

    /// The day the draft is made on, 2026-09-25 in New York. Deliberately NOT the
    /// fixture booking's shoot day, so a drafter that stamped one where the other
    /// belongs is caught rather than agreeing by coincidence.
    private static let draftedOn = BusinessDate.stamping(Date(timeIntervalSince1970: 1_790_352_000))

    private static func store() throws -> ModelContainer {
        try OvationSchema.container(inMemory: true)
    }

    private static func invoices(in container: ModelContainer) throws -> [Invoice] {
        try ModelContext(container).fetch(FetchDescriptor<Invoice>())
    }

    private static func clients(in container: ModelContainer) throws -> [Client] {
        try ModelContext(container).fetch(FetchDescriptor<Client>())
    }

    /// A client Ovation already holds, carrying Downbeat's own identifier, which
    /// is the only basis that links without asking (ovation#34).
    @discardableResult
    private static func knownClient(in container: ModelContainer,
                                    downbeatID: UUID) throws -> Client {
        let context = ModelContext(container)
        let client = Client(name: "Ashgrove Chamber Players", taxStatus: .notExempt)
        client.downbeatClientID = downbeatID
        client.email = "booking@ashgrove.example"
        context.insert(client)
        try context.save()
        return client
    }

    // MARK: what one booking becomes

    @Test("a queued booking becomes a draft for the client Ovation already holds")
    func abookingBecomesADraft() async throws {
        let container = try Self.store()
        let record = try Self.record()
        try Self.knownClient(in: container, downbeatID: record.client.id)

        let outcome = try await BookingDrafter(modelContainer: container)
            .draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        guard case .drafted = outcome else {
            Issue.record("the booking was not drafted: \(outcome)")
            return
        }
        let drafts = try Self.invoices(in: container)
        let invoice = try #require(drafts.first)
        #expect(drafts.count == 1)
        #expect(invoice.client?.downbeatClientID == record.client.id)
        #expect(invoice.kind == .photography)
        #expect(invoice.hourlyRate == Pricing.standardHourlyRate)
        let clientCount = try Self.clients(in: container).count
        #expect(clientCount == 1, "a second client was manufactured")
    }

    /// ovation#510, PRD 51d. The history opens with Draft created, so the day is
    /// stored when the draft is made rather than inferred later.
    @Test("a drafted invoice records the day it was created, which is not its shoot's day")
    func adraftRecordsTheDayItWasCreated() async throws {
        let container = try Self.store()
        let record = try Self.record()
        try Self.knownClient(in: container, downbeatID: record.client.id)

        _ = try await BookingDrafter(modelContainer: container)
            .draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        let invoice = try #require(try Self.invoices(in: container).first)
        #expect(invoice.createdOn?.dayKey == Self.draftedOn.dayKey)
        #expect(invoice.createdOn?.dayKey != invoice.invoiceDate?.dayKey,
                "the fixture's shoot day and the drafting day differ, so this can tell them apart")
    }

    /// THE SHOOT ARRIVES WITH ITS DAY AND NO TIMES (PRD 3a, 3c). The record
    /// carries `startsAt` and `endsAt` and they are deliberately not copied: they
    /// are Downbeat's placeholder, and an invoice priced from them is the failure
    /// both requirements were written against.
    @Test("the shoot carries the booking's day, and no times to price from")
    func theshootHasItsDayAndNoTimes() async throws {
        let container = try Self.store()
        let record = try Self.record()
        try Self.knownClient(in: container, downbeatID: record.client.id)

        _ = try await BookingDrafter(modelContainer: container)
            .draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        let invoice = try #require(try Self.invoices(in: container).first)
        let shoot = try #require(invoice.orderedShoots.first)
        #expect(shoot.name == record.booking.shootName)
        #expect(shoot.venue == record.booking.venueName)
        #expect(shoot.day?.dayKey == record.booking.startDate)
        #expect(shoot.shotFrom == nil, "the booking's placeholder start was priced from")
        #expect(shoot.shotUntil == nil, "the booking's placeholder end was priced from")
        #expect(invoice.isUnpriced, "a draft arrived already priced, which PRD 3c forbids")
    }

    /// AND THE LINE IS THERE WITH NO HOURS, which is the shape the rest of the
    /// product is already built on: `ReviewGate` refuses an invoice with nothing
    /// on it (ovation#458), so a draft with a shoot and no line at all would be
    /// refused for the wrong reason, naming an empty invoice when the truth is
    /// that it is waiting on a time.
    @Test("the photography line is there, waiting on the hours rather than missing")
    func thelineIsThereWaitingOnHours() async throws {
        let container = try Self.store()
        let record = try Self.record()
        try Self.knownClient(in: container, downbeatID: record.client.id)

        _ = try await BookingDrafter(modelContainer: container)
            .draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        let invoice = try #require(try Self.invoices(in: container).first)
        let line = try #require(invoice.orderedLineItems.first)
        #expect(invoice.lineItems.count == 1)
        #expect(line.hours == nil)
        #expect(line.shoot?.persistentModelID == invoice.orderedShoots.first?.persistentModelID)
        let says = ReviewGate.refusal(for: invoice, footer: .fixed)
        #expect(says == "Waiting on the shoot's start and end times.", "it says \(says ?? "nothing")")
    }

    /// PRD 5.7. Fourteen days after the invoice date, and the invoice is dated
    /// from the SHOOT rather than from when the record was committed, which is
    /// the distinction an unconsumed record turning up months later depends on.
    @Test("the invoice is dated from the shoot and falls due fourteen days later")
    func theinvoiceIsDatedFromTheShoot() async throws {
        let container = try Self.store()
        let record = try Self.record()
        try Self.knownClient(in: container, downbeatID: record.client.id)

        _ = try await BookingDrafter(modelContainer: container)
            .draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        let invoice = try #require(try Self.invoices(in: container).first)
        #expect(invoice.invoiceDate?.dayKey == "2026-09-06")
        #expect(invoice.dueDate?.dayKey == "2026-09-20")
    }

    // MARK: doing it once

    /// DOING IT TWICE IS THE FAILURE THIS WHOLE TYPE IS SHAPED AROUND. The queue
    /// is not consumed, so the same record is read again on the next run, and a
    /// second draft for one shoot is an invoice Dan sends twice.
    ///
    /// NOT A UNIQUE CONSTRAINT, and `Invoice.swift` says why in as many words:
    /// there is no `@Attribute(.unique)` anywhere, including on id, because PRD
    /// 42c makes it choose which failure a duplicate becomes rather than prevent
    /// one, and a colliding id destroys the row that was there. The mechanism
    /// this codebase has is a serialized writer, which is what `@ModelActor`
    /// gives, and it is proved by holding two callers at the decision point
    /// rather than by running the thing twice in sequence (L157, L407).
    @Test("two callers racing on one booking produce one invoice, not two")
    func tworacingCallersProduceOneInvoice() async throws {
        let container = try Self.store()
        let record = try Self.record()
        try Self.knownClient(in: container, downbeatID: record.client.id)
        let drafter = BookingDrafter(modelContainer: container)

        async let first = drafter.draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)
        async let second = drafter.draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)
        let outcomes = try await [first, second]

        let drafted = try Self.invoices(in: container).count
        #expect(drafted == 1, "the race drafted \(drafted) invoices")
        #expect(outcomes.filter { if case .drafted = $0 { return true } else { return false } }
                    .count == 1)
        #expect(outcomes.filter { if case .alreadyDrafted = $0 { return true } else { return false } }
                    .count == 1)
    }

    @Test("and running it again later says it was already drafted rather than drafting again")
    func runningItAgainSaysSo() async throws {
        let container = try Self.store()
        let record = try Self.record()
        try Self.knownClient(in: container, downbeatID: record.client.id)
        let drafter = BookingDrafter(modelContainer: container)
        _ = try await drafter.draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        let again = try await drafter.draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        #expect(again == .alreadyDrafted(bookingKey: record.booking.id.uuidString))
        let count = try Self.invoices(in: container).count
        #expect(count == 1)
    }

    /// A RERUN CARRIES A DIFFERENT BOOKING ID, so matching on the key alone
    /// cannot catch it. `HandoffRecord.Booking.isRerunOf`'s own doc comment warns
    /// that dropping it drafts a SECOND invoice for one shoot with nothing
    /// reporting it, and that is the field it is easiest to map past.
    @Test("a rerun of a booking already drafted is recognised by what it reruns")
    func arerunIsRecognised() async throws {
        let container = try Self.store()
        let original = try Self.record()
        try Self.knownClient(in: container, downbeatID: original.client.id)
        let drafter = BookingDrafter(modelContainer: container)
        _ = try await drafter.draft(from: original, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        let rerun = try Self.record(booking: [
            "id": UUID().uuidString,
            "isRerunOf": original.booking.id.uuidString,
        ])
        let outcome = try await drafter.draft(from: rerun, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        #expect(outcome == .alreadyDrafted(bookingKey: original.booking.id.uuidString))
        let count = try Self.invoices(in: container).count
        #expect(count == 1, "the rerun drafted a second invoice for one shoot")
    }

    /// THE POSITIVE CONTROL. Without it, a drafter that refused EVERY record
    /// would pass both cases above (L159).
    @Test("a different booking for the same client is drafted, not mistaken for a rerun")
    func adifferentBookingIsStillDrafted() async throws {
        let container = try Self.store()
        let first = try Self.record()
        try Self.knownClient(in: container, downbeatID: first.client.id)
        let drafter = BookingDrafter(modelContainer: container)
        _ = try await drafter.draft(from: first, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        let second = try Self.record(booking: ["id": UUID().uuidString,
                                               "startDate": "2026-10-04",
                                               "endDate": "2026-10-04"])
        let outcome = try await drafter.draft(from: second, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        guard case .drafted = outcome else {
            Issue.record("a second booking was not drafted: \(outcome)")
            return
        }
        let count = try Self.invoices(in: container).count
        #expect(count == 2)
    }

    // MARK: which client, and every answer to it

    /// THE MEASURED CASE, 2026-09-21. The one record in the live queue names a
    /// client that is in NEITHER Ovation's 31 clients NOR Downbeat's own current
    /// export: it was removed upstream after the booking was committed, which is
    /// exactly what `HandoffRecord.Client` is frozen at commit for. So no match
    /// is not the rare arm here, it is the arm the real record takes, and a
    /// drafter that refused it would leave ovation#42 with nothing to send.
    ///
    /// THE CLIENT IS CREATED THROUGH `ClientImport`, never by a second creator
    /// written here. One creator means the tax status rule, the identifier
    /// stamping and the address ownership cannot be right in one place and
    /// forgotten in the other.
    @Test("a booking for a client Ovation has never seen creates that client, from the frozen record")
    func anunknownClientIsCreated() async throws {
        let container = try Self.store()
        let record = try Self.record(client: ["isTaxExempt": false])

        let outcome = try await BookingDrafter(modelContainer: container)
            .draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        guard case .drafted = outcome else {
            Issue.record("an unknown client was not drafted for: \(outcome)")
            return
        }
        let made = try Self.clients(in: container)
        let client = try #require(made.first)
        #expect(made.count == 1)
        #expect(client.downbeatClientID == record.client.id)
        #expect(client.name == record.client.displayName)
        #expect(client.email == record.client.email)
        #expect(client.taxStatus == .notExempt)
    }

    /// AND AN ABSENT TAX ANSWER IS NEVER READ AS TAXABLE. Downbeat's three states
    /// are three here too: a missing `isTaxExempt` is `neverRecorded`, which is
    /// what the roster pass exists to clear (PRD 5, L257).
    @Test("a record that says nothing about tax leaves the client unanswered")
    func anabsentTaxAnswerStaysUnanswered() async throws {
        let container = try Self.store()
        // The measured record has no `isTaxExempt` key at all.
        let record = try Self.record()

        _ = try await BookingDrafter(modelContainer: container)
            .draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        let status = try Self.clients(in: container).first?.taxStatus
        #expect(status == .neverRecorded)
    }

    /// A NAME ONLY MATCH IS NOT ENOUGH TO LINK, and there is no surface in this
    /// slice for asking, so it waits. A rename or a namesake attaching a shoot to
    /// the wrong client is the failure `linksWithoutAsking` exists to name, and
    /// creating a client beside the one that matched would manufacture the
    /// duplicate identity every later invoice and payment then feeds (ovation#34).
    @Test("a client matched on the name alone is neither linked nor duplicated")
    func anameOnlyMatchWaits() async throws {
        let container = try Self.store()
        let record = try Self.record()
        let context = ModelContext(container)
        // Same display name, no Downbeat identifier, a different address.
        let namesake = Client(name: record.client.displayName, taxStatus: .notExempt)
        namesake.email = "someone@elsewhere.example"
        context.insert(namesake)
        try context.save()

        let outcome = try await BookingDrafter(modelContainer: container)
            .draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        #expect(outcome == .refused(.clientNeedsConfirming(named: record.client.displayName)))
        let leftBehind = try Self.invoices(in: container)
        let clientCount = try Self.clients(in: container).count
        #expect(leftBehind.isEmpty, "a draft was left behind by a refusal")
        #expect(clientCount == 1, "a duplicate client was created")
    }

    /// SEVERAL MATCHES IS ITS OWN REFUSAL, never a pick (L521). A guess here
    /// invoices the wrong customer, and the cost compounds silently through every
    /// later payment and referral credit.
    @Test("two clients carrying the same Downbeat identifier are refused, not chosen between")
    func anambiguousMatchIsRefused() async throws {
        let container = try Self.store()
        let record = try Self.record()
        try Self.knownClient(in: container, downbeatID: record.client.id)
        try Self.knownClient(in: container, downbeatID: record.client.id)

        let outcome = try await BookingDrafter(modelContainer: container)
            .draft(from: record, at: Pricing.standardHourlyRate, on: Self.draftedOn)

        #expect(outcome == .refused(.clientIsAmbiguous(count: 2)))
        let leftBehind = try Self.invoices(in: container)
        #expect(leftBehind.isEmpty)
    }

    /// EVERY REFUSAL SAYS WHAT HAPPENED, so none can reach a screen mute, and the
    /// lookup is total so a case added later cannot take a default that reads as
    /// a deliberate silence (L109, L113).
    @Test("every refusal says what happened", arguments: [
        BookingDraftRefusal.clientIsAmbiguous(count: 2),
        .clientNeedsConfirming(named: "Ashgrove Chamber Players"),
        .ovationCouldNotResolveTheClient,
    ])
    func everyRefusalSaysWhatHappened(refusal: BookingDraftRefusal) {
        #expect(refusal.sentence.count > 20, "\(refusal) says \(refusal.sentence)")
        #expect(refusal.sentence.hasSuffix("."))
    }
}
