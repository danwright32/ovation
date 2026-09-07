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

    static var schema: Schema { Schema(models, version: OvationSchemaV1.versionIdentifier) }

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
    static var versionedSchema: any VersionedSchema.Type { OvationSchemaV1.self }

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
///
/// THE MODEL LIST IS NOT REPEATED HERE. It reads `OvationSchema.models`, which is
/// the one list the registration script already holds to the sources, so a type
/// added to the app cannot be in the store and missing from its version, or the
/// reverse. A second hand maintained list is the defect that guard exists for
/// (L41, L96).
enum OvationSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { OvationSchema.models }
}

/// The plan that carries a store from one version to the next.
///
/// IT HAS ONE STAGE TODAY AND THAT IS THE POINT. A plan naming only version 1 is
/// what makes version 2 a migration rather than a fresh start, and it is here
/// before there is a version 2 for the same reason the version identifier is:
/// afterwards is too late for every store already written.
///
/// WHAT A LATER STAGE MUST NOT DO. A stage added for an additive change can be
/// `.lightweight`, and one for anything else (a renamed property, a changed
/// type, a new required relationship) needs a custom stage that MOVES the data,
/// because SwiftData's lightweight migration does not cover those and does not
/// say so: it opens a store that looks fine and is empty. Measured in
/// `SchemaMigrationTests`, which is the standing re-read of that behaviour on
/// whatever OS is current (L82).
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [OvationSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
