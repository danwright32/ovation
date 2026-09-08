// Ported-From: danwright32/downbeat Downbeat/Downbeat/Persistence/StoreSchemaGuard.swift @ e2b59df4411270fefaa3551e7f73a4f60bb51137
//
// Port discipline: docs/PORT-DISCIPLINE.md. Plan 1.2, ovation#52. Downbeat's is
// the one ported, because its verdict set is already named for the owning app
// rather than a generic `ours`, and that is the distinction Ovation needs when
// the file it finds may belong to EITHER sibling. Overture's
// mac/Overture/App/StoreSchemaGuard.swift @ b29c2fa0 was diffed against it and
// three of its behaviours are taken instead; each is marked below.
//
// WHAT THIS DOES. It reads the raw sqlite_master at the store path, read only,
// and says what the file actually IS, before ModelContainer ever opens it.
//
// Core Data does not throw on a foreign file. It creates its missing tables
// fresh inside whatever it is handed and successfully opens what looks like an
// empty store, so the other app's data is destroyed and the app reports nothing
// wrong. That has happened twice on this Mac at Application Support/default.store:
// once to Overture at the hands of Downbeat (2026-07-08) and once at the hands of
// /usr/libexec/icloudmailagent, which migrated its own schema straight over
// Overture's tables (2026-07-23).
//
// WHAT THIS DOES NOT DO, so its absence is visible rather than assumed. The plan's
// launch ordering is IDENTIFY, CHECKPOINT, BACK UP, THEN OPEN. This is the first
// step only. Overture's guard performs a backup snapshot from inside its refusal;
// Ovation's does not, because backup and its rotation are ovation#57 and a guard
// that writes cannot honestly promise that nothing has been opened or changed.
// The launch sequence that runs the four steps in order, and the surface that
// shows a refusal, are ovation#57 and ovation#59.
//
// Downbeat has no open issue against this file, and neither does Overture against
// theirs. Searched both repositories by file name with a positive control.
import Foundation
import SQLite3
import SwiftData

enum StoreSchemaGuard {

    /// What the file at the store path is. Seven facts, not one boolean.
    ///
    /// Ovation's own store, an empty one, a file that is not a database, a
    /// database that is somebody else's, a file that could not be read at all, a
    /// database this build has no way to recognise, and a path with nothing at
    /// it are different findings with different remedies. A single "could not
    /// open the store" collapses them, and a message may claim only what its
    /// check actually measured (L11).
    ///
    /// TAKEN FROM OVERTURE, NOT DOWNBEAT: `unreadable` is its own verdict.
    /// Downbeat folds an unreadable file into `.empty`, on the grounds that
    /// there is no other app's data there to protect. Ovation cannot: `.empty`
    /// PERMITS OPENING, so folding would let Core Data create a fresh store
    /// inside a file that is merely locked or briefly unreadable, and that file
    /// is seven years of tax records. A guard protecting data fails closed (L42).
    ///
    /// ALSO FROM OVERTURE: a file that is READ successfully and turns out not to
    /// be a database is a finding rather than a failure, and it is separated
    /// from `unreadable` because the remedies differ. `notADatabase` means
    /// something is at Ovation's path that Dan can look at and move. `unreadable`
    /// may be Ovation's own store held open by another program, where moving it
    /// is the wrong thing to do. They also earn different labels on the evidence
    /// snapshot ovation#57 takes, so they are not two names for one outcome
    /// (L260).
    enum Verdict: Equatable {
        /// Nothing at the path. A first launch, free to create a store.
        case noStoreFile
        /// A readable database carrying no entity tables. A freshly created store.
        case empty
        /// Carries at least one of Ovation's own entity tables.
        case ovation
        /// Carries entity tables, none of them Ovation's. Somebody else's data.
        case foreign(entityTables: [String])
        /// Read successfully, and it is not a database.
        case notADatabase
        /// Could not be opened or queried, so whose it is is unknown.
        case unreadable(detail: String)
        /// A database carrying entity tables, and this build declares no names to
        /// recognise its own by. Not an accusation: the guard has nothing to
        /// examine WITH.
        case unidentifiable(entityTables: [String])

        /// Ovation's own store, written by a NEWER build than the one running
        /// (ovation#116).
        ///
        /// ITS OWN VERDICT RATHER THAN `foreign`, because the two need opposite
        /// remedies and one sentence cannot serve both (L11). A foreign store is
        /// somebody else's file to move out of the way. A newer one is Ovation's
        /// own data, and the remedy is to run the newer build: moving it aside
        /// would be moving Dan's invoices aside.
        ///
        /// WHY IT IS A REFUSAL RATHER THAN A WARNING, measured rather than
        /// argued. `SchemaMigrationTests` opens a store written by version two
        /// with version one: it does not refuse, it migrates BACKWARDS, and the
        /// field only version two knew about is gone, with the backup taken
        /// before any of it.
        case fromANewerVersion(found: String, running: String)

        /// Ovation's own store, and the marker beside it could not be read.
        /// Distinct from a store with no marker at all: that one was never
        /// opened by a build that writes them, this one has a file saying
        /// something nobody can parse.
        case versionUnreadable(detail: String)
    }

    /// Core Data writes these into every store it manages regardless of app, so
    /// they say nothing about whose file this is. Measured by Downbeat across all
    /// three Core Data stores on this Mac, 2026-08-10, and taken unchanged
    /// because the set is a property of Core Data rather than of Downbeat.
    private static let schemaAgnosticTables: Set<String> = [
        "ACHANGE", "ATRANSACTION", "ATRANSACTIONSTRING",
        "Z_METADATA", "Z_MODELCACHE", "Z_MODELDATA", "Z_PRIMARYKEY",
    ]

    /// Core Data names an entity's table by upper casing the entity name and
    /// prefixing `Z`.
    nonisolated static func tableName(forEntityNamed name: String) -> String {
        "Z" + name.uppercased()
    }

    /// The tables that identify a store as Ovation's, DERIVED from the shipped
    /// schema rather than hand listed beside it, so renaming or adding a model
    /// cannot leave the guard checking a name nothing writes any more (L96).
    ///
    /// This is Downbeat's behaviour rather than Overture's, whose guard asks for
    /// one hardcoded table name and would go on answering about a model that had
    /// been renamed.
    nonisolated static func entityTableNames(for schema: Schema) -> Set<String> {
        Set(schema.entities.map { tableName(forEntityNamed: $0.name) })
    }

    /// Read only, and it creates nothing: asking the question must never bring a
    /// store into existence, nor modify one.
    ///
    /// `ownEntityTables` is passed in rather than read from a schema constant,
    /// because Ovation ships no models yet (ovation#60). An EMPTY set is answered
    /// with `unidentifiable`, never `foreign`: a guard handed no needles examines
    /// nothing, and answering foreign would accuse Ovation's own store while
    /// reading exactly like the guard working (L98, L217).
    /// `runningVersion` is REQUIRED rather than defaulted, and that is the
    /// difference between a guard and a suggestion. A default would let a caller
    /// get the old behaviour by omitting an argument, which is a guard standing
    /// down for a reason nobody chose (L324), and the case it stands down on is
    /// the one that loses data.
    nonisolated static func inspect(
        storeURL: URL,
        ownEntityTables: Set<String>,
        runningVersion: Schema.Version,
        readMarker: (URL) -> StoreVersionMarker.Reading = StoreVersionMarker.read(besideStoreAt:),
        fileManager: FileManager = .default
    ) -> Verdict {
        guard fileManager.fileExists(atPath: storeURL.path) else { return .noStoreFile }

        var database: OpaquePointer?
        var lastCode: Int32 = SQLITE_OK
        var lastMessage = ""

        // The plain open is tried FIRST because it sees the write ahead log, so a
        // live store whose newest tables are still only in the log reads
        // correctly. It fails on a WAL database with no sidecar files beside it
        // and nowhere to create them, which is exactly what a copied backup is,
        // so that falls back to an immutable open reading the main file alone.
        // From Downbeat; Overture has no such fallback and would report a good
        // backup as unreadable, which is the file ovation#57 hands this guard.
        func attempt(_ path: String, flags: Int32) -> Bool {
            var candidate: OpaquePointer?
            let opened = sqlite3_open_v2(path, &candidate, flags, nil)
            guard opened == SQLITE_OK, let candidate else {
                lastCode = opened
                lastMessage = candidate.map { String(cString: sqlite3_errmsg($0)) }
                    ?? "sqlite could not open the file (code \(opened))"
                sqlite3_close(candidate)
                return false
            }
            // sqlite3_open_v2 is lazy: it does not touch the header until the
            // first statement, so a file that is not a database lands here.
            let probe = sqlite3_exec(candidate, "SELECT count(*) FROM sqlite_master;", nil, nil, nil)
            guard probe == SQLITE_OK else {
                lastCode = probe
                lastMessage = String(cString: sqlite3_errmsg(candidate))
                sqlite3_close(candidate)
                return false
            }
            database = candidate
            return true
        }

        if !attempt(storeURL.path, flags: SQLITE_OPEN_READONLY) {
            _ = attempt("file:\(storeURL.path)?immutable=1",
                        flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI)
        }

        guard let database else {
            // SQLITE_NOTADB is the one outcome here that is a FINDING rather than
            // a failure: the file was read and it is not a database. Every other
            // error means the read did not happen, which says nothing about whose
            // file it is.
            return lastCode == SQLITE_NOTADB ? .notADatabase : .unreadable(detail: lastMessage)
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database, "SELECT name FROM sqlite_master WHERE type='table';", -1, &statement, nil
        ) == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(database))
            return .unreadable(detail: message)
        }
        defer { sqlite3_finalize(statement) }

        var entityTables: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(statement, 0) else { continue }
            let name = String(cString: raw)
            guard !schemaAgnosticTables.contains(name), !name.hasPrefix("sqlite_") else { continue }
            entityTables.append(name)
        }

        guard !entityTables.isEmpty else { return .empty }
        guard !ownEntityTables.isEmpty else {
            return .unidentifiable(entityTables: entityTables.sorted())
        }

        // Partial overlap counts as ours: if any of Ovation's tables are in
        // there, Ovation has data to lose, and the permissive answer is the one
        // that does not destroy it.
        guard entityTables.contains(where: { ownEntityTables.contains($0) }) else {
            return .foreign(entityTables: entityTables.sorted())
        }

        // ONLY NOW IS THE VERSION WORTH ASKING ABOUT. The marker beside a
        // foreign store says nothing about it, and a store that is not ours is
        // refused for a better reason first.
        switch readMarker(storeURL) {
        case .version(let found) where found > runningVersion:
            return .fromANewerVersion(found: Self.describe(found),
                                      running: Self.describe(runningVersion))
        case .version, .absent:
            // ABSENT IS NOT A REFUSAL, and the reason is measured rather than
            // assumed. A marker cannot describe a store written before markers
            // existed, which is exactly the population such a detector is blind
            // to (L223). Measured 2026-09-08: no store exists on this machine on
            // either build path, so that population is empty and stays empty,
            // because every store now gets a marker at its first successful open.
            return .ovation
        case .unreadable(let detail):
            return .versionUnreadable(detail: detail)
        }
    }

    nonisolated static func describe(_ version: Schema.Version) -> String {
        "\(version.major).\(version.minor).\(version.patch)"
    }

    /// Whether this verdict permits opening the store for writing.
    ///
    /// One predicate, and the switch is exhaustive, so a verdict added later
    /// stops the build rather than silently taking a default branch (L113).
    nonisolated static func mayOpenForWriting(_ verdict: Verdict) -> Bool {
        switch verdict {
        case .noStoreFile, .empty, .ovation:
            return true
        case .foreign, .notADatabase, .unreadable, .unidentifiable,
             .fromANewerVersion, .versionUnreadable:
            return false
        }
    }

    /// The one sentence for each way this can refuse, or nil when it does not.
    ///
    /// Each says only what its own check measured. Overture shipped the opposite
    /// and it was proved on 2026-08-08: a store that had merely become unreadable
    /// reported the sentence about another app having written to it, and the
    /// refusal then filed Dan's own data into a folder its own docs define as one
    /// never to restore from.
    nonisolated static func refusalSentence(for verdict: Verdict, at path: String) -> String? {
        let restraint = "Nothing has been opened or changed."
        switch verdict {
        case .noStoreFile, .empty, .ovation:
            return nil

        case .foreign(let entityTables):
            return "The database at \(path) belongs to another app. It carries tables Ovation "
                + "does not own (\(entityTables.joined(separator: ", "))). \(restraint) "
                + "Move that file aside before opening Ovation again."

        case .notADatabase:
            return "The file at \(path) is not a database. Ovation read it and found no database "
                + "in it. \(restraint) Move that file aside before opening Ovation again."

        case .unreadable(let detail):
            return "Ovation could not read the file at \(path), so it cannot tell whose it is. "
                + "SQLite reported: \(detail). \(restraint) The file may be in use by another "
                + "program, or its permissions may have changed."

        case .unidentifiable(let entityTables):
            return "Ovation cannot tell whether the database at \(path) is its own, because this "
                + "build declares no models to recognise one by. It carries "
                + "\(entityTables.count) table(s). \(restraint) This is a fault in Ovation, not "
                + "in the file."

        // THE SENTENCE THAT MAKES THE EIGHTH VERDICT WORTH HAVING. It never says
        // "move the file aside", which every other refusal here says, because
        // this file is Dan's own invoices. It names the two versions and the one
        // action that helps.
        case .fromANewerVersion(let found, let running):
            return "This database was written by a newer version of Ovation (\(found)) than the "
                + "one running (\(running)). \(restraint) Opening it with this build would "
                + "remove anything the newer version added. Open the newer Ovation instead, or "
                + "install it again."

        case .versionUnreadable(let detail):
            return "Ovation could not tell which version of itself last opened the database at "
                + "\(path): \(detail). \(restraint) The version file beside the database is "
                + "damaged, and until it is readable Ovation cannot rule out that this database "
                + "came from a newer build."
        }
    }
}
