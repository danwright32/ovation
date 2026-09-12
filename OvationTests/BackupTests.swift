import Foundation
import Testing

/// Plan 1.8, ovation#57. Dated backups, verified by enumerating every referenced
/// document rather than by asking whether anything opens.
struct BackupTests {

    // MARK: taking one

    @Test("a backup copies every member that exists and records the ones that do not")
    func theArchiveSaysWhatItHolds() throws {
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)

        let manifest = try world.manifest(of: archive)
        #expect(manifest.dayKey == BusinessCalendar.dayKey(for: world.instant))

        let copied = manifest.members.filter { $0.status == .copied }.map(\.path).sorted()
        #expect(copied == ["Ovation.store", "Ovation.store.version", "custody", "documents",
                           "problems.jsonl"])

        // An archive is HONEST about what it could not contain. A member nothing
        // has built yet is recorded with the issue that will build it, rather
        // than being silently absent (L98).
        //
        // TWO, AND THE COUNT HAS COME DOWN TWICE FOR TWO DIFFERENT REASONS.
        // `referral-ledger.jsonl` left the plan when ovation#38 shipped, because
        // the ledger is a model INSIDE the store rather than a file beside it, so
        // the file it named will never exist: a member whose issue is closed
        // reads as work outstanding forever and makes every archive report itself
        // short of a file nothing writes. `export-runs.jsonl` left it when
        // ovation#64 BUILT it, and moved to the absent-for-a-good-reason list
        // below rather than out of the plan, because a fresh installation has
        // never run an export and legitimately has no file.
        let pending = manifest.members.filter { $0.status == .notYetBuilt }
        #expect(pending.count == 2)
        #expect(!pending.contains { $0.path.contains("referral") })
        #expect(pending.allSatisfy { $0.issue?.hasPrefix("ovation#") == true })

        // And a member that is legitimately absent says SO, in its own word,
        // rather than borrowing the one that means nobody has built it (L11).
        // The two need opposite responses: one is normal, the other is a
        // reminder that the archive is short.
        let absent = manifest.members.filter { $0.status == .legitimatelyAbsent }
        #expect(absent.map(\.path).sorted()
                == ["Ovation.store-shm", "Ovation.store-wal", "export-runs.jsonl"])
        #expect(absent.allSatisfy { $0.issue == nil })
    }

    @Test("an archive with no database is REFUSED, not verified clean")
    func aMissingStoreRefuses() throws {
        // ovation#88. The store holds the only copy of every invoice, and
        // BackupPlan went on listing it as not yet built long after ovation#60
        // shipped it. The consequence was not that archives lacked it: the
        // staging step copies whatever exists. It was that the VERIFICATION
        // only checks members marked required, so a failed copy, or a backup
        // taken before the store existed, recorded it as not yet built and
        // verified clean. That is the exact shape BackupPlan's own header warns
        // about, in the file written to prevent it (L98, L63).
        let world = try World()
        try FileManager.default.removeItem(
            at: world.dataDirectory.appendingPathComponent("Ovation.store"))

        #expect(throws: BackupError.requiredMemberMissing("Ovation.store")) {
            try world.service.takeBackup(now: world.instant)
        }
    }

    @Test("a write ahead log that is absent because the store was checkpointed is not a failure")
    func anAbsentLogVerifiesClean() throws {
        // The other half of the same change, and the reason the log cannot
        // simply be required alongside the database. A checkpointed SQLite
        // store legitimately has no log beside it, so requiring one would
        // refuse every healthy backup, which is a guard failing in the
        // direction nobody expects.
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)

        let report = try world.service.verify(archive: archive)
        #expect(report.failures.isEmpty)
    }

    @Test("a write ahead log that IS there is carried, since it holds committed pages")
    func aPresentLogIsCarried() throws {
        // The pair only reconstructs the database if both halves travel. This
        // is what makes ovation#88's checkpoint the safe path rather than an
        // optimisation: without it, an archive can hold a store whose newest
        // pages are in a log that was never copied.
        let world = try World()
        try Data("fabricated log".utf8).write(
            to: world.dataDirectory.appendingPathComponent("Ovation.store-wal"))

        let archive = try world.service.takeBackup(now: world.instant)

        let manifest = try world.manifest(of: archive)
        let log = try #require(manifest.members.first { $0.path == "Ovation.store-wal" })
        #expect(log.status == .copied)
        #expect(FileManager.default.fileExists(
            atPath: archive.appendingPathComponent("Ovation.store-wal").path))
        #expect(try world.service.verify(archive: archive).failures.isEmpty)
    }

    @Test("the files land on disk, not only in the manifest")
    func theArchiveHoldsRealBytes() throws {
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)

        #expect(FileManager.default.fileExists(
            atPath: archive.appendingPathComponent("problems.jsonl").path))
        #expect(FileManager.default.fileExists(
            atPath: archive.appendingPathComponent("documents/\(world.receiptPath)").path))
        #expect(FileManager.default.fileExists(
            atPath: archive.appendingPathComponent("custody/note.txt").path))
    }

    @Test("a member that should be there and is not REFUSES the backup")
    func aMissingRequiredMemberRefuses() throws {
        // The whole reason the members are enumerated. Silently skipping one
        // gives an archive that reads as complete and fails in an audit.
        let world = try World()
        // THE SUBJECT CHANGED IN ovation#222, AND THE CLAIM DID NOT. This removed
        // `problems.jsonl`, which stopped being required: it is written when the
        // first problem is raised, so an installation where nothing has gone
        // wrong legitimately has none. The rule being asserted is unchanged, so
        // the case is retargeted rather than deleted (L430).
        //
        // `documents` IS THE RIGHT SUBJECT NOW, and it is the one that makes the
        // decision behind ovation#222 testable: the directory is CREATED at
        // launch rather than having its expectation softened, precisely so that
        // its absence once receipts exist still refuses instead of reading as
        // legitimate for ever (L63).
        try FileManager.default.removeItem(at: world.dataDirectory
            .appendingPathComponent("documents"))

        // ASSERTED BY NAME, not merely that something threw. Planting "skip the
        // missing member" left this green when it only checked for any error:
        // the archive was then refused a step later by the verification, for a
        // different reason, and the test could not tell the two apart (L140).
        #expect(throws: BackupError.requiredMemberMissing("documents")) {
            try world.service.takeBackup(now: world.instant)
        }
    }

    // MARK: verification enumerates, it does not merely open

    @Test("a backup verifies when every file it recorded is there and unchanged")
    func agoodArchiveVerifies() throws {
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)

        let report = try world.service.verify(archive: archive)
        #expect(report.isVerified)
        #expect(report.failures.isEmpty)
        #expect(report.filesChecked > 0)
    }

    @Test("a backup missing one receipt FAILS, even though everything opens")
    func aMissingDocumentFailsVerification() throws {
        // The failure this issue exists to prevent: a store that opens fine and
        // receipt files that are not there. Asking whether the database opens
        // cannot see it.
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)
        try FileManager.default.removeItem(
            at: archive.appendingPathComponent("documents/\(world.receiptPath)"))

        let report = try world.service.verify(archive: archive)
        #expect(!report.isVerified)
        #expect(report.failures.contains { $0.verdict == .absent })
    }

    @Test("a receipt whose bytes changed FAILS, at the same length")
    func aTamperedDocumentFailsVerification() throws {
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)
        let receipt = archive.appendingPathComponent("documents/\(world.receiptPath)")
        let original = try Data(contentsOf: receipt)
        let tampered = Data(String(repeating: "x", count: original.count).utf8)
        #expect(original.count == tampered.count)
        try tampered.write(to: receipt)

        let report = try world.service.verify(archive: archive)
        #expect(!report.isVerified)
        #expect(report.failures.contains { $0.verdict == .mismatch })
    }

    @Test("an archive with no manifest is refused, never treated as empty")
    func aManifestlessArchiveIsRefused() throws {
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)
        try FileManager.default.removeItem(
            at: archive.appendingPathComponent(BackupManifest.filename))

        #expect(throws: BackupError.self) { try world.service.verify(archive: archive) }
    }

    // MARK: the credential store must never be in there

    @Test("the token file is refused BY NAME before an archive is finished")
    func theTokenFileIsRefusedByName() throws {
        // Seen to fail by planting it in the staging set, which is the only way
        // to know the guard fires (L1, L19).
        let world = try World()
        try Data("{\"refresh_token\":\"fabricated\"}".utf8).write(
            to: world.dataDirectory.appendingPathComponent("gmail-tokens.json"))
        let archive = try world.service.takeBackup(now: world.instant)

        // It is not a member, so it is not copied. The verification says so
        // rather than trusting that.
        #expect(!FileManager.default.fileExists(
            atPath: archive.appendingPathComponent("gmail-tokens.json").path))
        #expect(try world.service.verify(archive: archive).isVerified)
    }

    @Test("a token copied under ANOTHER name is caught by its content")
    func theTokenFileIsRefusedByHash() throws {
        // A name check alone is satisfied by renaming the file, and the secret is
        // the bytes rather than the filename.
        let world = try World()
        let token = Data("{\"refresh_token\":\"fabricated\"}".utf8)
        let tokenURL = world.dataDirectory.appendingPathComponent("gmail-tokens.json")
        try token.write(to: tokenURL)

        let archive = try world.service.takeBackup(now: world.instant)
        // Somebody puts it in the archive wearing an innocent name.
        try token.write(to: archive.appendingPathComponent("custody/notes-backup.json"))

        let report = try world.service.verify(archive: archive,
                                              secrets: [DocumentStore.hash(of: token)])
        #expect(!report.isVerified)
        #expect(report.failures.contains { $0.verdict == .secretPresent })
    }

    @Test("with no secret to compare against, the check says it could not look")
    func aSecretCheckWithNoSecretsSaysSo() throws {
        // A guard handed nothing to look for examines nothing, and reporting
        // "clean" would be indistinguishable from having checked (L98).
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)

        let report = try world.service.verify(archive: archive, secrets: [])
        #expect(report.secretsChecked == 0)
        #expect(!report.secretCheckWasPossible)
    }

    // MARK: rotation

    /// RETARGETED IN ovation#227, NOT DELETED. This asserted "keep the newest N
    /// and evict the rest", which Dan reversed on 2026-09-11 in favour of
    /// fourteen by count plus the last archive of every calendar month. The claim
    /// that rotation evicts something is unchanged, so the case is aimed at the
    /// rule that now decides (L430).
    @Test("rotation keeps the newest and evicts the oldest")
    func rotationKeepsTheNewest() throws {
        let world = try World(dailyKeep: 2)
        let first = try world.service.takeBackup(now: world.instant)
        let second = try world.service.takeBackup(now: world.instant.addingTimeInterval(60))
        let third = try world.service.takeBackup(now: world.instant.addingTimeInterval(120))

        let remaining = try world.service.archives()
        // All three are in one calendar month, so the last of that month is the
        // third, which is also the newest: the monthly keeper protects nothing
        // extra here and the daily count decides.
        #expect(remaining.count == 2)
        #expect(remaining.contains(second))
        #expect(remaining.contains(third))
        #expect(!remaining.contains(first))
    }

    // MARK: fourteen by count, plus the last of each month (ovation#227)

    /// THE MONTHLY KEEPER IS THE LAST OF THE MONTH, and this is the case the
    /// original plan got backwards. The first archive of a month is taken before
    /// anything in that month has happened, so it holds the previous month's
    /// state: keeping it would delete every snapshot containing a month's own
    /// invoices and keep the one containing none of them (L334, L648).
    @Test("the archive kept from an older month is its last, not its first")
    func theMonthlyKeeperIsTheLastOfTheMonth() throws {
        let world = try World(dailyKeep: 1)
        world.plantArchive(named: "Ovation-backup-2026-03-02-090000")
        world.plantArchive(named: "Ovation-backup-2026-03-17-090000")
        world.plantArchive(named: "Ovation-backup-2026-03-28-090000")
        world.plantArchive(named: "Ovation-backup-2026-04-04-090000")

        let outcome = try world.service.rotate(now: world.april(10))

        #expect(outcome.deleted.sorted() == ["Ovation-backup-2026-03-02-090000",
                                             "Ovation-backup-2026-03-17-090000"])
        #expect(outcome.kept.contains("Ovation-backup-2026-03-28-090000"))
        #expect(outcome.kept.contains("Ovation-backup-2026-04-04-090000"))
    }

    /// FOURTEEN BY COUNT, NOT A WINDOW OF DAYS. Used three days a week, a
    /// fourteen day window keeps six archives while reporting that it satisfies
    /// fourteen (L63). Fifteen archives an hour apart are all within one day, and
    /// exactly one of them may go.
    @Test("fourteen archives survive by count however close together they are")
    func fourteenSurviveByCount() throws {
        let world = try World(dailyKeep: 14)
        for hour in 0..<15 {
            world.plantArchive(named: String(format: "Ovation-backup-2026-04-04-%02d0000", hour))
        }

        let outcome = try world.service.rotate(now: world.april(10))

        // The oldest goes; it is not the last of its month, because fourteen
        // later archives share that month.
        #expect(outcome.deleted == ["Ovation-backup-2026-04-04-000000"])
        #expect(outcome.kept.count == 14)
    }

    /// THE NEWEST IS NEVER DELETED, whatever the arithmetic says (L5). Driven
    /// with a keep of zero, which is the only way to ask the question.
    @Test("the newest archive survives even when nothing else would keep it")
    func theNewestAlwaysSurvives() throws {
        let world = try World(dailyKeep: 0)
        world.plantArchive(named: "Ovation-backup-2026-04-04-090000")

        let outcome = try world.service.rotate(now: world.april(10))

        #expect(outcome.deleted.isEmpty)
        #expect(outcome.kept == ["Ovation-backup-2026-04-04-090000"])
    }

    /// A NAME THAT IS NOT A DATE IS KEPT AND REPORTED, never deleted. A failed
    /// parse otherwise lands on the permissive side, and here that side is
    /// deletion (L50). A Synology conflict copy is exactly this shape.
    @Test("an archive whose name is not a date is kept and named")
    func anUnreadableNameIsKept() throws {
        let world = try World(dailyKeep: 0)
        world.plantArchive(named: "Ovation-backup-2026-04-04-090000")
        world.plantArchive(named: "Ovation-backup-2026-03-01-090000 (conflicted copy)")

        let outcome = try world.service.rotate(now: world.april(10))

        #expect(outcome.keptUnreadable == ["Ovation-backup-2026-03-01-090000 (conflicted copy)"])
        #expect(outcome.deleted.isEmpty)
    }

    /// A DATE THAT CANNOT BE TRUE is treated the same way. A future dated archive
    /// sorts newest for ever: staleness never fires again, the daily trigger
    /// thinks it has backed up, and every genuine archive becomes old enough to
    /// evict in one pass while "never delete the newest" protects the impostor.
    @Test("an archive dated in the future is kept, named, and is not the newest")
    func aFutureDatedArchiveIsNotTheNewest() throws {
        let world = try World(dailyKeep: 1)
        world.plantArchive(named: "Ovation-backup-2099-01-01-090000")
        world.plantArchive(named: "Ovation-backup-2026-03-02-090000")
        world.plantArchive(named: "Ovation-backup-2026-03-17-090000")

        let outcome = try world.service.rotate(now: world.april(10))

        #expect(outcome.keptUnreadable == ["Ovation-backup-2099-01-01-090000"])
        // The real newest is still protected, and the real older one still goes.
        #expect(outcome.kept.contains("Ovation-backup-2026-03-17-090000"))
        #expect(outcome.deleted == ["Ovation-backup-2026-03-02-090000"])
    }

    /// AN INCOMPLETE ENUMERATION DELETES NOTHING (L211). `contentsOfDirectory`
    /// succeeds and returns fewer entries while a folder is mid sync, and a
    /// cleanup acting on a short read turns incompleteness into permanent
    /// deletion. The check is independent of the read it is judging (L70): the
    /// archive just created is known to exist, so a listing without it is short.
    @Test("a listing that cannot see the archive just written deletes nothing")
    func aShortReadRefusesToDelete() throws {
        let world = try World(dailyKeep: 0)
        world.plantArchive(named: "Ovation-backup-2026-03-02-090000")
        world.plantArchive(named: "Ovation-backup-2026-04-04-090000")

        let outcome = try world.service.rotate(
            now: world.april(10),
            mustSurvive: world.backupsDirectory
                .appendingPathComponent("Ovation-backup-2026-04-09-090000", isDirectory: true))

        #expect(outcome.refusedOnAShortRead)
        #expect(outcome.deleted.isEmpty)
        #expect(try world.service.archives().count == 2)
    }

    @Test("a backup that does not verify evicts NOTHING")
    func rotationWaitsForVerification() throws {
        // L5: never destroy good state before its replacement is verified to
        // exist. A run that produced an unverifiable archive must not also have
        // deleted the last good one.
        let world = try World(dailyKeep: 1)
        let good = try world.service.takeBackup(now: world.instant)
        // The seam is named for what it is: a hook that runs after staging and
        // before verification. The test uses it to damage the archive, which is
        // the only way to reach the failure path without corrupting a disk.
        world.service.willVerify = { archive in
            try FileManager.default.removeItem(
                at: archive.appendingPathComponent("problems.jsonl"))
        }

        #expect(throws: BackupError.self) {
            try world.service.takeBackup(now: world.instant.addingTimeInterval(60))
        }
        #expect(try world.service.archives().contains(good))
    }

    // MARK: a refusal carries its cause (ovation#229)

    /// `BackupService` caught the underlying file system error and threw the PATH
    /// alone, so a volume that is gone, a disk that is full and a permission macOS
    /// withdrew all rendered one sentence through
    /// `StoreLaunchSequence.backupCondition(for:)`. Those are the three likeliest
    /// causes on this configuration and they need three different actions from
    /// Dan, so a refusal that names none of them is a refusal he cannot act on
    /// (L11, L148).
    ///
    /// DRIVEN AGAINST A REAL FAILURE, not an injected error. A case that threw
    /// `couldNotWrite` at a seam would assert the sentence and say nothing about
    /// whether anything ever puts a cause in it (L52).
    @Test("a backup that cannot create its staging directory says WHY")
    func aWriteRefusalCarriesTheUnderlyingCause() throws {
        let world = try World()
        // A FILE standing where the backups directory belongs, so the real
        // `createDirectory` fails for a real reason the system describes.
        let blocked = world.root.appendingPathComponent("Blocked", isDirectory: false)
        try Data("not a directory".utf8).write(to: blocked)
        let service = BackupService(dataDirectory: world.dataDirectory,
                                    backupsDirectory: blocked,
                                    dailyKeep: 3,
                                    referencedDocuments: { [] })

        var thrown: BackupError?
        do {
            _ = try service.takeBackup(now: world.instant)
        } catch let error as BackupError {
            thrown = error
        }

        guard case .couldNotWrite(let detail) = try #require(thrown) else {
            Issue.record("expected couldNotWrite, got \(String(describing: thrown))")
            return
        }
        // THE EXACT BARE PATH, computed rather than guessed, so the assertion can
        // only pass when something was appended to it. A first version asserted
        // that the detail was merely LONGER than the folder name, which a full
        // temp path satisfies on its own: it passed with the cause stripped out,
        // which is the shape of an assertion that measures nothing (L140).
        let bare = blocked.appendingPathComponent(
            BackupService.stagingPrefix + BackupService.stamp(for: world.instant),
            isDirectory: true).standardizedFileURL.path
        #expect(detail.hasPrefix(bare), "the refusal no longer names the path: \(detail)")
        #expect(detail != bare, "the refusal names the path and nothing about why")
    }

    // MARK: an archive is tellable from the wreckage of one (ovation#226)

    /// THE LIST OF ARCHIVES IS WHAT THREE LATER RULES READ: the once a day
    /// trigger, the staleness notice and retention. Until now `takeBackup` built
    /// straight into the final name and every throw after the first line left a
    /// directory carrying today's stamp behind, with the verification failure
    /// path leaving one DELIBERATELY, as evidence. So one failed backup
    /// suppressed its own retry for the rest of the day, silenced staleness, and
    /// could become the permanent monthly keeper (L121, L421, L334).
    @Test("an archive that did not verify is not one of the archives")
    func wreckageIsNotAnArchive() throws {
        let world = try World()
        world.service.willVerify = { archive in
            try FileManager.default.removeItem(
                at: archive.appendingPathComponent("Ovation.store"))
        }

        #expect(throws: BackupError.self) {
            try world.service.takeBackup(now: world.instant)
        }

        #expect(try world.service.archives().isEmpty)
    }

    /// AND THE EVIDENCE SURVIVES, under its own name. The archive that failed is
    /// the only record of what went wrong, so it is kept and merely stops
    /// counting as a backup. Deleting it would answer the first case by
    /// destroying the diagnosis (L277).
    @Test("the archive that did not verify is kept, under a name of its own")
    func wreckageIsKeptSeparately() throws {
        let world = try World()
        world.service.willVerify = { archive in
            try FileManager.default.removeItem(
                at: archive.appendingPathComponent("Ovation.store"))
        }

        #expect(throws: BackupError.self) {
            try world.service.takeBackup(now: world.instant)
        }

        let left = try FileManager.default.contentsOfDirectory(
            atPath: world.backupsDirectory.path)
        #expect(left.contains { $0.hasPrefix(BackupService.unverifiedPrefix) })
    }

    /// A FAILURE BEFORE THE MANIFEST LEAVES NOTHING TO ACCUMULATE. There is no
    /// diagnosis inside a half copied directory that the thrown error does not
    /// already carry, and a leftover per failed launch is an unbounded leak into
    /// the folder Dan chose.
    @Test("a backup that failed before it could verify leaves nothing behind")
    func aFailureBeforeVerifyingLeavesNothing() throws {
        let world = try World()
        try FileManager.default.removeItem(at: world.dataDirectory
            .appendingPathComponent("documents"))

        #expect(throws: BackupError.requiredMemberMissing("documents")) {
            try world.service.takeBackup(now: world.instant)
        }

        let left = try FileManager.default.contentsOfDirectory(
            atPath: world.backupsDirectory.path)
        #expect(left.isEmpty)
    }

    /// A DIRECTORY WEARING THE NAME IS NOT AN ARCHIVE. A Synology conflict copy,
    /// a half finished sync, or anything else that lands in the folder with the
    /// right prefix must not be able to answer for a backup that was never taken
    /// (L100, L412).
    @Test("a directory carrying the prefix and no manifest is not an archive")
    func aDirectoryWithNoManifestIsNotAnArchive() throws {
        let world = try World()
        let impostor = world.backupsDirectory
            .appendingPathComponent("Ovation-backup-2099-01-01-000000 (conflicted copy)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: impostor,
                                                withIntermediateDirectories: true)

        #expect(try world.service.archives().isEmpty)
    }

    /// THE CONTROL. Without it every assertion above is satisfied by a service
    /// that never produces an archive at all (L159).
    @Test("a backup that verified IS one of the archives, and leaves no staging behind")
    func aGoodBackupIsAnArchive() throws {
        let world = try World()

        let archive = try world.service.takeBackup(now: world.instant)

        #expect(try world.service.archives() == [archive])
        let left = try FileManager.default.contentsOfDirectory(
            atPath: world.backupsDirectory.path)
        #expect(!left.contains { $0.hasPrefix(BackupService.stagingPrefix) })
    }

    // MARK: restoring

    @Test("restoring puts the archived bytes back")
    func restoringReplacesTheData() throws {
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)

        try Data("{\"action\":\"something else\"}\n".utf8).write(
            to: world.dataDirectory.appendingPathComponent("problems.jsonl"))

        try world.service.restore(from: archive, now: world.instant.addingTimeInterval(60))

        let restored = try Data(contentsOf: world.dataDirectory
            .appendingPathComponent("problems.jsonl"))
        #expect(String(data: restored, encoding: .utf8) == "{\"action\":\"raised\"}\n")
    }

    @Test("restoring takes a snapshot of what is there FIRST")
    func restoringSnapshotsTheCurrentState() throws {
        // L5. The state being overwritten may be the only copy of something, and
        // it is certainly the only evidence of what went wrong.
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)
        try Data("the state at the moment of the restore".utf8).write(
            to: world.dataDirectory.appendingPathComponent("problems.jsonl"))

        try world.service.restore(from: archive, now: world.instant.addingTimeInterval(60))

        let snapshots = try world.service.preRestoreSnapshots()
        #expect(snapshots.count == 1)
        let kept = try Data(contentsOf: try #require(snapshots.first)
            .appendingPathComponent("problems.jsonl"))
        #expect(String(data: kept, encoding: .utf8) == "the state at the moment of the restore")
    }

    @Test("a snapshot is taken even when the current state is too broken to back up")
    func theSnapshotDoesNotRequireAHealthyState() throws {
        // A restore is what somebody does when things are broken, so requiring a
        // full backup first would refuse the remedy precisely when it is needed
        // (L362). The snapshot copies whatever is there, in whatever state.
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)
        try FileManager.default.removeItem(
            at: world.dataDirectory.appendingPathComponent("problems.jsonl"))

        try world.service.restore(from: archive, now: world.instant.addingTimeInterval(60))

        #expect(try world.service.preRestoreSnapshots().count == 1)
    }

    @Test("an archive that does not verify restores NOTHING")
    func aBadArchiveIsNotRestored() throws {
        // Never destroy good state before its replacement is verified to exist.
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)
        try FileManager.default.removeItem(
            at: archive.appendingPathComponent("documents/\(world.receiptPath)"))
        try Data("the live state".utf8).write(
            to: world.dataDirectory.appendingPathComponent("problems.jsonl"))

        #expect(throws: BackupError.self) {
            try world.service.restore(from: archive, now: world.instant.addingTimeInterval(60))
        }

        let live = try Data(contentsOf: world.dataDirectory
            .appendingPathComponent("problems.jsonl"))
        #expect(String(data: live, encoding: .utf8) == "the live state")
        #expect(try world.service.preRestoreSnapshots().isEmpty)
    }

    @Test("restoring leaves the Gmail credential store exactly where it was")
    func restoringDoesNotTouchTheCredentialStore() throws {
        // The credential store is never IN a backup, so a restore cannot bring
        // one back. What it must also not do is delete the live one as a side
        // effect of being thorough: that would log Dan out of his mailbox for a
        // reason nothing told him about.
        let world = try World()
        let token = Data("{\"refresh_token\":\"fabricated\"}".utf8)
        let tokenURL = world.dataDirectory.appendingPathComponent("gmail-tokens.json")
        try token.write(to: tokenURL)
        let archive = try world.service.takeBackup(now: world.instant)

        try world.service.restore(from: archive, now: world.instant.addingTimeInterval(60))

        #expect(try Data(contentsOf: tokenURL) == token)
    }

    @Test("and no snapshot carries the credential store out of the machine either")
    func theSnapshotExcludesTheCredentialStore() throws {
        let world = try World()
        let tokenURL = world.dataDirectory.appendingPathComponent("gmail-tokens.json")
        try Data("{\"refresh_token\":\"fabricated\"}".utf8).write(to: tokenURL)
        let archive = try world.service.takeBackup(now: world.instant)

        try world.service.restore(from: archive, now: world.instant.addingTimeInterval(60))

        let snapshot = try #require(try world.service.preRestoreSnapshots().first)
        #expect(!FileManager.default.fileExists(
            atPath: snapshot.appendingPathComponent("gmail-tokens.json").path))
    }

    // MARK: what the STORE references, not what the backup copied (ovation#104)

    @Test("a receipt the store REFERENCES and the archive lacks REFUSES the backup")
    func aReferencedDocumentMissingFromTheArchiveRefuses() throws {
        // The gap PRD 5.29 and plan 1.8 both describe and nothing implemented.
        // The old verification walked what it had STAGED and hashed those files,
        // so every file it recorded was present and matched, which says nothing
        // about whether a document the store points at is in there at all. It
        // was vacuously complete only while nothing referenced a document, and
        // Expense.receipt now does (L98, L63).
        //
        // It REFUSES rather than reports, because takeBackup verifies before it
        // rotates: an archive missing a receipt must never evict the one that
        // still has it (L5).
        let world = try World()
        let ghost = ReferencedDocument(relativePath: "de/adbeef.pdf",
                                       sha256: String(repeating: "d", count: 64))
        let service = world.service(referencing: [world.receiptReference, ghost])

        #expect(throws: BackupError.verificationFailed(
            [.init(path: ghost.relativePath, verdict: .referencedDocumentAbsent)])) {
            try service.takeBackup(now: world.instant)
        }
    }

    @Test("a referenced receipt whose bytes changed is its OWN verdict, not merely absent")
    func aReferencedDocumentWithWrongBytesFails() throws {
        // Distinct causes, distinct verdicts, because the remedies differ: one
        // is a receipt that never reached the archive, the other is one that
        // reached it damaged (L11).
        let world = try World()
        let service = world.service(referencing: [world.receiptReference])
        let archive = try service.takeBackup(now: world.instant)
        let copied = archive.appendingPathComponent("documents/\(world.receiptPath)")
        try Data(String(repeating: "x", count: 9).utf8).write(to: copied)

        let report = try service.verify(archive: archive)

        #expect(report.failures.contains {
            $0.path == world.receiptPath && $0.verdict == .referencedDocumentMismatch
        })
    }

    @Test("a document NOTHING references is reported without refusing the backup")
    func anOrphanIsANoticeNotAFailure() throws {
        // The archive holds everything the store points at, so the backup did
        // its job. Refusing over a spare file would leave Dan with yesterday's
        // backup because of something harmless, and an orphan and a lost receipt
        // need opposite remedies (L11, L5).
        //
        // Putting orphans in `failures` was tried and did exactly that: the
        // backup threw and no archive was written at all.
        let world = try World()
        let service = world.service(referencing: [])

        let archive = try service.takeBackup(now: world.instant)
        let report = try service.verify(archive: archive)

        #expect(report.isVerified)
        #expect(report.failures.isEmpty)
        #expect(report.orphans.contains(world.receiptPath))
    }

    @Test("with every referenced receipt present and intact, it verifies")
    func theHappyPathStillVerifies() throws {
        // The positive control. Without it the three above could all pass while
        // the check refused every archive ever taken (L159).
        let world = try World()
        let service = world.service(referencing: [world.receiptReference])
        let archive = try service.takeBackup(now: world.instant)

        let report = try service.verify(archive: archive)

        #expect(report.isVerified)
        #expect(report.failures.isEmpty)
    }

    // MARK: fixtures

    /// A data directory with one of everything, and a backup folder beside it.
    private struct World {
        let root: URL
        let dataDirectory: URL
        let backupsDirectory: URL
        let service: BackupService
        let receiptPath: String
        let receiptReference: ReferencedDocument
        let dailyKeep: Int
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)

        init(dailyKeep: Int = 3) throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("ovation-backup-\(UUID().uuidString)", isDirectory: true)
            dataDirectory = root.appendingPathComponent("Ovation", isDirectory: true)
            backupsDirectory = root.appendingPathComponent("Backups", isDirectory: true)

            let manager = FileManager.default
            try manager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try manager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            try manager.createDirectory(at: dataDirectory
                .appendingPathComponent("custody", isDirectory: true),
                                        withIntermediateDirectories: true)
            try Data("a custody note".utf8).write(
                to: dataDirectory.appendingPathComponent("custody/note.txt"))
            try Data("{\"action\":\"raised\"}\n".utf8).write(
                to: dataDirectory.appendingPathComponent("problems.jsonl"))
            // The database. ovation#60 shipped it, so a data directory without
            // one is not a real one. No write ahead log beside it, which is the
            // ordinary state of a checkpointed store and is why the log cannot
            // be required (ovation#88).
            try Data("a fabricated store".utf8).write(
                to: dataDirectory.appendingPathComponent("Ovation.store"))
            // The version marker beside it (ovation#116). Required for the same
            // reason the store is: an archive carrying the database without it
            // restores a store nobody can date, and the guard that refuses a
            // downgrade then has nothing to read. A real data folder always has
            // one, because the launch sequence writes it straight after opening.
            try Data("1.0.0\n".utf8).write(
                to: dataDirectory.appendingPathComponent("Ovation.store.version"))

            let documents = DocumentStore(
                root: dataDirectory.appendingPathComponent("documents", isDirectory: true))
            receiptPath = try documents.store(Data("a receipt".utf8), extension: "pdf")
                .relativePath

            let receiptBytes = Data("a receipt".utf8)
            // ovation#224. What the STORE records about a document is its path
            // and its hash; the byte count is DocumentStore's, from the moment it
            // wrote the file, and no reader before the open can know it.
            receiptReference = ReferencedDocument(relativePath: receiptPath,
                                                  sha256: DocumentStore.hash(of: receiptBytes))
            self.dailyKeep = dailyKeep
            // The default service references exactly what the fixture filed, so
            // the existing tests stay about what they were about.
            // Bound to a local rather than to self: the closure is @Sendable and
            // World is still being initialised, so capturing self here is both
            // rejected and wrong.
            let reference = receiptReference
            service = BackupService(dataDirectory: dataDirectory,
                                    backupsDirectory: backupsDirectory,
                                    dailyKeep: dailyKeep,
                                    referencedDocuments: { [reference] })
        }

        /// A service whose STORE points at the given documents. The closure is
        /// how the store reaches the backup: walking the documents directory
        /// instead would answer a different question, namely whether the files
        /// that are there are intact, and say nothing about the ones that are
        /// not (ovation#104).
        func service(referencing documents: [ReferencedDocument]) -> BackupService {
            BackupService(dataDirectory: dataDirectory,
                          backupsDirectory: backupsDirectory,
                          dailyKeep: dailyKeep,
                          referencedDocuments: { documents })
        }

        /// Plants an archive directory carrying a manifest, so a retention case
        /// can put twenty archives across several months on disk without paying
        /// for twenty real backups. It is what `archives()` recognises: a
        /// directory with the prefix AND a manifest.
        func plantArchive(named name: String) {
            let archive = backupsDirectory.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: archive,
                                                     withIntermediateDirectories: true)
            try? Data("{}".utf8).write(
                to: archive.appendingPathComponent(BackupManifest.filename))
        }

        /// A day in April 2026, in Ovation's own timezone, so a case reads as the
        /// date it is about rather than as an interval from a reference instant.
        func april(_ day: Int) -> Date {
            var components = DateComponents()
            components.year = 2026
            components.month = 4
            components.day = day
            components.hour = 12
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = BusinessCalendar.timeZone
            return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
        }

        func manifest(of archive: URL) throws -> BackupManifest {
            let data = try Data(contentsOf: archive
                .appendingPathComponent(BackupManifest.filename))
            return try JSONDecoder().decode(BackupManifest.self, from: data)
        }
    }
}
