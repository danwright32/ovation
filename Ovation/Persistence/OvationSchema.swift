// ovation#60. The one list of what the store holds, and the one way to open it.
//
// EVERY MODEL TYPE IS NAMED HERE. A type missing from this list is simply absent
// from the store: SwiftData does not complain, it just has no table for it, and
// the first symptom is a fetch that returns nothing (L96). `models` is therefore
// checked against the sources by a script rather than maintained by whoever
// remembers, the same way the isolation floor is.
//
// THE LIVE STORE IS NOT REACHED FROM HERE. `StoreLocation.liveStoreURL()` is on
// the isolation floor and already refuses under a disposable launch; this factory
// takes a URL or builds an in memory container, so a test can never open the real
// one by forgetting an argument (L196, L2).
//
// IT DOES NOT RUN THE LAUNCH SEQUENCE. Identify, checkpoint, back up, then open
// is ovation#88, and putting it here would make every test pay for it and would
// hide the ordering inside a factory. This opens a container and nothing else.
import Foundation
import SwiftData

enum OvationSchema {
    /// Everything the store holds.
    static let models: [any PersistentModel.Type] = [
        Client.self,
        Invoice.self,
        Shoot.self,
        LineItem.self,
        ServiceType.self,
        Payment.self,
        PaymentAllocation.self,
        Refund.self,
        Expense.self,
        ReferralLedgerEntry.self,
    ]

    static var schema: Schema { Schema(models, version: OvationSchemaV2.versionIdentifier) }

    /// Today's shape, with a NAME (ovation#105).
    ///
    /// WHY THIS EXISTS BEFORE THERE IS ANYTHING TO MIGRATE TO. A schema with no
    /// version is an unnamed baseline, and an unnamed baseline cannot be a
    /// migration SOURCE: the name has to be in the store file before that store
    /// holds anything, and it cannot be added to one already on disk. The window
    /// closes the first time Dan installs Ovation and puts a real invoice in it,
    /// because from then on the store is the only copy of records the backup
    /// exists to protect and PRD 5.30 says nothing is ever deleted automatically.
    ///
    /// It delegates to `models` rather than repeating the list, so the two
    /// cannot drift into disagreement about what the store holds (L41).
    static var versionedSchema: any VersionedSchema.Type { OvationSchemaV2.self }

    /// A container over a store file, or an in memory one for tests.
    ///
    /// The URL is REQUIRED for an on disk container rather than defaulted,
    /// because a default would be the platform's own path and a caller that
    /// forgot the argument would silently get a store somewhere nobody chose.
    static func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: OvationMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
    }

    static func container(inMemory: Bool) throws -> ModelContainer {
        precondition(inMemory, "an on disk container is opened with container(at:)")
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}

/// Version 1: the shape ovation#60 shipped, named on 2026-09-07 (ovation#105).
/// Superseded by version 2 on 2026-09-19 (ovation#382) and kept as history.
///
/// ITS CLASSES ARE IN `OvationSchemaV1Shape.swift`, frozen, and that file says why
/// all ten are copied rather than only the one that changed.
///
/// V1 WAS WRITTEN TO DISK, and the sentence here used to say it never had been.
/// That was verified on 2026-09-08 and stopped being true when Dan installed the
/// app: measured 2026-09-19, `Ovation.store` under Application Support held 31
/// clients. A file loaded and believed without re-checking is how a stale claim
/// governs a decision (L244), and this one governed whether a field could be
/// added or removed without a version at all. It could, once, which is how
/// ovation#38 added `ReferralLedgerEntry.spentOnInvoiceID` without bumping. It
/// cannot now, and ovation#382 is the first change made under the new rule.
enum OvationSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    /// What version 1 holds, said by version 1 (ovation#134).
    ///
    /// THIS LIST IS NOT `OvationSchema.models` AND MUST NEVER BECOME IT AGAIN.
    /// That list is what the app holds RIGHT NOW. At one version the two are the
    /// same sentence, which is why the delegation read as a saving rather than a
    /// defect; at two versions this one would silently describe the newer one's
    /// models, both versions would be the same shape, and any stage between them
    /// would have nothing to carry. `check-schema-registered.sh` refuses the
    /// delegation by name so it cannot come back as a tidy-up.
    ///
    /// THE TYPES THEMSELVES BELONG TO THIS VERSION, declared in an extension of it
    /// in `OvationSchemaV1Shape.swift`, with a `typealias` in each domain file
    /// pointing the bare name at the version in force.
    ///
    /// THIS USED TO SAY A VERSION 2 COULD DECLARE ITS OWN COPY OF WHATEVER CHANGED
    /// AND NAME THIS VERSION'S TYPES FOR EVERYTHING ELSE, "which is what keeps ten
    /// identical copies from appearing the first time one field moves". MEASURED
    /// FALSE, 2026-09-19, macOS 26.5.1 (ovation#382): reusing an older version's
    /// type for a RELATED entity dies with
    ///
    ///     Fatal error: Failed to cast model V2.Parent for PersistentIdentifier(...)
    ///                  to Parent
    ///
    /// because SwiftData keys an entity by its CLASS NAME, so the reused type's
    /// relationship resolves to the other version's class. Copying BOTH entities
    /// works: the rows carry, the removed column goes, the link survives. Every one
    /// of Ovation's ten models sits in one relationship graph, so a version costs a
    /// copy of all ten. The standing case is in `SchemaMigrationTests`.
    static var models: [any PersistentModel.Type] { [
        Client.self,
        Invoice.self,
        Shoot.self,
        LineItem.self,
        ServiceType.self,
        Payment.self,
        PaymentAllocation.self,
        Refund.self,
        Expense.self,
        ReferralLedgerEntry.self,
    ] }
}

/// Version 2: version 1 without the invoice's own `noteToClient` (ovation#382).
///
/// THE ONE DIFFERENCE IS A REMOVED OPTIONAL FIELD, which is why the stage below
/// can be lightweight. Dan's decision on 2026-09-19: there is no per invoice note,
/// only the standing one ovation#319 put in Settings, and the field was stored and
/// read by nothing while sharing a name with it (L46, L263).
///
/// ITS TYPES ARE THE APP'S OWN, in `Ovation/Domain`, declared in extensions of
/// THIS version with a `typealias` in each file pointing the bare name here. That
/// is what makes "the shape in force" and "version 2" one thing rather than two
/// that can drift, and it is why version 1's copy had to be taken out into a file
/// of its own the day this version existed.
///
/// WHAT THE NEXT VERSION COSTS, said here so it is not rediscovered. Version 3
/// means taking a frozen copy of these ten classes the way
/// `OvationSchemaV1Shape.swift` holds version 1's, because a version cannot reuse
/// another's types for anything it is related to. That is measured rather than
/// assumed; the measurement and its error message are on `OvationSchemaV1.models`.
enum OvationSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    /// What version 2 holds, said by version 2.
    ///
    /// NOT `OvationSchema.models`, for the reason version 1's list records: a
    /// version that delegates describes whatever the app holds right now rather
    /// than what that version held, and `check-schema-registered.sh` refuses the
    /// delegation by name. This one and the app's list DO agree today, because
    /// version 2 is the shape in force, and the guard holds the NEWEST version to
    /// the app for exactly that reason.
    static var models: [any PersistentModel.Type] { [
        Client.self,
        Invoice.self,
        Shoot.self,
        LineItem.self,
        ServiceType.self,
        Payment.self,
        PaymentAllocation.self,
        Refund.self,
        Expense.self,
        ReferralLedgerEntry.self,
    ] }
}

/// The plan that carries a store from one version to the next.
///
/// IT HAS ONE VERSION AND NO STAGES TODAY, AND THAT IS THE POINT. A plan naming
/// only version 1 is what makes version 2 a migration rather than a fresh start,
/// and it is here before there is a version 2 for the same reason the version
/// identifier is: afterwards is too late for every store already written.
///
/// WHAT HOLDS THE TWO LISTS IN STEP is `scripts/check-migration-stages.sh`
/// (ovation#119), run by the push gate. Both lists are correct today and exactly
/// one of them is silently wrong the moment a second version is added, and
/// nothing in the sources can tell, because an empty `stages` is the right value
/// right up until it is not (L65). The check refuses a version with no stage
/// carrying a store into it, and separately refuses a stage naming a pair that
/// is not a step, because those need opposite remedies.
///
/// WHAT A LATER STAGE MUST NOT DO. A stage added for an additive change can be
/// `.lightweight`, and one for anything else (a renamed property, a changed
/// type, a new required relationship) needs a custom stage that MOVES the data,
/// because SwiftData's lightweight migration does not cover those and does not
/// say so: it opens a store that looks fine and is empty. Measured in
/// `SchemaMigrationTests`, which is the standing re-read of that behaviour on
/// whatever OS is current (L82).
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [OvationSchemaV1.self, OvationSchemaV2.self] }

    /// LIGHTWEIGHT, AND THAT IS A MEASUREMENT RATHER THAN A HOPE. The only
    /// difference between the two versions is a REMOVED optional field, and
    /// `SchemaMigrationTests` measures on this OS that dropping a field keeps every
    /// row and removes only the column. A renamed property, a changed type or a new
    /// required relationship would need a custom stage that MOVES the data, because
    /// SwiftData does not refuse those: it opens a store that looks fine and is
    /// empty.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: OvationSchemaV1.self, toVersion: OvationSchemaV2.self)]
    }
}
