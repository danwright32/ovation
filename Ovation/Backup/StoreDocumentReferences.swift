// ovation#224. WHAT THE STORE POINTS AT, READ WITHOUT OPENING THE STORE.
//
// `BackupService.verify` enumerates the documents the store references
// (ovation#104): an archive can hold every file it recorded and still be missing
// a receipt the store points at, and only the store can say. The backup runs
// BEFORE the store is opened, deliberately, because opening can migrate and a
// migration is the moment the only copy of Dan's invoices is at risk
// (`StoreLaunchSequence`). So this reader cannot have a `ModelContainer`, and
// reads the file with raw SQLite the way `StoreSchemaGuard` and `StoreCheckpoint`
// already do.
//
// WHETHER THAT WAS POSSIBLE AT ALL WAS MEASURED FIRST (ovation#223), not
// assumed. SwiftData does not store a Codable enum as an opaque value: it
// flattens it into one column per associated value plus one per payload free
// case, so `ReceiptEvidence.file(sha256:relativePath:)` lands in `ZSHA256` and
// `ZRELATIVEPATH` as plain text. There is nothing here to decode, which is why
// this route exists rather than the fallback of opening a copy of the store.
//
// THE TABLES ARE FOUND BY THE COLUMNS THEY CARRY, never by a list of model
// names. Plan 5.11 keeps the PDF of every invoice version sent, which will be a
// second model referencing documents. A reader naming `ZEXPENSE` would omit
// every one of them silently: verification would report clean while no invoice
// PDF was checked, and each of them would be reported as an orphan instead.
// That is ovation#104's own defect arriving one model later (L96, L247).
//
// A COLUMN NAME IS NOT A PROPERTY NAME. `ZRELATIVEPATH` comes from the
// associated value's LABEL, not from `Expense.receipt`, so renaming that label
// renames a column this selects by name. `SwiftDataBehaviourTests` pins the
// layout so that rename fails a test here rather than silently emptying the
// verification.
import Foundation
import SQLite3

/// A document the store points at: where it is, and what it must contain.
///
/// NOT `DocumentReference`, and the difference is the point. That type also
/// carries a `byteCount`, which `DocumentStore` knows when it writes a file and
/// the STORE never records. A reader that filled it in would be presenting an
/// invented number as a recorded fact (L192), and a reader that passed zero
/// would be worse, because zero is a number somebody could act on.
struct ReferencedDocument: Equatable, Hashable, Sendable {
    /// Relative to the documents root.
    let relativePath: String
    /// The hash the archived bytes must match.
    let sha256: String
}

enum StoreDocumentReferences {

    /// The columns a referencing table carries, which is also how one is
    /// recognised. Both, never one: a path with no hash cannot be verified.
    private static let pathColumn = "ZRELATIVEPATH"
    private static let hashColumn = "ZSHA256"

    /// Every document the store at `storeURL` points at.
    ///
    /// REFUSES RATHER THAN ANSWERING SHORT. A reader that returned an empty list
    /// when it could not read is indistinguishable from a correct reading of a
    /// store with no receipts, and it empties the whole verification while
    /// leaving it reporting clean (L215, L98). Every failure here throws.
    static func read(storeURL: URL) throws -> [ReferencedDocument] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw BackupError.couldNotRead(storeURL.path)
        }

        var database: OpaquePointer?
        // READ ONLY, so asking the question cannot bring a store into existence
        // nor modify one. The whole value of reading before the open is that
        // nothing has been written yet.
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY, nil)
                == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw BackupError.couldNotRead(storeURL.path)
        }
        defer { sqlite3_close(database) }

        // `sqlite3_open_v2` is lazy and succeeds on any file, so a text file
        // opens cleanly and fails only when something reads the header. The same
        // probe `StoreSchemaGuard` uses, for the same reason.
        guard sqlite3_exec(database, "SELECT count(*) FROM sqlite_master;", nil, nil, nil)
                == SQLITE_OK else {
            throw BackupError.couldNotRead(storeURL.path)
        }

        var references: [ReferencedDocument] = []
        for table in try referencingTables(in: database, at: storeURL) {
            references += try read(from: table, in: database, at: storeURL)
        }
        return references
    }

    /// Every table carrying BOTH columns. Derived from the store itself, so a
    /// model nobody has built yet is covered the day it lands.
    private static func referencingTables(in database: OpaquePointer,
                                          at path: URL) throws -> [String] {
        var tables: [String] = []
        for table in try query("SELECT name FROM sqlite_master WHERE type = 'table' "
                                 + "AND name LIKE 'Z%' ORDER BY name;",
                               in: database, at: path, columns: 1).map({ $0[0] ?? "" }) {
            guard !table.isEmpty else { continue }
            // A table name cannot be bound as a parameter in a PRAGMA, and it
            // comes from sqlite_master rather than from anything a person typed,
            // so the only shapes that can reach here are ones SQLite itself
            // stored. Refused anyway if it is not a plain identifier.
            guard table.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
            let columns = try query("PRAGMA table_info(\(table));",
                                    in: database, at: path, columns: 2)
                .compactMap { $0[1] }
            if columns.contains(pathColumn) && columns.contains(hashColumn) {
                tables.append(table)
            }
        }
        return tables
    }

    private static func read(from table: String, in database: OpaquePointer,
                             at path: URL) throws -> [ReferencedDocument] {
        // EVERY ROW WHERE EITHER COLUMN IS SET, not only the rows where both are.
        // Selecting the well formed ones would make a half written reference
        // vanish from the answer rather than refuse it, which is the shorter list
        // that reads exactly like a store with fewer receipts (L98).
        let rows = try query("SELECT \(pathColumn), \(hashColumn) FROM \(table) "
                               + "WHERE \(pathColumn) IS NOT NULL OR \(hashColumn) IS NOT NULL;",
                             in: database, at: path, columns: 2)
        return try rows.map { row in
            guard let relativePath = row[0], !relativePath.isEmpty,
                  let sha256 = row[1], !sha256.isEmpty else {
                // A path with no hash cannot be verified: the archived bytes
                // would be compared against nothing and the document reported
                // fine, which is the vacuous verification ovation#104 exists to
                // prevent (L215, L67). A hash with no path names no file.
                throw BackupError.couldNotRead(
                    "\(path.path): \(table) holds a document reference with only "
                        + "one of its path and its hash, which cannot be verified")
            }
            return ReferencedDocument(relativePath: relativePath, sha256: sha256)
        }
    }

    /// Runs one statement and returns its rows as optional text, refusing rather
    /// than returning what it managed to read.
    private static func query(_ sql: String, in database: OpaquePointer, at path: URL,
                              columns: Int32) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            sqlite3_finalize(statement)
            throw BackupError.couldNotRead("\(path.path): \(String(cString: sqlite3_errmsg(database)))")
        }
        defer { sqlite3_finalize(statement) }

        var rows: [[String?]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                // A read that stopped part way through is not a short answer, it
                // is no answer: carrying on with the rows already gathered is the
                // silent partial read this whole type refuses (L211, L215).
                throw BackupError.couldNotRead(
                    "\(path.path): \(String(cString: sqlite3_errmsg(database)))")
            }
            var row: [String?] = []
            for index in 0..<columns {
                if let text = sqlite3_column_text(statement, index) {
                    row.append(String(cString: text))
                } else {
                    row.append(nil)
                }
            }
            rows.append(row)
        }
        return rows
    }
}
