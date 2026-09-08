import Foundation
import SwiftData
import Testing
@testable import Ovation

/// Plan 1.12, ovation#38. The one writer of the referral ledger, from both the
/// earning and the spending side.
///
/// AN APPEND ONLY LEDGER PROTECTS THE SUM, NEVER THE WRITER. Re-summing always
/// gives the right answer for the entries that are there, and says nothing about
/// whether an entry should have been there twice. Credit fires when the first
/// invoice is marked paid; paid is itself derived from summed payments; and both
/// edit-and-resend (ovation#46) and cancel-with-refund (ovation#47) can re-cross
/// that transition. So the key is what stops the credit being granted twice, and
/// it is the thing these tests are mostly about.
struct ReferralLedgerWriterTests {

    private static let day = BusinessDate.stamping(Date(timeIntervalSince1970: 1_794_531_600))
    private static let later = BusinessDate.stamping(Date(timeIntervalSince1970: 1_794_618_000))

    private static func store() throws -> ModelContainer {
        try OvationSchema.container(inMemory: true)
    }

    private static func client(_ context: ModelContext, _ name: String) -> Client {
        let client = Client(name: name, taxStatus: .notExempt)
        context.insert(client)
        return client
    }

    private static func balance(_ container: ModelContainer, _ id: UUID) throws -> Hours {
        let context = ModelContext(container)
        return try #require(try context.fetch(FetchDescriptor<Client>())
            .first { $0.id == id }).referralBalance
    }

    // MARK: earning, once

    @Test("a credit is earned against the booking it came from")
    func creditIsEarned() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        try await ledger.earn(Hours(whole: 2), for: client.persistentModelID,
                              fromBooking: "booking-a", on: Self.day)

        #expect(try Self.balance(container, client.id) == Hours(whole: 2))
    }

    @Test("driving the paid transition twice grants the credit ONCE")
    func thesameBookingCannotEarnTwice() async throws {
        // The failure this exists for, driven rather than argued. An invoice
        // paid, edited, resent and paid again re-crosses the transition, and
        // nothing about a ledger's shape prevents the second grant.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        try await ledger.earn(Hours(whole: 2), for: client.persistentModelID,
                              fromBooking: "booking-a", on: Self.day)
        await #expect(throws: ReferralRefusal.alreadyEarnedForBooking(key: "booking-a")) {
            try await ledger.earn(Hours(whole: 2), for: client.persistentModelID,
                                  fromBooking: "booking-a", on: Self.later)
        }

        #expect(try Self.balance(container, client.id) == Hours(whole: 2))
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<ReferralLedgerEntry>()).count == 1)
    }

    @Test("the key is the BOOKING, not the client, so a second referral still earns")
    func adifferentBookingEarnsAgain() async throws {
        // Keyed on the client, a client who referred twice would be paid once,
        // and the loss would be invisible.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        try await ledger.earn(Hours(whole: 2), for: client.persistentModelID,
                              fromBooking: "booking-a", on: Self.day)
        try await ledger.earn(Hours(whole: 1), for: client.persistentModelID,
                              fromBooking: "booking-b", on: Self.later)

        #expect(try Self.balance(container, client.id) == Hours(whole: 3))
    }

    @Test("the key is global, so one booking cannot earn for two different clients")
    func onebookingEarnsForOneClientOnly() async throws {
        // A booking has one referrer. Keyed per client, the same booking key
        // would grant a credit to each of them and the ledger would be right
        // about each client while being wrong about the booking.
        let container = try Self.store()
        let context = ModelContext(container)
        let first = Self.client(context, "Northmoor Ensemble")
        let second = Self.client(context, "Harbour Line Theatre")
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        try await ledger.earn(Hours(whole: 2), for: first.persistentModelID,
                              fromBooking: "booking-a", on: Self.day)
        await #expect(throws: ReferralRefusal.alreadyEarnedForBooking(key: "booking-a")) {
            try await ledger.earn(Hours(whole: 2), for: second.persistentModelID,
                                  fromBooking: "booking-a", on: Self.later)
        }
    }

    @Test("an earning of nothing or less is refused, because it records no decision")
    func anemptyEarningIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        await #expect(throws: ReferralRefusal.hoursAreNotPositive(asked: Hours.zero)) {
            try await ledger.earn(Hours.zero, for: client.persistentModelID,
                                  fromBooking: "booking-a", on: Self.day)
        }
        await #expect(throws: ReferralRefusal.self) {
            try await ledger.earn(Hours(tenths: -10), for: client.persistentModelID,
                                  fromBooking: "booking-b", on: Self.day)
        }
    }

    @Test("an earning with no booking key at all is refused, because nothing could deduplicate it")
    func anunkeyedEarningIsRefused() async throws {
        // A key that can be empty is not a key. Without it the credit is granted
        // again on every retry, and the ledger's shape hides it.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        await #expect(throws: ReferralRefusal.bookingKeyIsEmpty) {
            try await ledger.earn(Hours(whole: 1), for: client.persistentModelID,
                                  fromBooking: "   ", on: Self.day)
        }
    }

    @Test("a client that is not there is refused, rather than the process dying")
    func anabsentClientIsRefused() async throws {
        // Same hazard as ovation#37 measured on the allocators: the identifier
        // subscript hands back an invalidated object for a deleted row and traps
        // on the first property read.
        let container = try Self.store()
        let context = ModelContext(container)
        let doomed = Self.client(context, "Gone")
        try context.save()
        let id = doomed.persistentModelID
        context.delete(doomed)
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        await #expect(throws: ReferralRefusal.noSuchClient) {
            try await ledger.earn(Hours(whole: 1), for: id,
                                  fromBooking: "booking-a", on: Self.day)
        }
    }

    // MARK: spending, which names the invoice it went onto

    @Test("spending is a negative entry naming the invoice it was spent on")
    func spendingNamesItsInvoice() async throws {
        // The ledger entry and the invoice must agree about which credit was
        // used, because the invoice FREEZES what it applied and the ledger is
        // the running record. Without the link neither can be reconciled against
        // the other.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        let invoice = Invoice(client: client, kind: .fromABooking, invoiceDate: nil,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        context.insert(invoice)
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        try await ledger.earn(Hours(whole: 3), for: client.persistentModelID,
                              fromBooking: "booking-a", on: Self.day)
        try await ledger.spend(Hours(whole: 1), for: client.persistentModelID,
                               onInvoice: invoice.id, on: Self.later)

        #expect(try Self.balance(container, client.id) == Hours(whole: 2))
        let reader = ModelContext(container)
        let spent = try #require(try reader.fetch(FetchDescriptor<ReferralLedgerEntry>())
            .first { $0.hours < Hours.zero })
        #expect(spent.hours == Hours(whole: -1))
        #expect(spent.spentOnInvoiceID == invoice.id)
        #expect(spent.earnedFromBookingKey == nil, "a spending entry earns from no booking")
    }

    @Test("spending MORE than the balance is allowed, because PRD 5.8 warns rather than refusing")
    func spendingBeyondTheBalanceIsAllowed() async throws {
        // PRD 5.8: Ovation "warns when a booking is flagged as spending credit
        // the client does not have". A warning, not a refusal, so the ledger must
        // be able to represent it. Refusing here would make the requirement
        // unimplementable and would push the reversal into the database by hand.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        let invoice = Invoice(client: client, kind: .fromABooking, invoiceDate: nil,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        context.insert(invoice)
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        try await ledger.spend(Hours(whole: 2), for: client.persistentModelID,
                               onInvoice: invoice.id, on: Self.day)

        #expect(try Self.balance(container, client.id) == Hours(whole: -2),
                "and the balance says so, which is what a warning can be derived from")
    }

    @Test("the same invoice cannot be charged the same credit twice")
    func spendingOnOneInvoiceIsIdempotentToo() async throws {
        // Editing and resending an invoice re-runs whatever applied its credit,
        // exactly as it re-crosses the paid transition. Without a key here the
        // client is charged their own credit twice.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        let invoice = Invoice(client: client, kind: .fromABooking, invoiceDate: nil,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        context.insert(invoice)
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        try await ledger.earn(Hours(whole: 5), for: client.persistentModelID,
                              fromBooking: "booking-a", on: Self.day)
        try await ledger.spend(Hours(whole: 1), for: client.persistentModelID,
                               onInvoice: invoice.id, on: Self.day)
        await #expect(throws: ReferralRefusal.alreadySpentOnInvoice(id: invoice.id)) {
            try await ledger.spend(Hours(whole: 1), for: client.persistentModelID,
                                   onInvoice: invoice.id, on: Self.later)
        }

        #expect(try Self.balance(container, client.id) == Hours(whole: 4))
    }

    // MARK: withdrawing, which is another entry and never a deletion

    @Test("a credit is withdrawn by appending its reverse, so the history stays readable")
    func awithdrawalIsAnEntry() async throws {
        // The issue asked for this to be settled rather than left. It CAN be
        // withdrawn, and it is an append: a reversal that has no representation
        // gets done by hand in the database eventually, and then the ledger's
        // history is a record of everything except the interesting part.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        try await ledger.earn(Hours(whole: 2), for: client.persistentModelID,
                              fromBooking: "booking-a", on: Self.day)
        try await ledger.withdrawEarning(fromBooking: "booking-a",
                                         because: "the referred shoot was cancelled",
                                         on: Self.later)

        #expect(try Self.balance(container, client.id) == Hours.zero)
        let reader = ModelContext(container)
        let entries = try reader.fetch(FetchDescriptor<ReferralLedgerEntry>())
        #expect(entries.count == 2, "the earning is still there, with its reversal beside it")
        #expect(entries.contains { $0.note?.contains("cancelled") == true })
    }

    @Test("a withdrawal names WHY, because one without a reason cannot be told from a mistake")
    func awithdrawalNeedsItsReason() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        try await ledger.earn(Hours(whole: 2), for: client.persistentModelID,
                              fromBooking: "booking-a", on: Self.day)
        await #expect(throws: ReferralRefusal.reasonIsEmpty) {
            try await ledger.withdrawEarning(fromBooking: "booking-a", because: " ",
                                             on: Self.later)
        }
    }

    @Test("withdrawing an earning that never happened is refused, not silently ignored")
    func withdrawingNothingIsRefused() async throws {
        // A withdrawal that matched nothing reports success and leaves the state
        // nobody created (L100).
        let container = try Self.store()
        _ = ModelContext(container)

        let ledger = ReferralLedger(modelContainer: container)
        await #expect(throws: ReferralRefusal.noEarningForBooking(key: "booking-z")) {
            try await ledger.withdrawEarning(fromBooking: "booking-z", because: "a mistake",
                                             on: Self.day)
        }
    }

    @Test("a withdrawn booking can be earned again, because the reversal is not a deletion")
    func awithdrawnBookingCanEarnAgain() async throws {
        // The earning entry is still there, so the idempotency key is still
        // taken. That is deliberate: re-earning the same booking must be an
        // explicit act rather than something a retry can do.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        try await ledger.earn(Hours(whole: 2), for: client.persistentModelID,
                              fromBooking: "booking-a", on: Self.day)
        try await ledger.withdrawEarning(fromBooking: "booking-a", because: "cancelled",
                                         on: Self.later)

        await #expect(throws: ReferralRefusal.alreadyEarnedForBooking(key: "booking-a")) {
            try await ledger.earn(Hours(whole: 2), for: client.persistentModelID,
                                  fromBooking: "booking-a", on: Self.later)
        }
    }

    // MARK: the race

    @Test("two grants for one booking racing cannot both land")
    func tworacingGrantsCannotBothLand() async throws {
        // L157: held at the decision point at once rather than hoping an
        // interleaving reproduces. There is no unique attribute and there never
        // will be (PRD 42a), so the serialized writer is the whole mechanism.
        let container = try Self.store()
        let context = ModelContext(container)
        let client = Self.client(context, "Northmoor Ensemble")
        try context.save()

        let ledger = ReferralLedger(modelContainer: container)
        let clientID = client.persistentModelID
        let day = Self.day

        let refusals = await withTaskGroup(of: ReferralRefusal?.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        try await ledger.earn(Hours(whole: 2), for: clientID,
                                              fromBooking: "booking-a", on: day)
                        return nil
                    } catch let refusal as ReferralRefusal {
                        return refusal
                    } catch {
                        Issue.record("an earning failed for a reason that is not a refusal")
                        return nil
                    }
                }
            }
            var found: [ReferralRefusal] = []
            for await outcome in group { if let outcome { found.append(outcome) } }
            return found
        }

        #expect(refusals == [.alreadyEarnedForBooking(key: "booking-a")])
        #expect(try Self.balance(container, client.id) == Hours(whole: 2))
    }
}
