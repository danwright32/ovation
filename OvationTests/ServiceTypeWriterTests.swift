import Foundation
import SwiftData
import Testing

/// ovation#457, PRD 5.4. Making a service type from inside an invoice.
///
/// THE ROLE IS CODE'S AND NOT DAN'S, which the design record states as the reason
/// the panel does not ask for it: exactly one type is the hourly photography line
/// and a second would make the invoice's own pricing ambiguous
/// (Ovation/Domain/LineItem.swift). So every type made here is ordinary.
///
/// THE PANEL ASKS ONE OTHER QUESTION, what the type usually charges, and the
/// design record says why it is worth asking: a `ServiceType` genuinely carries
/// it and none of the three seeded ones has one, so it is what makes the second
/// field earn its place.
@MainActor
struct ServiceTypeWriterTests {

    private static func store() throws -> ModelContainer {
        try OvationSchema.container(inMemory: true)
    }

    private static func types(in container: ModelContainer) throws -> [ServiceType] {
        try ModelContext(container).fetch(FetchDescriptor<ServiceType>())
    }

    // MARK: the type lands

    @Test("a new type carries the name it was given, and is ordinary")
    func anewTypeCarriesItsName() async throws {
        let container = try Self.store()

        _ = try await ServiceTypeWriter(modelContainer: container)
            .create(named: "Travel", usualAmount: nil)

        let made = try #require(try Self.types(in: container).first)
        #expect(made.name == "Travel")
        #expect(made.role == .ordinary)
        #expect(made.retiredOn == nil)
    }

    /// A TYPE WITH NO USUAL AMOUNT IS THE ORDINARY CASE, and nil is the truth
    /// rather than a placeholder standing in for one: none of the three seeded
    /// types has an amount either (ServiceTypeSeed.swift, L548).
    @Test("a type with no usual amount records none, rather than nothing")
    func atypeWithNoAmountRecordsNone() async throws {
        let container = try Self.store()

        _ = try await ServiceTypeWriter(modelContainer: container)
            .create(named: "Travel", usualAmount: nil)

        #expect(try Self.types(in: container).first?.defaultUnitAmount == nil)
    }

    /// AND A ZERO IS NOT THE SAME AS NONE. A type that charges nothing and a type
    /// with no usual amount are different things, and the design record names the
    /// consequence of merging them: one of them would prefill every line it is
    /// used on with 0.00, which PRD 5.1b says must never look like a missing
    /// figure.
    @Test("a type that usually charges nothing records a zero, which is not none")
    func azeroUsualAmountIsRecorded() async throws {
        let container = try Self.store()

        _ = try await ServiceTypeWriter(modelContainer: container)
            .create(named: "Comped travel", usualAmount: .zero)

        #expect(try Self.types(in: container).first?.defaultUnitAmount == Money.zero)
    }

    @Test("the identifier it hands back is the type it just made")
    func itHandsBackWhatItMade() async throws {
        let container = try Self.store()

        let made = try await ServiceTypeWriter(modelContainer: container)
            .create(named: "Travel", usualAmount: Money(dollars: 40))

        let found = try #require(try Self.types(in: container)
            .first { $0.persistentModelID == made })
        #expect(found.name == "Travel")
    }

    // MARK: what cannot be written

    /// A NAME IS WHAT A TYPE IS. The panel's create control is drawn inert while
    /// the name is empty, and this refuses it as well, because a screen gating a
    /// write is not the write being guarded (L196).
    @Test("a type with no name is refused, and nothing is written")
    func anamelessTypeIsRefused() async throws {
        let container = try Self.store()

        await #expect(throws: ServiceTypeRefusal.nameIsEmpty) {
            _ = try await ServiceTypeWriter(modelContainer: container)
                .create(named: "   ", usualAmount: nil)
        }
        #expect(try Self.types(in: container).isEmpty)
    }

    /// TWO TYPES WITH ONE NAME ARE ONE VOCABULARY WITH A COLLISION IN IT. The
    /// list offers them by name and the line records the name it was given, so a
    /// second `Travel` is indistinguishable on every surface that shows one
    /// (L131, L185).
    @Test("a name already in use is refused, ignoring case and surrounding space")
    func aduplicateNameIsRefused() async throws {
        let container = try Self.store()
        let writer = ServiceTypeWriter(modelContainer: container)
        _ = try await writer.create(named: "Travel", usualAmount: nil)

        await #expect(throws: ServiceTypeRefusal.nameIsAlreadyUsed) {
            _ = try await writer.create(named: "  travel ", usualAmount: nil)
        }
        #expect(try Self.types(in: container).count == 1)
    }

    /// A RETIRED TYPE STILL HOLDS ITS NAME (PRD 5.30 retires rather than
    /// deletes), so the name is still taken and reusing it would put two types
    /// with one name in the history every report reads.
    @Test("a name held by a retired type is still in use")
    func aretiredTypesNameIsStillTaken() async throws {
        let container = try Self.store()
        let writer = ServiceTypeWriter(modelContainer: container)
        let made = try await writer.create(named: "Travel", usualAmount: nil)
        let context = ModelContext(container)
        let type = try #require(try context.fetch(FetchDescriptor<ServiceType>())
            .first { $0.persistentModelID == made })
        type.retiredOn = BusinessCalendar.day(forKey: "2026-11-01")
        try context.save()

        await #expect(throws: ServiceTypeRefusal.nameIsAlreadyUsed) {
            _ = try await writer.create(named: "Travel", usualAmount: nil)
        }
    }

    /// THE NAME IS STORED AS IT WILL BE READ, trimmed, because a name with
    /// trailing space is a different string everywhere it is compared and the
    /// same word everywhere it is drawn (L185).
    @Test("the name is recorded trimmed, the way every surface will show it")
    func thenameIsRecordedTrimmed() async throws {
        let container = try Self.store()

        _ = try await ServiceTypeWriter(modelContainer: container)
            .create(named: "  Travel  ", usualAmount: nil)

        #expect(try Self.types(in: container).first?.name == "Travel")
    }

    @Test("every refusal carries a sentence, and none of them is empty")
    func everyrefusalSaysSomething() {
        for refusal in ServiceTypeRefusal.allCases {
            #expect(refusal.sentence.isEmpty == false)
            #expect(refusal.sentence.hasSuffix("."))
        }
    }
}
