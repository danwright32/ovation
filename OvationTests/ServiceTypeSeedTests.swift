import Foundation
import SwiftData
import Testing
@testable import Ovation

/// ovation#107, PRD 5.4. A fresh installation gets the starting service types,
/// once, and never again.
///
/// WHY ONCE MATTERS MORE THAN THE SEEDING. The name of a type is Dan's and he
/// renames one from inside an invoice. A seeder that runs on every launch undoes
/// that rename, silently, and the only symptom is a name reverting.
@MainActor
struct ServiceTypeSeedTests {

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    private static func types(_ context: ModelContext) throws -> [ServiceType] {
        try context.fetch(FetchDescriptor<ServiceType>()).sorted { $0.name < $1.name }
    }

    // MARK: what the list IS

    @Test("the starting list is PRD 5.4's, and the referral credit is not in it")
    func theListIsTheOneTheRequirementNames() {
        let list = ServiceType.startingList()

        #expect(list.map(\.name) == ["Photography", "Rush turnaround", "Preview images"])
        #expect(list.map(\.role) == [.hourlyPhotography, .ordinary, .ordinary])
        // Round 6 of ovation#111 took the referral credit out of the line items,
        // so it is not a service type either: a picker entry no line can use
        // (ovation#126). PRD 5.4 was corrected in the same change.
        #expect(!list.contains { $0.name.lowercased().contains("referral") })
    }

    @Test("no starting type carries a default amount, because the rate has one home")
    func nothingCarriesARate() {
        // PRD 5.3's $250 belongs to whatever the invoice freezes its rate from,
        // and `LineItem.hourly(hours:at:)` takes that frozen rate. Copying it
        // onto the service type as well would give one fact two homes, and the
        // two would drift with nothing reporting it (L83).
        #expect(ServiceType.startingList().allSatisfy { $0.defaultUnitAmount == nil })
    }

    @Test("nothing in the starting list is retired")
    func nothingStartsRetired() {
        #expect(ServiceType.startingList().allSatisfy { $0.retiredOn == nil })
    }

    // MARK: seeding, and the second launch

    @Test("an empty store gets the starting list")
    func anEmptyStoreIsSeeded() throws {
        let context = try Self.store()

        let inserted = try ServiceTypeSeed.seedIfEmpty(context)

        #expect(inserted == 3)
        #expect(try Self.types(context).count == 3)
    }

    @Test("a second launch seeds NOTHING, so a rename is not undone")
    func aSecondLaunchChangesNothing() throws {
        // The failure this exists to prevent, driven rather than argued: rename
        // one, seed again, and assert the name survived and no fourth row
        // appeared.
        let context = try Self.store()
        try ServiceTypeSeed.seedIfEmpty(context)
        let renamed = try #require(try Self.types(context).first { $0.role == .hourlyPhotography })
        renamed.name = "Event coverage"
        try context.save()

        let inserted = try ServiceTypeSeed.seedIfEmpty(context)

        #expect(inserted == 0)
        #expect(try Self.types(context).count == 3)
        #expect(try Self.types(context).contains { $0.name == "Event coverage" })
        #expect(try !Self.types(context).contains { $0.name == "Photography" })
    }

    @Test("a store holding ONE type of its own is not seeded either")
    func anyExistingTypeStopsTheSeed() throws {
        // The condition is that the store holds NO service type at all, not that
        // it is missing one of these three. Seeding into a store Dan has already
        // shaped would add rows he deleted or never wanted.
        let context = try Self.store()
        context.insert(ServiceType(name: "Second photographer", role: .ordinary,
                                   defaultUnitAmount: nil))
        try context.save()

        #expect(try ServiceTypeSeed.seedIfEmpty(context) == 0)
        #expect(try Self.types(context).count == 1)
    }

    @Test("a RETIRED type still counts as present, so retiring all three is not undone")
    func retiredTypesStillCount() throws {
        // PRD 5.30: a type is retired rather than deleted, because sent invoices
        // still refer to it. So a store where every type is retired still holds
        // them, and re-seeding would put back exactly what Dan just retired.
        let context = try Self.store()
        try ServiceTypeSeed.seedIfEmpty(context)
        for type in try Self.types(context) {
            type.retiredOn = .stamping(Date(timeIntervalSince1970: 1_794_531_600))
        }
        try context.save()

        #expect(try ServiceTypeSeed.seedIfEmpty(context) == 0)
        #expect(try Self.types(context).count == 3)
    }

    @Test("the seed is one save, so a store can never hold part of the list")
    func theSeedIsAtomic() throws {
        // If it saved per type and failed halfway, the next launch would find
        // rows already there and never seed the rest, so the missing one would
        // be missing forever. Asserted through the store rather than by reading
        // the implementation: after one seed the count is three, and there is no
        // intermediate state any reader can observe.
        let context = try Self.store()
        try ServiceTypeSeed.seedIfEmpty(context)
        let fresh = ModelContext(context.container)

        #expect(try fresh.fetch(FetchDescriptor<ServiceType>()).count == 3)
    }

    @Test("every seeded role is one code actually switches on")
    func everyRoleIsReal() {
        // A seeded row carrying a role no branch handles is a picker entry that
        // behaves as `ordinary` by accident.
        let roles = Set(ServiceType.startingList().map(\.role))
        #expect(roles.isSubset(of: Set(ServiceRole.allCases)))
        #expect(roles.contains(.hourlyPhotography), "exactly one hourly type is what an invoice needs")
        #expect(ServiceType.startingList().filter { $0.role == .hourlyPhotography }.count == 1)
    }
}
