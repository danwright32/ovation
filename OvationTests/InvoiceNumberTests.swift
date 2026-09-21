import Foundation
import SwiftData
import Testing

/// Plan 1.10, ovation#37. One continuous invoice sequence, starting at 1123,
/// with its floor DERIVED from the store rather than asserted.
///
/// WHY DERIVED. The QuickBooks import is a SECOND WRITER of this field, and it
/// writes numbers QuickBooks issued, before the allocator ever issues one. A
/// read modify write over Ovation allocated numbers only cannot see them, so an
/// allocated number can land on an imported one, and the allocator's own tests
/// pass throughout because no fixture contains an imported row (L101). So the
/// fixtures here DO contain them.
struct InvoiceNumberTests {

    private static let day = Date(timeIntervalSince1970: 1_794_531_600)

    private static func store() throws -> ModelContainer {
        try OvationSchema.container(inMemory: true)
    }

    @discardableResult
    private static func invoice(
        _ context: ModelContext, number: Int64? = nil, importKey: String? = nil
    ) -> Invoice {
        let invoice = Invoice(client: nil, kind: .fromABooking, invoiceDate: .stamping(day),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        invoice.number = number
        invoice.importKey = importKey
        context.insert(invoice)
        return invoice
    }

    /// Cancels an invoice through a context that has just READ it, never through
    /// one holding a copy from before the allocator wrote.
    private static func cancel(_ id: UUID, in container: ModelContainer, on day: Date) throws {
        try change(id, in: container) {
            $0.closure = .cancelled(on: .stamping(day), reason: "shoot did not happen")
        }
    }

    /// Changes an invoice through a fresh context, for the same reason as `cancel`.
    private static func change(
        _ id: UUID, in container: ModelContainer, _ edit: (Invoice) -> Void
    ) throws {
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        edit(invoice)
        try context.save()
    }

    /// What the STORE holds for one invoice, read through a fresh context (L225).
    private static func storedNumber(of id: UUID, in container: ModelContainer) throws -> Int64? {
        let reader = ModelContext(container)
        return try #require(try reader.fetch(FetchDescriptor<Invoice>()).first { $0.id == id }).number
    }

    /// Every number the store holds, sorted.
    private static func storedNumbers(in container: ModelContainer) throws -> [Int64] {
        try ModelContext(container).fetch(FetchDescriptor<Invoice>()).compactMap(\.number).sorted()
    }

    // MARK: the floor

    @Test("the first invoice ever issued takes the number the sequence starts at")
    func theFirstOneStartsTheSequence() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let draft = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let number = try await allocator.allocate(to: draft.persistentModelID)

        #expect(number == 1123, "PRD's sequence starts here")
    }

    @Test("the floor comes from the STORE, so an imported number is never reissued")
    func thefloorIsDerivedFromWhatIsStored() async throws {
        // The collision this exists to prevent, and it arrives two milestones
        // early: the import writes QuickBooks numbers before the allocator has
        // issued anything. A constant floor of 1123 would hand out 1123 here.
        let container = try Self.store()
        let context = ModelContext(container)
        Self.invoice(context, number: 1_057, importKey: "qb:2026:1057")
        Self.invoice(context, number: 1_204, importKey: "qb:2026:1204")
        let draft = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let number = try await allocator.allocate(to: draft.persistentModelID)

        #expect(number == 1_205, "above everything in the store, imported rows included")
    }

    @Test("a number BELOW the start of the sequence never lowers the floor")
    func thefloorIsNeverBelowTheStart() async throws {
        // An import can legitimately carry an older, smaller number. It must not
        // pull the sequence back down into numbers a client has already seen.
        let container = try Self.store()
        let context = ModelContext(container)
        Self.invoice(context, number: 42, importKey: "qb:2019:42")
        let draft = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        #expect(try await allocator.allocate(to: draft.persistentModelID) == 1123)
    }

    @Test("the sequence is continuous, and a cancelled invoice KEEPS its number")
    func acancelledInvoiceKeepsItsNumber() async throws {
        // Reissuing a cancelled number would put two different invoices under one
        // number in a client's records and in the accountant's.
        let container = try Self.store()
        let context = ModelContext(container)
        let first = Self.invoice(context)
        let second = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let cancelledNumber = try await allocator.allocate(to: first.persistentModelID)
        // CANCELLED THROUGH A FRESH CONTEXT, and the reason is measured in
        // `SwiftDataBehaviourTests`: a context holding an object from before
        // another context wrote to it still holds the old value, and its next
        // save writes that back over the new one with no error. Reusing `context`
        // here would clobber the number this test is about.
        try Self.cancel(first.id, in: container, on: Self.day)
        let nextNumber = try await allocator.allocate(to: second.persistentModelID)

        #expect(cancelledNumber == 1123)
        #expect(nextNumber == 1124, "the cancelled one kept 1123, so the sequence moved on")
        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Invoice>()).first { $0.id == first.id })
        #expect(read.number == 1123)
    }

    // MARK: what it refuses

    @Test("an invoice that already carries a number is refused rather than renumbered")
    func analreadyNumberedInvoiceIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context, number: 1_500)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        await #expect(throws: InvoiceNumberRefusal.alreadyNumbered(existing: 1_500)) {
            _ = try await allocator.allocate(to: invoice.persistentModelID)
        }
    }

    @Test("an invoice that is not there is refused by name")
    func anabsentInvoiceIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let doomed = Self.invoice(context)
        try context.save()
        let id = doomed.persistentModelID
        context.delete(doomed)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        await #expect(throws: InvoiceNumberRefusal.noSuchInvoice) {
            _ = try await allocator.allocate(to: id)
        }
    }

    // MARK: the OTHER writer, which is the import

    @Test("an import CLAIMS the number QuickBooks issued rather than being allocated one")
    func animportKeepsItsOwnNumber() async throws {
        // An imported invoice keeps its original number, because that number is
        // what the client has, what the accountant has, and what a bank reference
        // points at (ovation#71).
        let container = try Self.store()
        let context = ModelContext(container)
        let imported = Self.invoice(context, importKey: "qb:2026:1057")
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        try await allocator.claim(1_057, for: imported.persistentModelID)

        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Invoice>()).first)
        #expect(read.number == 1_057)
    }

    @Test("an import cannot take a number the allocator already issued")
    func animportCannotTakeAnAllocatedNumber() async throws {
        // The mirror of the derived floor. A rule enforced at one site is not
        // enforced by the system, because every other writer can produce the same
        // state (L280), so BOTH writers go through the same serialized actor.
        let container = try Self.store()
        let context = ModelContext(container)
        let native = Self.invoice(context)
        let imported = Self.invoice(context, importKey: "qb:2026:1123")
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let taken = try await allocator.allocate(to: native.persistentModelID)
        await #expect(throws: InvoiceNumberRefusal.numberAlreadyHeld(number: taken)) {
            try await allocator.claim(taken, for: imported.persistentModelID)
        }

        let reader = ModelContext(container)
        let read = try #require(try reader.fetch(FetchDescriptor<Invoice>())
            .first { $0.importKey != nil })
        #expect(read.number == nil, "the refused claim wrote nothing at all")
    }

    @Test("and the allocator cannot take a number an import already brought in")
    func theallocatorCannotTakeAnImportedNumber() async throws {
        // The same assertion from the other side, in the ORDER that puts the
        // import first, because both orders must be safe and a check that happens
        // to run first is not a guarantee (ovation#71).
        let container = try Self.store()
        let context = ModelContext(container)
        let imported = Self.invoice(context, importKey: "qb:2026:1123")
        let native = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        try await allocator.claim(1_123, for: imported.persistentModelID)
        let allocated = try await allocator.allocate(to: native.persistentModelID)

        #expect(allocated == 1_124, "it went above the imported one rather than onto it")
    }

    @Test("a claim of a number at or below zero is refused, because no invoice carries one")
    func aclaimMustBeARealNumber() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let imported = Self.invoice(context, importKey: "qb:bad")
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        await #expect(throws: InvoiceNumberRefusal.numberIsNotPositive(asked: 0)) {
            try await allocator.claim(0, for: imported.persistentModelID)
        }
    }

    // MARK: the race, held open rather than hoped for

    @Test("two invoices numbered at once cannot take the same number")
    func twoAllocationsCannotCollide() async throws {
        // L157: two callers held at the decision point at once, rather than
        // hoping an interleaving reproduces. There is no unique attribute to fall
        // back on and there deliberately never will be: PRD 42a measured that on
        // this Mac a unique attribute does not REFUSE a duplicate, it destroys the
        // original, silently. So the serialized writer is the whole mechanism, and
        // this is the test that says whether it works.
        let container = try Self.store()
        let context = ModelContext(container)
        let first = Self.invoice(context)
        let second = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let firstID = first.persistentModelID
        let secondID = second.persistentModelID

        let numbers = await withTaskGroup(of: Int64?.self) { group in
            for id in [firstID, secondID] {
                group.addTask {
                    try? await allocator.allocate(to: id)
                }
            }
            var found: [Int64] = []
            for await number in group { if let number { found.append(number) } }
            return found.sorted()
        }

        #expect(numbers == [1123, 1124], "both succeeded, and they are different")
        let reader = ModelContext(container)
        let stored = try reader.fetch(FetchDescriptor<Invoice>()).compactMap(\.number).sorted()
        #expect(stored == [1123, 1124])
    }

    @Test("no two invoices in the store share a number, across import, cancel and reissue")
    func nothingEverShares() async throws {
        // The invariant itself, asserted over the STORE rather than over the
        // allocator's return values, because the question is what is stored (L225).
        let container = try Self.store()
        let context = ModelContext(container)
        Self.invoice(context, number: 1_123, importKey: "qb:2026:1123")
        let a = Self.invoice(context)
        let b = Self.invoice(context)
        let c = Self.invoice(context, importKey: "qb:2026:1500")
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        _ = try await allocator.allocate(to: a.persistentModelID)
        try Self.cancel(a.id, in: container, on: Self.day)
        _ = try await allocator.allocate(to: b.persistentModelID)
        try await allocator.claim(1_500, for: c.persistentModelID)

        let reader = ModelContext(container)
        let numbers = try reader.fetch(FetchDescriptor<Invoice>()).compactMap(\.number)
        #expect(numbers.count == 4)
        #expect(Set(numbers).count == numbers.count, "no two invoices share a number")
    }

    // MARK: giving a number back (ovation#327)
    //
    // PRD 10c: an invoice gets its number when Review is pressed, because the
    // number is printed on the page Dan reviews, and closing the sheet without
    // sending gives it back, so PRD 6's sequence has no hole in it. Clearing the
    // field is only safe while nothing was numbered after it: two reviews closed in
    // the opposite order would return a number from the middle of the sequence. So
    // a number goes back only when it is still the highest one issued, and every
    // other case is a refusal that leaves the store exactly as it was.

    @Test("giving back the highest number leaves no gap: the next invoice takes it")
    func releasingTheHighestNumberReusesIt() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let first = Self.invoice(context)
        let reviewed = Self.invoice(context)
        let next = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        _ = try await allocator.allocate(to: first.persistentModelID)
        let shown = try await allocator.allocate(to: reviewed.persistentModelID)
        try await allocator.release(shown, from: reviewed.persistentModelID)

        #expect(try Self.storedNumber(of: reviewed.id, in: container) == nil,
                "the closed review holds no number")
        #expect(try await allocator.allocate(to: next.persistentModelID) == shown,
                "the number went back into the sequence rather than being skipped")
        #expect(try Self.storedNumbers(in: container) == [1123, 1124])
    }

    @Test("giving back the only number ever issued returns the sequence to its start")
    func releasingTheOnlyNumberReturnsToTheStart() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let reviewed = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        try await allocator.release(try await allocator.allocate(to: reviewed.persistentModelID),
                                    from: reviewed.persistentModelID)

        #expect(try Self.storedNumbers(in: container) == [])
        #expect(try await allocator.allocate(to: reviewed.persistentModelID) == 1123)
    }

    @Test("a number with a higher one issued after it is refused, naming both, and kept")
    func aNumberBelowTheHighestIsKept() async throws {
        // Two reviews opened one after the other and closed in the opposite order.
        // Returning the first would put a hole in the middle of the sequence.
        let container = try Self.store()
        let context = ModelContext(container)
        let opened = Self.invoice(context)
        let openedAfter = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let earlier = try await allocator.allocate(to: opened.persistentModelID)
        let later = try await allocator.allocate(to: openedAfter.persistentModelID)

        await #expect(throws: InvoiceNumberRefusal.notTheHighest(number: earlier, highest: later)) {
            try await allocator.release(earlier, from: opened.persistentModelID)
        }
        #expect(try Self.storedNumber(of: opened.id, in: container) == earlier,
                "the refused release wrote nothing")
    }

    @Test("an imported number above it counts as the highest, whichever writer put it there")
    func anImportedNumberAboveCountsAsTheHighest() async throws {
        // Both writers share one ceiling (L280), so the release reads it too.
        let container = try Self.store()
        let context = ModelContext(container)
        let reviewed = Self.invoice(context)
        let imported = Self.invoice(context, importKey: "qb:2026:1500")
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let shown = try await allocator.allocate(to: reviewed.persistentModelID)
        try await allocator.claim(1_500, for: imported.persistentModelID)

        await #expect(throws: InvoiceNumberRefusal.notTheHighest(number: shown, highest: 1_500)) {
            try await allocator.release(shown, from: reviewed.persistentModelID)
        }
        #expect(try Self.storedNumber(of: reviewed.id, in: container) == shown)
    }

    @Test("a sent invoice's number is refused, because a client may be holding it",
          arguments: [
              SentStatus.sent(route: .ovationSentIt, at: InvoiceNumberTests.day),
              SentStatus.sent(route: .foundInTheMailbox, at: InvoiceNumberTests.day),
          ])
    func aSentInvoiceKeepsItsNumber(status: SentStatus) async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let number = try await allocator.allocate(to: invoice.persistentModelID)
        try Self.change(invoice.id, in: container) { $0.sentStatus = status }

        await #expect(throws: InvoiceNumberRefusal.invoiceWasSent(number: number)) {
            try await allocator.release(number, from: invoice.persistentModelID)
        }
        #expect(try Self.storedNumber(of: invoice.id, in: container) == number)
    }

    @Test("a number whose send could not be determined is refused, because not knowing is not unsent")
    func anUndeterminedSendKeepsItsNumber() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let number = try await allocator.allocate(to: invoice.persistentModelID)
        try Self.change(invoice.id, in: container) { $0.sentStatus = .couldNotDetermine(checkedAt: Self.day) }

        await #expect(throws: InvoiceNumberRefusal.sendCouldNotBeDetermined(number: number)) {
            try await allocator.release(number, from: invoice.persistentModelID)
        }
        #expect(try Self.storedNumber(of: invoice.id, in: container) == number)
    }

    /// ovation#460. THE DEFECT THIS WHOLE CASE EXISTS FOR, and the one the two
    /// above could not cover. While Ovation is handing a message to Gmail the
    /// invoice used to stay `notSent`, which is the ONE arm of this switch that
    /// permits a release. So a timeout, a dropped connection or a quit mid send
    /// let Dan close the sheet, hand the number back, reopen Review and be issued
    /// the same number for an invoice Gmail may already have delivered. Two
    /// different invoices under one number, in a client's records and the
    /// accountant's, which is exactly what PRD 6 exists to prevent.
    @Test("a number whose send is in flight is refused, because the client may already have it")
    func asendInFlightKeepsItsNumber() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let number = try await allocator.allocate(to: invoice.persistentModelID)
        let attempt = SendAttempt(destination: ["client@example.com"], wasRedirected: false,
                                  renderSHA256: "abc", startedAt: Self.day)
        try Self.change(invoice.id, in: container) { $0.sentStatus = .attempting(attempt) }

        await #expect(throws: InvoiceNumberRefusal.sendIsInFlight(number: number)) {
            try await allocator.release(number, from: invoice.persistentModelID)
        }
        #expect(try Self.storedNumber(of: invoice.id, in: container) == number,
                "the number was handed back while a send was in flight")
    }

    /// THE POSITIVE CONTROL. An ordinary unsent draft still gives its number back,
    /// so the three refusals above are not a release that simply never works
    /// (L159).
    @Test("and an ordinary unsent draft still gives its number back")
    func anordinaryDraftStillReleases() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let number = try await allocator.allocate(to: invoice.persistentModelID)
        try await allocator.release(number, from: invoice.persistentModelID)

        #expect(try Self.storedNumber(of: invoice.id, in: container) == nil)
    }

    @Test("an imported invoice's number is refused even when it is the highest")
    func anImportedNumberIsNeverGivenBack() async throws {
        // QuickBooks issued it, and a client and the accountant already have it
        // (ovation#71). Being the highest does not make it Ovation's to return.
        let container = try Self.store()
        let context = ModelContext(container)
        let imported = Self.invoice(context, importKey: "qb:2026:1500")
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        try await allocator.claim(1_500, for: imported.persistentModelID)

        await #expect(throws: InvoiceNumberRefusal.importedNumber(number: 1_500)) {
            try await allocator.release(1_500, from: imported.persistentModelID)
        }
        #expect(try Self.storedNumber(of: imported.id, in: container) == 1_500)
    }

    @Test("a closed invoice's number is refused, because PRD 6 says a cancelled invoice keeps it",
          arguments: [
              InvoiceClosure.cancelled(on: .stamping(InvoiceNumberTests.day), reason: "shoot did not happen"),
              InvoiceClosure.deleted(on: .stamping(InvoiceNumberTests.day), reason: "duplicate booking"),
          ])
    func aClosedInvoiceKeepsItsNumber(closure: InvoiceClosure) async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let number = try await allocator.allocate(to: invoice.persistentModelID)
        try Self.change(invoice.id, in: container) { $0.closure = closure }

        await #expect(throws: InvoiceNumberRefusal.invoiceIsClosed(number: number)) {
            try await allocator.release(number, from: invoice.persistentModelID)
        }
        #expect(try Self.storedNumber(of: invoice.id, in: container) == number)
    }

    @Test("a number the invoice does not hold is refused, naming what it does hold")
    func aStaleNumberIsRefused() async throws {
        // A sheet holding an old idea of the number must not give back a
        // different one. Only the number the invoice actually holds can go back.
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let number = try await allocator.allocate(to: invoice.persistentModelID)

        await #expect(throws: InvoiceNumberRefusal.notTheNumberHeld(asked: 9_999, holds: number)) {
            try await allocator.release(9_999, from: invoice.persistentModelID)
        }
        #expect(try Self.storedNumber(of: invoice.id, in: container) == number)
    }

    @Test("giving a number back twice refuses the second, because it already went back")
    func releasingTwiceRefusesTheSecond() async throws {
        // The close runs twice, or is retried: the second must not succeed quietly
        // and must not touch whatever holds that number by then.
        let container = try Self.store()
        let context = ModelContext(container)
        let invoice = Self.invoice(context)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let number = try await allocator.allocate(to: invoice.persistentModelID)
        try await allocator.release(number, from: invoice.persistentModelID)

        await #expect(throws: InvoiceNumberRefusal.notTheNumberHeld(asked: number, holds: nil)) {
            try await allocator.release(number, from: invoice.persistentModelID)
        }
    }

    @Test("an invoice that is not there is refused by name when giving a number back")
    func releasingFromAnAbsentInvoiceIsRefused() async throws {
        let container = try Self.store()
        let context = ModelContext(container)
        let doomed = Self.invoice(context)
        try context.save()
        let id = doomed.persistentModelID
        context.delete(doomed)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        await #expect(throws: InvoiceNumberRefusal.noSuchInvoice) {
            try await allocator.release(1123, from: id)
        }
    }

    @Test("a give back and a new number at once leave the sequence whole, in either order")
    func releasingAndAllocatingAtOnceLeavesNoGap() async throws {
        // L157: both callers are started together rather than hoping an
        // interleaving reproduces, and the serialized writer decides the order.
        // Either the give back lands first and the new invoice takes that number,
        // or the new number lands first and the give back is refused because it is
        // no longer the highest. Both are whole sequences, and the store is what
        // is asserted (L225). Run several times, since one run shows one order.
        for _ in 0..<20 {
            let container = try Self.store()
            let context = ModelContext(container)
            let reviewed = Self.invoice(context)
            let arriving = Self.invoice(context)
            try context.save()

            let allocator = InvoiceNumberAllocator(modelContainer: container)
            let shown = try await allocator.allocate(to: reviewed.persistentModelID)
            let reviewedID = reviewed.persistentModelID
            let arrivingID = arriving.persistentModelID

            // THE REFUSAL IS READ, NOT MERELY COUNTED. A test that accepts any
            // error accepts one thrown for a reason it is not about, and would
            // pass while the give back was failing for something else entirely
            // (L11, L140).
            // AND AN ERROR OF ANY OTHER KIND KEEPS ITS OWN IDENTITY rather than
            // being reported as one of these refusals, which would be the same
            // fault one level down (L11).
            async let releaseOutcome: Result<Void, any Error> = {
                do {
                    try await allocator.release(shown, from: reviewedID)
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }()
            async let allocated: Int64? = try? await allocator.allocate(to: arrivingID)
            let (outcome, newNumber) = await (releaseOutcome, allocated)

            var refusal: InvoiceNumberRefusal?
            if case .failure(let error) = outcome {
                refusal = try #require(error as? InvoiceNumberRefusal,
                                       "the give back threw something that is not one of its refusals: \(error)")
            }

            let stored = try Self.storedNumbers(in: container)
            #expect(Set(stored).count == stored.count, "no two invoices share a number")
            if refusal == nil {
                #expect(newNumber == shown && stored == [shown], "the new invoice took the number given back")
            } else {
                #expect(refusal == .notTheHighest(number: shown, highest: shown + 1),
                        "refused because the new number was issued first, and for no other reason")
                #expect(newNumber == shown + 1 && stored == [shown, shown + 1],
                        "the give back was refused and the review kept its number")
            }
        }
    }
}
