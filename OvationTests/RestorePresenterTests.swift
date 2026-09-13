import Foundation
import Testing

/// ovation#247. PUTTING THE RECORDS BACK, from inside Ovation.
///
/// `BackupService.restore` existed, was tested, and took a snapshot of whatever
/// was there before replacing anything. Nothing in the app offered it, and PRD
/// 29 asks for it in as many words. Every other phase of this milestone is worth
/// nothing on the day it counts if getting the data back needs a terminal, a
/// path, and somebody who remembers the command. That day is by definition a bad
/// one.
///
/// THE DANGEROUS PART IS THE SURFACE, not the engine. Choosing which archive,
/// saying what will be replaced BEFORE it is, and saying what happened
/// afterwards from the finished state rather than from the code path that got
/// there (L78, L180).
@MainActor
struct RestorePresenterTests {

    @Test("the archives are offered newest first, because that is the one usually wanted")
    func newestFirst() throws {
        let world = try World()
        world.plant("Ovation-backup-2026-03-02-090000")
        world.plant("Ovation-backup-2026-04-04-090000")

        let offered = try world.presenter.archives()

        #expect(offered.map(\.name) == ["Ovation-backup-2026-04-04-090000",
                                        "Ovation-backup-2026-03-02-090000"])
    }

    /// WHETHER IT STILL VERIFIES NOW, not when it was written. ovation#233
    /// re-checks one archive per launch, so most carry no recent verdict, and an
    /// archive that verified in March and has rotted since would otherwise be
    /// offered as though it were sound (L336).
    @Test("each archive says whether it verifies NOW")
    func saysWhetherItVerifiesNow() throws {
        let world = try World()
        let good = try world.service.takeBackup(now: world.instant)
        let broken = try world.service.takeBackup(
            now: world.instant.addingTimeInterval(86_400))
        try FileManager.default.removeItem(
            at: broken.appendingPathComponent("Ovation.store"))

        let offered = try world.presenter.archives()

        let goodRow = try #require(offered.first { $0.name == good.lastPathComponent })
        let brokenRow = try #require(offered.first { $0.name == broken.lastPathComponent })
        #expect(goodRow.verifies)
        #expect(!brokenRow.verifies)
    }

    /// THE CONSEQUENCE SENTENCE IS DERIVED FROM WHAT IS ABOUT TO BE REPLACED, not
    /// written once and reused. A confirmation that reads the same taking one
    /// file or a whole folder is one nobody reads twice (L180).
    @Test("the confirmation names what will be replaced, from the archive itself")
    func theConfirmationNamesWhatItReplaces() throws {
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)

        let sentence = try world.presenter.consequence(of: archive.lastPathComponent)

        #expect(sentence.contains("Ovation.store"))
        #expect(sentence.contains("documents"))
    }

    /// AND IT SAYS A SNAPSHOT IS TAKEN FIRST, because that is the fact that makes
    /// the decision reversible and the one a person most needs before saying yes.
    @Test("the confirmation says the current state is kept first")
    func theConfirmationSaysASnapshotIsTaken() throws {
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)

        let sentence = try world.presenter.consequence(of: archive.lastPathComponent)

        #expect(sentence.lowercased().contains("before"))
    }

    /// RESTORING REPORTS WHAT IT DID, assembled from the finished state rather
    /// than from the path that did it (L78).
    @Test("a restore says what it put back")
    func restoreSaysWhatItDid() throws {
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)

        let outcome = world.presenter.restore(archive.lastPathComponent)

        guard case .restored(let detail) = outcome else {
            Issue.record("a good archive did not restore, got \(outcome)")
            return
        }
        #expect(detail.contains(archive.lastPathComponent))
    }

    /// AN ARCHIVE THAT NO LONGER VERIFIES IS REFUSED, not restored with a
    /// warning. Replacing good state with an archive known to be damaged is the
    /// one mistake this whole milestone exists to prevent (L5).
    @Test("an archive that does not verify is refused, and nothing is replaced")
    func aDamagedArchiveIsRefused() throws {
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)
        try FileManager.default.removeItem(
            at: archive.appendingPathComponent("Ovation.store"))

        let outcome = world.presenter.restore(archive.lastPathComponent)

        guard case .refused = outcome else {
            Issue.record("a damaged archive was restored, got \(outcome)")
            return
        }
    }

    /// AN ARCHIVE THAT IS NOT THERE IS ITS OWN REFUSAL, never a silent no-op. A
    /// control that appears to work and does nothing is worse than one that
    /// refuses (L100).
    @Test("restoring something that is not there refuses by name")
    func anAbsentArchiveIsRefused() throws {
        let world = try World()

        let outcome = world.presenter.restore("Ovation-backup-2099-01-01-000000")

        guard case .refused(let detail) = outcome else {
            Issue.record("an absent archive did not refuse, got \(outcome)")
            return
        }
        #expect(detail.contains("2099"))
    }

    // MARK: the fixture

    @MainActor
    private struct World {
        let root: URL
        let dataDirectory: URL
        let backupsDirectory: URL
        let service: BackupService
        let presenter: RestorePresenter
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)

        init() throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("ovation-restore-\(UUID().uuidString)",
                                        isDirectory: true)
            dataDirectory = root.appendingPathComponent("Ovation", isDirectory: true)
            backupsDirectory = root.appendingPathComponent("Backups", isDirectory: true)
            let manager = FileManager.default
            try manager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try manager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            try Data("a store".utf8)
                .write(to: dataDirectory.appendingPathComponent("Ovation.store"))
            try Data("1.0.0\n".utf8)
                .write(to: dataDirectory.appendingPathComponent("Ovation.store.version"))
            try DataDirectory.prepare(dataDirectory)

            service = BackupService(dataDirectory: dataDirectory,
                                    backupsDirectory: backupsDirectory,
                                    dailyKeep: BackupService.defaultDailyKeep,
                                    referencedDocuments: { [] })
            // The clock is a local constant rather than the fixture's property,
            // because the closure is built before `self` exists.
            let clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
            presenter = RestorePresenter(service: service, now: { clock })
        }

        func plant(_ name: String) {
            let archive = backupsDirectory.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: archive,
                                                     withIntermediateDirectories: true)
            try? Data("{}".utf8).write(
                to: archive.appendingPathComponent(BackupManifest.filename))
        }
    }
}
