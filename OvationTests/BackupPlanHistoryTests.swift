import Foundation
import Testing

/// ovation#610. EVERY OLDER ARCHIVE IS STILL JUDGED AS IT WAS WRITTEN, whatever
/// the plan has become since.
///
/// PR #573 added one optional member to `BackupPlan.members`, and every archive
/// written before it stopped verifying and could no longer be restored, although
/// every file in each was exactly as written. Nothing noticed, because every test
/// took a backup with today's plan and verified it with today's plan, so a change
/// to the plan could only ever agree with itself (L70). This suite holds the
/// verifier to archives written under EARLIER plans, which is the class the fix
/// has to cover rather than the one member that exposed it (L30).
///
/// THE FIXTURES ARE `OvationTests/Fixtures/backup-manifests/`, one manifest per
/// revision of the plan, built from the plan's own history in git (108cb40,
/// 2c5ced0, 4058a4c, 7a5fd20, bdfcf74, 69ca8b7, daa2386) and NEVER from Dan's
/// archives (L2). Each is in the leanest state its plan allowed: required members
/// copied, and every other member absent in the word that plan's build wrote. That
/// is the state a later change is likeliest to break, since nothing in it is
/// carried beyond what the plan insisted on. The files they list hold invented
/// text, "fixture: <path>", which the archive built here reproduces.
///
/// WHEN YOU CHANGE `BackupPlan.members`, the last test here fails until the
/// change is a new plan version: the old list frozen into the plan's history, and
/// a manifest of the new one committed beside these.
struct BackupPlanHistoryTests {

    /// What each committed archive may fail with TODAY, and nothing else.
    ///
    /// These two were written before the database and its version marker were
    /// required, so they do not hold them. That is not damage, and it is not a
    /// pass either: restoring one would put back data with no database or no
    /// marker to date it, so it gets its own verdict (ovation#610).
    static let expectedFailures: [String: [String]] = [
        "plan-1-2026-09-06.json": ["Ovation.store requiredAfterItWasWritten",
                                   "Ovation.store.version requiredAfterItWasWritten"],
        "plan-2-2026-09-07.json": ["Ovation.store.version requiredAfterItWasWritten"],
    ]

    @Test("an archive written under every earlier plan is judged by the plan it was written under")
    func everyEarlierPlanStillVerifies() throws {
        let fixtures = try Self.fixtures()
        try #require(fixtures.count >= 8, "found \(fixtures.count) committed manifests")

        for fixture in fixtures {
            let world = try World(archivedFrom: fixture)
            let report = try world.service.verify(archive: world.archive)
            let found = report.failures.map { "\($0.path) \($0.verdict.rawValue)" }
            #expect(found == Self.expectedFailures[fixture.lastPathComponent] ?? [],
                    "\(fixture.lastPathComponent) is judged differently from the plan it was written under")
        }
    }

    /// Part (4) of the issue, over every past plan rather than one: a restore
    /// puts back only what the archive holds, so a member the plan gained later,
    /// absent from the archive, is left exactly as it is in the data folder.
    @Test("restoring an archive from any earlier plan leaves every member it lacks alone")
    func restoringLeavesWhatTheArchiveLacks() throws {
        for fixture in try Self.fixtures()
        where Self.expectedFailures[fixture.lastPathComponent] == nil {
            let world = try World(archivedFrom: fixture)
            let manifest = try Self.json(fixture)
            let recorded = Set((manifest["members"] as? [[String: Any]] ?? [])
                .compactMap { $0["path"] as? String })
            let lacking = BackupPlan.members.filter {
                $0.kind == .file && !recorded.contains($0.path)
            }
            for member in lacking {
                try Data("live \(member.path)".utf8)
                    .write(to: world.dataDirectory.appendingPathComponent(member.path))
            }

            try world.service.restore(from: world.archive,
                                      now: Date(timeIntervalSinceReferenceDate: 820_000_000))

            for member in lacking {
                let live = try Data(contentsOf: world.dataDirectory
                    .appendingPathComponent(member.path))
                #expect(String(decoding: live, as: UTF8.self) == "live \(member.path)",
                        "restoring \(fixture.lastPathComponent) changed \(member.path)")
            }
        }
    }

    /// THE GUARD ON THE NEXT CHANGE. A backup taken today, in the leanest state,
    /// must write exactly what the newest committed manifest holds, plan version
    /// included. A change to `BackupPlan.members` fails here until it is a new
    /// plan version with its own committed manifest, which is what puts the plan
    /// it replaces under the test above.
    @Test("a backup taken today writes what the newest committed manifest holds")
    func todaysBackupMatchesTheNewestFixture() throws {
        let newest = try #require(try Self.fixtures().last { $0.lastPathComponent.hasSuffix("-named.json") })
        let world = try World(leanDataFolder: ())
        let archive = try world.service.takeBackup(
            now: Date(timeIntervalSinceReferenceDate: 820_000_000)).archive

        let taken = try Self.json(archive.appendingPathComponent(BackupManifest.filename))
        let committed = try Self.json(newest)
        #expect(Self.shape(of: taken) == Self.shape(of: committed),
                "BackupPlan.members changed without a new plan version and a committed manifest of it")
    }

    /// THE SAME GUARD OVER EVERY FIELD, not only what a manifest records. The
    /// test above compares paths and recorded words, so a member promoted from
    /// present sometimes to required while it happens to be present, a changed
    /// restore policy or an edited reason all passed it (L247). Today's list must
    /// equal the newest frozen plan member for member, every field compared
    /// through `BackupMember`'s own equality, so any change that is not a new
    /// plan version fails here.
    @Test("today's plan is exactly the newest frozen plan, every field of every member")
    func todaysPlanIsTheNewestFrozenPlan() throws {
        let newest = try #require(BackupPlan.revisions.last)
        #expect(newest.version == BackupPlan.version)
        #expect(newest.day == BackupPlan.versionDay)
        #expect(BackupPlan.members.count == newest.members.count)
        for (today, frozen) in zip(BackupPlan.members, newest.members) {
            #expect(today == frozen,
                    "\(today.path) differs from plan version \(newest.version): a change to BackupPlan.members is a new plan version")
        }
    }

    /// The bookkeeping the guard above relies on: the versions are the whole run
    /// from 1 to today's, in the order they reached main, and every one has its
    /// committed manifest, so no version can be judged without a fixture.
    @Test("the plan's versions run from 1 to today's, in order, each with a committed manifest")
    func everyVersionHasItsManifest() throws {
        let revisions = BackupPlan.revisions
        #expect(revisions.map(\.version) == Array(1...BackupPlan.version))
        #expect(revisions.map(\.day) == revisions.map(\.day).sorted())

        let names = Set(try Self.fixtures().map(\.lastPathComponent))
        for revision in revisions {
            #expect(names.contains("plan-\(revision.version)-\(revision.day).json"),
                    "no committed manifest for plan version \(revision.version)")
        }
        #expect(names.contains("plan-\(BackupPlan.version)-\(BackupPlan.versionDay)-named.json"))
    }

    /// A manifest that names no version is matched to the plan that wrote it by
    /// its date and its members together, and each committed one is found to be
    /// the plan it was built from.
    @Test("a manifest naming no version is matched to the plan it was written under")
    func anUnnamedManifestFindsItsPlan() throws {
        for fixture in try Self.fixtures() where !fixture.lastPathComponent.hasSuffix("-named.json") {
            let manifest = try JSONDecoder().decode(BackupManifest.self,
                                                    from: Data(contentsOf: fixture))
            #expect(manifest.planVersion == nil)
            let expected = Int(fixture.lastPathComponent.split(separator: "-")[1])
            #expect(BackupPlan.revision(thatWrote: manifest).version == expected,
                    "\(fixture.lastPathComponent) was matched to the wrong plan")
        }
    }

    // MARK: fixtures

    /// Every committed manifest, oldest plan first. Located from this file, never
    /// from the working directory, which is wherever the runner started (L372).
    static func fixtures(_ file: StaticString = #filePath) throws -> [URL] {
        let folder = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appending(path: "Fixtures/backup-manifests", directoryHint: .isDirectory)
        return try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
            .map { folder.appending(path: $0) }
    }

    static func json(_ url: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// The plan version and each member's path and status: what a plan decides
    /// about a manifest, without the dates and hashes the data decides.
    static func shape(of manifest: [String: Any]) -> [String] {
        let members = (manifest["members"] as? [[String: Any]] ?? []).map {
            "\($0["path"] as? String ?? "?") \($0["status"] as? String ?? "?")"
        }
        return ["planVersion \(manifest["planVersion"] as? Int ?? -1)"] + members
    }

    /// The text every committed manifest's files were hashed from.
    static func content(of path: String) -> Data { Data("fixture: \(path)\n".utf8) }

    private struct World {
        let dataDirectory: URL
        let archive: URL
        let service: BackupService

        /// A temporary folder holding the committed manifest as an archive, with
        /// every file it lists written back from its invented text.
        init(archivedFrom fixture: URL) throws {
            let root = Self.root()
            dataDirectory = root.appending(path: "Ovation", directoryHint: .isDirectory)
            let backups = root.appending(path: "Backups", directoryHint: .isDirectory)
            archive = backups.appending(path: "Ovation-backup-2026-09-06-210000",
                                        directoryHint: .isDirectory)
            let manager = FileManager.default
            try manager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try manager.createDirectory(at: archive, withIntermediateDirectories: true)
            try manager.copyItem(at: fixture,
                                 to: archive.appending(path: BackupManifest.filename))

            let manifest = try BackupPlanHistoryTests.json(fixture)
            for record in manifest["members"] as? [[String: Any]] ?? []
            where record["status"] as? String == "copied" {
                let path = try #require(record["path"] as? String)
                if path == "documents" || path == "custody" || path == "booking-queue" {
                    try manager.createDirectory(at: archive.appending(path: path),
                                                withIntermediateDirectories: true)
                }
            }
            for record in manifest["files"] as? [[String: Any]] ?? [] {
                let path = try #require(record["path"] as? String)
                let url = archive.appending(path: path)
                try manager.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
                try BackupPlanHistoryTests.content(of: path).write(to: url)
            }
            service = BackupService(dataDirectory: dataDirectory, backupsDirectory: backups,
                                    dailyKeep: 3, referencedDocuments: { _ in [] })
        }

        /// A data folder holding only what today's plan requires.
        init(leanDataFolder: Void) throws {
            let root = Self.root()
            dataDirectory = root.appending(path: "Ovation", directoryHint: .isDirectory)
            let backups = root.appending(path: "Backups", directoryHint: .isDirectory)
            archive = backups
            let manager = FileManager.default
            try manager.createDirectory(at: backups, withIntermediateDirectories: true)
            try manager.createDirectory(at: dataDirectory.appending(path: "documents"),
                                        withIntermediateDirectories: true)
            try manager.createDirectory(at: dataDirectory.appending(path: "custody"),
                                        withIntermediateDirectories: true)
            for path in ["custody/note.txt", "Ovation.store", "Ovation.store.version"] {
                try BackupPlanHistoryTests.content(of: path)
                    .write(to: dataDirectory.appending(path: path))
            }
            service = BackupService(dataDirectory: dataDirectory, backupsDirectory: backups,
                                    dailyKeep: 3, referencedDocuments: { _ in [] })
        }

        private static func root() -> URL {
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appending(path: "ovation-plan-history-\(UUID().uuidString)",
                           directoryHint: .isDirectory)
        }
    }
}
