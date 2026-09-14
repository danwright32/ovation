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

    /// THE QUEUE IS ADDED TO, NOT REPLACED, and Downbeat's record is not put back
    /// at all (ovation#253), so a sentence listing them among what is replaced
    /// would describe a restore that does not happen (L180).
    @Test("the confirmation says queued bookings are added back, not replaced")
    func theConfirmationSaysWhatHappensToTheQueue() throws {
        let world = try World()
        try queue("0D5E7C21-5A3B-4C8E-9F10-000000000011", in: world)
        try Data("{}".utf8).write(
            to: world.dataDirectory.appendingPathComponent("downbeat-queued-bookings.json"))
        let archive = try world.service.takeBackup(now: world.instant)

        let sentence = try world.presenter.consequence(of: archive.lastPathComponent)

        #expect(sentence.contains("queued booking"))
        #expect(!sentence.contains("booking-queue"))
        #expect(!sentence.contains("downbeat-queued-bookings.json"))
    }

    /// WHAT HAPPENED TO THE QUEUE IS SAID, both ways, because a booking held back
    /// and a booking put back need different things from Dan (L11).
    @Test("a restore says how many queued bookings it added back",
          arguments: [false, true])
    func restoreSaysWhatHappenedToTheQueue(heldBack: Bool) throws {
        let world = try World()
        let lost = try queue("0D5E7C21-5A3B-4C8E-9F10-000000000012", in: world)
        let archive = try world.service.takeBackup(now: world.instant)
        try FileManager.default.removeItem(at: lost)
        if heldBack {
            try Data("{}\n".utf8).write(
                to: world.dataDirectory.appendingPathComponent("consumed-bookings.jsonl"))
        }

        let outcome = world.presenter.restore(archive.lastPathComponent)

        guard case .restored(let detail) = outcome else {
            Issue.record("a good archive did not restore, got \(outcome)")
            return
        }
        #expect(detail.contains(heldBack ? "1 queued booking held back"
                                         : "1 queued booking added back"))
    }

    @discardableResult
    private func queue(_ bookingId: String, in world: World) throws -> URL {
        let queue = world.dataDirectory.appendingPathComponent("booking-queue", isDirectory: true)
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        let file = queue.appendingPathComponent("\(bookingId).json")
        try Data("a queued booking".utf8).write(to: file)
        return file
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

    /// READING THE ARCHIVES MUST NOT HAPPEN ON THE DRAWING THREAD. `archives()`
    /// verifies each one, which reads and hashes every file in every backup, and
    /// a SwiftUI body is re-evaluated constantly: calling it there put the
    /// heaviest work in the app on the main thread on every redraw, which on a
    /// folder that syncs to a NAS is a frozen window. That is the defect
    /// ovation#246 exists to prevent, written into the pane that fixes it, and
    /// caught by reading the view back rather than by any test.
    @Test("the archives are read off the main thread, not merely read correctly")
    @MainActor
    func archivesAreReadOffTheMainThread() async throws {
        let world = try World()
        _ = try world.service.takeBackup(now: world.instant)
        // Taking the backup asks for the references too, on this thread, because
        // the test called it directly. Only what happens after this counts.
        world.forgetSetUp()

        let rows = await world.presenter.archivesOffTheMainActor()

        #expect(rows.count == 1)
        #expect(rows.first?.verifies == true)
        // THE POINT, ASSERTED DIRECTLY. A case that only checked the rows would
        // pass just as well with the work back on the drawing thread, which is
        // the defect rather than the feature (L63). `verify` calls
        // `referencedDocuments` for every archive, so the fixture's closure is
        // inside the work and can say which thread it ran on.
        #expect(world.sawMainThread == false,
                "the verification ran on the main thread, which is what this moved")
        #expect(world.timesAsked > 0,
                "nothing asked for the references, so the closure proves nothing")
    }

    /// AND IT ANSWERS THE SAME THING as the main actor path, or the surface would
    /// show something different from what a restore would act on (L70).
    @Test("both ways of reading the archives agree")
    func bothWaysAgree() async throws {
        let world = try World()
        _ = try world.service.takeBackup(now: world.instant)

        let onTheMainActor = try world.presenter.archives()
        let offIt = await world.presenter.archivesOffTheMainActor()

        #expect(onTheMainActor == offIt)
    }

    // MARK: the fixture

    @MainActor
    /// A RESTORE THAT STOPS PARTWAY DOES NOT SAY NOTHING CHANGED (ovation#258).
    /// By then the data folder is a mix of the backup and what was there, and
    /// the way back is the snapshot taken first, so the sentence has to name it
    /// (L11, L12).
    @Test("a restore that stops partway says it was partly restored and names the saved copy")
    func aPartlyRestoredArchiveSaysSo() throws {
        let world = try World()
        let archive = try world.service.takeBackup(now: world.instant)
        // `documents` is the first member put back here and `custody` the second.
        let presenter = presenter(for: world, refusingCopyOf: "custody")

        let outcome = presenter.restore(archive.lastPathComponent)

        guard case .partlyRestored(let detail) = outcome else {
            Issue.record("a restore that stopped partway was reported as \(outcome)")
            return
        }
        let snapshot = try #require(try world.service.preRestoreSnapshots().first)
        #expect(detail.contains(snapshot.lastPathComponent))
        #expect(detail.contains("custody"))
        #expect(!detail.contains("Nothing in Ovation has been changed"))
        // AND WHY IT STOPPED (ovation#269), because freeing space, granting access
        // again and reconnecting a drive are different remedies (L11). The
        // fixture's file manager refuses with a permission error, so the sentence
        // must carry that error's own words.
        let cause = CocoaError(.fileWriteNoPermission).localizedDescription
        #expect(!cause.isEmpty)
        #expect(detail.contains(cause),
                "the partway sentence did not say why the write failed: \(detail)")
    }

    /// A presenter over the fixture's folders whose file manager refuses one copy
    /// into the data folder, so one write can be refused without damaging a disk.
    ///
    /// THE FILE MANAGER IS MADE INSIDE THE CLOSURE, never captured by it. A
    /// `FileManager` is not Sendable, and CI's compiler refused a closure that
    /// captured one even with `@unchecked Sendable` declared on the subclass,
    /// while the local one let it through (L376). Only the name and the folder
    /// cross, and both are Sendable.
    private func presenter(for world: World, refusingCopyOf name: String) -> RestorePresenter {
        let clock = world.instant
        let dataDirectory = world.dataDirectory
        return RestorePresenter(dataDirectory: dataDirectory,
                                backupsDirectory: world.backupsDirectory,
                                dailyKeep: BackupService.defaultDailyKeep,
                                referencedDocuments: { [] },
                                now: { clock },
                                fileManager: { RefusingFileManager(refusing: name, in: dataDirectory) })
    }

    private struct World {
        let root: URL
        let dataDirectory: URL
        let backupsDirectory: URL
        let service: BackupService
        let presenter: RestorePresenter
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)
        /// Whether the verification ran on the main thread, and whether it ran at
        /// all, recorded from INSIDE the work by the closure `verify` calls.
        private let watcher = ThreadWatcher()
        var sawMainThread: Bool { watcher.sawMainThread }
        var timesAsked: Int { watcher.timesAsked }
        func forgetSetUp() { watcher.forgetSetUp() }

        final class ThreadWatcher: @unchecked Sendable {
            private let lock = NSLock()
            private var main = false
            private var asked = 0
            var sawMainThread: Bool { lock.withLock { main } }
            var timesAsked: Int { lock.withLock { asked } }
            func note() {
                lock.withLock {
                    asked += 1
                    if Thread.isMainThread { main = true }
                }
            }

            /// Forgets what the SETUP did. Taking the backup calls the same
            /// closure, on the main thread, because the test calls it directly, so
            /// without this the watcher reports the fixture rather than the thing
            /// under test (L375).
            func forgetSetUp() { lock.withLock { main = false; asked = 0 } }
        }

        /// On the main actor, like the presenter it builds and every test that
        /// uses it. ovation#258 gave the presenter a Sendable file manager maker,
        /// and the compiler then refused to build the presenter from a
        /// nonisolated initializer.
        @MainActor
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

            let watching = watcher
            service = BackupService(dataDirectory: dataDirectory,
                                    backupsDirectory: backupsDirectory,
                                    dailyKeep: BackupService.defaultDailyKeep,
                                    referencedDocuments: { watching.note(); return [] })
            // The clock is a local constant rather than the fixture's property,
            // because the closure is built before `self` exists.
            let clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
            presenter = RestorePresenter(
                dataDirectory: dataDirectory,
                backupsDirectory: backupsDirectory,
                dailyKeep: BackupService.defaultDailyKeep,
                referencedDocuments: { watching.note(); return [] },
                now: { clock },
                fileManager: { .default })
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
