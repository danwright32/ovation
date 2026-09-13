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
        case refused(String)
    }

    private let service: BackupService
    private let now: @MainActor () -> Date

    init(service: BackupService, now: @escaping @MainActor () -> Date) {
        self.service = service
        self.now = now
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

    /// What restoring this archive will do, DERIVED from what it holds.
    ///
    /// A confirmation that reads the same taking one file or a whole folder is
    /// one nobody reads twice, so the sentence is built from the archive's own
    /// manifest rather than written once and reused (L180).
    func consequence(of name: String) throws -> String {
        let manifest = try service.manifest(of: url(of: name))
        let members = manifest.members.filter { $0.status == .copied }.map(\.path)
        let list = members.sorted().joined(separator: ", ")
        return "Restoring this backup replaces \(list) in Ovation's data folder "
            + "with what they were when it was taken. Ovation keeps a copy of "
            + "everything as it is now BEFORE it does, so this can be undone."
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
        do {
            try service.restore(from: archive, now: now())
        } catch BackupError.verificationFailed(let failures) {
            return .refused("\(name) does not verify, so it was NOT restored: "
                            + "\(failures.count) problem(s) with what is in it. "
                            + "Nothing in Ovation has been changed.")
        } catch {
            return .refused("\(name) could not be restored: \(error). "
                            + "Nothing in Ovation has been changed.")
        }
        // SAID FROM THE FINISHED STATE, never from the path that got here (L78).
        let restored = (try? service.manifest(of: archive))?
            .members.filter { $0.status == .copied }.map(\.path).sorted() ?? []
        return .restored("Ovation was restored from \(name): "
                         + "\(restored.joined(separator: ", ")) put back. "
                         + "A copy of what was there before is in the same folder.")
    }

    private func url(of name: String) -> URL {
        service.backupsDirectory.appendingPathComponent(name, isDirectory: true)
    }
}
