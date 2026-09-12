// ovation#231. WHERE DAN CHOOSES THE BACKUP FOLDER.
//
// Dan's answer, 2026-09-11: the standard Mac Settings window rather than a fifth
// entry in the rail. The rail holds places you work; this is a place you
// configure, and PRD 9 needs a settings home anyway for the invoice identity,
// the payment instructions and the note to customer, so the room is built once
// and this is the first thing in it.
//
// THE PANEL IS INJECTED. A presenter that opened its own `NSOpenPanel` would be
// beyond every refusal a test could offer (L196), and none of the outcomes below
// could be reached without a person clicking.
//
// IT IS A SECOND WINDOW, which `OvationApp` is otherwise deliberately without: a
// flag on shared state is presented once per SURFACE bound to it, so a second
// window would put up a second copy of every launch notice and dismissing one
// would leave the other standing (L238). This binds to the folder setting and to
// the problems store's `resolve`, and to nothing that PRESENTS a problem.
import Foundation

@MainActor
@Observable
final class BackupSettingsPresenter {

    /// What one press of Choose did. Four outcomes, because dismissing the panel
    /// is not a refusal, and a folder refused for where it sits is not the same
    /// as one refused for what happened when it was written down (L11).
    enum ChoiceOutcome: Equatable {
        case chosen(URL)
        /// Dismissed. Changes nothing, including a folder already chosen.
        case cancelled
        case refusedInsideTheDataDirectory(String)
        case refused(String)
    }

    private(set) var resolution: BackupFolderSetting.Resolution

    private let setting: BackupFolderSetting
    private let dataDirectory: URL
    private let problems: ProblemsStore
    private let now: @Sendable () -> Date
    private let askForAFolder: () -> URL?

    init(setting: BackupFolderSetting,
         dataDirectory: URL,
         problems: ProblemsStore,
         now: @escaping @Sendable () -> Date,
         askForAFolder: @escaping () -> URL?) {
        self.setting = setting
        self.dataDirectory = dataDirectory
        self.problems = problems
        self.now = now
        self.askForAFolder = askForAFolder
        self.resolution = setting.resolve()
    }

    /// What Ovation will do with the folder, composed FROM the rule rather than
    /// typed beside it.
    ///
    /// A consequence sentence that enumerates what an action does is a second
    /// copy of the action's own list, so the day the policy changes the sentence
    /// stays true and goes incomplete, and every word still in it is correct
    /// (L679).
    var retentionSentence: String {
        "Ovation copies everything it holds into this folder once a day, when it "
            + "starts. It keeps the most recent \(BackupService.defaultDailyKeep), "
            + "and the last one of every month for good."
    }

    @discardableResult
    func choose() -> ChoiceOutcome {
        guard let folder = askForAFolder() else { return .cancelled }
        let standardized = folder.standardizedFileURL

        // INSIDE THE DATA DIRECTORY IS REFUSED. Each archive copies the whole
        // data directory, so a backup folder inside it makes archive N contain
        // archives 1 to N-1: the growth is exponential and the hashing pass
        // quadratic. An open panel will happily offer it, and nothing else
        // refuses it.
        if isInside(dataDirectory, standardized) {
            return .refusedInsideTheDataDirectory(
                "\(standardized.path) is inside Ovation's own data folder, so every "
                    + "backup would contain every backup before it.")
        }

        do {
            try setting.remember(standardized)
        } catch {
            return .refused("\(standardized.path) could not be remembered: \(error)")
        }

        resolution = setting.resolve()

        // THE STANDING CONDITION IS RESOLVED (ovation#229). `ProblemsStore` never
        // retracts on its own, `raise` clears `acknowledgedAt`, and the presenter
        // shows the oldest first, so a condition re-raised on every launch would
        // sit at the head of the queue for ever and push every more urgent notice
        // behind it.
        for problem in problems.open where problem.kind == .backupFolderNotChosen {
            _ = problems.resolve(problem.id, because: "a backup folder was chosen",
                                 now: now())
        }
        return .chosen(standardized)
    }

    /// Whether `candidate` is the directory itself or sits under it.
    ///
    /// COMPARED AS PATH COMPONENTS, never as a string prefix: `/data-backups` has
    /// `/data` as a string prefix and is a different folder (L266).
    private func isInside(_ directory: URL, _ candidate: URL) -> Bool {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let here = candidate.resolvingSymlinksInPath().pathComponents
        guard here.count >= root.count else { return false }
        return Array(here.prefix(root.count)) == root
    }
}
