import Foundation
import SwiftData
import Testing
@testable import Ovation

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
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        invoice.closure = .cancelled(on: .stamping(day), reason: "shoot did not happen")
        try context.save()
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
}
