import Foundation
import SwiftData
import Testing

/// ovation#60 step 3c, PRD 5.8 and plan 1.12. Referral credit is a SUM over an
/// append only ledger, never a stored balance.
///
/// What EARNS an entry, and the idempotency key that stops the credit being
/// earned twice when a paid transition is re-crossed, is ovation#38. This is the
/// ledger and the one predicate that reads it.
struct ReferralLedgerTests {

    private static let day = Date(timeIntervalSince1970: 1_794_531_600)

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    private static func client(_ context: ModelContext) -> Client {
        let client = Client(name: "A company", taxStatus: .notExempt)
        context.insert(client)
        return client
    }

    @Test("a client who has referred nobody has no credit, and that is a zero rather than a gap")
    func noEntriesIsZero() throws {
        let context = try Self.store()
        #expect(Self.client(context).referralBalance == Hours.zero)
    }

    @Test("the balance is the sum of the ledger, earned and spent together")
    func theBalanceIsTheSumOfTheLedger() throws {
        let context = try Self.store()
        let client = Self.client(context)
        context.insert(ReferralLedgerEntry(client: client, hours: Hours(whole: 3),
                                           occurredOn: .stamping(Self.day),
                                           earnedFromBookingKey: "booking-a", note: nil))
        context.insert(ReferralLedgerEntry(client: client, hours: Hours(whole: 2),
                                           occurredOn: .stamping(Self.day),
                                           earnedFromBookingKey: "booking-b", note: nil))
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Client>()).first)
        #expect(read.referralBalance == Hours(whole: 5))
    }

    @Test("spending credit is a negative entry, so the ledger is append only in both directions")
    func spendingIsANegativeEntry() throws {
        let context = try Self.store()
        let client = Self.client(context)
        context.insert(ReferralLedgerEntry(client: client, hours: Hours(whole: 3),
                                           occurredOn: .stamping(Self.day),
                                           earnedFromBookingKey: "booking-a", note: nil))
        context.insert(ReferralLedgerEntry(client: client, hours: Hours(whole: -1),
                                           occurredOn: .stamping(Self.day),
                                           earnedFromBookingKey: nil, note: "Spent on invoice 1130"))
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Client>()).first)
        #expect(read.referralBalance == Hours(whole: 2))
    }

    @Test("credit is measured in HOURS, because that is what is earned and what is spent")
    func creditIsInHours() throws {
        let context = try Self.store()
        let client = Self.client(context)
        context.insert(ReferralLedgerEntry(client: client, hours: Hours(tenths: 25),
                                           occurredOn: .stamping(Self.day),
                                           earnedFromBookingKey: "booking-a", note: nil))
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Client>()).first)
        #expect(read.referralBalance == Hours(tenths: 25),
                "one hour per hour of the referred client's first booking, PRD 5.8")
    }

    @Test("credit and money held on a client are different balances and never add up")
    func creditIsNotMoneyHeld() throws {
        let context = try Self.store()
        let client = Self.client(context)
        context.insert(ReferralLedgerEntry(client: client, hours: Hours(whole: 3),
                                           occurredOn: .stamping(Self.day),
                                           earnedFromBookingKey: "booking-a", note: nil))
        let payment = Payment(client: client, amount: Money(dollars: 200), method: .zelle,
                              receivedOn: .stamping(Self.day))
        context.insert(payment)
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Client>()).first)
        #expect(read.moneyHeld == Money(dollars: 200))
        #expect(read.referralBalance == Hours(whole: 3))
        // PRD 5.14c. They look alike on a client screen, which is exactly why
        // they are two accessors of two types rather than one number.
    }

    @Test("an earned entry names the booking it came from, which is what stops it being earned twice")
    func anEarnedEntryNamesItsBooking() throws {
        let context = try Self.store()
        let client = Self.client(context)
        context.insert(ReferralLedgerEntry(client: client, hours: Hours(whole: 3),
                                           occurredOn: .stamping(Self.day),
                                           earnedFromBookingKey: "booking-a", note: nil))
        try context.save()

        let entries = try context.fetch(FetchDescriptor<ReferralLedgerEntry>())
        #expect(entries.first?.earnedFromBookingKey == "booking-a")
        #expect(entries.count == 1)
    }
}
