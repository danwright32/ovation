import Foundation
import SQLite3
import SwiftData
import Testing

/// Plan 1.2, ovation#52. What the file at the store path actually IS, before
/// anything opens it for writing.
///
/// Every fixture is a real SQLite file built by these tests in a directory they
/// own. Nothing here reads or writes the live store path.
struct StoreSchemaGuardTests {
    // MARK: the facts, one test each

    @Test("nothing at the path is a first launch, not a refusal")
    func anAbsentFileIsAFirstLaunch() throws {
        let scratch = try Scratch()
        #expect(StoreSchemaGuard.inspect(storeURL: scratch.url("Ovation.store"),
                                         ownEntityTables: ["ZINVOICE"],
                                     runningVersion: Schema.Version(1, 0, 0)) == .noStoreFile)
    }

    @Test("a database carrying only Core Data's own bookkeeping tables is empty")
    func aFreshStoreIsEmpty() throws {
        let scratch = try Scratch()
        let store = scratch.url("Ovation.store")
        // Core Data writes these into every store it manages regardless of app,
        // so they say nothing about whose file this is.
        try makeDatabase(at: store, tables: ["Z_METADATA", "Z_PRIMARYKEY", "ACHANGE"])

        #expect(StoreSchemaGuard.inspect(storeURL: store,
                                         ownEntityTables: ["ZINVOICE"],
                                     runningVersion: Schema.Version(1, 0, 0)) == .empty)
    }

    @Test("a database carrying one of Ovation's own tables is Ovation's")
    func ourOwnStoreIsRecognised() throws {
        let scratch = try Scratch()
        let store = scratch.url("Ovation.store")
        try makeDatabase(at: store, tables: ["Z_METADATA", "ZINVOICE"])

        #expect(StoreSchemaGuard.inspect(storeURL: store,
                                         ownEntityTables: ["ZINVOICE", "ZEXPENSE"],
                                     runningVersion: Schema.Version(1, 0, 0)) == .ovation)
    }

    @Test("a partial overlap counts as ours, because the permissive answer is the one that destroys nothing")
    func aPartialOverlapIsStillOurs() throws {
        let scratch = try Scratch()
        let store = scratch.url("Ovation.store")
        try makeDatabase(at: store, tables: ["ZINVOICE", "ZSOMETHINGELSE"])

        #expect(StoreSchemaGuard.inspect(storeURL: store,
                                         ownEntityTables: ["ZINVOICE", "ZEXPENSE"],
                                     runningVersion: Schema.Version(1, 0, 0)) == .ovation)
    }

    @Test("a database whose entity tables are none of ours is somebody else's data")
    func aSiblingsStoreIsForeign() throws {
        let scratch = try Scratch()
        let store = scratch.url("Ovation.store")
        // ZPROSPECT is Overture's, ZBOOKING is Downbeat's. Either sibling landing
        // at Ovation's path is the case this whole guard exists for.
        try makeDatabase(at: store, tables: ["Z_METADATA", "ZPROSPECT", "ZBOOKING"])

        #expect(StoreSchemaGuard.inspect(storeURL: store,
                                         ownEntityTables: ["ZINVOICE"],
                                     runningVersion: Schema.Version(1, 0, 0))
                == .foreign(entityTables: ["ZBOOKING", "ZPROSPECT"]))
    }

    @Test("a file that is not a database at all is its own finding")
    func aNonDatabaseFileIsNamedAsOne() throws {
        let scratch = try Scratch()
        let store = scratch.url("Ovation.store")
        try Data("this is not a database".utf8).write(to: store)

        // The read HAPPENED and the answer is certain, which is what separates
        // this from unreadable below. It is still a refusal: something is at
        // Ovation's path and Ovation did not put it there.
        #expect(StoreSchemaGuard.inspect(storeURL: store,
                                         ownEntityTables: ["ZINVOICE"],
                                     runningVersion: Schema.Version(1, 0, 0)) == .notADatabase)
    }

    @Test("a file that cannot be read says so, and claims nothing about whose it is")
    func anUnreadableFileIsNotAccusedOfBeingForeign() throws {
        let scratch = try Scratch()
        let store = scratch.url("Ovation.store")
        // A directory at the store path: the file exists as far as the file
        // manager is concerned, and sqlite cannot open it.
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)

        let verdict = StoreSchemaGuard.inspect(storeURL: store, ownEntityTables: ["ZINVOICE"],
                                     runningVersion: Schema.Version(1, 0, 0))
        guard case .unreadable(let detail) = verdict else {
            Issue.record("expected unreadable, got \(verdict)")
            return
        }
        #expect(!detail.isEmpty)
    }

    @Test("with nothing to recognise Ovation by, the guard says so instead of calling every store foreign")
    func anEmptyNeedleSetRefusesRatherThanAccusing() throws {
        let scratch = try Scratch()
        let store = scratch.url("Ovation.store")
        try makeDatabase(at: store, tables: ["ZINVOICE"])

        // Ovation ships no models yet (ovation#60), so today the derived needle
        // set is EMPTY. A guard handed no needles examines nothing, and one that
        // answered `foreign` would accuse Ovation's own store the moment the
        // schema was wired in wrong, while reading exactly like the guard working
        // (L98, L217).
        #expect(StoreSchemaGuard.inspect(storeURL: store, ownEntityTables: [],
                                     runningVersion: Schema.Version(1, 0, 0))
                == .unidentifiable(entityTables: ["ZINVOICE"]))
    }

    // MARK: what each verdict permits

    @Test("only the three safe verdicts permit opening the store for writing")
    func theGuardFailsClosed() {
        #expect(StoreSchemaGuard.mayOpenForWriting(.noStoreFile))
        #expect(StoreSchemaGuard.mayOpenForWriting(.empty))
        #expect(StoreSchemaGuard.mayOpenForWriting(.ovation))

        #expect(!StoreSchemaGuard.mayOpenForWriting(.foreign(entityTables: ["ZPROSPECT"])))
        #expect(!StoreSchemaGuard.mayOpenForWriting(.notADatabase))
        #expect(!StoreSchemaGuard.mayOpenForWriting(.unreadable(detail: "disk I/O error")))
        #expect(!StoreSchemaGuard.mayOpenForWriting(.unidentifiable(entityTables: ["ZINVOICE"])))
    }

    // MARK: the sentences, which may claim only what the check measured

    @Test("every refusal carries its own sentence, and no two refusals share one")
    func distinctCausesGetDistinctSentences() {
        let refusals: [StoreSchemaGuard.Verdict] = [
            .foreign(entityTables: ["ZPROSPECT"]),
            .notADatabase,
            .unreadable(detail: "disk I/O error"),
            .unidentifiable(entityTables: ["ZINVOICE"]),
        ]
        let sentences = refusals.compactMap {
            StoreSchemaGuard.refusalSentence(for: $0, at: "/tmp/Ovation/Ovation.store")
        }

        #expect(sentences.count == refusals.count)
        #expect(Set(sentences).count == refusals.count)
        for sentence in sentences {
            #expect(!sentence.isEmpty)
        }
    }

    @Test("a verdict that permits opening has no refusal sentence")
    func theSafeVerdictsSayNothing() {
        let path = "/tmp/Ovation/Ovation.store"
        #expect(StoreSchemaGuard.refusalSentence(for: .noStoreFile, at: path) == nil)
        #expect(StoreSchemaGuard.refusalSentence(for: .empty, at: path) == nil)
        #expect(StoreSchemaGuard.refusalSentence(for: .ovation, at: path) == nil)
    }

    @Test("the unreadable sentence does not accuse another app, because nothing measured that")
    func theUnreadableSentenceClaimsOnlyWhatWasMeasured() throws {
        // Overture shipped this defect and it was proved on 2026-08-08: an
        // Overture store that had merely become unreadable reported the sentence
        // about another app having written to it, and the refusal then filed Dan's
        // own data into a folder labelled foreign, which its own docs define as a
        // copy that must never be restored from (L11).
        let sentence = try #require(StoreSchemaGuard.refusalSentence(
            for: .unreadable(detail: "database is locked"), at: "/tmp/Ovation/Ovation.store"))

        #expect(!sentence.lowercased().contains("another app"))
        #expect(!sentence.lowercased().contains("another program's"))
        #expect(sentence.contains("database is locked"))
    }

    @Test("the foreign sentence names the tables it actually found")
    func theForeignSentenceCarriesItsEvidence() throws {
        let sentence = try #require(StoreSchemaGuard.refusalSentence(
            for: .foreign(entityTables: ["ZBOOKING", "ZPROSPECT"]), at: "/tmp/Ovation/Ovation.store"))

        #expect(sentence.contains("ZBOOKING"))
        #expect(sentence.contains("ZPROSPECT"))
    }

    @Test("every refusal sentence says that nothing was opened or changed")
    func everySentencePromisesTheSameRestraint() {
        let refusals: [StoreSchemaGuard.Verdict] = [
            .foreign(entityTables: ["ZPROSPECT"]),
            .notADatabase,
            .unreadable(detail: "disk I/O error"),
            .unidentifiable(entityTables: ["ZINVOICE"]),
        ]
        for refusal in refusals {
            let sentence = StoreSchemaGuard.refusalSentence(
                for: refusal, at: "/tmp/Ovation/Ovation.store") ?? ""
            #expect(sentence.contains("Nothing has been opened or changed"))
            // Every refusal names the file it is about, or it is not actionable.
            #expect(sentence.contains("/tmp/Ovation/Ovation.store"))
        }
    }

    // MARK: the needles are DERIVED, never hand listed

    @Test("the needle set is derived from the shipped schema, so a renamed model cannot leave it stale")
    func theNeedlesComeFromTheSchema() {
        let schema = Schema([StoreSchemaGuardFixtureInvoice.self])

        #expect(StoreSchemaGuard.entityTableNames(for: schema)
                == ["Z" + "StoreSchemaGuardFixtureInvoice".uppercased()])
    }

    @Test("Core Data's table naming rule is stated once")
    func tableNamesFollowCoreDatasRule() {
        #expect(StoreSchemaGuard.tableName(forEntityNamed: "Invoice") == "ZINVOICE")
    }

    // MARK: reading a copied store

    @Test("a copy of a WAL store, with no sidecar files and nowhere to write them, still reads")
    func aCopiedBackupIsNotReportedUnreadable() throws {
        // This is what ovation#57's restore hands the guard: the main database
        // file alone, in a directory it cannot write to. A plain read only open
        // fails there, because sqlite wants to create the shared memory file, and
        // the verdict would be `unreadable` on a perfectly good backup.
        let scratch = try Scratch()
        let source = scratch.url("source.store")
        try makeDatabase(at: source, tables: ["ZINVOICE"], walMode: true)

        let vault = scratch.url("read-only-vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let copy = vault.appendingPathComponent("Ovation.store")
        try FileManager.default.copyItem(at: source, to: copy)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: vault.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: vault.path)
        }

        #expect(StoreSchemaGuard.inspect(storeURL: copy,
                                         ownEntityTables: ["ZINVOICE"],
                                     runningVersion: Schema.Version(1, 0, 0)) == .ovation)
    }

    // MARK: no side effects

    @Test("asking the question never brings a store into existence")
    func inspectingCreatesNothing() throws {
        let scratch = try Scratch()
        let store = scratch.url("Ovation.store")

        _ = StoreSchemaGuard.inspect(storeURL: store, ownEntityTables: ["ZINVOICE"],
                                     runningVersion: Schema.Version(1, 0, 0))

        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test("inspecting a real store leaves its bytes untouched")
    func inspectingModifiesNothing() throws {
        let scratch = try Scratch()
        let store = scratch.url("Ovation.store")
        try makeDatabase(at: store, tables: ["ZINVOICE"])
        let before = try Data(contentsOf: store)

        _ = StoreSchemaGuard.inspect(storeURL: store, ownEntityTables: ["ZINVOICE"],
                                     runningVersion: Schema.Version(1, 0, 0))

        #expect(try Data(contentsOf: store) == before)
    }
}

/// A model that exists only to give `Schema` something real to derive a table
/// name from. Ovation's own models arrive with ovation#60.
@Model
final class StoreSchemaGuardFixtureInvoice {
    var number: Int
    init(number: Int) { self.number = number }
}

// MARK: fixtures

/// A directory this test owns, removed when it goes.
private final class Scratch {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ovation-schema-guard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    deinit { try? FileManager.default.removeItem(at: root) }
}

/// Builds a real SQLite file carrying exactly the named tables.
private func makeDatabase(at url: URL, tables: [String], walMode: Bool = false) throws {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
          let db else {
        sqlite3_close(db)
        throw FixtureError.couldNotCreate(url.path)
    }
    defer { sqlite3_close(db) }

    if walMode {
        guard sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.couldNotCreate(url.path)
        }
    }
    for table in tables {
        guard sqlite3_exec(db, "CREATE TABLE \(table) (Z_PK INTEGER PRIMARY KEY);",
                           nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.couldNotCreate(table)
        }
    }
}

private enum FixtureError: Error {
    case couldNotCreate(String)
}
