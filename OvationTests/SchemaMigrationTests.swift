import Foundation
import SQLite3
import SwiftData
import Testing

/// ovation#105. Today's schema has a NAME to migrate from, and a store written by
/// one version opens under the next with its rows intact.
///
/// WHY THE WINDOW MATTERS. Before Dan installs Ovation and puts real invoices in
/// it, a broken migration costs nothing, because the store can be deleted.
/// Afterwards the store holds the only copy of records the backup exists to
/// protect, and PRD 5.30 says Ovation deletes nothing automatically, ever.
///
/// WHY THE FIXTURE IS SHAPED THE WAY IT IS, recorded because the obvious shape is
/// wrong and looked convincing. A first version declared `ProbeV1` and `ProbeV2`
/// as two top level types and opened one store with each. Both reads returned
/// ZERO rows, which read as SwiftData losing data on a purely additive change:
/// an alarming finding, and false. SwiftData derives the entity name from the
/// CLASS name, so those were two unrelated entities and the second open created
/// an empty table beside the first rather than migrating it. The measurement was
/// of the fixture, not of the platform (L52, L48).
///
/// The versions below therefore each carry a model class called `Probe`, nested
/// in its own `VersionedSchema`, which is what makes the second open a MIGRATION
/// of the same entity rather than a different table.
struct SchemaMigrationTests {

    // MARK: the shipped schema has a version

    @Test("the shipped schema declares a version, so there is something to migrate FROM")
    func theSchemaIsVersioned() throws {
        // An unnamed baseline cannot be a migration source. This is why the
        // issue is p1: the name has to be in the store file before that store
        // holds anything, and it cannot be added to one already on disk.
        #expect(OvationSchema.versionedSchema.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test("the version's models are exactly the ones the store holds")
    func theVersionMatchesTheStore() throws {
        // Two lists that must agree, derived from one place rather than
        // maintained beside each other (L41).
        let versioned = Set(OvationSchema.versionedSchema.models.map { String(describing: $0) })
        let shipped = Set(OvationSchema.models.map { String(describing: $0) })
        #expect(versioned == shipped)
    }

    @Test("the shipped plan names the shipped version, so a later one is a migration")
    func thePlanNamesTheVersion() throws {
        let named = OvationMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(named == [Schema.Version(1, 0, 0)])
    }

    // MARK: a store written by one version opens under the next

    @Test("an ADDED optional field carries every existing row and its values forward")
    func anAdditiveChangeCarriesTheData() throws {
        let url = try writeVersionOne()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try ModelContainer(
            for: ProbeSchemaV2.Probe.self,
            migrationPlan: ProbeMigrationPlan.self,
            configurations: ModelConfiguration(schema: Schema(versionedSchema: ProbeSchemaV2.self),
                                               url: url))
        let rows = try ModelContext(container).fetch(FetchDescriptor<ProbeSchemaV2.Probe>())

        // NOT merely that it opened. An empty store opens perfectly, and that is
        // the failure this test exists to catch (L98).
        #expect(rows.count == 1)
        #expect(rows.first?.name == "Ashgrove Chamber Players")
        #expect(rows.first?.amount == 27219)
        // The added field is absent rather than fabricated, which is what makes
        // an optional the safe shape for an additive change.
        #expect(rows.first?.note == nil)
    }

    @Test("dropping a required field keeps the rows and drops only the column")
    func aDroppedFieldKeepsTheRows() throws {
        // MEASURED 2026-09-07, macOS 15.5 (Darwin 25.5.0), with NO migration
        // plan supplied: SwiftData opens the store and the row is still there,
        // carrying its remaining fields. It removes the column, not the record.
        //
        // The case a green suite hides is the opposite one, and it is what this
        // asserts against: if SwiftData took this quietly and EMPTIED the store,
        // it would open what looks like a working app with the invoices gone,
        // and a silent empty store is indistinguishable from a fresh install
        // (L98). PRD 5.30 says Ovation deletes nothing automatically, ever.
        //
        // If this ever flips to a refusal, that is a SAFE direction and the test
        // should be updated to expect the throw. If it ever flips to opening
        // EMPTY, ovation#105's plan must gain a custom stage for every non
        // additive change before that change ships, and this test is where that
        // is discovered rather than a customer's store.
        let url = try writeVersionOne()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try ModelContainer(
            for: ProbeSchemaV3.Probe.self,
            migrationPlan: nil,
            configurations: ModelConfiguration(
                schema: Schema(versionedSchema: ProbeSchemaV3.self), url: url))
        let rows = try ModelContext(container).fetch(FetchDescriptor<ProbeSchemaV3.Probe>())

        #expect(rows.count == 1,
                "it opened and the row is GONE, which is the silent loss this exists to catch")
        #expect(rows.first?.name == "Ashgrove Chamber Players")
    }

    // MARK: fixtures

    /// A store written under version 1, checkpointed so the store file alone
    /// carries the row, and closed before it is reopened.
    // MARK: the DOWNGRADE, which ovation#116 needs measured before anything is built

    @Test("MEASUREMENT: what a store written by a LATER version does when an EARLIER one opens it")
    func adowngradeIsMeasuredRatherThanGuessed() throws {
        // ovation#116. Dan runs a newer build, its migration adds a field, then
        // he launches an older build. What SwiftData does then is what this
        // records. The possibilities are not equally bad: refusing is safe,
        // opening and ignoring the new column is survivable, and migrating
        // BACKWARDS would destroy data only the newer build knows about.
        //
        // Ovation ships as a Debug and a Release build on the same Mac
        // (ovation#103), and a restore from an archive taken by a newer build
        // lands in the same place, so this is not hypothetical.
        let directory = URL.temporaryDirectory
            .appending(path: "ovation-downgrade-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Probe.store")

        // A store written by version TWO, carrying a value only version two has.
        let newer = try ModelContainer(
            for: ProbeSchemaV2.Probe.self, migrationPlan: nil,
            configurations: ModelConfiguration(schema: Schema(versionedSchema: ProbeSchemaV2.self),
                                               url: url))
        let writing = ModelContext(newer)
        let row = ProbeSchemaV2.Probe(name: "Ashgrove Chamber Players", amount: 27219)
        row.note = "only version two knows this"
        writing.insert(row)
        try writing.save()
        #expect(StoreCheckpoint.run(storeURL: url) == .checkpointed)

        // Now the OLDER build opens it, with no plan, exactly as an older build
        // would.
        var opened = false
        var refusal: String?
        do {
            let older = try ModelContainer(
                for: ProbeSchemaV1.Probe.self, migrationPlan: nil,
                configurations: ModelConfiguration(
                    schema: Schema(versionedSchema: ProbeSchemaV1.self), url: url))
            opened = true
            let reading = ModelContext(older)
            let rows = try reading.fetch(FetchDescriptor<ProbeSchemaV1.Probe>())
            #expect(rows.count == 1, "MEASURED: the older build read the row")
            #expect(rows.first?.amount == 27219, "MEASURED: and the fields it knows about survived")
        } catch {
            refusal = "\(error)"
        }

        // THE FINDING, whichever way it went, recorded as the assertion so a
        // future OS changing it turns this red rather than passing quietly.
        #expect(opened, "MEASURED on macOS 26.5: an older build OPENS a newer store rather than refusing. Refusal would have been the safe answer, so the guard in ovation#116 has to supply it.")
        #expect(refusal == nil)

        // And the question that decides how bad that is: is the newer build's
        // value still there afterwards?
        let backAgain = try ModelContainer(
            for: ProbeSchemaV2.Probe.self, migrationPlan: nil,
            configurations: ModelConfiguration(schema: Schema(versionedSchema: ProbeSchemaV2.self),
                                               url: url))
        let after = try ModelContext(backAgain).fetch(FetchDescriptor<ProbeSchemaV2.Probe>())
        #expect(after.count == 1, "MEASURED: the row itself survived")
        #expect(after.first?.name == "Ashgrove Chamber Players",
                "MEASURED: and the fields BOTH versions know about survived")

        // THE FINDING, AND IT IS THE WORST OF THE THREE THE ISSUE NAMED.
        // Measured 2026-09-08 on macOS 26.5, Swift 6.3.3: the older build did not
        // refuse, and it did not merely ignore the column it does not know about.
        // It MIGRATED THE STORE BACKWARDS and the value is GONE. Reopening under
        // version two returns nil, not the string version two wrote.
        //
        // So the downgrade case destroys data that only the newer build knows
        // about, silently, on a store whose backup was taken before any of it.
        // Nothing in the app can currently tell this is about to happen, which is
        // the whole of ovation#116.
        #expect(after.first?.note == nil,
                Comment(rawValue: "MEASURED: the older build DROPPED the column it does not know "
                    + "about. This is data loss, not a graceful downgrade, and it is why the "
                    + "guard has to refuse before the store is opened."))
    }

    @Test("MEASUREMENT: whether a raw SQLite read can tell WHICH version wrote the store")
    func theversionInTheFileIsMeasured() throws {
        // ovation#116's first question. `StoreSchemaGuard` already reads
        // sqlite_master read only, so if the version is reachable that way the
        // guard can answer; if it is not, the answer has to come from somewhere
        // else, such as a version file Ovation writes beside the store.
        let directory = URL.temporaryDirectory
            .appending(path: "ovation-version-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Probe.store")

        let container = try ModelContainer(
            for: ProbeSchemaV2.Probe.self, migrationPlan: nil,
            configurations: ModelConfiguration(schema: Schema(versionedSchema: ProbeSchemaV2.self),
                                               url: url))
        let context = ModelContext(container)
        context.insert(ProbeSchemaV2.Probe(name: "Ashgrove Chamber Players", amount: 1))
        try context.save()
        #expect(StoreCheckpoint.run(storeURL: url) == .checkpointed)

        let tables = Self.rawTableNames(at: url)
        #expect(tables.contains("Z_METADATA"),
                "MEASURED: Core Data's metadata table is there and a raw read can reach it")

        // WHAT IT DOES NOT CARRY is the finding that matters. Z_METADATA holds
        // Core Data's model version HASHES, not the semantic version Ovation
        // declares. A hash answers "different", never "newer", and ovation#116
        // needs the DIRECTION: a foreign store is a file to move aside, and a
        // newer one means "you are running the wrong build", which is a
        // completely different sentence to read at launch (L11).
        let metadata = Self.rawMetadataText(at: url)
        #expect(metadata != nil, "MEASURED: a raw read can pull the metadata blob out")
        #expect(metadata?.contains("2.0.0") == false,
                Comment(rawValue: "MEASURED: the semantic version Ovation declares is NOT in "
                    + "the file, so the guard cannot answer this question from sqlite_master alone"))
    }

    /// The table names in a store file, read only, the same way
    /// `StoreSchemaGuard` does. Here rather than in production because nothing
    /// in the app needs it: this is a measurement, and adding API for a
    /// measurement is how a test's convenience becomes a shipped surface.
    private static func rawTableNames(at url: URL) -> [String] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { return [] }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT name FROM sqlite_master WHERE type='table';",
                                 -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 0) { names.append(String(cString: raw)) }
        }
        return names
    }

    /// Everything readable out of Z_METADATA, as text, so the measurement can ask
    /// what is and is not in it.
    private static func rawMetadataText(at url: URL) -> String? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { return nil }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT * FROM Z_METADATA;",
                                 -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        var found = ""
        while sqlite3_step(statement) == SQLITE_ROW {
            for column in 0..<sqlite3_column_count(statement) {
                if let raw = sqlite3_column_text(statement, column) {
                    found += String(cString: raw)
                }
                if let blob = sqlite3_column_blob(statement, column) {
                    let size = Int(sqlite3_column_bytes(statement, column))
                    let data = Data(bytes: blob, count: size)
                    found += String(decoding: data, as: UTF8.self)
                }
            }
        }
        return found
    }

    private func writeVersionOne() throws -> URL {
        let directory = URL.temporaryDirectory
            .appending(path: "ovation-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Probe.store")

        let container = try ModelContainer(
            for: ProbeSchemaV1.Probe.self,
            migrationPlan: nil,
            configurations: ModelConfiguration(schema: Schema(versionedSchema: ProbeSchemaV1.self),
                                               url: url))
        let context = ModelContext(container)
        context.insert(ProbeSchemaV1.Probe(name: "Ashgrove Chamber Players", amount: 27219))
        try context.save()

        // The row lives in the write ahead log until this runs, measured in
        // SwiftDataBehaviourTests. Without it the reopen below could read a
        // store file that never held the row, and the test would be measuring
        // the checkpoint rather than the migration.
        #expect(StoreCheckpoint.run(storeURL: url) == .checkpointed)
        return url
    }
}

/// Three versions of ONE entity. Each nests a model class called `Probe`, so all
/// three are the same SwiftData entity and the second open is a migration rather
/// than a new table beside the old one.
enum ProbeSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Probe.self] }

    @Model
    final class Probe {
        var name: String = ""
        var amount: Int = 0
        init(name: String, amount: Int) {
            self.name = name
            self.amount = amount
        }
    }
}

enum ProbeSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Probe.self] }

    @Model
    final class Probe {
        var name: String = ""
        var amount: Int = 0
        /// The additive change: OPTIONAL, so a row written under version 1 has a
        /// legitimate value for it without anybody supplying one.
        var note: String?
        init(name: String, amount: Int) {
            self.name = name
            self.amount = amount
        }
    }
}

enum ProbeSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] { [Probe.self] }

    /// Drops `amount`, which version 1 required. Deliberately opened with NO
    /// migration plan, because the question is what SwiftData does when nobody
    /// has told it how.
    @Model
    final class Probe {
        var name: String = ""
        init(name: String) {
            self.name = name
        }
    }
}

enum ProbeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ProbeSchemaV1.self, ProbeSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: ProbeSchemaV1.self, toVersion: ProbeSchemaV2.self)]
    }
}
