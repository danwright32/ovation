import Foundation
import Testing
@testable import Ovation

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
        #expect(copied == ["custody", "documents", "problems.jsonl"])

        // An archive is HONEST about what it could not contain. A member nothing
        // has built yet is recorded with the issue that will build it, rather
        // than being silently absent (L98).
        let pending = manifest.members.filter { $0.status == .notYetBuilt }
        #expect(pending.count == 7)
        #expect(pending.allSatisfy { $0.issue?.hasPrefix("ovation#") == true })
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
        try FileManager.default.removeItem(at: world.dataDirectory
            .appendingPathComponent("problems.jsonl"))

        // ASSERTED BY NAME, not merely that something threw. Planting "skip the
        // missing member" left this green when it only checked for any error:
        // the archive was then refused a step later by the verification, for a
        // different reason, and the test could not tell the two apart (L140).
        #expect(throws: BackupError.requiredMemberMissing("problems.jsonl")) {
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

    @Test("rotation keeps the newest and evicts the oldest")
    func rotationKeepsTheNewest() throws {
        let world = try World(keep: 2)
        let first = try world.service.takeBackup(now: world.instant)
        let second = try world.service.takeBackup(now: world.instant.addingTimeInterval(60))
        let third = try world.service.takeBackup(now: world.instant.addingTimeInterval(120))

        let remaining = try world.service.archives()
        #expect(remaining.count == 2)
        #expect(remaining.contains(second))
        #expect(remaining.contains(third))
        #expect(!remaining.contains(first))
    }

    @Test("a backup that does not verify evicts NOTHING")
    func rotationWaitsForVerification() throws {
        // L5: never destroy good state before its replacement is verified to
        // exist. A run that produced an unverifiable archive must not also have
        // deleted the last good one.
        let world = try World(keep: 1)
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

    // MARK: fixtures

    /// A data directory with one of everything, and a backup folder beside it.
    private struct World {
        let root: URL
        let dataDirectory: URL
        let backupsDirectory: URL
        let service: BackupService
        let receiptPath: String
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)

        init(keep: Int = 3) throws {
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

            let documents = DocumentStore(
                root: dataDirectory.appendingPathComponent("documents", isDirectory: true))
            receiptPath = try documents.store(Data("a receipt".utf8), extension: "pdf")
                .relativePath

            service = BackupService(dataDirectory: dataDirectory,
                                    backupsDirectory: backupsDirectory,
                                    keep: keep)
        }

        func manifest(of archive: URL) throws -> BackupManifest {
            let data = try Data(contentsOf: archive
                .appendingPathComponent(BackupManifest.filename))
            return try JSONDecoder().decode(BackupManifest.self, from: data)
        }
    }
}
