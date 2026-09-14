// ovation#247. PUTTING THE RECORDS BACK, from inside Ovation.
//
// `BackupService.restore` existed, was tested, and took a snapshot of whatever
// was there before replacing anything. Nothing in the app offered it, and PRD 29
// asks for it in as many words: Ovation "writes dated, self contained backups to
// a folder Dan chooses, keeps a rolling set, verifies each is readable after
// writing, and offers Restore in the app".
//
// EVERY OTHER PHASE OF THIS MILESTONE IS WORTH NOTHING on the day it counts if
// getting the data back needs a terminal, a path, and somebody who remembers the
// command. That day is by definition a bad one: a store that will not open, a
// Mac being replaced, a mistake noticed months later.
//
// THE DANGEROUS PART IS THE SURFACE, not the engine. Choosing which archive,
// saying what will be replaced BEFORE it is, refusing one that is not sound, and
// saying what happened afterwards from the finished state rather than from the
// code path that got there (L78, L180).
import Foundation

@MainActor
@Observable
final class RestorePresenter {

    /// One archive, as a person has to judge it.
    struct Archive: Equatable, Identifiable {
        var id: String { name }
        let name: String
        /// When it was taken, from its own manifest rather than the file date: a
        /// sync client rewrites mtimes (L414).
        let takenAt: Date?
        /// WHETHER IT VERIFIES NOW, not when it was written. ovation#233 re-checks
        /// one archive per launch, so most carry no recent verdict, and one that
        /// verified in March and has rotted since would otherwise be offered as
        /// though it were sound (L336).
        let verifies: Bool
    }

    enum Outcome: Equatable {
        case restored(String)
        /// A restore that began changing Ovation's data and could not finish
        /// (ovation#258). Its own case because neither of the others is true:
        /// nothing was refused before a change, and nothing was fully put back.
        case partlyRestored(String)
        case refused(String)
    }

    /// THE INGREDIENTS, NOT THE SERVICE, because `BackupService` holds a
    /// `FileManager` and is not Sendable: reading the archives off the main actor
    /// means building one INSIDE that work rather than carrying one across
    /// (ovation#247). The main actor path uses the same recipe, so there is one
    /// definition of what service this presenter talks to (L70).
    private let dataDirectory: URL
    private let backupsDirectory: URL
    private let dailyKeep: Int
    private let referencedDocuments: @Sendable () throws -> [ReferencedDocument]
    private let now: @MainActor () -> Date
    /// What the restore writes through. INJECTED so a test can make a write fail
    /// partway without damaging a disk (ovation#258, L196).
    ///
    /// A MAKER, NOT A FILE MANAGER, and REQUIRED. A `FileManager` is not Sendable
    /// and this presenter is main actor isolated, so a stored one or a default
    /// argument cannot be supplied from a caller off the main actor, which the
    /// fixtures are. A Sendable closure crosses that boundary, and having no
    /// default means no caller writes through a file manager it did not choose.
    /// The off main actor read builds its own, and only reads.
    private let fileManager: @Sendable () -> FileManager

    init(dataDirectory: URL,
         backupsDirectory: URL,
         dailyKeep: Int,
         referencedDocuments: @escaping @Sendable () throws -> [ReferencedDocument],
         now: @escaping @MainActor () -> Date,
         fileManager: @escaping @Sendable () -> FileManager) {
        self.dataDirectory = dataDirectory
        self.backupsDirectory = backupsDirectory
        self.dailyKeep = dailyKeep
        self.referencedDocuments = referencedDocuments
        self.now = now
        self.fileManager = fileManager
    }

    private var service: BackupService {
        BackupService(dataDirectory: dataDirectory,
                      backupsDirectory: backupsDirectory,
                      dailyKeep: dailyKeep,
                      referencedDocuments: referencedDocuments,
                      fileManager: fileManager())
    }

    /// Every archive, newest first, each saying whether it is sound today.
    ///
    /// NEWEST FIRST because that is the one usually wanted, and ordering for the
    /// reader rather than for the data is the rule (L609).
    func archives() throws -> [Archive] {
        try service.archives().reversed().map { url in
            let manifest = try? service.manifest(of: url)
            let report = try? service.verify(archive: url)
            return Archive(name: url.lastPathComponent,
                           takenAt: manifest?.createdAt,
                           verifies: report?.isVerified ?? false)
        }
    }

    /// The same list, read OFF the main actor.
    ///
    /// `archives()` verifies each one, which reads and hashes every file in every
    /// backup. That is the heaviest work in the app, and a surface that called it
    /// on the drawing thread would freeze the window on a folder that syncs to a
    /// NAS: the defect ovation#246 exists to prevent (L241). It goes through the
    /// same helper the launch uses, under the same deadline, so a share that has
    /// gone quiet cannot hang the window either (L110).
    ///
    /// AN EMPTY LIST IS WHAT A FAILURE ANSWERS WITH, and that is honest only
    /// because the surface distinguishes "still looking" from "none": a pane that
    /// showed an empty list while still reading would say the wrong thing (L10).
    func archivesOffTheMainActor() async -> [Archive] {
        let dataDirectory = self.dataDirectory
        let backupsDirectory = self.backupsDirectory
        let dailyKeep = self.dailyKeep
        let referencedDocuments = self.referencedDocuments
        let outcome = await BlockingWork.run { () -> [Archive] in
            // Built HERE, from Sendable values, because the service itself cannot
            // cross the boundary.
            let service = BackupService(dataDirectory: dataDirectory,
                                        backupsDirectory: backupsDirectory,
                                        dailyKeep: dailyKeep,
                                        referencedDocuments: referencedDocuments)
            return try service.archives().reversed().map { url in
                let manifest = try? service.manifest(of: url)
                let report = try? service.verify(archive: url)
                return Archive(name: url.lastPathComponent,
                               takenAt: manifest?.createdAt,
                               verifies: report?.isVerified ?? false)
            }
        }
        if case .answered(let rows) = outcome { return rows }
        return []
    }

    /// What restoring this archive will do, DERIVED from what it holds.
    ///
    /// A confirmation that reads the same taking one file or a whole folder is
    /// one nobody reads twice, so the sentence is built from the archive's own
    /// manifest rather than written once and reused (L180).
    func consequence(of name: String) throws -> String {
        let archive = url(of: name)
        let copied = try service.manifest(of: archive)
            .members.filter { $0.status == .copied }.map(\.path)
        let replaced = copied.filter { BackupPlan.restorePolicy(of: $0) == .replace }.sorted()
        var sentence = "Restoring this backup replaces \(replaced.joined(separator: ", ")) "
            + "in Ovation's data folder with what they were when it was taken."
        // THE QUEUE IS ADDED TO, NOT REPLACED (ovation#253), and which of its two
        // outcomes applies is decided by the same predicate the restore uses, so
        // this cannot promise a booking back that the restore will hold (L16).
        if copied.contains(where: { BackupPlan.restorePolicy(of: $0) == .addMissingBookings }) {
            sentence += try service.holdsQueuedBookingsBack(restoring: archive)
                ? " Any queued booking in it that is missing now is held back, because "
                    + "Ovation cannot yet tell whether it was already invoiced."
                : " Any queued booking in it that is missing now is added back, and no "
                    + "booking already in the queue is removed or changed."
        }
        if copied.contains(where: { BackupPlan.restorePolicy(of: $0).isNeverRestored }) {
            sentence += " Downbeat's own record of what it queued is left as it is."
        }
        return sentence + " Ovation keeps a copy of everything as it is now BEFORE it "
            + "does, so this can be undone."
    }

    /// Put it back.
    ///
    /// IT REFUSES AN ARCHIVE THAT DOES NOT VERIFY rather than restoring it with a
    /// warning. Replacing good state with one known to be damaged is the single
    /// mistake this whole milestone exists to prevent (L5), and a warning that
    /// can be clicked past is not a refusal.
    @discardableResult
    func restore(_ name: String) -> Outcome {
        let archive = url(of: name)
        let result: BackupService.RestoreResult
        do {
            result = try service.restore(from: archive, now: now())
        } catch BackupError.verificationFailed(let failures) {
            return .refused("\(name) does not verify, so it was NOT restored: "
                            + "\(failures.count) problem(s) with what is in it. "
                            + "Nothing in Ovation has been changed.")
        } catch BackupError.restoredPartway(let replaced, let failedAt, let snapshot, let cause) {
            // THE DATA FOLDER IS NOW A MIX (ovation#258), so this can never borrow
            // the sentence below. It names what went back, what may be missing, and
            // the snapshot, because the snapshot is the way back (L11, L12).
            //
            // AND WHY IT STOPPED (ovation#269). Freeing space, granting access again
            // and reconnecting a drive are three different remedies, and a sentence
            // that names only where it stopped leaves Dan guessing which one applies.
            let done = replaced.isEmpty
                ? "Nothing had been put back yet"
                : "\(replaced.sorted().joined(separator: ", ")) had been put back"
            return .partlyRestored(
                "\(name) was only partly restored. \(done) when \(failedAt) could not be: "
                    + "\(Self.asSentence(cause)) So \(failedAt) may now be missing or "
                    + "incomplete, and Ovation's data is a mix of the backup and what was "
                    + "there before. Everything as it was just before the restore is in "
                    + "\(snapshot), in the backups folder.")
        } catch {
            // ONLY A FAILURE BEFORE THE SNAPSHOT REACHES HERE, because the service
            // turns every failure after it into `restoredPartway`, so this sentence
            // is true wherever it is shown.
            return .refused("\(name) could not be restored: \(error). "
                            + "Nothing in Ovation has been changed.")
        }
        // SAID FROM THE FINISHED STATE, never from the path that got here (L78).
        let copied = (try? service.manifest(of: archive))?
            .members.filter { $0.status == .copied }.map(\.path) ?? []
        let replaced = copied.filter { BackupPlan.restorePolicy(of: $0) == .replace }.sorted()
        var detail = "Ovation was restored from \(name): "
            + "\(replaced.joined(separator: ", ")) put back."
        if copied.contains(where: { BackupPlan.restorePolicy(of: $0) == .addMissingBookings }) {
            detail += " " + Self.whatHappenedToTheQueue(result)
        }
        return .restored(detail + " A copy of what was there before is in the same folder.")
    }

    /// The queue's own sentence, one per outcome, because a booking held back
    /// needs something from Dan and a booking put back does not (L11).
    private static func whatHappenedToTheQueue(_ result: BackupService.RestoreResult) -> String {
        let held = result.bookingsHeldBack.count
        let added = result.bookingsAddedBack.count
        if held > 0 {
            return "\(bookings(held)) held back, because Ovation cannot yet tell whether "
                + "\(held == 1 ? "it was" : "they were") already invoiced. "
                + "The backup still holds \(held == 1 ? "it" : "them")."
        }
        if added > 0 {
            return "\(bookings(added)) added back."
        }
        return "Every queued booking in it is already in the queue."
    }

    /// A cause ends in a full stop before the next sentence starts, whether or not
    /// the text it came from had one.
    private static func asSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }

    private static func bookings(_ count: Int) -> String {
        count == 1 ? "1 queued booking" : "\(count) queued bookings"
    }

    private func url(of name: String) -> URL {
        backupsDirectory.appendingPathComponent(name, isDirectory: true)
    }
}
