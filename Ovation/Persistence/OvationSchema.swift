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

    static var schema: Schema { Schema(models, version: OvationSchemaV6.versionIdentifier) }

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
    static var versionedSchema: any VersionedSchema.Type { OvationSchemaV6.self }

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
/// Superseded by version 3 on 2026-09-19 (ovation#43) and kept as history.
///
/// THE ONE DIFFERENCE FROM VERSION 1 IS A REMOVED OPTIONAL FIELD, which is why
/// its stage is lightweight. Dan's decision on 2026-09-19: there is no per invoice
/// note, only the standing one ovation#319 put in Settings, and the field was
/// stored and read by nothing while sharing a name with it (L46, L263).
///
/// ITS CLASSES ARE IN `OvationSchemaV2Shape.swift`, frozen, moved there the day
/// version 3 existed for the same reason version 1's were.
enum OvationSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    /// What version 2 holds, said by version 2.
    ///
    /// NOT `OvationSchema.models`, for the reason version 1's list records: a
    /// version that delegates describes whatever the app holds right now rather
    /// than what that version held, and `check-schema-registered.sh` refuses the
    /// delegation by name.
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

/// Version 3: version 2 plus the two clock times Dan types after a shoot
/// (ovation#43).
///
/// THE ONE DIFFERENCE IS TWO ADDED OPTIONAL FIELDS on `Shoot`, `shotFrom` and
/// `shotUntil`, which is why the stage below can be lightweight: `SchemaMigrationTests`
/// measures on this OS that an added optional field carries every existing row and
/// its values forward.
///
/// WHY THEY HAD TO BE STORED AT ALL is PRD 3a. Downbeat derives a booking's end
/// from its start and nothing ever goes back to correct it, so 16 of 19 committed
/// bookings say exactly one hour while only 16% of Dan's issued invoices over 2019
/// to 2024 were one hour. The real times are his input on the invoice, and an
/// input that is not stored is not an input.
///
/// `ClockTime` IS NEW IN THIS VERSION and appears on no class in
/// `OvationSchemaV2Shape.swift`, which is what makes the change purely additive.
/// The value types shared by every version are the stated limitation both frozen
/// shapes carry: a change to one of THEM changes what they describe.
///
/// ITS CLASSES ARE IN `OvationSchemaV3Shape.swift`, frozen, moved there the day
/// version 4 existed (ovation#510), for the reason versions 1 and 2 were: a
/// version cannot reuse another's types for anything it is related to. VERSION 3
/// WAS WRITTEN TO DISK by the installed app, so its frozen copy is held to the
/// fingerprint `SchemaFingerprintTests` pinned rather than to anybody's reading.
enum OvationSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    /// What version 3 holds, said by version 3.
    ///
    /// NOT `OvationSchema.models`, for the reason version 1's list records.
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

/// Version 4: version 3 plus the day each invoice was created (ovation#510).
///
/// THE ONE DIFFERENCE IS ONE ADDED OPTIONAL FIELD, `Invoice.createdOn`, which is
/// why the stage below can be lightweight, measured for version 3's own additive
/// change in `SchemaMigrationTests`. An invoice written before it arrives with no
/// creation day, and that is the truth rather than a gap to fill: the day was
/// never recorded, and a date standing in for one nobody recorded is L192.
///
/// WHY IT HAD TO BE STORED is PRD 51d. The invoice's history opens with `Draft
/// created`, and Dan chose on 2026-09-25 to record the day rather than have the
/// history begin at `Sent`.
///
/// ITS CLASSES ARE IN `OvationSchemaV4Shape.swift`, frozen, moved there the day
/// version 5 existed (ovation#185), for the reason every older version's were.
/// VERSION 4 WAS WRITTEN TO DISK by the installed app, so its frozen copy is held
/// to the fingerprint `SchemaFingerprintTests` pinned rather than to anybody's
/// reading.
enum OvationSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    /// What version 4 holds, said by version 4.
    ///
    /// NOT `OvationSchema.models`, for the reason version 1's list records.
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

/// Version 5: version 4 plus the two facts applying held money needs (ovation#185).
///
/// THE ONLY DIFFERENCES ARE TWO ADDED OPTIONAL FIELDS, which is why the stage
/// below can be lightweight, measured for version 3's and version 4's own
/// additive changes in `SchemaMigrationTests`:
///
///   - `PaymentAllocation.source`, where the money on an allocation came from.
///     PRD 14i puts `Remove` on the held money line and on nothing else, so the
///     invoice has to tell held money applied from a payment recorded against
///     it, and an allocation carries no other fact that could say so. A row from
///     before this version has none, and it reads as recorded with its payment,
///     which is measured rather than assumed: before version 5 nothing in the app
///     applied held money, and `PaymentAllocator.record` wrote every allocation.
///   - `Invoice.heldMoneyRemovedOn`, the day Dan pressed `Remove`. PRD 14h has
///     Ovation apply held money by itself, and without this the next pass would
///     put back what he had just taken off, so `Remove` would not be the way out
///     14i says it is.
///
/// ITS CLASSES ARE IN `OvationSchemaV5Shape.swift`, frozen, moved there the day
/// version 6 existed (ovation#482), for the reason every older version's were.
/// VERSION 5 WAS WRITTEN TO DISK by the installed app, so its frozen copy is held
/// to the fingerprint `SchemaFingerprintTests` pinned rather than to anybody's
/// reading.
enum OvationSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    /// What version 5 holds, said by version 5.
    ///
    /// NOT `OvationSchema.models`, for the reason version 1's list records.
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

/// Version 6: version 5 plus the tax status each invoice was SENT under
/// (ovation#482, PRD 51j1).
///
/// THE ONE DIFFERENCE IS ONE ADDED OPTIONAL FIELD, `Invoice.taxStatusWhenSent`.
/// PRD 5a1 has an invoice read its client's status when it is drawn, and PRD 51j1
/// lets Dan correct a status on the client's page, so without this a corrected
/// status would silently re-draw every invoice already sent under the old one.
/// What went out is what it says (Dan, 2026-09-23), so the send records the
/// status it went out under and a sent invoice reads that rather than the client.
///
/// ITS STAGE IS CUSTOM, NOT LIGHTWEIGHT, and that is the part that matters. The
/// column is additive, so a lightweight stage would carry every row, and every
/// invoice already sent would arrive with no status recorded and go on reading
/// the client's: exactly the re-draw this version exists to stop, for every
/// invoice sent before it. So the stage fills the field for each of them, from
/// the client's status at the moment of migration, which IS the status each was
/// sent under: before this version nothing could change a recorded status (the
/// only writer refuses the absence of an answer and the import fills only a
/// status never recorded), and the send gate refuses a client whose status was
/// never recorded, so no invoice went out before its client's answer existed.
///
/// ITS TYPES ARE THE APP'S OWN, in `Ovation/Domain`, declared in extensions of
/// THIS version with a `typealias` in each file pointing the bare name here. That
/// is what makes "the shape in force" and "version 6" one thing rather than two
/// that can drift.
///
/// WHAT THE NEXT VERSION COSTS, said here so it is not rediscovered. Version 7
/// means taking a frozen copy of these ten classes the way the five shape files
/// hold versions 1 to 5, because a version cannot reuse another's types for
/// anything it is related to. That is measured rather than assumed; the
/// measurement and its error message are on `OvationSchemaV1.models`.
enum OvationSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    /// What version 6 holds, said by version 6.
    ///
    /// NOT `OvationSchema.models`, for the reason version 1's list records. This
    /// one and the app's list DO agree today, because version 6 is the shape in
    /// force, and `check-schema-registered.sh` holds the NEWEST version to the app
    /// for exactly that reason.
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
    static var schemas: [any VersionedSchema.Type] {
        [OvationSchemaV1.self, OvationSchemaV2.self, OvationSchemaV3.self, OvationSchemaV4.self,
         OvationSchemaV5.self, OvationSchemaV6.self]
    }

    /// THE FIRST FOUR ARE LIGHTWEIGHT, AND THAT IS A MEASUREMENT RATHER THAN A HOPE.
    /// Each carries a removed or an added optional field, and `SchemaMigrationTests`
    /// measures on this OS that both keep every row. THE FIFTH IS CUSTOM (ovation#482)
    /// because its new field has to be FILLED for rows already there, which a
    /// lightweight stage cannot do and would not say it had not done. A renamed
    /// property, a changed type or a new required relationship would need a custom
    /// stage that MOVES the data too, because SwiftData does not refuse those: it
    /// opens a store that looks fine and is empty.
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: OvationSchemaV1.self, toVersion: OvationSchemaV2.self),
            .lightweight(fromVersion: OvationSchemaV2.self, toVersion: OvationSchemaV3.self),
            .lightweight(fromVersion: OvationSchemaV3.self, toVersion: OvationSchemaV4.self),
            .lightweight(fromVersion: OvationSchemaV4.self, toVersion: OvationSchemaV5.self),
            // CUSTOM, because a sent invoice must arrive knowing the status it went
            // out under; see `OvationSchemaV6` for why the client's status at the
            // moment of migration is that status. `SchemaMigrationTests` carries a
            // real version 5 store across and reads the field back.
            .custom(fromVersion: OvationSchemaV5.self, toVersion: OvationSchemaV6.self,
                    willMigrate: nil,
                    didMigrate: { context in try SentTaxStatusBackfill.run(in: context) }),
        ]
    }
}

/// ovation#482. Records, on every invoice already sent when version 6 arrives, the
/// tax status it was sent under.
///
/// A NAMED STEP RATHER THAN A CLOSURE BODY, so a test can run it over a store it
/// built and so the rule it applies lives beside the one the send applies:
/// `Invoice.recordSendState(_:)` stamps a send as it happens, and this stamps the
/// sends that happened before anything could.
///
/// IT FILLS ONLY WHAT IS EMPTY AND ONLY WHAT WENT OUT, so running it twice changes
/// nothing the first run did (a migration that crashed part way can be re-run),
/// and a draft is left reading its client, which is what a draft is for.
enum SentTaxStatusBackfill {
    /// Returns how many invoices it stamped, so a caller can say so.
    @discardableResult
    static func run(in context: ModelContext) throws -> Int {
        var stamped = 0
        for invoice in try context.fetch(FetchDescriptor<Invoice>()) {
            if invoice.stampSentTaxStatusIfMissing() { stamped += 1 }
        }
        if stamped > 0 { try context.save() }
        return stamped
    }
}
