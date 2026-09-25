import Foundation
import SQLite3
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
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        screen.insert(invoice)
        try screen.save()
        let id = invoice.id

        // Another context writes the number, exactly as the allocator does.
        let writer = ModelContext(container)
        let there = try #require(try writer.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        there.number = 1_123
        try writer.save()

        // The screen, which never saw that, saves something unrelated.
        //
        // THE UNRELATED FIELD USED TO BE `noteToClient`, which ovation#382 removed
        // from the invoice. The measurement is about a stale CONTEXT and not about
        // any particular field, so it moved to another one rather than going with
        // it: this is the standing evidence for ovation#133, and deleting it would
        // destroy the only record of how that was diagnosed (L277).
        invoice.bookingKey = "booking-1"
        try screen.save()

        let reader = ModelContext(container)
        let after = try #require(try reader.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        #expect(after.number == nil,
                "the stale context wrote its own nil back over 1123, silently")
        #expect(after.bookingKey == "booking-1", "and its own edit did land")
    }

    /// ovation#133, and the measurement that decides which of its three shapes is
    /// even available. The test above records that a stale context clobbers
    /// another's write; this one asks what a screen can DO about it, because
    /// "merge the changes in" was proposed from how Core Data behaved and the
    /// issue says in as many words that it needs measuring on SwiftData before it
    /// is believed (L82, L175).
    ///
    /// Written as a hypothesis and then corrected to what actually happened, which
    /// is the point of a probe: the assertions below are the OBSERVED behaviour on
    /// macOS 26.5.1, not the expected one.
    @Test("what a stale context has to do to see another context's write")
    func astaleContextCanBeMadeToSeeTheWrite() throws {
        let container = try OvationSchema.container(inMemory: true)
        let screen = ModelContext(container)
        let invoice = Invoice(client: nil, kind: .fromABooking, invoiceDate: nil,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        screen.insert(invoice)
        try screen.save()
        let id = invoice.id

        let writer = ModelContext(container)
        let there = try #require(try writer.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        there.number = 1_123
        try writer.save()

        // FIRST QUESTION: does simply fetching again, in the stale context, hand
        // back the new value or the object it is already holding? If a plain
        // re-fetch is enough, shape 1 costs a screen nothing but remembering.
        let refetched = try #require(try screen.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        #expect(refetched.number == OvationSchemaProbe.numberAfterPlainRefetch,
                "a plain re-fetch in the stale context")

        // SECOND QUESTION: does discarding what the context holds and reading
        // again get there? This is the cheapest thing a screen could be told to do
        // before it writes.
        screen.rollback()
        let afterRollback = try #require(try screen.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        #expect(afterRollback.number == OvationSchemaProbe.numberAfterRollback,
                "after rollback and a re-read")

        // THE FACT THE DECISION ACTUALLY TURNS ON. A screen does not write through
        // the result of a fetch it just made; SwiftUI holds the object, and the
        // clobber above happens because the screen writes through a reference it
        // captured earlier. So the question is whether fetching in the context
        // repairs the object the SCREEN is still holding, or only hands back a
        // second, fresh one beside it (L237, L443).
        #expect(refetched === invoice,
                "the fetch hands back the very object the screen is holding")
        #expect(invoice.number == OvationSchemaProbe.numberOnTheHeldObject,
                "read through the reference captured before the other write")

        // AND THE WHOLE POINT: the screen writes through the reference it has held
        // all along, exactly as the clobbering test does, and saves.
        invoice.bookingKey = "booking-1"
        try screen.save()

        let reader = ModelContext(container)
        let after = try #require(try reader.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        #expect(after.number == OvationSchemaProbe.numberSurvivingTheScreensSave,
                "the number after the screen saved its own unrelated edit")
        #expect(after.bookingKey == "booking-1", "and the screen's own edit landed")
    }

    /// ovation#133, the second half. The probe above shows a fetch repairs the
    /// screen's held object. A screen cannot be told to fetch before it writes
    /// unless doing so is SAFE, and the thing that would make it unsafe is losing
    /// what Dan has typed but not yet saved.
    ///
    /// This is the measurement that decides whether the repair can be owned by one
    /// shared component (L621) or has to be a rule each screen remembers.
    @Test("a fetch that repairs the held object does not discard the screen's unsaved edits")
    func afetchKeepsWhatTheScreenHasNotSavedYet() throws {
        let container = try OvationSchema.container(inMemory: true)
        let screen = ModelContext(container)
        let invoice = Invoice(client: nil, kind: .fromABooking, invoiceDate: nil,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        screen.insert(invoice)
        try screen.save()
        let id = invoice.id

        // Dan types something and it is NOT saved yet, which is the ordinary state
        // of a screen he is working in.
        invoice.bookingKey = "typed-but-not-saved"

        // Meanwhile the allocator writes the number from its own context.
        let writer = ModelContext(container)
        let there = try #require(try writer.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        there.number = 1_123
        try writer.save()

        // The screen fetches, which the probe above shows repairs what it holds.
        _ = try screen.fetch(FetchDescriptor<Invoice>())

        #expect(invoice.bookingKey == OvationSchemaProbe.unsavedEditAfterAFetch,
                "what Dan typed survives the fetch")
        // THE ANSWER, AND IT IS THE OPPOSITE OF THE CLEAN CASE ABOVE. A context
        // with pending changes does NOT take the other context's write when it
        // fetches, so the repair that works on a settled screen does nothing on the
        // one state a screen is actually in while Dan is working.
        #expect(invoice.number == OvationSchemaProbe.numberOnADirtyHeldObject,
                "the allocator's write, on an object the screen has already edited")

        try screen.save()
        let reader = ModelContext(container)
        let after = try #require(try reader.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        #expect(after.number == OvationSchemaProbe.numberAfterADirtySave,
                "and the save wrote the stale value back over it")
        #expect(after.bookingKey == OvationSchemaProbe.unsavedEditAfterAFetch,
                "while the screen's own edit landed, so the surface reports success")
    }

    // MARK: Q6, what a Codable enum looks like to a reader that is not SwiftData

    /// ovation#223. THE QUESTION THE BACKUP ORDERING DEPENDS ON.
    ///
    /// `BackupService.verify` enumerates the documents the STORE references
    /// (ovation#104), and the backup runs BEFORE the store is opened, because
    /// opening can migrate and a migration is the moment the only copy of Dan's
    /// invoices is at risk (`StoreLaunchSequence`). So whatever reads those
    /// references cannot have a `ModelContainer`: it has to read the file the way
    /// `StoreSchemaGuard` and `StoreCheckpoint` already do, with raw SQLite.
    ///
    /// Whether that is even possible was unknown. `Expense.receipt` is a Codable
    /// enum with associated values, and nobody had looked at what SwiftData puts
    /// in the column. If it were an opaque encoding, the only route left would be
    /// opening a container before the backup, which weakens the ordering the
    /// backup exists for.
    ///
    /// WHAT THIS OS ACTUALLY DOES, measured 2026-09-11 on macOS (Darwin 25.6.0):
    /// SwiftData does not store the enum as a blob at all. It FLATTENS it into
    /// one column per associated value plus one column per payload free case:
    ///
    ///     Z_PK  Z_ENT  Z_OPT  ZLABEL  ZSHA256  ZRELATIVEPATH  ZNONERECORDED  ZIMPORTEDWITHOUTONE
    ///
    /// A `.file` row carries its two values in `ZSHA256` and `ZRELATIVEPATH` with
    /// both case columns NULL; a `.noneRecorded` row carries the text
    /// `noneRecorded` in `ZNONERECORDED` with the rest NULL. So a reader outside
    /// SwiftData can select the references directly, and `ZRELATIVEPATH IS NOT
    /// NULL` is exactly "this expense has a receipt file".
    ///
    /// THE NAMES COME FROM THE LABELS AND THE CASES, not from the property. The
    /// column is `ZRELATIVEPATH`, not `ZRECEIPT` and not `ZRECEIPTRELATIVEPATH`.
    /// That is what this test pins: renaming an associated value renames a column
    /// that a reader outside SwiftData is selecting by name, with nothing else in
    /// the repository saying so.
    ///
    /// If this ever flips to an opaque encoding, the reader in ovation#224 stops
    /// working and the fallback is to copy the store to a scratch location and
    /// open the COPY read only, which is a mechanism rather than a comment
    /// (L407). Say so there rather than deleting this.
    enum ProbeReceipt: Codable, Equatable, Hashable, Sendable {
        case file(sha256: String, relativePath: String)
        case noneRecorded
        case importedWithoutOne
    }

    @Model
    final class ProbeReceipted {
        var label: String = ""
        var receipt: ProbeReceipt = ProbeReceipt.noneRecorded
        init(label: String, receipt: ProbeReceipt) {
            self.label = label
            self.receipt = receipt
        }
    }

    @Test("a Codable enum is flattened into columns a reader outside SwiftData can select")
    func aCodableEnumIsReadableWithoutSwiftData() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "ovation-column-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "Probe.store")
        let schema = Schema([ProbeReceipted.self])
        let container = try ModelContainer(
            for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
        let context = ModelContext(container)
        context.insert(ProbeReceipted(label: "with a receipt",
                                      receipt: .file(sha256: "abc123",
                                                     relativePath: "ab/abc123.pdf")))
        context.insert(ProbeReceipted(label: "without one", receipt: .noneRecorded))
        try context.save()

        // The rows live in the write ahead log until something checkpoints, which
        // the test above this one measures. The launch sequence checkpoints
        // before the backup for exactly this reason, so the reader under design
        // will always meet a checkpointed file; this does the same.
        var attempts = 0
        while attempts < 200, StoreCheckpoint.run(storeURL: storeURL) != .checkpointed {
            attempts += 1
        }

        let columns = try Self.columnNames(of: "ZPROBERECEIPTED", in: storeURL)
        // NAMED EXACTLY, not merely "contains something". A test satisfied by any
        // column would pass against an opaque blob column too, which is the
        // answer that would rule out the whole route (L140).
        #expect(columns.contains("ZSHA256"))
        #expect(columns.contains("ZRELATIVEPATH"))
        #expect(columns.contains("ZNONERECORDED"))
        #expect(!columns.contains("ZRECEIPT"),
                "the enum is stored under one column after all, so it may be an opaque value")

        let references = try Self.textColumn("ZRELATIVEPATH",
                                             of: "ZPROBERECEIPTED", in: storeURL)
        #expect(references == ["ab/abc123.pdf"])
    }

    // MARK: reading the store file the way something outside SwiftData must

    /// The column names of one table, read with raw SQLite.
    private static func columnNames(of table: String, in storeURL: URL) throws -> [String] {
        try rows("PRAGMA table_info(\(table));", in: storeURL).compactMap { $0.count > 1 ? $0[1] : nil }
    }

    /// One text column of one table, skipping nulls.
    private static func textColumn(_ column: String, of table: String,
                                   in storeURL: URL) throws -> [String] {
        try rows("SELECT \(column) FROM \(table) WHERE \(column) IS NOT NULL;", in: storeURL)
            .compactMap { $0.first }
    }

    private static func rows(_ sql: String, in storeURL: URL) throws -> [[String]] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            throw ProbeFailure.couldNotOpen(storeURL.path)
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            sqlite3_finalize(statement)
            throw ProbeFailure.couldNotRead(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var out: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String] = []
            for index in 0..<sqlite3_column_count(statement) {
                if let text = sqlite3_column_text(statement, index) {
                    row.append(String(cString: text))
                } else {
                    row.append("")
                }
            }
            out.append(row)
        }
        return out
    }

    // MARK: ovation#451, how anything LEARNS that a writer committed

    /// ovation#451. The invoice list is derived state, and derived state has to
    /// re-derive on every input that feeds it (L14). The probes above settle that
    /// a SETTLED context can see another context's write by fetching again, and
    /// that a DIRTY one cannot. Neither says WHEN to fetch.
    ///
    /// WHY THAT IS A PLATFORM QUESTION RATHER THAN A DESIGN ONE. The obvious
    /// answer is that each writer tells the screen after it saves. That is a
    /// behaviour every present and future writer has to opt into, and a behaviour
    /// each call site must opt into cannot be enforced by a scan (L621): the
    /// fifth actor somebody adds is the one that forgets, and the symptom is a
    /// screen quietly showing an old answer, which is the defect ovation#451
    /// already is.
    ///
    /// So the question measured here is whether the PLATFORM says a write
    /// happened, with no opt in available to forget. If it does, the signal is
    /// owned by the one thing every writer necessarily goes through, which is
    /// `save()` itself.
    ///
    /// Written as a hypothesis and corrected to what ran, exactly like the
    /// ovation#133 probes above. The constants live in `ModelSaveNoticeProbe`.
    @Test("a @ModelActor's save announces itself to the rest of the process")
    func amodelActorSaveAnnouncesItself() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let screen = ModelContext(container)
        let invoice = Invoice(client: nil, kind: .fromABooking, invoiceDate: nil,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        screen.insert(invoice)
        try screen.save()
        let id = invoice.persistentModelID

        // EVERY SAVE IN THE PROCESS POSTS THIS, this suite's neighbours included,
        // so what arrives is filtered down to the notification naming THIS
        // invoice rather than taking whichever came first. A probe that took the
        // first would measure whatever else the run happened to be doing (L205).
        //
        // The observer is registered BEFORE the write, because a notification
        // posted before anybody was listening is indistinguishable from one that
        // never fired (L1).
        let seen = SaveNotices(container: container)
        let token = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: nil
        ) { [seen] notice in seen.record(notice) }
        defer { NotificationCenter.default.removeObserver(token) }

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        try await allocator.allocate(to: id)

        let mine = seen.naming(id)
        #expect((mine != nil) == ModelSaveNoticeProbe.actorSaveIsAnnounced,
                "whether the actor's save posted ModelContext.didSave at all")
        let notice = try #require(mine, "no didSave named this invoice")

        #expect(Set(notice.keys) == ModelSaveNoticeProbe.didSaveKeys,
                "the keys the notification carries")
        #expect(notice.updated.contains(id) == ModelSaveNoticeProbe.updatedNamesTheRowWritten,
                "whether the row the actor wrote is named under 'updated'")

        // THE FACT THE DESIGN TURNS ON, and the reason this is not only about the
        // notification firing. A signal that arrives BEFORE the write is readable
        // would have every listener re-read the old value and then sit on it,
        // which is the original defect with a notification bolted on top. So the
        // read was done from a fresh context INSIDE the observer, at the moment
        // of delivery, rather than afterwards where `allocate` has already
        // returned and the answer is true for the wrong reason (L457).
        #expect(notice.numberVisibleAtDelivery == ModelSaveNoticeProbe.numberReadableWhenAnnounced,
                "what a fresh reader saw at the instant the notification arrived")

        // AND WHETHER A LISTENER CAN TELL WHOSE STORE IT WAS. Every save in the
        // process posts on this name, so a listener that cannot scope the notice
        // to its own container re-reads on a neighbour's write. In the app there
        // is one container and it would not show; in a suite running tests beside
        // each other it is every other container in the process (L205, L463).
        #expect(notice.objectIsAContextOfThisContainer
                    == ModelSaveNoticeProbe.noticeNamesTheStoreItCameFrom,
                "whether the notification's object identifies the container that saved")
    }

    /// Collects `ModelContext.didSave` notices, keeping only what a probe may
    /// look at afterwards.
    ///
    /// IT READS THE STORE AT DELIVERY TIME rather than holding the notification,
    /// because the question is what was true THEN.
    private final class SaveNotices: @unchecked Sendable {
        struct Notice {
            let keys: [String]
            let inserted: [PersistentIdentifier]
            let updated: [PersistentIdentifier]
            let deleted: [PersistentIdentifier]
            let numberVisibleAtDelivery: Int64?
            let objectIsAContextOfThisContainer: Bool
        }

        private let mutex = NSLock()
        private var notices: [Notice] = []
        private let container: ModelContainer

        init(container: ModelContainer) { self.container = container }

        func record(_ notification: Notification) {
            let info = notification.userInfo ?? [:]
            func ids(_ key: String) -> [PersistentIdentifier] {
                (info[key] as? [PersistentIdentifier]) ?? []
            }
            let reader = ModelContext(container)
            let visible = (try? reader.fetch(FetchDescriptor<Invoice>()))?
                .compactMap(\.number).max()
            let notice = Notice(
                keys: info.keys.compactMap { $0 as? String }.sorted(),
                inserted: ids("inserted"),
                updated: ids("updated"),
                deleted: ids("deleted"),
                numberVisibleAtDelivery: visible,
                objectIsAContextOfThisContainer:
                    (notification.object as? ModelContext)?.container === container)
            mutex.lock()
            defer { mutex.unlock() }
            notices.append(notice)
        }

        /// The notice naming this row, or nil where none did.
        func naming(_ id: PersistentIdentifier) -> Notice? {
            mutex.lock()
            defer { mutex.unlock() }
            return notices.first {
                $0.inserted.contains(id) || $0.updated.contains(id) || $0.deleted.contains(id)
            }
        }
    }

    enum ProbeFailure: Error {
        case couldNotOpen(String)
        case couldNotRead(String)
    }
}
