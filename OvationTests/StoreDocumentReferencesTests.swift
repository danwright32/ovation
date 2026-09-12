import Foundation
import SQLite3
import SwiftData
import Testing

/// ovation#224. WHAT THE STORE POINTS AT, READ WITHOUT OPENING THE STORE.
///
/// `BackupService.verify` enumerates the documents the store references
/// (ovation#104), and the backup runs BEFORE the store is opened, because
/// opening can migrate and a migration is the moment the only copy of Dan's
/// invoices is at risk. So the reader cannot have a `ModelContainer`. It reads
/// the file the way `StoreSchemaGuard` and `StoreCheckpoint` already do.
///
/// ovation#223 measured what that reader is up against: SwiftData flattens a
/// Codable enum into one column per associated value, so `.file(sha256:
/// relativePath:)` lands in `ZSHA256` and `ZRELATIVEPATH` as plain text. There is
/// nothing to decode, which is why Route A is possible at all.
///
/// THE TABLES ARE FOUND BY THE COLUMN, NOT BY A LIST. Plan 5.11 keeps the PDF of
/// every invoice version sent, which will be a second model referencing
/// documents. A reader naming `ZEXPENSE` would silently omit every one of them,
/// verification would report clean, and every invoice PDF in the folder would
/// read as an orphan: ovation#104's own defect, one model later (L96).
@MainActor
struct StoreDocumentReferencesTests {

    /// THE REAL MODEL, not a probe. A test against a fabricated model would
    /// prove SwiftData's behaviour and say nothing about `Expense.receipt`,
    /// which is the thing the backup actually has to read (L52).
    @Test("a receipt written through the real model is read back without opening the store")
    func readsAReceiptTheRealModelWrote() throws {
        let world = try World()
        try world.write(receipts: [
            .file(sha256: "abc123", relativePath: "ab/abc123.pdf")
        ])

        let references = try StoreDocumentReferences.read(storeURL: world.storeURL)

        #expect(references == [ReferencedDocument(relativePath: "ab/abc123.pdf",
                                                  sha256: "abc123")])
    }

    /// THE OTHER CASES OF THE SAME ENUM ARE NOT REFERENCES. An expense with no
    /// receipt points at no file, and reporting one would make the verification
    /// look for something nobody stored.
    @Test("expenses with no receipt file contribute nothing")
    func casesWithNoFileAreNotReferences() throws {
        let world = try World()
        try world.write(receipts: [.noneRecorded, .importedWithoutOne,
                                   .file(sha256: "dd", relativePath: "dd/dd.pdf")])

        let references = try StoreDocumentReferences.read(storeURL: world.storeURL)

        #expect(references == [ReferencedDocument(relativePath: "dd/dd.pdf", sha256: "dd")])
    }

    /// AN EMPTY ANSWER IS ONLY EVER A REAL ONE. A store holding no receipts
    /// references no documents, and that must be reachable, because otherwise
    /// the refusal below would fire on every ordinary installation.
    @Test("a store with no receipts answers none, which is a real answer")
    func noReceiptsIsAnAnswer() throws {
        let world = try World()
        try world.write(receipts: [])

        #expect(try StoreDocumentReferences.read(storeURL: world.storeURL).isEmpty)
    }

    /// A HALF WRITTEN REFERENCE REFUSES. A path with no hash cannot be verified:
    /// `verify` would compare the archived bytes against nothing and report the
    /// document fine, which is the vacuous verification ovation#104 exists to
    /// prevent (L215, L67). It is refused rather than skipped, because skipping
    /// it returns a shorter list that reads exactly like a store with fewer
    /// receipts (L98).
    @Test("a reference carrying a path and no hash refuses the whole read")
    func aHalfWrittenReferenceRefuses() throws {
        let world = try World()
        try world.write(receipts: [.file(sha256: "abc", relativePath: "ab/abc.pdf")])
        try world.execute("UPDATE ZEXPENSE SET ZSHA256 = NULL WHERE ZRELATIVEPATH IS NOT NULL;")

        #expect(throws: BackupError.self) {
            try StoreDocumentReferences.read(storeURL: world.storeURL)
        }
    }

    /// THE DERIVATION, which is the whole reason this is not a query against one
    /// named table. A second model carrying the same shape is read with no change
    /// here, so plan 5.11's sent invoice PDFs cannot be silently omitted (L96).
    @Test("a second table carrying the same columns is read too")
    func aSecondReferencingTableIsRead() throws {
        let world = try World()
        try world.write(receipts: [.file(sha256: "aa", relativePath: "aa/aa.pdf")])
        try world.execute("""
            CREATE TABLE ZSENTINVOICE (Z_PK INTEGER PRIMARY KEY, \
            ZSHA256 TEXT, ZRELATIVEPATH TEXT);
            """)
        try world.execute("""
            INSERT INTO ZSENTINVOICE (ZSHA256, ZRELATIVEPATH) \
            VALUES ('bb', 'bb/bb.pdf');
            """)

        let references = try StoreDocumentReferences.read(storeURL: world.storeURL)

        #expect(Set(references) == Set([
            ReferencedDocument(relativePath: "aa/aa.pdf", sha256: "aa"),
            ReferencedDocument(relativePath: "bb/bb.pdf", sha256: "bb"),
        ]))
    }

    /// A STORE IT CANNOT READ IS A REFUSAL, never an empty list. An empty answer
    /// from a reader that failed is indistinguishable from a correct reading of a
    /// store with no receipts, and it empties the whole verification (L215).
    @Test("a store that is not there refuses rather than answering none")
    func anAbsentStoreRefuses() throws {
        let world = try World()

        #expect(throws: BackupError.self) {
            try StoreDocumentReferences.read(
                storeURL: world.directory.appending(path: "no-such.store"))
        }
    }

    @Test("a file that is not a database refuses rather than answering none")
    func aFileThatIsNotADatabaseRefuses() throws {
        let world = try World()
        let notAStore = world.directory.appending(path: "notes.txt")
        try Data("this is not a database".utf8).write(to: notAStore)

        #expect(throws: BackupError.self) {
            try StoreDocumentReferences.read(storeURL: notAStore)
        }
    }

    /// IT OPENS READ ONLY AND CREATES NOTHING. Asking what a store references
    /// must never bring one into existence, which is the same rule
    /// `StoreSchemaGuard.inspect` already states about itself: the whole point of
    /// reading before the open is that nothing has been written yet.
    @Test("reading creates no store where there was none")
    func readingCreatesNothing() throws {
        let world = try World()
        let absent = world.directory.appending(path: "untouched.store")

        _ = try? StoreDocumentReferences.read(storeURL: absent)

        #expect(!FileManager.default.fileExists(atPath: absent.path))
    }

    // MARK: the fixture

    private struct World {
        let directory: URL
        let storeURL: URL

        init() throws {
            directory = URL.temporaryDirectory
                .appending(path: "ovation-refs-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            storeURL = directory.appending(path: "Ovation.store")
        }

        /// Writes expenses through the REAL model and then checkpoints, because a
        /// saved row lives in the write ahead log until something does
        /// (`SwiftDataBehaviourTests`). The launch sequence checkpoints before the
        /// backup for that reason, so the reader always meets a checkpointed
        /// file, and this fixture stands where the sequence does.
        func write(receipts: [ReceiptEvidence]) throws {
            let schema = Schema([Expense.self])
            let container = try ModelContainer(
                for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
            let context = ModelContext(container)
            for receipt in receipts {
                context.insert(Expense(amount: Money(dollars: 10),
                                       incurredOn: .stamping(Date(timeIntervalSinceReferenceDate: 0)),
                                       receipt: receipt))
            }
            try context.save()

            // WAITING ON THE CONDITION, never on a duration: a fixed sleep here
            // asserts how busy the machine is (L290). The bound exists so a
            // genuinely stuck file fails rather than hangs (L110).
            var attempts = 0
            while attempts < 200, StoreCheckpoint.run(storeURL: storeURL) != .checkpointed {
                attempts += 1
            }
        }

        /// Raw SQL against the same file, so a case can plant the states SwiftData
        /// will not produce on request: a half written row, and a second table
        /// shaped like a model nobody has built yet.
        func execute(_ sql: String) throws {
            var handle: OpaquePointer?
            guard sqlite3_open_v2(storeURL.path, &handle, SQLITE_OPEN_READWRITE, nil)
                    == SQLITE_OK, let handle else {
                sqlite3_close(handle)
                throw FixtureFailure.couldNotOpen
            }
            defer { sqlite3_close(handle) }
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                throw FixtureFailure.statementFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    enum FixtureFailure: Error {
        case couldNotOpen
        case statementFailed(String)
    }
}
