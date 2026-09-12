import Foundation
import Testing

/// ovation#222. A BACKUP OF THE REAL DATA DIRECTORY COULD NOT SUCCEED.
///
/// `BackupPlan.members` declares `documents` and `custody` as `.required`, and
/// `BackupService.takeBackup` throws `requiredMemberMissing` before doing
/// anything else when a required member is absent. Nothing in the app created
/// either one: `DocumentStore` makes `documents` on the first byte written
/// through it and nothing writes a document until ovation#78, and nothing
/// creates `custody` at all.
///
/// Measured 2026-09-11 on Dan's Mac: `Application Support/Ovation/` held
/// `booking-queue`, `custody` and `downbeat-queued-bookings.json`. No
/// `documents`, no `problems.jsonl`.
///
/// WHY NOTHING CAUGHT IT. Both backup fixtures build those directories before
/// running (`BackupTests.World.init`, `BackupCostTests`), so the suite measures
/// a data directory shaped to make the rule under test fire rather than the one
/// the app produces (L48). The assertions below are deliberately made against a
/// directory this file does NOT furnish by hand.
///
/// WHY THE DIRECTORIES ARE CREATED RATHER THAN THE EXPECTATION DOWNGRADED.
/// `documents` absent once receipts exist is genuinely alarming, and marking it
/// `presentSometimes` would make that state read as legitimate for ever (L63).
/// Creating it empty keeps the requirement true and loses nothing, because the
/// safeguard against receipts actually going missing is the reference check
/// ovation#104 built into `verify`, never the directory's existence.
@MainActor
struct DataDirectoryTests {

    /// THE CASE THE ISSUE IS ABOUT. A data directory holding what the app itself
    /// puts there, and nothing a fixture invented, must be backable up.
    @Test("a data directory the app prepared can be backed up")
    func aPreparedDirectoryCanBeBackedUp() throws {
        let world = try World()

        try DataDirectory.prepare(world.dataDirectory)

        // No throw is the assertion. Before ovation#222 this threw
        // `requiredMemberMissing("documents")`.
        let archive = try world.service.takeBackup(now: world.instant)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    /// THE CLASS, NOT THE INSTANCE (L30). Enumerated from `BackupPlan.members`
    /// rather than from the two names known today, so a required directory added
    /// later fails here until something creates it, instead of failing on Dan's
    /// machine months afterwards the way these two did.
    @Test("every required directory in the plan is one the preparation creates")
    func everyRequiredDirectoryIsCreated() throws {
        let world = try World()

        try DataDirectory.prepare(world.dataDirectory)

        let required = BackupPlan.members.filter {
            $0.kind == .directory && $0.expectation == .required
        }
        #expect(!required.isEmpty, "the derivation read nothing, so it proves nothing (L100)")
        for member in required {
            let path = world.dataDirectory.appendingPathComponent(member.path).path
            var isDirectory: ObjCBool = false
            let there = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            #expect(there && isDirectory.boolValue,
                    "\(member.path) is required by BackupPlan and nothing creates it")
        }
    }

    /// PREPARING IS NOT EMPTYING. Run on a directory that already holds receipts,
    /// it must leave every one of them where it is: a step that ran at launch and
    /// cleared the documents folder would destroy exactly what the backup exists
    /// to carry (L5).
    @Test("preparing an existing directory leaves what is already in it")
    func preparingKeepsWhatIsThere() throws {
        let world = try World()
        let documents = world.dataDirectory.appendingPathComponent("documents",
                                                                   isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let receipt = documents.appendingPathComponent("a-receipt.pdf")
        try Data("a receipt".utf8).write(to: receipt)

        try DataDirectory.prepare(world.dataDirectory)

        #expect(FileManager.default.fileExists(atPath: receipt.path))
    }

    /// IT RUNS TWICE. The launch sequence runs it on every launch, so the second
    /// run must be as ordinary as the first (assume it runs twice, CLAUDE.md).
    @Test("preparing twice is not an error")
    func preparingIsIdempotent() throws {
        let world = try World()

        try DataDirectory.prepare(world.dataDirectory)
        try DataDirectory.prepare(world.dataDirectory)
    }

    /// A PREPARATION THAT COULD NOT HAPPEN SAYS SO, in the vocabulary the backup
    /// step already speaks, so the launch sequence's existing sentence for it is
    /// the one Dan reads (L11). Driven against a path that cannot hold a
    /// directory: an ordinary FILE where the data directory should be.
    @Test("a preparation that cannot create the directories refuses by name")
    func aPreparationThatCannotRunRefuses() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ovation-prepare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let notADirectory = root.appendingPathComponent("Ovation")
        try Data("a file standing where the data directory should be".utf8)
            .write(to: notADirectory)

        #expect(throws: BackupError.self) {
            try DataDirectory.prepare(notADirectory)
        }
    }

    /// THE ONE REQUIRED FILE NOBODY WRITES ON A CLEAN INSTALL.
    ///
    /// `problems.jsonl` is appended to when the FIRST problem is raised
    /// (`AppendOnlyLineFile.append`), so an installation that has had nothing go
    /// wrong legitimately has no file, exactly like the export run log and the
    /// write ahead log beside it. Requiring it refuses every healthy backup until
    /// something breaks, which is the wrong way round.
    ///
    /// It is NOT answered by creating an empty file: for a journal, absent and
    /// empty are one fact, and manufacturing the file to satisfy a check would be
    /// a green tick over a member nobody wrote (L98).
    @Test("a data directory with no problems journal is still backable up")
    func aCleanInstallHasNoJournalAndBacksUpAnyway() throws {
        let world = try World(withProblemsJournal: false)

        try DataDirectory.prepare(world.dataDirectory)

        let archive = try world.service.takeBackup(now: world.instant)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    // MARK: the fixture

    /// A data directory holding ONLY what something in the app actually writes:
    /// the store, its version marker, and the problems journal when there has
    /// been a problem. Deliberately no `documents` and no `custody`, because
    /// furnishing those by hand is what hid ovation#222.
    private struct World {
        let root: URL
        let dataDirectory: URL
        let backupsDirectory: URL
        let service: BackupService
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)

        init(withProblemsJournal: Bool = true) throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("ovation-datadir-\(UUID().uuidString)", isDirectory: true)
            dataDirectory = root.appendingPathComponent("Ovation", isDirectory: true)
            backupsDirectory = root.appendingPathComponent("Backups", isDirectory: true)

            let manager = FileManager.default
            try manager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try manager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

            // The store and its marker, which by the time any backup is attempted
            // are both there: the launch sequence skips the backup entirely when
            // there is no store file, and writes the marker immediately after the
            // open that establishes it.
            try Data("a fabricated store".utf8)
                .write(to: dataDirectory.appendingPathComponent("Ovation.store"))
            try Data("1.0.0\n".utf8)
                .write(to: dataDirectory.appendingPathComponent("Ovation.store.version"))
            if withProblemsJournal {
                try Data("{\"action\":\"raised\"}\n".utf8)
                    .write(to: dataDirectory.appendingPathComponent("problems.jsonl"))
            }

            service = BackupService(dataDirectory: dataDirectory,
                                    backupsDirectory: backupsDirectory,
                                    keep: 3,
                                    referencedDocuments: { [] })
        }
    }
}
