import Foundation
import Testing

/// ovation#231. WHERE DAN CHOOSES THE BACKUP FOLDER.
///
/// Dan's answer, 2026-09-11: the standard Mac Settings window rather than a
/// fifth entry in the rail. The rail holds places you work; this is a place you
/// configure, and PRD 9 needs a settings home anyway for the invoice identity,
/// the payment instructions and the note to customer.
///
/// THE PANEL IS INJECTED, so every outcome is reachable without a person
/// clicking: a presenter that opened its own `NSOpenPanel` would be beyond every
/// refusal a test could offer (L196), and none of the cases below could exist.
@MainActor
struct BackupSettingsPresenterTests {

    @Test("choosing a folder remembers it, and the pane says so")
    func choosingRemembersIt() throws {
        let world = try World()

        let outcome = world.presenter.choose()

        #expect(outcome == .chosen(world.folder.standardizedFileURL))
        #expect(world.presenter.resolution == .chosen(world.folder.standardizedFileURL))
    }

    /// A PANEL DISMISSED CHANGES NOTHING. Cancelling is not a refusal and must
    /// not be reported as one, nor may it clear a folder already chosen (L11).
    @Test("dismissing the panel changes nothing")
    func dismissingChangesNothing() throws {
        let world = try World()
        _ = world.presenter.choose()
        world.panelAnswers = nil

        let outcome = world.presenter.choose()

        #expect(outcome == .cancelled)
        #expect(world.presenter.resolution == .chosen(world.folder.standardizedFileURL))
    }

    /// A FOLDER INSIDE THE DATA DIRECTORY IS REFUSED. Each archive copies the
    /// whole data directory, so a backup folder inside it would make archive N
    /// contain archives 1 to N-1: the growth is exponential and the hashing pass
    /// quadratic. Nothing stopped this before, and an open panel will happily
    /// offer it.
    @Test("a folder inside the data directory is refused, by name")
    func aFolderInsideTheDataDirectoryIsRefused() throws {
        let world = try World()
        let inside = world.dataDirectory.appendingPathComponent("documents",
                                                                isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        world.panelAnswers = inside

        let outcome = world.presenter.choose()

        guard case .refusedInsideTheDataDirectory(let detail) = outcome else {
            Issue.record("a folder inside the data directory was accepted: \(outcome)")
            return
        }
        #expect(detail.contains("documents"))
        #expect(world.presenter.resolution == .notChosen)
    }

    /// AND THE DATA DIRECTORY ITSELF, which is the same fault one level up and
    /// the one that makes the pre restore snapshot copy itself.
    @Test("the data directory itself is refused too")
    func theDataDirectoryItselfIsRefused() throws {
        let world = try World()
        world.panelAnswers = world.dataDirectory

        guard case .refusedInsideTheDataDirectory = world.presenter.choose() else {
            Issue.record("the data directory itself was accepted as a backup folder")
            return
        }
    }

    /// THE STANDING CONDITION IS RESOLVED WHEN A FOLDER IS CHOSEN. `ProblemsStore`
    /// never retracts on its own, `raise` clears `acknowledgedAt`, and the
    /// presenter shows the oldest first, so a condition re-raised on every launch
    /// would sit at the head of the queue for ever and push every more urgent
    /// notice behind it (ovation#229).
    @Test("choosing a folder resolves the standing no folder condition")
    func choosingResolvesTheStandingCondition() throws {
        let world = try World()
        _ = world.problems.raise(kind: .backupFolderNotChosen, subject: "backups",
                                 sentence: "No backup folder has been chosen yet.",
                                 now: world.instant)
        #expect(world.problems.open.contains { $0.kind == .backupFolderNotChosen })

        _ = world.presenter.choose()

        #expect(!world.problems.open.contains { $0.kind == .backupFolderNotChosen })
    }

    /// A REFUSED CHOICE RESOLVES NOTHING. The standing condition is still true:
    /// there is still no folder (L98).
    @Test("a refused choice leaves the standing condition standing")
    func aRefusedChoiceResolvesNothing() throws {
        let world = try World()
        _ = world.problems.raise(kind: .backupFolderNotChosen, subject: "backups",
                                 sentence: "No backup folder has been chosen yet.",
                                 now: world.instant)
        world.panelAnswers = world.dataDirectory

        _ = world.presenter.choose()

        #expect(world.problems.open.contains { $0.kind == .backupFolderNotChosen })
    }

    /// THE SENTENCE IS COMPOSED FROM THE RULE, never typed beside it. A
    /// consequence sentence that enumerates what an action does is a second copy
    /// of the action's own list, so the day the policy changes the sentence stays
    /// true and goes incomplete, and every word still in it is correct (L679).
    @Test("what the pane promises is built from the retention constant")
    func theSentenceComesFromTheConstant() throws {
        let world = try World()

        #expect(world.presenter.retentionSentence
            .contains(String(BackupService.defaultDailyKeep)))
    }

    // MARK: the fixture

    @MainActor
    private final class World {
        let root: URL
        let dataDirectory: URL
        let folder: URL
        let problems: ProblemsStore
        let presenter: BackupSettingsPresenter
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)
        /// What the panel hands back next. Held in a BOX rather than on the
        /// fixture, because the closure has to be built before the presenter and
        /// capturing `self` there reads a property that does not exist yet.
        private let answer = Answer()
        var panelAnswers: URL? {
            get { answer.url }
            set { answer.url = newValue }
        }

        final class Answer: @unchecked Sendable { var url: URL? }

        init() throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("ovation-settings-\(UUID().uuidString)",
                                        isDirectory: true)
            dataDirectory = root.appendingPathComponent("Ovation", isDirectory: true)
            folder = root.appendingPathComponent("Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: dataDirectory,
                                                    withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: folder,
                                                    withIntermediateDirectories: true)
            guard let defaults = UserDefaults(suiteName: "ovation.tests.\(UUID().uuidString)")
            else { throw FixtureFailure.couldNotMakeDefaults }

            problems = ProblemsStore(journal: InMemoryProblemsJournal())
            answer.url = folder
            // The closure reads the BOX at press time rather than capturing a
            // value, so a case can change what the panel answers between presses.
            let box = answer
            let answers = { box.url }
            presenter = BackupSettingsPresenter(
                setting: BackupFolderSetting(defaults: defaults,
                                             isDisposableLaunch: { false }),
                dataDirectory: dataDirectory,
                problems: problems,
                now: { Date(timeIntervalSinceReferenceDate: 800_000_000) },
                askForAFolder: answers)
        }
    }

    enum FixtureFailure: Error {
        case couldNotMakeDefaults
    }
}
