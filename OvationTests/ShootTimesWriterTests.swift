import Foundation
import SwiftData
import Testing

/// ovation#457, PRD 3, 3a, 3c, 51l. Writing the times Dan types onto a shoot.
///
/// THIS IS THE PIECE THAT MAKES A DRAFT SENDABLE. PRD 3a says a booking's times are
/// a placeholder nothing may be priced from, and 3c that a draft carries no duration
/// and cannot be sent until Dan supplies one. He supplies it here, and until this
/// existed nothing in the app could: ovation#42's send waits on it.
///
/// A SCREEN NEVER WRITES, AN ACTOR DOES (PRD 51l, ovation#440). The screen holds what
/// Dan is typing as values and hands each field to this actor as he leaves it, which
/// Dan chose on 2026-09-20 against an explicit Save and against writing every
/// keystroke. So every case here drives the actor from a DIFFERENT context than the
/// one reading the result back, because the defect this whole arrangement exists to
/// prevent is two contexts that do not merge (`SwiftDataBehaviourTests`).
/// ON THE MAIN ACTOR, because `ReviewGate.refusal` is: these cases assert what the
/// SCREEN would say after a write, and the screen is main actor isolated. The
/// writer is an actor of its own and is awaited across that boundary, which is
/// exactly how the app calls it.
@MainActor
struct ShootTimesWriterTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    /// A draft as #461 will make it: a shoot with no times, and its photography
    /// line with no hours, which is what `Invoice.clearTimes(of:)` leaves.
    private static func draft() throws -> (ModelContainer, shoot: PersistentIdentifier,
                                           invoice: PersistentIdentifier) {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        client.email = "booker@example.com"
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: .stamping(noon),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        invoice.dueDate = .stamping(noon.addingTimeInterval(14 * 86_400))
        context.insert(invoice)
        let shoot = Shoot(name: "Autumn Evensong", when: .dayOnly(.stamping(noon)), venue: "St Anne's")
        invoice.add(shoot)
        let line = LineItem.hourly(hours: Hours(whole: 1), at: Money(dollars: 250),
                                   describedAs: "Photography", for: shoot)
        invoice.add(line)
        line.hours = nil
        try context.save()
        return (container, shoot.persistentModelID, invoice.persistentModelID)
    }

    private static func read(_ id: PersistentIdentifier, in container: ModelContainer) throws -> Invoice {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == id })
    }

    // MARK: the times land

    @Test("both times typed make the draft priced, and the gate lets it through")
    func bothTimesMakeTheDraftPriced() async throws {
        let (container, shoot, invoiceID) = try Self.draft()
        let writer = ShootTimesWriter(modelContainer: container)

        try await writer.setStart(ClockTime("19:00"), on: shoot)
        try await writer.setEnd(ClockTime("20:30"), on: shoot)

        let invoice = try Self.read(invoiceID, in: container)
        #expect(invoice.isUnpriced == false, "both times are in and it still reads as unpriced")
        #expect(invoice.total > .zero, "1.5 hours at $250 and the invoice comes to nothing")
        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) == nil,
                "the times were supplied and the draft still cannot be reviewed")
    }

    /// THE ORDINARY STATE OF EVERY DRAFT, which Dan described himself on 2026-09-08:
    /// "I plan to create drafts with no end time (although I can put the start time
    /// in from the creation)". A start with no end is not an error, it is waiting.
    @Test("a start with no end is waiting on the end, not refused as broken")
    func astartAloneIsWaitingOnTheEnd() async throws {
        let (container, shoot, invoiceID) = try Self.draft()

        try await ShootTimesWriter(modelContainer: container).setStart(ClockTime("19:00"), on: shoot)

        let invoice = try Self.read(invoiceID, in: container)
        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) == "Waiting on the time the shoot ended.")
    }

    // MARK: clearing a time

    /// CLEARING A TIME CLEARS THE HOURS BESIDE IT, in the same write, which is Dan's
    /// decision of 2026-09-19 and the reason `Invoice.clearTimes(of:)` exists. A
    /// shoot-linked line whose shoot has no times falls back to its OWN stored
    /// hours, so leaving them would price the invoice from a figure that appears on
    /// no screen (L46, L544).
    @Test("clearing the end time takes the invoice back to waiting, not to a stale price")
    func clearingATimeClearsTheHours() async throws {
        let (container, shoot, invoiceID) = try Self.draft()
        // THE LINE CARRIES STORED HOURS, which is the only fixture that can see this
        // at all. A draft's line has none, so clearing a time has nothing to clear
        // and the case passes whatever the writer does: the first version of this
        // test did exactly that, and was seen to pass with the clearing removed
        // (L159, L1). Stored hours are the QuickBooks import's shape (ovation#68),
        // and they are what a shoot-linked line falls back to once its times are
        // taken away.
        let setUp = ModelContext(container)
        let line = try #require(try setUp.fetch(FetchDescriptor<LineItem>()).first)
        line.hours = Hours(whole: 2)
        try setUp.save()

        let writer = ShootTimesWriter(modelContainer: container)
        try await writer.setStart(ClockTime("19:00"), on: shoot)
        try await writer.setEnd(ClockTime("20:30"), on: shoot)
        // While both times are in, the SHOOT decides the hours, so the stored two
        // are not what it prices from and the invoice is worth 1.5 hours.
        #expect(try Self.read(invoiceID, in: container).isUnpriced == false)

        try await writer.setEnd(nil, on: shoot)

        let invoice = try Self.read(invoiceID, in: container)
        #expect(invoice.lineItems.allSatisfy { $0.hours == nil },
                "a stored figure survived, and the invoice would price from it with no time on screen")
        #expect(invoice.isUnpriced, "the end was cleared and the invoice still prices from somewhere")
    }

    /// AND CLEARING ONE TIME LEAVES THE OTHER, because a start with no end is the
    /// ordinary state of a draft and clearing the end is how Dan gets back to it.
    @Test("clearing the end leaves the start where it was")
    func clearingTheEndLeavesTheStart() async throws {
        let (container, shoot, invoiceID) = try Self.draft()
        let writer = ShootTimesWriter(modelContainer: container)
        try await writer.setStart(ClockTime("19:00"), on: shoot)
        try await writer.setEnd(ClockTime("20:30"), on: shoot)

        try await writer.setEnd(nil, on: shoot)

        let invoice = try Self.read(invoiceID, in: container)
        #expect(invoice.orderedShoots.first?.shotFrom == ClockTime("19:00"))
        #expect(invoice.orderedShoots.first?.shotUntil == nil)
    }

    // MARK: what cannot be written

    /// A SHOOT DELETED SINCE THE SCREEN READ IT IS REFUSED BY NAME, never trapped on.
    /// `ModelContext`'s subscript traps on a row that is gone, and the screen is a
    /// photograph taken at the last write, so the shoot Dan is typing into can have
    /// been removed underneath him (L10).
    @Test("a shoot that is no longer there is refused by name")
    func agoneShootIsRefused() async throws {
        let (container, shoot, invoiceID) = try Self.draft()
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == invoiceID })
        for each in invoice.shoots { context.delete(each) }
        try context.save()

        await #expect(throws: ShootTimesRefusal.noSuchShoot) {
            try await ShootTimesWriter(modelContainer: container).setStart(ClockTime("19:00"), on: shoot)
        }
    }

    /// A SENT INVOICE'S TIMES ARE NOT REWRITTEN, because they priced a document a
    /// client already holds. Changing them would make Ovation's copy disagree with
    /// the client's, which is ovation#46's whole subject: an edit to something sent
    /// is a new version, never an overwrite.
    @Test("the times of an invoice that has been sent are refused rather than rewritten")
    func asentInvoicesTimesAreRefused() async throws {
        let (container, shoot, invoiceID) = try Self.draft()
        let writer = ShootTimesWriter(modelContainer: container)
        try await writer.setStart(ClockTime("19:00"), on: shoot)
        try await writer.setEnd(ClockTime("20:30"), on: shoot)
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == invoiceID })
        invoice.number = 1_123
        invoice.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)
        try context.save()

        await #expect(throws: ShootTimesRefusal.invoiceWasSent) {
            try await writer.setEnd(ClockTime("21:00"), on: shoot)
        }
        #expect(try Self.read(invoiceID, in: container).orderedShoots.first?.shotUntil
                    == ClockTime("20:30"), "the sent invoice's time was changed anyway")
    }
}
