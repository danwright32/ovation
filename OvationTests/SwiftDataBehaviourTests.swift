import Foundation
import SwiftData
import Testing
@testable import Ovation

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
}
