import Foundation
import Testing
@testable import Ovation

/// ovation#91. What a backup COSTS at a realistic number of documents, measured
/// rather than estimated.
///
/// WHY IT NEEDED MEASURING. `takeBackup` reads and hashes every file in the
/// staged archive to build the manifest, and `verify` reads and hashes every one
/// of them again. So a backup is two full reads of every receipt and every sent
/// PDF Ovation holds. A comment estimating that would be a measurement nobody
/// took (L353), and the fixture it was tested against holds ONE document, which
/// is the size at which the cost cannot show (L354).
///
/// WHAT IS ASSERTED IS THE SHAPE, NOT A DURATION. A test comparing elapsed time
/// against a fixed number is a test of what else the machine is running (L224),
/// and it would be the suite's first flake. So this measures the SAME work at two
/// sizes in the same run and asserts the cost is linear in the document count.
/// Linear is the claim that matters: it says the cost per document is bounded and
/// that nothing here is quadratic in the number of receipts, which is the shape
/// that would make a seven year store unbackupable.
///
/// The per document cost is REPORTED rather than asserted, because it is a fact
/// about this machine on this day and pinning it would make an unrelated
/// dependency upgrade turn the suite red (L376).
///
/// HOW TO RE-MEASURE AT REAL SCALE, which is the point of recording it as a
/// command rather than as a dated sentence (L316):
///
///     TEST_RUNNER_OVATION_BACKUP_COST_DOCUMENTS=4000 xcodebuild test \
///       -project Ovation.xcodeproj -scheme Ovation \
///       -only-testing:OvationTests/BackupCostTests
///
/// THE `TEST_RUNNER_` PREFIX IS LOAD BEARING and was found by the command not
/// working. `xcodebuild` does not pass the shell's environment to the test
/// process, so the obvious form runs at the DEFAULT size and prints a number
/// that looks like an answer to the question that was asked. That is the shape
/// of a remedy nobody runs until it is needed and which does not work when they
/// do (L406), so it was run before being written down.
///
/// MEASURED 2026-09-08 on this Mac:
///
///     2,000 documents of 40KB (80MB):  1.478s, 0.74ms per document
///     4,000 documents of 40KB (160MB): 3.065s, 0.77ms per document
///
/// So the cost is LINEAR and about 0.75ms per document, which puts seven years
/// of receipts and sent PDFs at a few seconds. That answers the question the
/// issue asked: it is not slow enough to sit through, so the lever it floated,
/// hashing once and carrying the result into the verification, is not needed and
/// would weaken what verification proves. That trade can be argued again if this
/// number moves, which is why the command is here rather than the conclusion
/// alone.
struct BackupCostTests {

    /// Small by default so the ordinary suite stays fast, and overridable so the
    /// real number can be taken without editing code.
    private static var documentCount: Int {
        ProcessInfo.processInfo.environment["OVATION_BACKUP_COST_DOCUMENTS"]
            .flatMap(Int.init) ?? 60
    }

    /// A receipt sized document. Real receipts are photographs and PDFs, so a
    /// handful of bytes would measure the file system's per file overhead and
    /// nothing about reading and hashing (L48).
    private static let documentBytes = 40_000

    @Test("a backup costs two reads of every document, and the cost is LINEAR in their number")
    func thecostIsLinearInTheDocumentCount() throws {
        let half = max(10, Self.documentCount / 2)
        let full = half * 2

        let small = try World(documents: half)
        defer { small.cleanUp() }
        let large = try World(documents: full)
        defer { large.cleanUp() }

        // Both worlds are built before either is measured, so neither run pays
        // for the other's setup.
        let smallCost = try small.timeOneBackupAndVerification()
        let largeCost = try large.timeOneBackupAndVerification()

        let perDocumentSmall = smallCost / Double(half)
        let perDocumentLarge = largeCost / Double(full)

        print("""
            BACKUP COST, measured in this run:
              \(half) documents of \(Self.documentBytes) bytes: \
            \(String(format: "%.3f", smallCost))s, \
            \(String(format: "%.2f", perDocumentSmall * 1000))ms per document
              \(full) documents of \(Self.documentBytes) bytes: \
            \(String(format: "%.3f", largeCost))s, \
            \(String(format: "%.2f", perDocumentLarge * 1000))ms per document
              total bytes read: about \(full * Self.documentBytes * 2) for the larger run, \
            because every document is read once for the manifest and once to verify
            """)

        // THE ASSERTION IS THE SHAPE. Doubling the documents should roughly
        // double the cost. The band is wide because it is measured on a machine
        // doing other things; what it rules out is quadratic growth, where
        // doubling would cost four times as much.
        let ratio = largeCost / max(smallCost, 0.0001)
        #expect(ratio < 3.2,
                Comment(rawValue: "doubling the documents multiplied the cost by "
                    + "\(String(format: "%.2f", ratio)), which is not linear. A backup whose "
                    + "cost grows against itself makes a seven year store unbackupable."))
        #expect(ratio > 0.8,
                Comment(rawValue: "doubling the documents barely changed the cost "
                    + "(x\(String(format: "%.2f", ratio))), so this measured something other "
                    + "than the documents and the number above means nothing (L102)."))
    }

    @Test("every document is hashed for the manifest AND read again to verify")
    func everyDocumentIsReadTwice() throws {
        // The claim the issue makes about the cost, asserted by its EFFECT rather
        // than by counting reads. The first pass is visible in the manifest: it
        // carries a sha256 for every document, which it could only compute by
        // reading each one. The second is proved by damaging the LAST document in
        // the archive and watching verification catch it, which it can only do by
        // having read all of them (L146: measure the difference, not the claim).
        //
        // A read COUNT was tried first and is not possible without changing the
        // service: it reads through `Data(contentsOf:)` rather than the injected
        // FileManager, so a counting FileManager saw zero. That is worth knowing
        // and is why this is shaped the way it is.
        let count = 12
        let world = try World(documents: count)
        defer { world.cleanUp() }

        let archive = try world.service.takeBackup(now: world.instant)
        let manifest = try world.manifest(of: archive)
        let documents = manifest.files.filter { $0.path.hasPrefix("documents/") }
        #expect(documents.count == count,
                "the first pass hashed every document to build the manifest")
        #expect(documents.allSatisfy { !$0.sha256.isEmpty })

        #expect(try world.service.verify(archive: archive).failures.isEmpty,
                "and an untouched archive verifies")

        // Damage the LAST one, at the same byte length, so only a full read finds
        // it. If verification stopped early this would pass while proving nothing,
        // and a length change would be caught without reading the bytes.
        let last = try #require(documents.last)
        let target = archive.appendingPathComponent(last.path)
        var damaged = try Data(contentsOf: target)
        #expect(damaged.count == BackupCostTests.documentBytes)
        damaged[damaged.count - 1] = damaged[damaged.count - 1] &+ 1
        try damaged.write(to: target)
        #expect(try Data(contentsOf: target).count == damaged.count, "the same length")

        let report = try world.service.verify(archive: archive)
        #expect(!report.failures.isEmpty,
                "the second pass read the last document and found the damage")
        #expect(report.failures.contains { $0.path.hasSuffix(last.path.split(separator: "/").last!) })
    }

    // MARK: the world

    private struct World {
        let root: URL
        let dataDirectory: URL
        let service: BackupService
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)
        private let references: [DocumentReference]

        init(documents count: Int) throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("ovation-cost-\(UUID().uuidString)", isDirectory: true)
            dataDirectory = root.appendingPathComponent("Ovation", isDirectory: true)
            let backups = root.appendingPathComponent("Backups", isDirectory: true)

            let manager = FileManager.default
            try manager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try manager.createDirectory(at: backups, withIntermediateDirectories: true)
            try manager.createDirectory(
                at: dataDirectory.appendingPathComponent("custody", isDirectory: true),
                withIntermediateDirectories: true)
            try Data("a custody note".utf8).write(
                to: dataDirectory.appendingPathComponent("custody/note.txt"))
            try Data("{\"action\":\"raised\"}\n".utf8).write(
                to: dataDirectory.appendingPathComponent("problems.jsonl"))
            try Data("a fabricated store".utf8).write(
                to: dataDirectory.appendingPathComponent("Ovation.store"))
            try Data("1.0.0\n".utf8).write(
                to: dataDirectory.appendingPathComponent("Ovation.store.version"))

            let store = DocumentStore(
                root: dataDirectory.appendingPathComponent("documents", isDirectory: true))
            var built: [DocumentReference] = []
            built.reserveCapacity(count)
            for index in 0..<count {
                // DISTINCT BYTES PER DOCUMENT, because the path is the content
                // hash: identical bytes would be ONE file and the fixture would
                // measure deduplication rather than scale (L48).
                var bytes = Data(repeating: UInt8(index % 251), count: BackupCostTests.documentBytes)
                bytes.replaceSubrange(0..<8, with: withUnsafeBytes(of: index) { Data($0) })
                built.append(try store.store(bytes, extension: "pdf"))
            }
            references = built
            let fixed = built

            service = BackupService(
                dataDirectory: dataDirectory, backupsDirectory: backups, keep: 3,
                referencedDocuments: { fixed })
        }

        /// One backup and one verification, timed together, because that pair is
        /// what Dan actually waits through.
        func timeOneBackupAndVerification() throws -> Double {
            let started = ContinuousClock.now
            let archive = try service.takeBackup(now: instant)
            _ = try service.verify(archive: archive)
            let elapsed = ContinuousClock.now - started
            return Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
        }

        func manifest(of archive: URL) throws -> BackupManifest {
            try JSONDecoder().decode(
                BackupManifest.self,
                from: try Data(contentsOf: archive.appendingPathComponent(BackupManifest.filename)))
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

}
