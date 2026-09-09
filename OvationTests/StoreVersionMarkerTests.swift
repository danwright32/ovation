import Foundation
import SwiftData
import Testing

/// ovation#116. The schema version that last opened the store, written beside it
/// so a raw read can answer the question before anything opens anything.
///
/// WHY IT EXISTS, measured in `SchemaMigrationTests` rather than argued: an older
/// build handed a store written by a newer one does not refuse and does not
/// merely ignore the column it does not know about. It migrates the store
/// BACKWARDS and the field only the newer build knew about is gone, with the
/// backup taken before any of it.
struct StoreVersionMarkerTests {

    private struct Scratch {
        let directory: URL
        let store: URL
        init() throws {
            directory = URL.temporaryDirectory
                .appending(path: "ovation-marker-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            store = directory.appending(path: "Ovation.store")
        }
        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: the marker itself

    @Test("a version written is the version read back")
    func aversionRoundTrips() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }

        try StoreVersionMarker.write(Schema.Version(2, 1, 3), besideStoreAt: scratch.store)

        #expect(StoreVersionMarker.read(besideStoreAt: scratch.store)
            == .version(Schema.Version(2, 1, 3)))
    }

    @Test("the marker sits BESIDE the store, so a copy of the folder carries both")
    func themarkerIsBesideTheStore() throws {
        // A restore that separated them would leave a store nobody can date.
        let scratch = try Scratch()
        defer { scratch.cleanUp() }

        let url = StoreVersionMarker.url(besideStoreAt: scratch.store)

        #expect(url.deletingLastPathComponent() == scratch.store.deletingLastPathComponent())
        #expect(url.lastPathComponent == "Ovation.store.version")
    }

    @Test("no marker at all is ABSENT, which is not the same as one that will not parse")
    func absentIsItsOwnAnswer() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }

        #expect(StoreVersionMarker.read(besideStoreAt: scratch.store) == .absent)
    }

    @Test("a marker that will not parse is UNREADABLE, and never read as a zero")
    func abadMarkerIsRefused() throws {
        // A value parsed from storage must never feed a comparison directly
        // (L50). Read as 0.0.0 it would compare older than everything and wave
        // every store through, which is the failure this whole guard exists for,
        // arriving through the guard itself.
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let marker = StoreVersionMarker.url(besideStoreAt: scratch.store)

        for rubbish in ["", "not a version", "2.1", "2.1.3.4", "2.x.3", "-1.0.0"] {
            try Data(rubbish.utf8).write(to: marker)
            let reading = StoreVersionMarker.read(besideStoreAt: scratch.store)
            guard case .unreadable = reading else {
                Issue.record("'\(rubbish)' was read as \(reading) rather than refused")
                continue
            }
        }
    }

    @Test("trailing whitespace and a newline do not make a marker unreadable")
    func awrittenMarkerSurvivesItsOwnNewline() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let marker = StoreVersionMarker.url(besideStoreAt: scratch.store)
        try Data("1.0.0\n\n  ".utf8).write(to: marker)

        #expect(StoreVersionMarker.read(besideStoreAt: scratch.store)
            == .version(Schema.Version(1, 0, 0)))
    }

    // MARK: the verdict the guard reaches

    private func storeCarryingOvationTables(at url: URL) throws {
        let container = try ModelContainer(
            for: Client.self,
            configurations: ModelConfiguration(schema: Schema([Client.self]), url: url))
        let context = ModelContext(container)
        context.insert(Client(name: "Ashgrove Chamber Players", taxStatus: .neverRecorded))
        try context.save()
        #expect(StoreCheckpoint.run(storeURL: url) == .checkpointed)
    }

    private func inspect(_ url: URL, running: Schema.Version) -> StoreSchemaGuard.Verdict {
        StoreSchemaGuard.inspect(
            storeURL: url,
            ownEntityTables: StoreSchemaGuard.entityTableNames(for: Schema([Client.self])),
            runningVersion: running)
    }

    @Test("a store written by a NEWER build is refused, and NOT as a foreign one")
    func anewerStoreIsItsOwnRefusal() throws {
        // The two need opposite remedies. A foreign store is somebody else's
        // file to move aside; a newer one is Dan's own invoices, and moving them
        // aside is the last thing anybody should do (L11).
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try storeCarryingOvationTables(at: scratch.store)
        try StoreVersionMarker.write(Schema.Version(2, 0, 0), besideStoreAt: scratch.store)

        let verdict = inspect(scratch.store, running: Schema.Version(1, 0, 0))

        #expect(verdict == .fromANewerVersion(found: "2.0.0", running: "1.0.0"))
        #expect(!StoreSchemaGuard.mayOpenForWriting(verdict))
    }

    @Test("and the sentence never says to move the file aside, because it is Dan's own data")
    func therefusalSaysWhatToDoInstead() throws {
        let sentence = try #require(StoreSchemaGuard.refusalSentence(
            for: .fromANewerVersion(found: "2.0.0", running: "1.0.0"),
            at: "/tmp/Ovation.store"))

        #expect(sentence.contains("2.0.0") && sentence.contains("1.0.0"))
        #expect(sentence.contains("newer version of Ovation"))
        #expect(!sentence.lowercased().contains("move that file aside"),
                "every other refusal says this, and here it would mean moving the invoices")
        #expect(sentence.contains("Open the newer Ovation"))
    }

    @Test("the SAME version opens, and so does an older store, which is an ordinary upgrade")
    func thesameOrOlderVersionOpens() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try storeCarryingOvationTables(at: scratch.store)

        try StoreVersionMarker.write(Schema.Version(1, 0, 0), besideStoreAt: scratch.store)
        #expect(inspect(scratch.store, running: Schema.Version(1, 0, 0)) == .ovation)

        try StoreVersionMarker.write(Schema.Version(1, 0, 0), besideStoreAt: scratch.store)
        #expect(inspect(scratch.store, running: Schema.Version(2, 0, 0)) == .ovation,
                "an older store under a newer build is the upgrade this app exists to do")
    }

    @Test("a store with NO marker opens, because no build that writes them ever opened it")
    func amarkerlessStoreOpens() throws {
        // A detector keyed on a marker can never see what was written before the
        // marker shipped (L223). Measured 2026-09-08: no store exists on this
        // machine, so that population is empty and stays empty.
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try storeCarryingOvationTables(at: scratch.store)

        #expect(inspect(scratch.store, running: Schema.Version(1, 0, 0)) == .ovation)
    }

    @Test("a DAMAGED marker refuses, because a downgrade cannot be ruled out")
    func adamagedMarkerRefuses() throws {
        // Different from having no marker: something wrote this and it says
        // nothing anybody can read, so the safe answer and the honest one agree.
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try storeCarryingOvationTables(at: scratch.store)
        try Data("who knows".utf8)
            .write(to: StoreVersionMarker.url(besideStoreAt: scratch.store))

        let verdict = inspect(scratch.store, running: Schema.Version(1, 0, 0))

        guard case .versionUnreadable = verdict else {
            Issue.record("a damaged marker gave \(verdict)")
            return
        }
        #expect(!StoreSchemaGuard.mayOpenForWriting(verdict))
    }

    @Test("a marker beside a FOREIGN store changes nothing, because it is refused first")
    func aforeignStoreIsStillForeign() throws {
        // The marker says nothing about somebody else's file, and the better
        // reason to refuse is the one the person can act on.
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let container = try ModelContainer(
            for: ProbeSchemaV1.Probe.self,
            configurations: ModelConfiguration(schema: Schema(versionedSchema: ProbeSchemaV1.self),
                                               url: scratch.store))
        let context = ModelContext(container)
        context.insert(ProbeSchemaV1.Probe(name: "somebody else", amount: 1))
        try context.save()
        #expect(StoreCheckpoint.run(storeURL: scratch.store) == .checkpointed)
        try StoreVersionMarker.write(Schema.Version(9, 0, 0), besideStoreAt: scratch.store)

        let verdict = inspect(scratch.store, running: Schema.Version(1, 0, 0))

        guard case .foreign = verdict else {
            Issue.record("a foreign store with a marker gave \(verdict)")
            return
        }
    }

    @Test("a patch level difference counts, so 1.0.1 is refused under 1.0.0")
    func theComparisonIsTheWholeVersion() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try storeCarryingOvationTables(at: scratch.store)
        try StoreVersionMarker.write(Schema.Version(1, 0, 1), besideStoreAt: scratch.store)

        #expect(inspect(scratch.store, running: Schema.Version(1, 0, 0))
            == .fromANewerVersion(found: "1.0.1", running: "1.0.0"))
    }
}
