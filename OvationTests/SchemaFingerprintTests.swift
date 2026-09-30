import CoreData
import Foundation
import SwiftData
import Testing

/// ovation#502 and ovation#408. Every frozen schema version is held to the
/// FINGERPRINT it actually wrote, so editing one fails here instead of orphaning
/// the stores written under it.
///
/// WHAT CORE DATA ACTUALLY MATCHES ON. A store records
/// `NSStoreModelVersionChecksumKey`, and staged migration finds its starting
/// point by comparing that against each declared version. Nothing else is
/// consulted: not `Ovation.store.version`, which is Ovation's own file, and not
/// the version identifier, which both stores carry as `1.0.0` while matching no
/// declared version at all. So a check that compared COLUMN NAMES could pass
/// while the fingerprint had moved, and the store would still refuse to open
/// (ovation#408's direction says columns; this is the correction to it).
///
/// WHY `SchemaMigrationTests` COULD NOT SEE THIS. Its cases write a store
/// THROUGH the declared version and then migrate that, so the expected value and
/// the actual value come from one declaration and it can only ever prove that
/// declaration is self-consistent, never that it describes what the app really
/// wrote (L70, L58). The V1 expectation below is the fix for exactly that: it is
/// a value read off a store this app wrote on 2026-09-12, before the frozen
/// copies existed, so the two sides are independent.
///
/// THE THREE EXPECTATIONS ARE NOT THE SAME KIND OF CLAIM, and the difference is
/// the whole design:
///
///   V1 is ANCHORED IN REALITY. Both stores on this Mac were written by the app
///   before any version was declared, and they carry the value below. A V1 that
///   does not produce it is wrong about the past, whatever it says.
///
///   V2 and V3 are a RATCHET. No store was ever written by V2, and V3 is current,
///   so there is no independent record to anchor them to. Their values are what
///   today's declaration produces, recorded here so that the NEXT edit to either
///   shape fails this suite and has to become a new version instead of silently
///   orphaning every store written under the old one (ovation#502's cause).
@MainActor
struct SchemaFingerprintTests {

    /// Read off `~/Library/Application Support/Ovation/Ovation.store` and its
    /// Debug sibling on 2026-09-23, from COPIES rather than the originals,
    /// because opening a live SQLite store rewrites its shm file beside it
    /// (L474). Both carried this value and both carried version identifier
    /// `1.0.0`, and the Debug build of the day refused both with "Cannot use
    /// staged migration with an unknown model version".
    ///
    /// IT IS A HASH AND NOT DATA. Nothing about a client, an invoice or an
    /// amount can be recovered from it, which is why this one value may be
    /// committed while the store it came from may not (L222).
    static let whatVersionOneReallyWrote = "18VrvSHivT9QLlcHEYenyvgXEc4DIAXFx6apSWzd19E="

    /// What versions 2 and 3 produce as they stand, recorded 2026-09-23 once
    /// version 1 had been corrected.
    ///
    /// THESE TWO ARE A RATCHET AND NOT A MEASUREMENT OF ANYTHING OUTSIDE THE APP.
    /// No store was ever written by version 2, and version 3 is current, so there
    /// is nothing independent to check them against. Their job is that the NEXT
    /// change to either shape, including a change to a value type they share with
    /// the live app, fails here rather than at somebody's install (ovation#502).
    ///
    /// WHEN ONE OF THESE GOES RED, DO NOT UPDATE THE VALUE. Ask first whether a
    /// store has been written by that version. If one has, the shape may not move
    /// and the change belongs in a NEW version with a stage; if none has, the
    /// value may be re-recorded here with a line saying what moved it.
    static let whatVersionTwoProducesToday = "lBdjBjBJyAoDfI383VeRcTRNQhrmnAEd9Vt/3eCQqe0="
    static let whatVersionThreeProducesToday = "o6KRleIyv+g3DDKPCohI96FEqJdOaWPiwd5MBsIcnSA="

    /// What version 4 produces, recorded when ovation#510 added it. VERSION 3'S
    /// VALUE ABOVE DID NOT MOVE when its classes were frozen into
    /// `OvationSchemaV3Shape.swift`, and that is the proof the frozen copy
    /// describes the stores the installed app already wrote. This one is a ratchet
    /// on the shape in force, as version 3's was until today.
    static let whatVersionFourProducesToday = "IzSpSIdMHOTG3Xa8oJTwkpcGtoI/KXMVvb5WF/th41c="

    /// What version 5 produces, recorded when ovation#185 added it. VERSION 4'S
    /// VALUE ABOVE DID NOT MOVE when its classes were frozen into
    /// `OvationSchemaV4Shape.swift`, and that is the proof the frozen copy
    /// describes the stores the installed app already wrote. This one is a
    /// ratchet on the shape in force, as version 4's was until today.
    static let whatVersionFiveProducesToday = "pKdsAZgnf91VcYiOEK//3yXuwKCNmVMQIqrzKHIO8wI="

    /// What version 6 produces, recorded when ovation#482 added it. VERSION 5'S
    /// VALUE ABOVE DID NOT MOVE when its classes were frozen into
    /// `OvationSchemaV5Shape.swift`, and that is the proof the frozen copy
    /// describes the stores the installed app already wrote. This one is a
    /// ratchet on the shape in force, as version 5's was until today.
    static let whatVersionSixProducesToday = "1sVbABJ8i4/ejBLgfUdmjACyHf0UChPLNrq3fbv8GnA="

    /// What version 7 produces, recorded when ovation#596 added it. VERSION 6'S
    /// VALUE ABOVE DID NOT MOVE when its classes were frozen into
    /// `OvationSchemaV6Shape.swift`, and that is the proof the frozen copy
    /// describes the stores the installed app already wrote. This one is a
    /// ratchet on the shape in force, as version 6's was until today. RE-RECORDED
    /// ONCE BEFORE MERGE, when `SentMessage.subject` was added for Dan's reply subject
    /// decision (2026-09-28): no store had been written by version 7 then.
    static let whatVersionSevenProducesToday = "OBZnj3MxnnLs2FjPs+d6w7EaFMqComq3jYC1y0RkrqE="

    /// What version 8 produces, recorded when ovation#362 added it. VERSION 7'S
    /// VALUE ABOVE DID NOT MOVE when its classes were frozen into
    /// `OvationSchemaV7Shape.swift`, and that is the proof the frozen copy
    /// describes the stores the installed app already wrote. This one is a
    /// ratchet on the shape in force, as version 7's was until today.
    static let whatVersionEightProducesToday = "I/x0AqLqs+4cO+sxza40XnBox3dtBxgUeU0919gnDDI="

    /// SPELLED OUT BECAUSE COCOA DOES NOT EXPORT IT TO SWIFT. `NSPersistentStore`
    /// declares this key in Objective-C only, so a Swift caller has to name the
    /// string. It is asserted against a real store's metadata below rather than
    /// trusted, so a typo here fails rather than reading as an absent value
    /// (L67, L706).
    static let checksumKey = "NSStoreModelVersionChecksumKey"

    /// The fingerprint a store gets when it is written through `version`.
    ///
    /// IT WRITES A REAL STORE RATHER THAN ASKING THE SCHEMA, because the
    /// fingerprint is a property of what LANDS ON DISK and the question here is
    /// what a store written by this version would carry (L3).
    static func fingerprint(of version: any VersionedSchema.Type) throws -> String {
        return try ScratchStore.with("fingerprint") { url in
            // NO MIGRATION PLAN, which `EarlierVersionStore` never passes. The question
            // is what THIS version writes, and a plan would let an older store be
            // carried forward into it, which is a different question and would make
            // the answer depend on what was there. Through `EarlierVersionStore`
            // because an earlier version's container open beside a current one
            // crashes whichever was opened first (ovation#632).
            try EarlierVersionStore.open(version, at: url) { _ in }

            let metadata = try NSPersistentStoreCoordinator
                .metadataForPersistentStore(type: .sqlite, at: url)
            return try #require(metadata[Self.checksumKey] as? String,
                                "a store with no recorded fingerprint cannot be migrated from")
        }
    }

    // MARK: the one anchored outside the declaration

    /// THE ONE THAT MATTERS, and the one this suite exists for. Every other case
    /// here compares the app against itself.
    @Test("version one describes the store this app actually wrote")
    func versiononeDescribesWhatWasWritten() throws {
        #expect(try Self.fingerprint(of: OvationSchemaV1.self)
                == Self.whatVersionOneReallyWrote)
    }

    // MARK: the ratchet on the two with nothing outside to check them against

    @Test("version two still has the shape it was pinned with")
    func versiontwoIsUnmoved() throws {
        #expect(try Self.fingerprint(of: OvationSchemaV2.self)
                == Self.whatVersionTwoProducesToday)
    }

    @Test("version three still has the shape it was pinned with")
    func versionthreeIsUnmoved() throws {
        #expect(try Self.fingerprint(of: OvationSchemaV3.self)
                == Self.whatVersionThreeProducesToday)
    }

    @Test("version four still has the shape it was pinned with")
    func versionfourIsUnmoved() throws {
        // Measured first, so a failure prints the value it found: a `try` inside
        // the comparison is reported as not evaluated, which says nothing.
        let measured = try Self.fingerprint(of: OvationSchemaV4.self)
        #expect(measured == Self.whatVersionFourProducesToday)
    }

    @Test("version five still has the shape it was pinned with")
    func versionfiveIsUnmoved() throws {
        let measured = try Self.fingerprint(of: OvationSchemaV5.self)
        #expect(measured == Self.whatVersionFiveProducesToday)
    }

    @Test("version six still has the shape it was pinned with")
    func versionsixIsUnmoved() throws {
        let measured = try Self.fingerprint(of: OvationSchemaV6.self)
        #expect(measured == Self.whatVersionSixProducesToday)
    }

    @Test("version seven still has the shape it was pinned with")
    func versionsevenIsUnmoved() throws {
        let measured = try Self.fingerprint(of: OvationSchemaV7.self)
        #expect(measured == Self.whatVersionSevenProducesToday)
    }

    @Test("version eight still has the shape it was pinned with")
    func versioneightIsUnmoved() throws {
        let measured = try Self.fingerprint(of: OvationSchemaV8.self)
        #expect(measured == Self.whatVersionEightProducesToday)
    }

    /// THEY ARE ACTUALLY DIFFERENT, which is what makes a stage between them mean
    /// anything. Identical values would satisfy every case above while describing
    /// one shape under several names.
    @Test("the eight versions describe eight different shapes")
    func theeightDiffer() throws {
        let all = [Self.whatVersionOneReallyWrote,
                   Self.whatVersionTwoProducesToday,
                   Self.whatVersionThreeProducesToday,
                   Self.whatVersionFourProducesToday,
                   Self.whatVersionFiveProducesToday,
                   Self.whatVersionSixProducesToday,
                   Self.whatVersionSevenProducesToday,
                   Self.whatVersionEightProducesToday]

        #expect(Set(all).count == all.count)
    }

    // MARK: the guard is real, or it is decoration

    /// SEEN TO FAIL, over a difference of ONE FIELD, because a guard nobody has
    /// watched fail is a guard nobody knows the sensitivity of (L1, L147). It
    /// uses the probe entities rather than Ovation's own, so the case cannot be
    /// satisfied by any accident of the real schema.
    @Test("a version that differs by a single field has a different fingerprint")
    func onefieldMovesTheFingerprint() throws {
        let first = try Self.fingerprint(of: ProbeSchemaV1.self)
        let second = try Self.fingerprint(of: ProbeSchemaV2.self)

        #expect(first != second,
                "if these match, this suite cannot see a shape change at all")
    }

    /// AND THE SAME SHAPE GIVES THE SAME ANSWER, which is the other half: a
    /// fingerprint that moved on every run would fail this suite for ever and
    /// teach everybody to ignore it (L713, L339).
    @Test("the same version written twice fingerprints the same")
    func thesameVersionIsStable() throws {
        #expect(try Self.fingerprint(of: OvationSchemaV8.self)
                == (try Self.fingerprint(of: OvationSchemaV8.self)))
    }
}
