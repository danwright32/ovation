import Foundation
import SwiftData
import Testing

/// ovation#60, step 1. What SwiftData ACTUALLY does with the three things the
/// domain model is about to be designed around.
///
/// WHY THIS IS A STANDING TEST RATHER THAN A THROWAWAY PROBE. Every answer below
/// is a platform guarantee, not Ovation's own code, and a platform guarantee is
/// only true of the version it was measured on. SwiftData ships with the
/// operating system and changes under a system update with no build and no
/// commit here, so the model's foundations can stop holding with nothing in this
/// repository saying so (L82, L25, L175). These tests are the re-read.
///
/// Each one names what the model does with the answer, so a future failure says
/// which design decision has lost its basis rather than only that a fact changed.
struct SwiftDataBehaviourTests {

    // MARK: the two stores every answer is checked in

    /// Where the container lives. Every question below is asked of BOTH, because
    /// the suite will use in memory containers and the app ships a file backed
    /// one, and a test measuring a store that is not the one that ships measures
    /// nothing (L322, L2).
    enum StoreKind: CustomStringConvertible {
        case inMemory
        case onDisk

        var description: String { self == .inMemory ? "in memory" : "on disk" }
    }

    /// Builds a container for the given models, and hands back a cleanup the
    /// caller runs on every exit path.
    ///
    /// The temporary directory is made per call rather than shared, so two tests
    /// running at once cannot see each other's rows.
    private static func container(
        kind: StoreKind,
        for models: any PersistentModel.Type...
    ) throws -> (container: ModelContainer, cleanUp: () -> Void) {
        let schema = Schema(models.map { $0 })
        switch kind {
        case .inMemory:
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return (try ModelContainer(for: schema, configurations: configuration), {})
        case .onDisk:
            let directory = URL.temporaryDirectory
                .appending(path: "ovation-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(
                schema: schema,
                url: directory.appending(path: "Probe.store")
            )
            return (
                try ModelContainer(for: schema, configurations: configuration),
                { try? FileManager.default.removeItem(at: directory) }
            )
        }
    }

    // MARK: Q1, an enum with associated values

    /// A discount is ONE fact with two forms, dollars or a percentage of the pre
    /// tax subtotal (PRD 5.4a). L544 says a value and the flag describing it are
    /// one discriminated value and never two fields beside each other, because
    /// two fields let a call site read the amount without reading the kind, and
    /// a percentage read as dollars is a different invoice.
    ///
    /// If this fails, `Invoice.discount` cannot be the enum and becomes two
    /// private properties behind one computed accessor, which is weaker.
    enum ProbeDiscount: Codable, Equatable, Hashable {
        case dollars(Int64)
        case percentageBasisPoints(Int64)
    }

    @Model
    final class ProbeDiscounted {
        var label: String
        var discount: ProbeDiscount?
        init(label: String, discount: ProbeDiscount?) {
            self.label = label
            self.discount = discount
        }
    }

    @Test("an enum with associated values round trips, so a discount can be one value",
          arguments: [StoreKind.inMemory, StoreKind.onDisk])
    func associatedValueEnumRoundTrips(kind: StoreKind) throws {
        let (container, cleanUp) = try Self.container(kind: kind, for: ProbeDiscounted.self)
        defer { cleanUp() }
        let context = ModelContext(container)

        context.insert(ProbeDiscounted(label: "flat", discount: .dollars(5_000)))
        context.insert(ProbeDiscounted(label: "share", discount: .percentageBasisPoints(1_000)))
        context.insert(ProbeDiscounted(label: "none", discount: nil))
        try context.save()

        let read = try ModelContext(container)
            .fetch(FetchDescriptor<ProbeDiscounted>(sortBy: [SortDescriptor(\.label)]))
        #expect(read.count == 3, "three rows were saved")
        #expect(read[0].discount == .dollars(5_000), "the dollars case keeps its amount")
        #expect(read[1].discount == nil, "absent stays absent, never a zero")
        #expect(read[2].discount == .percentageBasisPoints(1_000),
                "the percentage case stays distinguishable from the dollars one")
    }

    // MARK: Q2, a colliding surrogate id

    /// PRD 42a recorded, on 2026-08-28, that a colliding `@Attribute(.unique)`
    /// SILENTLY REPLACES the original: the save does not throw and the fetch
    /// returns one row holding the SECOND value.
    ///
    /// The entire "no id is ever derived from an external identifier" rule in
    /// ovation#60 rests on that. The rule is right either way, but its stated
    /// reason is not, if this no longer holds. Measure it rather than inherit it.
    @Model
    final class ProbeIdentified {
        @Attribute(.unique) var id: UUID
        var label: String
        init(id: UUID, label: String) {
            self.id = id
            self.label = label
        }
    }

    @Test("a colliding unique id replaces the row rather than refusing, as PRD 42a measured",
          arguments: [StoreKind.inMemory, StoreKind.onDisk])
    func collidingUniqueIdReplacesSilently(kind: StoreKind) throws {
        let (container, cleanUp) = try Self.container(kind: kind, for: ProbeIdentified.self)
        defer { cleanUp() }
        let context = ModelContext(container)

        let shared = UUID()
        context.insert(ProbeIdentified(id: shared, label: "the original"))
        try context.save()
        context.insert(ProbeIdentified(id: shared, label: "the replacement"))
        try context.save()

        let read = try ModelContext(container).fetch(FetchDescriptor<ProbeIdentified>())
        #expect(read.count == 1, "one row survives a collision, not two")
        #expect(read.first?.label == "the replacement",
                "the survivor holds the SECOND value, so the first is gone with no error")
    }

    /// THE CONTRAST, kept as a standing assertion rather than as something seen
    /// once while probing. Removing `.unique` above changes the outcome from one
    /// surviving row to two, which is what proves the replacement is caused BY
    /// the attribute and not by anything incidental to the save (L1, L70).
    ///
    /// It also names the choice Ovation actually has, since neither outcome is
    /// good: with `.unique` a colliding id DESTROYS the row that was there, and
    /// without it the collision leaves a duplicate. A duplicate is detectable by
    /// the export reconciliation in ovation#63 and recoverable; a destroyed row
    /// is neither (L5).
    @Model
    final class ProbeUnconstrained {
        var id: UUID
        var label: String
        init(id: UUID, label: String) {
            self.id = id
            self.label = label
        }
    }

    @Test("without the unique attribute the same collision leaves TWO rows, not a replacement",
          arguments: [StoreKind.inMemory, StoreKind.onDisk])
    func collisionWithoutUniqueLeavesADuplicate(kind: StoreKind) throws {
        let (container, cleanUp) = try Self.container(kind: kind, for: ProbeUnconstrained.self)
        defer { cleanUp() }
        let context = ModelContext(container)

        let shared = UUID()
        context.insert(ProbeUnconstrained(id: shared, label: "the original"))
        try context.save()
        context.insert(ProbeUnconstrained(id: shared, label: "the second"))
        try context.save()

        let read = try ModelContext(container).fetch(FetchDescriptor<ProbeUnconstrained>())
        #expect(read.count == 2, "both rows survive, so the collision is visible rather than silent")
        #expect(read.contains { $0.label == "the original" },
                "and the row that was there first is still there")
    }


    // MARK: Q5, what a query can actually see

    /// THE QUESTION THAT DECIDES THE SHAPE OF EVERY ENTITY. `BusinessDate` holds
    /// an instant and its stamped day key as ONE value, deliberately, so that no
    /// code path can write one without the other (L544, L384). `Money` and
    /// `Discount` are composite values for the same reason.
    ///
    /// But the export selects rows by day key, the list sorts by date, and the
    /// reconciliation counts rows in a range. If SwiftData stores a composite
    /// value as an opaque blob, none of that can happen in a fetch, and the
    /// alternative is loading the whole store into memory to filter it, which
    /// stops being tolerable at exactly the size the tax record reaches.
    ///
    /// MEASURED 2026-09-07, and the answer decided two things. A predicate CAN
    /// reach inside a composite value, so `BusinessDate` stays one field and the
    /// day key is not duplicated into a column beside it. A predicate CANNOT
    /// compare a stored property against a captured ENUM value: it throws
    /// `unsupportedPredicate` naming the type. So a vocabulary is filtered in
    /// memory over rows a date range has already narrowed, never in the fetch,
    /// and anything that must be filtered in the fetch is a String, a Date, a
    /// number or a Bool.
    @Model
    final class ProbeQueryable {
        var label: String
        var stampedDate: BusinessDate
        var amount: Money
        var kind: InvoiceKind
        /// The same day key as a plain column, so the two can be compared as
        /// query targets rather than argued about.
        var flatDayKey: String
        init(label: String, stampedDate: BusinessDate, amount: Money, kind: InvoiceKind) {
            self.label = label
            self.stampedDate = stampedDate
            self.amount = amount
            self.kind = kind
            self.flatDayKey = stampedDate.dayKey
        }
    }

    private static func queryableRows(in context: ModelContext) throws {
        // 2026-12-31 23:30 America/New_York, the boundary instant the whole
        // export rests on, and one a day either side of it.
        let boundary = Date(timeIntervalSince1970: 1_798_774_200)
        context.insert(ProbeQueryable(
            label: "before", stampedDate: .stamping(boundary.addingTimeInterval(-86_400)),
            amount: Money(dollars: 100), kind: .photography))
        context.insert(ProbeQueryable(
            label: "boundary", stampedDate: .stamping(boundary),
            amount: Money(dollars: 250), kind: .printSale))
        context.insert(ProbeQueryable(
            label: "after", stampedDate: .stamping(boundary.addingTimeInterval(86_400)),
            amount: Money(dollars: 400), kind: .photography))
        try context.save()
    }

    @Test("a composite value round trips whole, both halves intact",
          arguments: [StoreKind.inMemory, StoreKind.onDisk])
    func compositeValuesRoundTrip(kind: StoreKind) throws {
        let (container, cleanUp) = try Self.container(kind: kind, for: ProbeQueryable.self)
        defer { cleanUp() }
        try Self.queryableRows(in: ModelContext(container))

        let read = try ModelContext(container).fetch(
            FetchDescriptor<ProbeQueryable>(sortBy: [SortDescriptor(\.label)]))
        let boundary = try #require(read.first { $0.label == "boundary" })
        #expect(boundary.stampedDate.dayKey == boundary.flatDayKey,
                "the stamped key survives inside the composite value")
        #expect(boundary.stampedDate.agreesWithItsInstant,
                "and so does the instant it was stamped from")
        #expect(boundary.amount == Money(dollars: 250))
        #expect(boundary.kind == .printSale)
    }

    @Test("a plain string column can be filtered in the fetch itself",
          arguments: [StoreKind.inMemory, StoreKind.onDisk])
    func aFlatColumnIsFilterable(kind: StoreKind) throws {
        let (container, cleanUp) = try Self.container(kind: kind, for: ProbeQueryable.self)
        defer { cleanUp() }
        try Self.queryableRows(in: ModelContext(container))

        let lowerBound = "2026-01-01"
        let upperBound = "2026-12-31"
        var descriptor = FetchDescriptor<ProbeQueryable>(
            predicate: #Predicate { $0.flatDayKey >= lowerBound && $0.flatDayKey <= upperBound }
        )
        descriptor.sortBy = [SortDescriptor(\.flatDayKey)]
        let inRange = try ModelContext(container).fetch(descriptor)
        #expect(inRange.map(\.label) == ["before", "boundary"],
                "the range takes the boundary row and leaves the next day out")
    }

    @Test("a predicate CAN reach inside a composite value, so a date and its key stay one field",
          arguments: [StoreKind.inMemory, StoreKind.onDisk])
    func aCompositeValueIsReachableFromAPredicate(kind: StoreKind) throws {
        let (container, cleanUp) = try Self.container(kind: kind, for: ProbeQueryable.self)
        defer { cleanUp() }
        try Self.queryableRows(in: ModelContext(container))

        let lowerBound = "2026-12-31"
        var reachingIn = FetchDescriptor<ProbeQueryable>(
            predicate: #Predicate { $0.stampedDate.dayKey >= lowerBound }
        )
        reachingIn.sortBy = [SortDescriptor(\.flatDayKey)]
        var flat = FetchDescriptor<ProbeQueryable>(
            predicate: #Predicate { $0.flatDayKey >= lowerBound }
        )
        flat.sortBy = [SortDescriptor(\.flatDayKey)]

        let context = ModelContext(container)
        let throughTheComposite = try context.fetch(reachingIn).map(\.label)
        let throughTheColumn = try context.fetch(flat).map(\.label)
        #expect(throughTheColumn == ["boundary", "after"], "the plain column filters correctly")
        #expect(throughTheComposite == throughTheColumn,
                "and reaching into the composite value gives the same answer")
    }

    @Test("a predicate CANNOT compare against a captured enum value either",
          arguments: [StoreKind.inMemory, StoreKind.onDisk])
    func anEnumConstantIsNotUsableInAPredicate(kind: StoreKind) throws {
        let (container, cleanUp) = try Self.container(kind: kind, for: ProbeQueryable.self)
        defer { cleanUp() }
        try Self.queryableRows(in: ModelContext(container))

        let wanted = InvoiceKind.photography
        let descriptor = FetchDescriptor<ProbeQueryable>(predicate: #Predicate { $0.kind == wanted })
        #expect(throws: SwiftDataError.self) {
            _ = try ModelContext(container).fetch(descriptor)
        }
    }

    @Test("what a stored enum CAN still do is sort, round trip, and be filtered in memory",
          arguments: [StoreKind.inMemory, StoreKind.onDisk])
    func aStoredEnumIsStillUsableWithoutAPredicate(kind: StoreKind) throws {
        let (container, cleanUp) = try Self.container(kind: kind, for: ProbeQueryable.self)
        defer { cleanUp() }
        try Self.queryableRows(in: ModelContext(container))

        let all = try ModelContext(container).fetch(
            FetchDescriptor<ProbeQueryable>(sortBy: [SortDescriptor(\.flatDayKey)]))
        #expect(all.filter { $0.kind == .photography }.map(\.label) == ["before", "after"],
                "which is why a kind is filtered over a range the query already narrowed")
    }

    // MARK: Q3, the two delete rules the model needs to be different

    /// An invoice OWNS its shoots and its line items: deleting it takes them.
    /// A payment does not own its allocations that way. Cancelling an invoice
    /// RELEASES its allocations so the money returns to unallocated on the client
    /// (PRD 5.14d), which is a nullify and not a cascade.
    ///
    /// Those are two different rules on relationships that look alike at the call
    /// site, so the difference is measured here rather than assumed.
    @Model
    final class ProbeOwned {
        var label: String
        var owner: ProbeOwner?
        init(label: String) { self.label = label }
    }

    @Model
    final class ProbeReleasable {
        var label: String
        var owner: ProbeOwner?
        init(label: String) { self.label = label }
    }

    @Model
    final class ProbeOwner {
        var label: String
        @Relationship(deleteRule: .cascade, inverse: \ProbeOwned.owner)
        var owned: [ProbeOwned] = []
        @Relationship(deleteRule: .nullify, inverse: \ProbeReleasable.owner)
        var released: [ProbeReleasable] = []
        init(label: String) { self.label = label }
    }

    @Test("cascade takes the children and nullify leaves them standing",
          arguments: [StoreKind.inMemory, StoreKind.onDisk])
    func deleteRulesDifferAsTheModelNeeds(kind: StoreKind) throws {
        let (container, cleanUp) = try Self.container(
            kind: kind, for: ProbeOwner.self, ProbeOwned.self, ProbeReleasable.self
        )
        defer { cleanUp() }
        let context = ModelContext(container)

        let owner = ProbeOwner(label: "the invoice")
        let owned = ProbeOwned(label: "a line item")
        let released = ProbeReleasable(label: "an allocation")
        context.insert(owner)
        context.insert(owned)
        context.insert(released)
        owner.owned = [owned]
        owner.released = [released]
        try context.save()

        context.delete(owner)
        try context.save()

        let reader = ModelContext(container)
        let survivingOwned = try reader.fetch(FetchDescriptor<ProbeOwned>())
        let survivingReleased = try reader.fetch(FetchDescriptor<ProbeReleasable>())
        #expect(survivingOwned.isEmpty, "cascade removed what the owner owned")
        #expect(survivingReleased.count == 1,
                "nullify left the allocation standing, which is what releasing means")
        #expect(survivingReleased.first?.owner == nil,
                "and it no longer points at the row that was deleted")
    }

    // MARK: does the store file alone carry a saved row (ovation#88)

    /// The fact the launch checkpoint is built on, measured rather than assumed.
    ///
    /// A backup copies the store file, and copies the write ahead log beside it
    /// only when one is there. If SwiftData leaves committed pages in that log,
    /// then a store file copied WITHOUT it reconstructs to an older state, and
    /// an archive holding both copies them at two different instants and can be
    /// internally inconsistent. Checkpointing before the backup reads the store
    /// is what removes both hazards, and it is only worth its cost if the log
    /// really does hold pages here (L82: measure the guarantee on the real
    /// target, since SwiftData ships with the OS and changes under it).
    ///
    /// This test asserts nothing about WHICH answer is right. It records what
    /// this OS does, and names what changes if that flips.
    @Test("a saved row, and whether the store file alone carries it")
    func theStoreFileAloneAfterASave() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "ovation-wal-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "Ovation.store")
        let schema = Schema([Client.self])
        let container = try ModelContainer(
            for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
        let context = ModelContext(container)
        context.insert(Client(name: "Ashgrove Chamber Players", taxStatus: .neverRecorded))
        try context.save()

        // Copy the store file ALONE, exactly as a backup would if the log were
        // absent, and read it with a container that has never seen the original.
        let alone = directory.appending(path: "alone.store")
        try FileManager.default.copyItem(at: storeURL, to: alone)

        let log = directory.appending(path: "Ovation.store-wal")
        let logExists = FileManager.default.fileExists(atPath: log.path)
        let logBytes = (try? Data(contentsOf: log).count) ?? 0

        let copiedSchema = Schema([Client.self])
        let copied = try ModelContainer(
            for: copiedSchema,
            configurations: ModelConfiguration(schema: copiedSchema, url: alone))
        let rows = try ModelContext(copied).fetch(FetchDescriptor<Client>())

        // The row is in the original either way. That is the control: without it
        // a fetch of zero from the copy could mean the save never happened.
        #expect(try ModelContext(container).fetch(FetchDescriptor<Client>()).count == 1)

        // What this OS actually does, recorded rather than asserted one way.
        // A log holding the pages is what makes the checkpoint load bearing; a
        // store file that already carries them means the checkpoint protects
        // only against a crash, and ovation#88's reasoning must say so.
        // MEASURED 2026-09-07, macOS 15.5 (Darwin 25.5.0). The log is 57,712
        // bytes and the store file alone holds NOTHING. So on this OS a saved
        // row lives entirely in the write ahead log until something checkpoints.
        //
        // What this decides, which is the reason the test exists: the launch
        // checkpoint in ovation#88 is LOAD BEARING, not an optimisation. A
        // backup that copied Ovation.store without its log would restore an
        // empty database, and BackupPlan cannot require the log, because a
        // checkpointed store legitimately has none. Checkpointing first is what
        // makes the store file self sufficient before it is read.
        //
        // If this ever flips, so that the store file alone carries the row, the
        // checkpoint stops protecting against a missing log and protects only
        // against a crash. Say so in ovation#88 rather than deleting it.
        #expect(logExists, "no write ahead log beside the store at all")
        #expect(logBytes > 0, "the log exists but is empty, which is a different world")
        #expect(rows.isEmpty, "the store file alone now carries the row, which reverses the reasoning above")
    }

    @Test("a second context that has not seen a write CLOBBERS it on its next save")
    func astaleContextOverwritesAnotherContextsWrite() throws {
        // MEASURED, because ovation#37 depends on knowing it. Two contexts over
        // one container do not merge on their own. A context holding an object
        // from before another context wrote to it still holds the OLD value, and
        // its next save writes that old value back over the new one, with no
        // error anywhere.
        //
        // It is recorded here rather than worked around at one call site, because
        // it applies to every field any @ModelActor writes while a screen holds
        // the same row.
        let container = try OvationSchema.container(inMemory: true)
        let screen = ModelContext(container)
        let invoice = Invoice(client: nil, kind: .fromABooking, invoiceDate: nil,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        screen.insert(invoice)
        try screen.save()
        let id = invoice.id

        // Another context writes the number, exactly as the allocator does.
        let writer = ModelContext(container)
        let there = try #require(try writer.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        there.number = 1_123
        try writer.save()

        // The screen, which never saw that, saves something unrelated.
        invoice.noteToClient = "thank you"
        try screen.save()

        let reader = ModelContext(container)
        let after = try #require(try reader.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        #expect(after.number == nil,
                "the stale context wrote its own nil back over 1123, silently")
        #expect(after.noteToClient == "thank you", "and its own edit did land")
    }
}
