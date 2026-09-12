import Foundation
import SQLite3
import SwiftData
import Testing

/// Plan 1.2, ovation#88. The four steps in order: identify, checkpoint, back up,
/// then open.
///
/// WHY A SEQUENCE RATHER THAN FOUR CALLS. ovation#52 built the identify step and
/// ovation#57 built the backup step, and both closed with nothing running them,
/// so `StoreSchemaGuard` was written, tested, and called by NOTHING. A refusal
/// that runs nowhere is not a safeguard, and every check in it read as one
/// (L3, L98). The ordering is the requirement: each step exists to protect the
/// one after it, so a sequence that runs them in the wrong order, or that
/// carries on past a refusal, has the parts and none of the protection.
@MainActor
struct StoreLaunchSequenceTests {

    // MARK: the order is the requirement

    @Test("a clean launch runs all four steps, in order, and opens")
    func theHappyPathRunsEverything() throws {
        let world = try World()

        let outcome = world.sequence.run(now: world.instant)

        #expect(outcome == .opened)
        #expect(world.recorder.steps == ["identify", "checkpoint", "prepare", "backup", "open", "version", "seed", "import-clients", "export-notices"])
        #expect(world.store.open.isEmpty)
    }

    @Test("a foreign store REFUSES, and nothing after the identify step runs")
    func aForeignStoreStopsTheSequence() throws {
        // The failure the guard exists for, and the reason the order matters.
        // Core Data does not throw on a foreign file: it creates its missing
        // tables inside whatever it is handed and opens what looks like an empty
        // store, destroying the other app's data. Checkpointing or backing up
        // first would also be writing to a file that is not ours.
        let world = try World()
        try world.writeForeignStore()

        let outcome = world.sequence.run(now: world.instant)

        guard case .refused = outcome else {
            Issue.record("a foreign store was not refused, it returned \(outcome)")
            return
        }
        #expect(world.recorder.steps == ["identify"])
        #expect(world.store.open.contains { $0.kind == .foreignStore })
    }

    @Test("the refusal says what was found and that nothing was touched")
    func theRefusalIsSpecific() throws {
        let world = try World()
        try world.writeForeignStore()

        _ = world.sequence.run(now: world.instant)

        let problem = try #require(world.store.open.first { $0.kind == .foreignStore })
        // A message may claim only what its check actually measured (L11), and
        // the claim that nothing was touched is only true because the sequence
        // stops here rather than after the backup.
        #expect(problem.sentence.contains("Nothing has been opened or changed."))
    }

    @Test("a checkpoint that could not complete stops the sequence BEFORE the backup")
    func aFailedCheckpointStopsTheBackup() throws {
        // This is the whole reason the checkpoint sits where it does. Backing up
        // a store whose log still holds the rows produces an archive that
        // restores an empty database and verifies clean, so carrying on past a
        // failed checkpoint would manufacture exactly the reassuring corrupt
        // backup the verification cannot see (L63).
        let world = try World(checkpoint: { _ in .failed(detail: "a reader is holding it open") })

        let outcome = world.sequence.run(now: world.instant)

        guard case .refused = outcome else {
            Issue.record("a failed checkpoint did not stop the sequence, it returned \(outcome)")
            return
        }
        #expect(world.recorder.steps == ["identify", "checkpoint"])
        #expect(!world.recorder.steps.contains("backup"))
    }

    @Test("a first launch with no store yet checkpoints nothing and still opens")
    func aFirstLaunchIsOrdinary() throws {
        // A fresh install has no store. Treating that as a failed checkpoint
        // would raise a problem on every first run, which is a guard firing on
        // the commonest case rather than the dangerous one (L11).
        let world = try World(withStore: false)

        let outcome = world.sequence.run(now: world.instant)

        #expect(outcome == .opened)
        #expect(world.store.open.isEmpty)
    }

    @Test("a first launch with no store yet does not attempt a backup at all")
    func aFirstLaunchDoesNotBackUp() throws {
        // ovation#137. `Ovation.store` is a REQUIRED member, so a backup taken
        // before the store exists throws `requiredMemberMissing` and the sequence
        // raises "the backup was refused because Ovation.store is missing" about
        // a database that has simply never been created. That fires on the one
        // launch where a person is most likely to conclude the app is broken.
        //
        // A first launch has nothing to back up, which is a state rather than a
        // failure, so the step does not run. The distinction comes from the
        // CHECKPOINT's own `noStoreFile`, the measurement the sequence has
        // already taken, rather than from a second existence check that could
        // disagree with it (L70).
        //
        // The backup here throws the real error, so a sequence that still called
        // it would fail this rather than pass on a lenient seam.
        let world = try World(withStore: false,
                              backup: { _ in throw BackupError.requiredMemberMissing("Ovation.store") })

        let outcome = world.sequence.run(now: world.instant)

        #expect(outcome == .opened)
        #expect(!world.recorder.steps.contains("backup"))
        #expect(world.recorder.steps == ["identify", "checkpoint", "open", "version", "seed", "import-clients", "export-notices"])
        #expect(world.store.open.isEmpty)
    }

    @Test("a store that IS there and cannot be backed up still says so")
    func aMissingMemberBesideAStoreIsStillRaised() throws {
        // The positive control for the test above, and the case it must not
        // swallow. A required member missing while the store is present is the
        // genuinely alarming one: something was deleted from the data folder.
        // Without this, a change that simply stopped backing up would pass
        // (L159, L98).
        let world = try World(backup: { _ in throw BackupError.requiredMemberMissing("documents") })

        _ = world.sequence.run(now: world.instant)

        #expect(world.recorder.steps.contains("backup"))
        // RETARGETED IN ovation#229, NOT DELETED. This asserted `.backupFailed`
        // for every backup failure, which was the defect: one kind meant one
        // record whose sentence was whichever condition spoke last (L53, L430).
        // The claim is unchanged; the kind it names is the one that now carries
        // this cause.
        let problem = try #require(world.store.open.first { $0.kind == .backupCouldNotBeWritten })
        #expect(problem.sentence.contains("documents"))
    }

    // MARK: a failed backup is reported, and does not lock Dan out

    @Test("a backup that fails is RAISED but the app still opens")
    func aFailedBackupIsReportedNotFatal() throws {
        // Deliberate, and the reason is stated because the opposite is also
        // defensible. Refusing to open would leave Dan unable to invoice
        // because a folder on a Synology was unreachable, which is a worse
        // failure than the one being guarded against. So it is reported.
        //
        // This becomes a REFUSAL once ovation#105 can say whether opening would
        // run a migration, because that is the case where opening without a
        // backup can lose data rather than merely leave it unprotected.
        let world = try World(backup: { _ in throw BackupError.couldNotWrite("Backups") })

        let outcome = world.sequence.run(now: world.instant)

        #expect(outcome == .opened)
        // RETARGETED IN ovation#229, NOT DELETED. This asserted `.backupFailed`
        // for every backup failure, which was the defect: one kind meant one
        // record whose sentence was whichever condition spoke last (L53, L430).
        // The claim is unchanged; the kind it names is the one that now carries
        // this cause.
        #expect(world.store.open.contains { $0.kind == .backupCouldNotBeWritten })
        #expect(world.recorder.steps == ["identify", "checkpoint", "prepare", "backup", "open", "version", "seed", "import-clients", "export-notices"])
    }

    @Test("the backup failure names which half failed")
    func theBackupFailureNamesItsHalf() throws {
        // ovation#87 asks for two labels, not one: an archive that could not be
        // WRITTEN and one that was written and did not VERIFY are different
        // failures needing different sentences (L11).
        let world = try World(backup: { _ in throw BackupError.couldNotWrite("Backups") })

        _ = world.sequence.run(now: world.instant)

        // RETARGETED IN ovation#229, NOT DELETED. This asserted `.backupFailed`
        // for every backup failure, which was the defect: one kind meant one
        // record whose sentence was whichever condition spoke last (L53, L430).
        // The claim is unchanged; the kind it names is the one that now carries
        // this cause.
        let problem = try #require(world.store.open.first { $0.kind == .backupCouldNotBeWritten })
        #expect(problem.sentence.lowercased().contains("could not be written"))
    }

    // MARK: one kind per backup condition (ovation#229)

    /// `ProblemsStore.raise` keys a record on kind PLUS subject and OVERWRITES
    /// its sentence, so several backup conditions under one kind were ONE record
    /// whose text was whichever spoke last. Two backup conditions can be true in
    /// the same launch, and the second silently erased the first (L53, L260).
    /// Four sentences under one kind satisfies L11 and is not enough.
    @Test("an archive that could not be written and one that did not verify are different kinds")
    func theTwoBackupFailuresAreDifferentKinds() throws {
        let couldNotWrite = try World(backup: { _ in
            throw BackupError.couldNotWrite("/Volumes/Backups")
        })
        _ = couldNotWrite.sequence.run(now: couldNotWrite.instant)

        let didNotVerify = try World(backup: { _ in
            throw BackupError.verificationFailed([])
        })
        _ = didNotVerify.sequence.run(now: didNotVerify.instant)

        #expect(couldNotWrite.store.open.contains { $0.kind == .backupCouldNotBeWritten })
        #expect(!couldNotWrite.store.open.contains { $0.kind == .backupFailed })
        #expect(didNotVerify.store.open.contains { $0.kind == .backupFailed })
        #expect(!didNotVerify.store.open.contains { $0.kind == .backupCouldNotBeWritten })
    }

    /// THE CASE THAT PROVES IT MATTERS. Two conditions raised in one launch must
    /// leave TWO open problems, not one. Under a single kind the second call
    /// overwrote the first and the panel showed one card.
    @Test("two backup conditions in one launch leave two problems, not one")
    func twoConditionsLeaveTwoProblems() throws {
        let world = try World(backup: { _ in throw BackupError.couldNotWrite("/Volumes/Backups") })

        _ = world.sequence.run(now: world.instant)
        // The second condition, raised the way a later phase will raise it.
        _ = world.store.raise(kind: .backupsAreStale, subject: world.storeURL.path,
                              sentence: "The newest archive is older than your data.",
                              now: world.instant)

        let backupProblems = world.store.open.filter { $0.kind.rawValue.hasPrefix("backup.") }
        #expect(backupProblems.count == 2)
    }

    /// A REFUSAL MAY CLAIM ONLY WHAT IT MEASURED (L11). `BackupService` threw
    /// `couldNotWrite(path)` with the underlying error discarded, so a volume that
    /// is gone, a disk that is full and a permission macOS withdrew rendered one
    /// sentence. Those are the three likeliest causes on this configuration and
    /// they need three different actions.
    @Test("a write failure carries the cause it was given")
    func aWriteFailureCarriesItsCause() throws {
        let world = try World(backup: { _ in
            throw BackupError.couldNotWrite("/Volumes/Backups: the volume is not mounted")
        })

        _ = world.sequence.run(now: world.instant)

        let problem = try #require(world.store.open.first { $0.kind == .backupCouldNotBeWritten })
        #expect(problem.sentence.contains("the volume is not mounted"))
    }

    /// THE STANDING CONDITION HAS AN EXIT. `ProblemsStore` never retracts on its
    /// own, `raise` clears `acknowledgedAt`, and the presenter shows the oldest
    /// first, so a condition re-raised on every launch sits at the head of the
    /// queue for ever and pushes every more urgent notice behind it. It is
    /// resolved when a folder is chosen.
    @Test("the standing no folder condition is resolved once a folder exists")
    func theStandingConditionIsResolvable() throws {
        let world = try World()
        let raised = world.store.raise(
            kind: .backupFolderNotChosen, subject: "backups",
            sentence: "No backup folder has been chosen yet.", now: world.instant)
        #expect(world.store.open.contains { $0.id == raised.id })

        let resolved = world.store.resolve(raised.id,
                                           because: "a backup folder was chosen",
                                           now: world.instant)

        #expect(resolved)
        #expect(!world.store.open.contains { $0.id == raised.id })
    }

    /// A FOLDER THAT COULD NOT BE READ IS REPORTED (ovation#228). It is not a
    /// skip: "there is no archive for today" and "I could not look" are the same
    /// silence otherwise, and the silence is the one that means no backups are
    /// happening at all (L98).
    @Test("a backup folder that cannot be read is reported and the app still opens")
    func anUnreachableFolderIsReported() throws {
        let world = try World(backup: { _ in
            .folderUnreachable("/Volumes/Backups: the volume is not mounted")
        })

        let outcome = world.sequence.run(now: world.instant)

        #expect(outcome == .opened)
        let problem = try #require(world.store.open.first { $0.kind == .backupCouldNotBeWritten })
        #expect(problem.sentence.contains("the volume is not mounted"))
    }

    /// A SKIP SAYS NOTHING, which is the commonest case: a second launch on the
    /// same day. A notice there is one Dan learns to click past, and then the
    /// ones that matter go past with it (L36).
    @Test("a backup already taken today raises nothing")
    func aSkipRaisesNothing() throws {
        let world = try World(backup: { _ in
            .alreadyTakenToday(URL(fileURLWithPath: "/dev/null"))
        })

        _ = world.sequence.run(now: world.instant)

        #expect(!world.store.open.contains { $0.kind.rawValue.hasPrefix("backup.") })
    }

    // MARK: what is true about the export is said at launch (ovation#64)

    @Test("an export notice is raised through the one launch presenter")
    func exportNoticesReachTheProblemsStore() throws {
        // Both notices reach Dan through this presenter rather than as
        // independent alerts (L242), and they are derived at launch rather than
        // stored as a conclusion (L175).
        let world = try World(exportNotices: { _, _ in [.stale(days: 41)] })

        let outcome = world.sequence.run(now: world.instant)

        #expect(outcome == .opened)
        let problem = try #require(world.store.open.first { $0.kind == .exportStale })
        #expect(problem.sentence.contains("41 days"))
    }

    @Test("with nothing to say it raises nothing, because that is every ordinary launch")
    func noExportNoticeRaisesNothing() throws {
        let world = try World(exportNotices: { _, _ in [] })

        _ = world.sequence.run(now: world.instant)

        #expect(world.store.open.isEmpty)
    }

    @Test("the notices are asked for AFTER the store opened, because one is about its contents")
    func exportNoticesComeAfterTheOpen() throws {
        let world = try World(exportNotices: { _, _ in [] })

        _ = world.sequence.run(now: world.instant)

        let steps = world.recorder.steps
        let open = try #require(steps.firstIndex(of: "open"))
        let notices = try #require(steps.firstIndex(of: "export-notices"))
        #expect(open < notices)
    }

    @Test("a store refused at IDENTIFY is never asked about its export history")
    func arefusedStoreRaisesNoExportNotice() throws {
        // Asking would mean reading a store the sequence has just refused to
        // open, and answering "nobody has exported" about a database Ovation
        // could not identify is a claim the check never measured (L11).
        let world = try World(exportNotices: { _, _ in [.stale(days: 99)] })
        try world.writeForeignStore()

        _ = world.sequence.run(now: world.instant)

        #expect(!world.recorder.steps.contains("export-notices"))
        #expect(world.store.open.allSatisfy { $0.kind != .exportStale })
    }

    // MARK: fixtures

    /// A real store directory, a recorder that says which steps ran, and seams
    /// for the checkpoint and the backup so a test never has to make a real one
    /// fail by damaging the machine.
    @MainActor
    // MARK: recording the version, which is what makes the next launch safe

    @Test("the version is recorded straight after the open that established it")
    func theversionIsRecordedAfterOpening() throws {
        // ovation#116. It must be written by whatever ESTABLISHES the version
        // rather than by a surface that happens to notice (L319), and it goes
        // before the seed so a store that opened is marked even if seeding fails.
        let world = try World()

        _ = world.sequence.run(now: world.instant)

        let steps = world.recorder.steps
        // REQUIRED RATHER THAN FORCE UNWRAPPED. A `!` here does not fail the
        // test, it TRAPS: the whole test process dies, the run reports exit 65
        // with no failing test named, and the steps that did run are lost with
        // it. That happened on CI on 2026-09-09, and the diagnosis cost a push
        // because the one thing that would have said which step was missing was
        // the thing the trap destroyed.
        let versionAt = try #require(steps.firstIndex(of: "version"),
                                     Comment(rawValue: "steps were \(steps)"))
        let openAt = try #require(steps.firstIndex(of: "open"),
                                  Comment(rawValue: "steps were \(steps)"))
        let seedAt = try #require(steps.firstIndex(of: "seed"),
                                  Comment(rawValue: "steps were \(steps)"))
        #expect(versionAt > openAt)
        #expect(versionAt < seedAt)
    }

    @Test("a store refused at IDENTIFY has no version recorded")
    func arefusedLaunchRecordsNoVersion() throws {
        // Writing beside a file that is not ours is still writing beside somebody
        // else's file.
        let world = try World()
        try world.writeForeignStore()

        _ = world.sequence.run(now: world.instant)

        #expect(!world.recorder.steps.contains("version"))
    }

    @Test("a version that could not be written is RAISED and the app still opens")
    func afailedVersionRecordIsReported() throws {
        // The store is open and correct. What is lost is the ability to refuse a
        // downgrade NEXT time, which is worth saying and is not worth refusing to
        // open over (L10).
        let world = try World(recordVersion: { _ in throw VersionFailure.refused })

        let outcome = world.sequence.run(now: world.instant)

        #expect(outcome == .opened)
        let problem = try #require(world.store.open.first {
            (p: Problem) in p.kind == ProblemKind.storeVersionNotRecorded })
        #expect(problem.sentence.contains("older build"))
        #expect(problem.sentence.contains("opened normally"))
    }

    private enum VersionFailure: Error { case refused }

    // MARK: seeding, which happens AFTER the store is open

    @Test("the starting service types are seeded, and only after the store opened")
    func seedingRunsLast() throws {
        // ovation#107. It cannot run before `open`, because there is no container
        // to write into until then, and it must not run before the BACKUP either:
        // seeding writes, and a write before the backup is a write the backup
        // does not carry.
        let world = try World()

        _ = world.sequence.run(now: world.instant)

        // Asserted as the two ORDERINGS this test is about rather than as "seed
        // is last", which was only ever a proxy for them: ovation#64 added a step
        // after it that writes nothing, and the proxy went red for a reason that
        // has nothing to do with what this test defends (L430).
        let steps = world.recorder.steps
        let seedAt = try #require(steps.firstIndex(of: "seed"),
                                  Comment(rawValue: "steps were \(steps)"))
        let openAt = try #require(steps.firstIndex(of: "open"),
                                  Comment(rawValue: "steps were \(steps)"))
        let backupAt = try #require(steps.firstIndex(of: "backup"),
                                    Comment(rawValue: "steps were \(steps)"))
        #expect(seedAt > openAt)
        #expect(seedAt > backupAt)
    }

    @Test("a store that refuses at IDENTIFY is never seeded")
    func arefusedLaunchSeedsNothing() throws {
        // Seeding is a WRITE, and the whole reason identify comes first is that
        // every later step writes. A foreign file must not gain three service
        // types.
        let world = try World()
        try world.writeForeignStore()

        _ = world.sequence.run(now: world.instant)

        #expect(!world.recorder.steps.contains("seed"))
    }

    @Test("a seed that fails is RAISED and the app still opens")
    func afailedSeedIsReportedRatherThanFatal() throws {
        // Same choice as the backup, for a weaker reason and so a weaker
        // consequence: an empty service type picker is an annoyance Dan can fix
        // by typing a name, where refusing to open would leave him unable to
        // invoice at all. It is still SAID, because a picker that is silently
        // empty on a fresh install reads as a product with no service types
        // rather than as a step that failed (L10).
        let world = try World(seed: { _ in throw SeedFailure.refused })

        let outcome = world.sequence.run(now: world.instant)

        #expect(outcome == .opened)
        let problem = try #require(
            world.store.open.first { (p: Problem) in p.kind == ProblemKind.startingDataNotSeeded })
        #expect(problem.sentence.contains("service type"))
        #expect(problem.sentence.contains("opened anyway"))
    }

    @Test("a launch that seeded nothing raises nothing, because that is the ordinary case")
    func asecondLaunchIsQuiet() throws {
        // Every launch after the first seeds zero, and a notice on that would
        // fire forever on the commonest case.
        let world = try World(seed: { _ in 0 })

        _ = world.sequence.run(now: world.instant)

        #expect(world.store.open.isEmpty)
    }

    private enum SeedFailure: Error { case refused }

    private struct World {
        let directory: URL
        let storeURL: URL
        let store: ProblemsStore
        let recorder: Recorder
        let sequence: StoreLaunchSequence
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)

        final class Recorder: @unchecked Sendable {
            private(set) var steps: [String] = []
            func record(_ step: String) { steps.append(step) }
        }

        @MainActor
        init(withStore: Bool = true,
             checkpoint: (@Sendable (URL) -> StoreCheckpoint.Outcome)? = nil,
             backup: (@Sendable (Date) throws -> BackupService.Attempt)? = nil,
             prepareDataDirectory: (@Sendable () throws -> Void)? = nil,
             seed: (@Sendable (ModelContainer) throws -> Int)? = nil,
             recordVersion: (@Sendable (URL) throws -> Void)? = nil,
             exportNotices: (@Sendable (ModelContainer, Date) -> [ExportNotice])? = nil,
             importClients: (@Sendable (ModelContainer) -> [ClientImportNotice])? = nil) throws {
            directory = URL.temporaryDirectory
                .appending(path: "ovation-launch-\(UUID().uuidString)",
                           directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            storeURL = directory.appending(path: "Ovation.store")
            if withStore {
                let schema = Schema([Client.self])
                let container = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(schema: schema, url: storeURL))
                let context = ModelContext(container)
                context.insert(Client(name: "Ashgrove Chamber Players", taxStatus: .neverRecorded))
                try context.save()

                // AND WAIT UNTIL THE FIXTURE'S OWN WRITER HAS LET GO.
                //
                // Measured on CI, 2026-09-09 (ovation#159): the sequence refused
                // at CHECKPOINT with "database is locked", because the container
                // above still held the file when the checkpoint ran. It passes
                // here every time and failed twice on a runner, which is what a
                // window that only opens under load looks like.
                //
                // WAITING ON THE CONDITION, NOT ON A DURATION. A fixed sleep here
                // would be an assertion about how busy the machine is, and it
                // would be the suite's slowest test on a quiet one (L290, L524).
                // The bound exists so a genuinely stuck file fails the test rather
                // than hanging it (L110).
                var attempts = 0
                while attempts < 200, StoreCheckpoint.run(storeURL: storeURL) != .checkpointed {
                    attempts += 1
                }
            }

            store = ProblemsStore(journal: InMemoryProblemsJournal())
            let recorder = Recorder()
            self.recorder = recorder

            sequence = StoreLaunchSequence(
                storeURL: storeURL,
                problems: store,
                checkpoint: { url in
                    recorder.record("checkpoint")
                    return checkpoint?(url) ?? StoreCheckpoint.run(storeURL: url)
                },
                prepareDataDirectory: {
                    recorder.record("prepare")
                    if let prepareDataDirectory { return try prepareDataDirectory() }
                },
                takeBackup: { now in
                    recorder.record("backup")
                    if let backup { return try backup(now) }
                    return .taken(URL(fileURLWithPath: "/dev/null"))
                },
                openContainer: { url in
                    recorder.record("open")
                    let schema = Schema([Client.self])
                    return try ModelContainer(
                        for: schema,
                        configurations: ModelConfiguration(schema: schema, url: url))
                },
                identify: { url in
                    recorder.record("identify")
                    return StoreSchemaGuard.inspect(
                        storeURL: url,
                        ownEntityTables: StoreSchemaGuard.entityTableNames(
                            for: Schema([Client.self])),
                        runningVersion: Schema.Version(1, 0, 0))
                },
                seed: { container in
                    recorder.record("seed")
                    if let seed { return try seed(container) }
                    return try ServiceTypeSeed.seedIfEmpty(ModelContext(container))
                },
                recordVersion: { url in
                    recorder.record("version")
                    if let recordVersion { return try recordVersion(url) }
                    try StoreVersionMarker.write(Schema.Version(1, 0, 0), besideStoreAt: url)
                },
                exportNotices: { container, now in
                    recorder.record("export-notices")
                    return exportNotices?(container, now) ?? []
                },
                importClients: { container in
                    recorder.record("import-clients")
                    return importClients?(container) ?? []
                })
        }

        /// A database that is plainly somebody else's: real SQLite, carrying
        /// tables Ovation has never heard of.
        ///
        /// EVERY STATEMENT IS CHECKED. A first version renamed Ovation's own
        /// table and ignored the result, so when the rename matched nothing the
        /// fixture silently produced Ovation's own store and the test failed
        /// against a case it had never built (L100).
        func writeForeignStore() throws {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(
                at: directory.appending(path: "Ovation.store-wal"))
            try? FileManager.default.removeItem(
                at: directory.appending(path: "Ovation.store-shm"))

            var handle: OpaquePointer?
            guard sqlite3_open_v2(storeURL.path, &handle,
                                  SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
                  let handle else {
                sqlite3_close(handle)
                throw FixtureFailure.couldNotBuildForeignStore
            }
            defer { sqlite3_close(handle) }
            for table in ["ZBOOKING", "ZPROSPECT"] {
                guard sqlite3_exec(handle, "CREATE TABLE \(table) (Z_PK INTEGER PRIMARY KEY);",
                                   nil, nil, nil) == SQLITE_OK else {
                    throw FixtureFailure.couldNotBuildForeignStore
                }
            }
        }
    }

    enum FixtureFailure: Error {
        case couldNotBuildForeignStore
    }
    // MARK: the data directory is prepared before the backup (ovation#222)

    /// BUILT IS NOT WIRED (L3). `DataDirectory.prepare` makes the directories
    /// `BackupPlan` requires, and until something ran it a backup of the real
    /// data directory refused on its first member.
    @Test("the launch prepares the data directory before it backs up")
    func theLaunchPreparesBeforeBackingUp() throws {
        let world = try World()

        world.sequence.run(now: world.instant)

        let steps = world.recorder.steps
        let prepareIndex = try #require(steps.firstIndex(of: "prepare"))
        let backupIndex = try #require(steps.firstIndex(of: "backup"))
        #expect(prepareIndex < backupIndex)
    }

    /// AFTER IDENTIFY AND CHECKPOINT, never before them. The identify step's
    /// refusal says "Nothing has been opened or changed", and making directories
    /// beside a store that turned out to be somebody else's would make that
    /// sentence false (L11).
    @Test("a foreign store is refused before anything is created beside it")
    func aForeignStoreIsRefusedBeforePreparing() throws {
        let world = try World()
        try world.writeForeignStore()

        world.sequence.run(now: world.instant)

        #expect(!world.recorder.steps.contains("prepare"))
    }

    /// A PREPARATION THAT FAILED MEANS NO BACKUP, so the backup is not attempted
    /// after it: attempting it would fail for the same cause and raise a second
    /// problem under the same kind and subject, which `ProblemsStore.raise`
    /// merges into one whose sentence is whichever spoke last (L53).
    @Test("a preparation that fails stops the backup and says so once")
    func aFailedPreparationIsReportedOnce() throws {
        let world = try World(prepareDataDirectory: {
            throw BackupError.couldNotWrite("/nowhere/documents")
        })

        let outcome = world.sequence.run(now: world.instant)

        #expect(!world.recorder.steps.contains("backup"))
        let raised = world.store.open.filter { $0.kind == .backupCouldNotBeWritten }
        #expect(raised.count == 1)
        #expect(raised.first?.sentence.contains("/nowhere/documents") == true)
        // THE APP STILL OPENS. A missing backup is a thing to fix; refusing to
        // open would leave Dan unable to invoice, which is the same weighing the
        // seed and import steps already made.
        #expect(outcome == .opened)
    }

    // MARK: the opened store is handed on (ovation#162)

    @Test("a sequence that opened hands the store it opened to whoever needs it")
    func handsOnTheOpenedStore() throws {
        // A control that runs after launch cannot open its own container: two
        // containers over one file are two writers, which is what the second
        // instance check exists to prevent (ovation#84). So the one already open
        // is handed on, and this is what proves it happens at all (L3).
        let world = try World()
        // A counter the @Sendable hook can raise. The existing Recorder in this
        // file is the same shape and for the same reason.
        final class Box: @unchecked Sendable { var count = 0 }
        let box = Box()
        var sequence = world.sequence
        sequence.onOpened = { _ in box.count += 1 }

        #expect(sequence.run(now: world.instant) == .opened)
        #expect(box.count == 1)
    }

    @Test("a sequence that refused hands on nothing, because nothing opened")
    func handsOnNothingWhenItRefused() throws {
        // Handing on a store the sequence refused to open would give the control
        // a container nobody checked, which is the opposite of what the sequence
        // is for (L98).
        let world = try World()
        try world.writeForeignStore()
        // A counter the @Sendable hook can raise. The existing Recorder in this
        // file is the same shape and for the same reason.
        final class Box: @unchecked Sendable { var count = 0 }
        let box = Box()
        var sequence = world.sequence
        sequence.onOpened = { _ in box.count += 1 }

        #expect(sequence.run(now: world.instant) != .opened)
        #expect(box.count == 0)
    }

    // MARK: the client import (ovation#208)

    /// BUILT IS NOT WIRED (L3). ovation#52 and ovation#57 both closed with nothing
    /// running them, which is why this whole sequence exists, so the import gets
    /// the same assertion: that the launch actually calls it.
    @Test("the launch runs the client import")
    func theLaunchRunsTheClientImport() throws {
        let world = try World()
        world.sequence.run(now: world.instant)
        #expect(world.recorder.steps.contains("import-clients"))
    }

    /// IT RUNS AFTER THE BACKUP, and that is the requirement rather than a detail:
    /// the import WRITES, and a write made before the backup is a write the backup
    /// does not carry (L5). Same reason the seed runs where it does.
    @Test("the import runs after the store is open and backed up")
    func theImportRunsAfterTheBackup() throws {
        let world = try World()
        world.sequence.run(now: world.instant)
        let steps = world.recorder.steps
        let importIndex = try #require(steps.firstIndex(of: "import-clients"))
        let backupIndex = try #require(steps.firstIndex(of: "backup"))
        let openIndex = try #require(steps.firstIndex(of: "open"))
        #expect(importIndex > backupIndex)
        #expect(importIndex > openIndex)
    }

    @Test("what the import has to say reaches Dan through the one presenter")
    func importNoticesAreRaised() throws {
        let world = try World(importClients: { _ in [.broughtAcross(count: 31)] })
        world.sequence.run(now: world.instant)
        #expect(world.store.open.contains { $0.kind == .clientImportBroughtClientsAcross })
    }

    /// AN IMPORT THAT FOUND NOTHING TO SAY RAISES NOTHING, which is every launch
    /// after the first. A notice on the commonest case is one Dan learns to click
    /// past, and then the ones that matter go past with it (L36).
    @Test("an import with nothing to say raises nothing")
    func aQuietImportRaisesNothing() throws {
        let world = try World(importClients: { _ in [] })
        world.sequence.run(now: world.instant)
        #expect(!world.store.open.contains { $0.kind == .clientImportBroughtClientsAcross })
        #expect(!world.store.open.contains { $0.kind == .clientImportNeedsAnAnswer })
    }

    /// THE LAUNCH STILL OPENS. A roster that could not be refreshed is an
    /// annoyance; refusing to open would leave Dan unable to invoice at all, which
    /// is the same weighing the seed step already made, for the same reason.
    @Test("an import that cannot read the export still lets the app open")
    func aFailedImportStillOpens() throws {
        let world = try World(importClients: { _ in
            [.exportMissing(file: "downbeat-export.json")]
        })
        #expect(world.sequence.run(now: world.instant) == .opened)
        #expect(world.store.open.contains { $0.kind == .clientImportExportMissing })
    }
}
