import Foundation
import SwiftData
import Testing
@testable import Ovation

/// ovation#88. The checkpoint that makes the store file self sufficient before a
/// backup reads it.
///
/// WHY IT IS LOAD BEARING RATHER THAN TIDY. Measured on this OS in
/// `SwiftDataBehaviourTests`: after a save, the write ahead log holds 57,712
/// bytes and the store file alone carries NO rows. So a backup that copied
/// `Ovation.store` without its log would restore an empty database, and
/// `BackupPlan` cannot require the log, because a checkpointed store legitimately
/// has none. Copying both is not a fix either: they are copied at two different
/// instants and can be mutually inconsistent.
struct StoreCheckpointTests {

    @Test("after a checkpoint the store file ALONE carries the rows")
    func theStoreFileBecomesSelfSufficient() throws {
        let world = try World()

        // POSITIVE CONTROL, in the same fixture, run BEFORE the checkpoint. A
        // test that only asserted the copy holds the row afterwards cannot tell
        // a working checkpoint from a store that never needed one (L159).
        #expect(try world.rowsInStoreFileAlone(named: "before") == 0)

        let outcome = StoreCheckpoint.run(storeURL: world.storeURL)

        #expect(outcome == .checkpointed)
        #expect(try world.rowsInStoreFileAlone(named: "after") == 1)
    }

    @Test("it empties the log rather than leaving the pages in both places")
    func theLogIsTruncated() throws {
        let world = try World()
        let before = try world.logByteCount()
        #expect(before > 0, "nothing to checkpoint, so the test proves nothing")

        _ = StoreCheckpoint.run(storeURL: world.storeURL)

        #expect(try world.logByteCount() == 0)
    }

    @Test("a path with no store there is its own answer, not a failure")
    func nothingToCheckpoint() throws {
        // A first launch has no store yet, and that is ordinary. Reporting it as
        // a failure would raise a problem on every fresh install (L11).
        let directory = try World.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outcome = StoreCheckpoint.run(
            storeURL: directory.appending(path: "Ovation.store"))

        #expect(outcome == .noStoreFile)
    }

    @Test("a file that is not a database FAILS by name rather than reporting success")
    func aFileThatIsNotADatabase() throws {
        // The checkpoint runs BEFORE the backup, so a silent success here would
        // let the backup proceed against something nobody has identified. It
        // must say what went wrong rather than returning the same answer as a
        // clean run (L98, L11).
        let directory = try World.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notAStore = directory.appending(path: "Ovation.store")
        try Data("this is not a database".utf8).write(to: notAStore)

        let outcome = StoreCheckpoint.run(storeURL: notAStore)

        guard case .failed(let detail) = outcome else {
            Issue.record("expected a named failure, got \(outcome)")
            return
        }
        #expect(!detail.isEmpty)
    }

    // MARK: fixtures

    /// A real on disk store with one saved row and its log still holding the
    /// pages. The container stays OPEN, which is the state a live app is in and
    /// the only state in which the checkpoint has anything to do.
    private struct World {
        let directory: URL
        let storeURL: URL
        let container: ModelContainer

        static func makeDirectory() throws -> URL {
            let directory = URL.temporaryDirectory
                .appending(path: "ovation-checkpoint-\(UUID().uuidString)",
                           directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            return directory
        }

        init() throws {
            directory = try Self.makeDirectory()
            storeURL = directory.appending(path: "Ovation.store")
            let schema = Schema([Client.self])
            container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: storeURL))
            let context = ModelContext(container)
            context.insert(Client(name: "Ashgrove Chamber Players", taxStatus: .neverRecorded))
            try context.save()
        }

        func logByteCount() throws -> Int {
            let log = directory.appending(path: "Ovation.store-wal")
            guard FileManager.default.fileExists(atPath: log.path) else { return 0 }
            return try Data(contentsOf: log).count
        }

        /// Copies the store file and NOTHING else, then reads it with a
        /// container that has never seen the original. This is exactly what a
        /// restore does when the archive holds no log.
        func rowsInStoreFileAlone(named name: String) throws -> Int {
            let copy = directory.appending(path: "\(name).store")
            try FileManager.default.copyItem(at: storeURL, to: copy)
            let schema = Schema([Client.self])
            let opened = try ModelContainer(
                for: schema, configurations: ModelConfiguration(schema: schema, url: copy))
            return try ModelContext(opened).fetch(FetchDescriptor<Client>()).count
        }
    }
}
