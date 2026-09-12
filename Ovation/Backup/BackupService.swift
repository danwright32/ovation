// Plan 1.8, ovation#57. Dated backups, and the verification that makes them
// worth having.
//
// VERIFICATION MEANS ENUMERATING, NOT OPENING. A backup whose store opens fine
// and whose receipt files are missing is a backup that fails in an audit,
// quietly, months later. So every file the archive recorded is checked for
// presence AND for its hash, using the same distinctions the custody verifier
// already uses rather than a second vocabulary for the same question (L11).
//
// ROTATION EVICTS ONLY AFTER THE NEW ONE VERIFIES. Never destroy good state
// before its replacement is verified to exist (L5). A run that produced an
// unverifiable archive deletes nothing at all.
//
// WHAT IS IN AN ARCHIVE IS DECLARED IN BackupPlan, not decided here.
//
// AND WHAT THE STORE REFERENCES COMES FROM THE STORE (ovation#104). Verification
// used to walk what it had STAGED and hash those files, so every file it
// recorded was present and matched, which says nothing about whether a document
// the store points at is in the archive at all. That was vacuously complete only
// while nothing referenced a document, and `Expense.receipt` now does. Walking
// the documents directory instead would answer a different question: whether the
// files that ARE there are intact, and nothing about the ones that are not.
import Foundation

struct BackupManifest: Codable, Equatable, Sendable {
    static let filename = "manifest.json"

    enum MemberStatus: String, Codable, Sendable {
        case copied
        case notYetBuilt
        /// It is absent, and absent is one of its correct states. A checkpointed
        /// store has no write ahead log beside it. Distinct from `notYetBuilt`
        /// because the two need opposite responses: this one is normal, and that
        /// one is a standing reminder that the archive is short (L11).
        case legitimatelyAbsent
    }

    struct MemberRecord: Codable, Equatable, Sendable {
        let path: String
        let status: MemberStatus
        /// The issue that will build it, when it does not exist yet.
        let issue: String?
    }

    struct FileRecord: Codable, Equatable, Sendable {
        let path: String
        let sha256: String
        let byteCount: Int
    }

    let createdAt: Date
    let dayKey: String
    let members: [MemberRecord]
    let files: [FileRecord]
}

/// Why one file in an archive is not what it should be. Distinct causes, distinct
/// verdicts, because they need different actions.
enum BackupFileVerdict: String, Equatable, Sendable {
    case absent
    case unreadable
    case mismatch
    /// A file in the archive has the same contents as a secret that must never
    /// leave the machine.
    case secretPresent
    /// A member the plan requires was never recorded as copied.
    case memberMissing
    /// The STORE points at a document and the archive has not got it. This is
    /// the one the whole enumeration exists for: every file the archive recorded
    /// can be present and correct while a receipt the store references was never
    /// in there at all (ovation#104).
    case referencedDocumentAbsent
    /// The store points at it, the archive has it, and the bytes are not the
    /// ones recorded.
    case referencedDocumentMismatch
    /// The archive holds a document NOTHING references. Not a lost receipt and
    /// must not be reported as one: the remedies are opposite, since this is
    /// something spare and that is something gone (L11).
    case orphanedDocument
}

struct BackupReport: Equatable, Sendable {
    struct Failure: Equatable, Sendable {
        let path: String
        let verdict: BackupFileVerdict
    }

    let filesChecked: Int
    let failures: [Failure]
    /// Documents in the archive that the store points at NOTHING for.
    ///
    /// DELIBERATELY NOT A FAILURE. The archive holds everything the store
    /// references, so the backup did its job; a spare file is something to tidy,
    /// not a reason to refuse a backup and leave Dan with yesterday's. Putting
    /// these in `failures` was tried and it did exactly that (L11, L5).
    let orphans: [String]
    /// How many secrets the archive was compared against.
    let secretsChecked: Int
    /// Whether the secret comparison could happen at all. Zero secrets is NOT a
    /// clean bill of health: a guard handed nothing to look for examines nothing,
    /// and reporting clean would be indistinguishable from having checked (L98).
    let secretCheckWasPossible: Bool

    var isVerified: Bool { failures.isEmpty }
}

enum BackupError: Error, Equatable {
    case requiredMemberMissing(String)
    case excludedFilePresent(String)
    case noManifest(String)
    case couldNotRead(String)
    case couldNotWrite(String)
    case verificationFailed([BackupReport.Failure])
}

final class BackupService {
    let dataDirectory: URL
    let backupsDirectory: URL
    /// HOW MANY OF THE MOST RECENT ARCHIVES ARE KEPT WHATEVER THEIR DATE, on top
    /// of the monthly keepers below (ovation#227). Dan's answer, 2026-09-11:
    /// fourteen daily, plus one per month for good.
    ///
    /// BY COUNT, NOT BY A WINDOW OF DAYS. "Everything from the last fourteen
    /// days" is the same thing only if Ovation is launched every day; used three
    /// days a week it keeps six archives while reporting that it satisfies
    /// fourteen (L63).
    ///
    /// It replaces `keep`, which asked a question the date rule now decides, and
    /// it is renamed rather than reused so no reader is left answering the
    /// superseded one (L428).
    let dailyKeep: Int

    /// Runs after an archive is staged and BEFORE it is verified. The seam exists
    /// so the failure path can be reached without corrupting a disk.
    var willVerify: ((URL) throws -> Void)?

    /// What the STORE points at, read from the store rather than by walking the
    /// documents folder (ovation#104).
    ///
    /// `ReferencedDocument` rather than `DocumentReference` (ovation#224): the
    /// store records a path and a hash and no byte count, so the wider type could
    /// only be filled by inventing one, and an invented number presented as a
    /// recorded fact is worse than a missing field (L192). Nothing in `verify`
    /// reads a byte count.
    ///
    /// REQUIRED, with no default. A default of "no documents" would be
    /// indistinguishable from a store that references none, so a caller who
    /// forgot it would get a verification that silently checks nothing and
    /// reports clean, which is this check's own failure mode (L168, L98).
    private let referencedDocuments: @Sendable () throws -> [ReferencedDocument]

    private let fileManager: FileManager

    init(dataDirectory: URL, backupsDirectory: URL, dailyKeep: Int,
         referencedDocuments: @escaping @Sendable () throws -> [ReferencedDocument],
         fileManager: FileManager = .default) {
        self.dataDirectory = dataDirectory
        self.backupsDirectory = backupsDirectory
        self.dailyKeep = dailyKeep
        self.referencedDocuments = referencedDocuments
        self.fileManager = fileManager
    }

    // MARK: at most once a day (ovation#228)

    /// What one launch's backup attempt did.
    ///
    /// FOUR OUTCOMES, NOT TWO AND AN EXCEPTION. The seam this reaches was
    /// `(Date) throws -> URL`, so a launch that SKIPPED because one had already
    /// been taken was indistinguishable from one that backed up, and a folder
    /// that could not be read looked like either (L98, L11).
    enum Attempt: Equatable {
        /// A backup was taken just now.
        case taken(URL)
        /// One had already been taken today, and here it is.
        case alreadyTakenToday(URL)
        /// The folder could not be read, so the question could not be answered.
        /// NOT a skip: "there is no archive for today" and "I could not look" are
        /// the same silence otherwise.
        case folderUnreachable(String)
    }

    /// Take today's backup, unless today's has already been taken.
    ///
    /// Dan's answer, 2026-09-11: at launch, at most once a day. At launch because
    /// the backup runs BEFORE the store is opened, which is the whole reason it is
    /// worth having. Once a day because five launches in one day would otherwise
    /// make the rolling set five copies of today and evict yesterday.
    ///
    /// IT ASKS WHETHER A VERIFIED ARCHIVE EXISTS FOR TODAY, which is only a
    /// question worth asking because ovation#226 made the archive list mean
    /// something: a directory only gets the archive prefix after it has verified,
    /// so anything answering here passed. Before that, this morning's FAILED
    /// backup left a directory carrying today's stamp, and a gate asking "is there
    /// something dated today" would see the wreckage and skip, so the one day the
    /// backup broke was the one day nothing tried again (L121, L421).
    ///
    /// IT ASKS THE FOLDER RATHER THAN A STORED FLAG, so there is no second source
    /// of truth that can disagree with the files (L58, L70).
    func takeBackupIfDueToday(now: Date) throws -> Attempt {
        let existing: [URL]
        do {
            existing = try archives()
        } catch {
            return .folderUnreachable("\(backupsDirectory.path): \(error)")
        }

        let today = BusinessCalendar.dayKey(for: now)
        if let already = existing.last(where: { archive in
            guard let instant = Self.instant(fromArchiveNamed: archive.lastPathComponent)
            else { return false }
            return BusinessCalendar.dayKey(for: instant) == today
        }) {
            return .alreadyTakenToday(already)
        }

        return .taken(try takeBackup(now: now))
    }

    // MARK: taking one

    @discardableResult
    func takeBackup(now: Date) throws -> URL {
        // STAGED UNDER A NAME THE ARCHIVE PREFIX DOES NOT MATCH, and renamed only
        // once it has verified (ovation#226).
        //
        // This used to build straight into the final name, so every throw after
        // the first line left a directory carrying today's stamp in the folder,
        // and the verification failure path left one DELIBERATELY, as evidence.
        // Three later rules read that list: the once a day trigger, the staleness
        // notice and retention. So one failed backup suppressed its own retry for
        // the rest of the day, silenced staleness, and could become the permanent
        // monthly keeper (L121, L421, L334).
        //
        // The rename is also what makes an archive appear ATOMICALLY, so a sync
        // client never starts uploading a half written one.
        let staging = url(ofArchiveNamed: Self.stagingPrefix + Self.stamp(for: now))
        let archive = url(ofArchiveNamed: Self.archiveName(for: now))
        try? fileManager.removeItem(at: staging)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            // THE CAUSE TRAVELS WITH IT (ovation#229). A volume that is gone, a
            // disk that is full and a permission macOS withdrew are the three
            // likeliest causes on this configuration, they need three different
            // actions, and discarding the error rendered one sentence for all
            // three (L11).
            throw BackupError.couldNotWrite("\(staging.path): \(error.localizedDescription)")
        }
        // A FAILURE BEFORE THE MANIFEST LEAVES NOTHING BEHIND. There is no
        // diagnosis inside a half copied directory that the thrown error does not
        // already carry, and one leftover per failed launch is an unbounded leak
        // into the folder Dan chose. The verification failure below is the one
        // case with evidence worth keeping, and it keeps it under its own name.
        var stagingSurvives = false
        defer {
            if !stagingSurvives { try? fileManager.removeItem(at: staging) }
        }

        var members: [BackupManifest.MemberRecord] = []
        for member in BackupPlan.members {
            let source = dataDirectory.appendingPathComponent(member.path)
            guard fileManager.fileExists(atPath: source.path) else {
                switch member.expectation {
                case .required:
                    // Silently skipping it would give an archive that reads as
                    // complete (L98).
                    throw BackupError.requiredMemberMissing(member.path)
                case .presentSometimes:
                    members.append(.init(path: member.path,
                                         status: .legitimatelyAbsent, issue: nil))
                    continue
                case .notYetBuilt(let issue):
                    members.append(.init(path: member.path, status: .notYetBuilt, issue: issue))
                    continue
                }
            }

            do {
                try fileManager.copyItem(at: source,
                                         to: staging.appendingPathComponent(member.path))
            } catch {
                throw BackupError.couldNotWrite(
                    "\(member.path): \(error.localizedDescription)")
            }
            members.append(.init(path: member.path, status: .copied, issue: nil))
        }

        let staged = try walk(staging)
        // Defence in depth: the credential store is not a member, so it should
        // never be here. Checked anyway, because "should never" is not a check.
        if let excluded = staged.first(where: {
            BackupPlan.excludedNames.contains(($0 as NSString).lastPathComponent)
        }) {
            throw BackupError.excludedFilePresent(excluded)
        }

        let files = try staged.map { path -> BackupManifest.FileRecord in
            let data = try readFile(staging.appendingPathComponent(path))
            return .init(path: path, sha256: DocumentStore.hash(of: data), byteCount: data.count)
        }

        let manifest = BackupManifest(createdAt: now,
                                      dayKey: BusinessCalendar.dayKey(for: now),
                                      members: members,
                                      files: files)
        try write(manifest, to: staging)

        try willVerify?(staging)

        let report = try verify(archive: staging)
        guard report.isVerified else {
            // Nothing is evicted, and the archive that failed is KEPT, because it
            // is the only record of what went wrong (L277). It is kept under its
            // own prefix, so it stops answering for a backup that was never
            // taken while staying there to be read.
            let evidence = url(ofArchiveNamed: Self.unverifiedPrefix + Self.stamp(for: now))
            try? fileManager.removeItem(at: evidence)
            if (try? fileManager.moveItem(at: staging, to: evidence)) != nil {
                stagingSurvives = true
            }
            throw BackupError.verificationFailed(report.failures)
        }

        // THE ARCHIVE EXISTS FROM HERE, and not before. A rename is atomic, so
        // nothing ever sees a partly built archive under a name the rules read.
        do {
            try? fileManager.removeItem(at: archive)
            try fileManager.moveItem(at: staging, to: archive)
            stagingSurvives = true
        } catch {
            throw BackupError.couldNotWrite(archive.path)
        }

        // The archive just created is handed to the rotation as the thing that
        // MUST be in the listing, so an incomplete enumeration refuses instead of
        // deleting on it (L211).
        _ = try rotate(now: now, mustSurvive: archive)
        return archive
    }

    // MARK: verifying

    /// Check an archive against its own manifest.
    ///
    /// `secrets` are content hashes that must not appear in the archive under ANY
    /// name. A name check alone is satisfied by renaming the file, and the secret
    /// is the bytes rather than the filename.
    func verify(archive: URL, secrets: Set<String> = []) throws -> BackupReport {
        let manifestURL = archive.appendingPathComponent(BackupManifest.filename)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            // An archive with no manifest cannot be judged. That is not the same
            // as an archive with nothing in it (L98).
            throw BackupError.noManifest(archive.path)
        }

        let manifest: BackupManifest
        do {
            manifest = try JSONDecoder().decode(BackupManifest.self,
                                                from: try Data(contentsOf: manifestURL))
        } catch {
            throw BackupError.couldNotRead(manifestURL.path)
        }

        var failures: [BackupReport.Failure] = []

        // Every member the plan names must be ACCOUNTED FOR, in a way its own
        // expectation allows. Checking only the required ones left every other
        // member unverified, which is how the database went unchecked for as
        // long as it was mislabelled as not yet built.
        for member in BackupPlan.members {
            let recorded = manifest.members.first { $0.path == member.path }
            let allowed: Set<BackupManifest.MemberStatus>
            switch member.expectation {
            case .required:
                allowed = [.copied]
            case .presentSometimes:
                // Either is correct, but it must say WHICH. A member missing
                // from the manifest altogether is not the same as one recorded
                // as absent, and only the second is evidence anybody looked.
                allowed = [.copied, .legitimatelyAbsent]
            case .notYetBuilt:
                allowed = [.copied, .notYetBuilt]
            }
            guard let status = recorded?.status, allowed.contains(status) else {
                failures.append(.init(path: member.path, verdict: .memberMissing))
                continue
            }
        }

        // WHAT THE STORE POINTS AT, read from the store (ovation#104). Every
        // check below this line asks a question the loop that follows cannot:
        // that loop walks what the archive RECORDED, so it is complete about
        // the files that are there and silent about the ones that are not.
        let references = try referencedDocuments()
        var referencedPaths: Set<String> = []
        for reference in references {
            let inArchive = "documents/" + reference.relativePath
            referencedPaths.insert(reference.relativePath)
            let url = archive.appendingPathComponent(inArchive)
            guard let data = try? Data(contentsOf: url) else {
                failures.append(.init(path: reference.relativePath,
                                      verdict: .referencedDocumentAbsent))
                continue
            }
            if DocumentStore.hash(of: data) != reference.sha256 {
                failures.append(.init(path: reference.relativePath,
                                      verdict: .referencedDocumentMismatch))
            }
        }

        // A document in the archive that nothing points at. Reported, and
        // reported SEPARATELY: it is something spare, where the case above is
        // something gone, and one sentence for both would send Dan looking for a
        // lost receipt that is not lost (L11).
        var orphans: [String] = []
        for record in manifest.files where record.path.hasPrefix("documents/") {
            let relative = String(record.path.dropFirst("documents/".count))
            if !referencedPaths.contains(relative) {
                orphans.append(relative)
            }
        }

        // Every file it recorded, checked for presence and for content.
        for record in manifest.files {
            let url = archive.appendingPathComponent(record.path)
            guard fileManager.fileExists(atPath: url.path) else {
                failures.append(.init(path: record.path, verdict: .absent))
                continue
            }
            guard let data = try? Data(contentsOf: url) else {
                failures.append(.init(path: record.path, verdict: .unreadable))
                continue
            }
            if DocumentStore.hash(of: data) != record.sha256 {
                failures.append(.init(path: record.path, verdict: .mismatch))
            }
        }

        // And nothing in the archive may BE a secret, whatever it is called.
        var secretsChecked = 0
        if !secrets.isEmpty {
            secretsChecked = secrets.count
            for path in try walk(archive) {
                guard let data = try? Data(contentsOf: archive.appendingPathComponent(path)) else {
                    continue
                }
                if secrets.contains(DocumentStore.hash(of: data)) {
                    failures.append(.init(path: path, verdict: .secretPresent))
                }
            }
        }

        return BackupReport(filesChecked: manifest.files.count,
                            failures: failures,
                            orphans: orphans,
                            secretsChecked: secretsChecked,
                            secretCheckWasPossible: !secrets.isEmpty)
    }

    // MARK: restoring

    static let snapshotPrefix = "Ovation-pre-restore-"

    /// Put an archive back, after keeping what is there now.
    ///
    /// THE ARCHIVE IS VERIFIED FIRST, and a failure changes nothing at all: never
    /// destroy good state before its replacement is verified to exist (L5).
    ///
    /// THE SNAPSHOT IS NOT A BACKUP, deliberately. `takeBackup` refuses when a
    /// required member is missing, and a restore is what somebody does when
    /// things are broken, so requiring one would refuse the remedy precisely when
    /// it is needed (L362). The snapshot copies whatever is there, in whatever
    /// state, minus the credential store.
    ///
    /// THE CREDENTIAL STORE IS NOT TOUCHED, and this is a decision Dan signed off
    /// on 2026-09-06 rather than a side effect. Plan 1.8 requires it to be one:
    /// "a restore that does not require re-authorising Gmail is its own decision
    /// with its own sign off".
    ///
    /// The token file is never in an archive, so a restore cannot bring an old
    /// one back. What it also does not do is DELETE the live one, which would log
    /// Dan out of his mailbox for a reason nothing told him about, on an ordinary
    /// restore such as moving to a new Mac.
    ///
    /// WHAT THAT ACCEPTS, stated rather than discovered later: if a restore is
    /// ever a response to something having been tampered with, the credential is
    /// the one thing NOT returned to a known state. The alternatives put to Dan
    /// were forcing a re-login on every restore, and asking at the time.
    func restore(from archive: URL, now: Date, secrets: Set<String> = []) throws {
        let report = try verify(archive: archive, secrets: secrets)
        guard report.isVerified else {
            throw BackupError.verificationFailed(report.failures)
        }

        let manifest = try readManifest(at: archive)
        try snapshotCurrentState(now: now)

        for member in manifest.members where member.status == .copied {
            let source = archive.appendingPathComponent(member.path)
            let destination = dataDirectory.appendingPathComponent(member.path)
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                throw BackupError.couldNotWrite(member.path)
            }
        }
    }

    /// Every pre restore snapshot, oldest first.
    func preRestoreSnapshots() throws -> [URL] {
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: backupsDirectory.path)
        } catch {
            throw BackupError.couldNotRead(backupsDirectory.path)
        }
        return names.filter { $0.hasPrefix(Self.snapshotPrefix) }.sorted()
            .map { backupsDirectory.appendingPathComponent($0, isDirectory: true)
                .standardizedFileURL }
    }

    private func snapshotCurrentState(now: Date) throws {
        let destination = backupsDirectory
            .appendingPathComponent(Self.snapshotPrefix + Self.stamp(for: now), isDirectory: true)
            .standardizedFileURL
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            throw BackupError.couldNotWrite(destination.path)
        }

        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: dataDirectory.path)
        } catch {
            throw BackupError.couldNotRead(dataDirectory.path)
        }

        for name in names where !BackupPlan.excludedNames.contains(name) {
            do {
                try fileManager.copyItem(at: dataDirectory.appendingPathComponent(name),
                                         to: destination.appendingPathComponent(name))
            } catch {
                throw BackupError.couldNotWrite(name)
            }
        }
    }

    private func readManifest(at archive: URL) throws -> BackupManifest {
        let url = archive.appendingPathComponent(BackupManifest.filename)
        guard fileManager.fileExists(atPath: url.path) else {
            throw BackupError.noManifest(archive.path)
        }
        do {
            return try JSONDecoder().decode(BackupManifest.self, from: try Data(contentsOf: url))
        } catch {
            throw BackupError.couldNotRead(url.path)
        }
    }

    // MARK: rotation

    /// Every archive in the backups folder, oldest first. The name carries the
    /// instant, so sorting the names sorts the archives.
    func archives() throws -> [URL] {
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: backupsDirectory.path)
        } catch {
            throw BackupError.couldNotRead(backupsDirectory.path)
        }
        // Built by NAME through the same one function `takeBackup` uses, never
        // from whatever URL the file manager hands back. Those differ by a
        // symlinked prefix and a trailing slash while naming the same directory,
        // and two spellings of one identity is how a caller ends up unable to
        // find what it just created (L15).
        // A DIRECTORY WEARING THE NAME IS NOT AN ARCHIVE (ovation#226). A
        // Synology conflict copy, a half finished sync, or anything else that
        // lands here with the right prefix must not be able to answer for a
        // backup that was never taken (L100). An archive is a directory carrying
        // its own manifest, which is also the only thing `verify` can judge.
        return names
            .filter { $0.hasPrefix(Self.archivePrefix) }
            .sorted()
            .map { url(ofArchiveNamed: $0) }
            .filter { carriesAManifest($0) }
    }

    private func carriesAManifest(_ archive: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: archive.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        return fileManager.fileExists(
            atPath: archive.appendingPathComponent(BackupManifest.filename).path)
    }

    private func url(ofArchiveNamed name: String) -> URL {
        backupsDirectory.appendingPathComponent(name, isDirectory: true).standardizedFileURL
    }

    /// What one rotation did, so a caller can SAY it (ovation#227).
    ///
    /// The old rotation deleted with `try?` and reported nothing, so a delete
    /// that failed and one that succeeded were the same silence, and "which
    /// archives has Ovation removed" was unanswerable (L12, L338). This is an
    /// automatic deletion policy over the only archived copies of Dan's records,
    /// so every outcome it can have is named.
    struct RotationOutcome: Equatable, Sendable {
        /// Archives that survive, newest last.
        var kept: [String] = []
        /// Archives this run removed.
        var deleted: [String] = []
        /// Archives it decided to remove and could not. Its own list, because a
        /// folder where deletes fail grows silently otherwise.
        var couldNotDelete: [String] = []
        /// Archives kept because their name could not be read as a date, or
        /// carried one that cannot be true. Kept and REPORTED, never deleted: a
        /// failed parse otherwise lands on the permissive side, and here that
        /// side is deletion (L50).
        var keptUnreadable: [String] = []
        /// True when the folder could not be enumerated completely, in which case
        /// NOTHING was deleted.
        var refusedOnAShortRead: Bool = false
    }

    /// Fourteen by count, plus the LAST archive of every calendar month, for good.
    ///
    /// EVERY MONTH, INCLUDING THE ONE IN PROGRESS. ovation#227 says "each
    /// completed calendar month", and this keeps the current month's last archive
    /// too. Almost always the same archive, since that one is usually the newest
    /// and protected anyway; where it differs it keeps one more rather than one
    /// fewer, which is the harmless direction for a rule that deletes the only
    /// archived copies of Dan's records (L648). Said here so the code and the
    /// issue do not quietly disagree.
    ///
    /// THE LAST OF THE MONTH, NOT THE FIRST. The first archive of a month is
    /// taken before anything in that month has happened, so it holds the previous
    /// month's state: keeping it would permanently delete every snapshot
    /// containing a month's own invoices and keep the one containing none of them
    /// (L334, L648). Dan chose the last on 2026-09-11, after the first was
    /// proposed and the fault was found.
    ///
    /// THE NEWEST IS NEVER DELETED, whatever the arithmetic says (L5).
    @discardableResult
    func rotate(now: Date, mustSurvive: URL? = nil) throws -> RotationOutcome {
        var outcome = RotationOutcome()
        let existing = try archives()

        // A SHORT READ REFUSES (L211). `contentsOfDirectory` succeeds and returns
        // fewer entries while a folder is mid sync, and a cleanup that deletes
        // whatever its read did not mention turns incompleteness into permanent
        // deletion. The check is independent of the read rather than derived from
        // it (L70): the archive this run just created is known to exist, so an
        // enumeration that cannot see it is not a complete enumeration.
        if let mustSurvive, !existing.contains(where: { $0.standardizedFileURL == mustSurvive.standardizedFileURL }) {
            outcome.refusedOnAShortRead = true
            outcome.kept = existing.map { $0.lastPathComponent }
            return outcome
        }

        var dated: [(url: URL, date: Date)] = []
        for archive in existing {
            let name = archive.lastPathComponent
            guard let date = Self.instant(fromArchiveNamed: name) else {
                outcome.keptUnreadable.append(name)
                continue
            }
            // A DATE THAT CANNOT BE TRUE is treated exactly like one that cannot
            // be parsed. A future dated archive sorts newest for ever, which
            // silences staleness, satisfies the daily trigger, and makes every
            // genuine archive old enough to evict in one pass, with "never delete
            // the newest" protecting only the impostor (ovation#227's comment).
            guard date <= now else {
                outcome.keptUnreadable.append(name)
                continue
            }
            dated.append((archive, date))
        }
        dated.sort { $0.date < $1.date }

        var survivors = Set<String>()
        for entry in dated.suffix(dailyKeep) { survivors.insert(entry.url.lastPathComponent) }
        if let newest = dated.last { survivors.insert(newest.url.lastPathComponent) }
        // The last archive of each calendar month, in Ovation's own timezone so a
        // trip cannot move an archive into a neighbouring month.
        var lastOfMonth: [String: (url: URL, date: Date)] = [:]
        for entry in dated {
            let key = Self.monthKey(for: entry.date)
            if let held = lastOfMonth[key], held.date >= entry.date { continue }
            lastOfMonth[key] = entry
        }
        for entry in lastOfMonth.values { survivors.insert(entry.url.lastPathComponent) }

        for entry in dated {
            let name = entry.url.lastPathComponent
            if survivors.contains(name) {
                outcome.kept.append(name)
                continue
            }
            do {
                try fileManager.removeItem(at: entry.url)
                outcome.deleted.append(name)
            } catch {
                outcome.couldNotDelete.append(name)
            }
        }
        outcome.kept += outcome.keptUnreadable
        return outcome
    }

    /// The instant an archive's name carries, or nil when the name is not one
    /// this wrote. Parsing is the inverse of `stamp(for:)`, through the same
    /// timezone and calendar, so the two cannot disagree.
    static func instant(fromArchiveNamed name: String) -> Date? {
        guard name.hasPrefix(archivePrefix) else { return nil }
        let stamp = String(name.dropFirst(archivePrefix.count))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = BusinessCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: stamp)
    }

    private static func monthKey(for instant: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = BusinessCalendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: instant)
    }

    // MARK: plumbing

    static let archivePrefix = "Ovation-backup-"

    /// Where an archive is built, and deliberately NOT starting with
    /// `archivePrefix`, so nothing reading the archives can see one mid build
    /// (ovation#226).
    static let stagingPrefix = "Ovation-staging-"

    /// Where an archive that did not verify is kept. Its own prefix, so it
    /// survives as the evidence of what went wrong without counting as a backup.
    static let unverifiedPrefix = "Ovation-unverified-"

    /// Named in Ovation's own timezone, not the host's, so two archives taken
    /// either side of a trip are still in order.
    static func archiveName(for instant: Date) -> String { archivePrefix + stamp(for: instant) }

    static func stamp(for instant: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = BusinessCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: instant)
    }

    /// Every regular file under a directory, as relative paths, sorted.
    private func walk(_ directory: URL) throws -> [String] {
        guard let walker = fileManager.enumerator(at: directory,
                                                  includingPropertiesForKeys: [.isRegularFileKey],
                                                  options: [.skipsHiddenFiles]) else {
            throw BackupError.couldNotRead(directory.path)
        }
        let base = directory.standardizedFileURL.path + "/"
        var found: [String] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            let relative = String(path.dropFirst(base.count))
            guard relative != BackupManifest.filename else { continue }
            found.append(relative)
        }
        return found.sorted()
    }

    private func readFile(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw BackupError.couldNotRead(url.path)
        }
    }

    private func write(_ manifest: BackupManifest, to archive: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            try encoder.encode(manifest)
                .write(to: archive.appendingPathComponent(BackupManifest.filename), options: .atomic)
        } catch {
            throw BackupError.couldNotWrite(BackupManifest.filename)
        }
    }
}
