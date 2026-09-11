import SwiftData
import SwiftUI

// The entry point, and the ONE file the pure test target cannot compile in,
// because it carries @main. Everything the tests need lives elsewhere so that
// the pure suite is not dragged behind the entry point (project.yml).
//
// Ovation is single window ON PURPOSE (PRD 41b). A flag on shared application
// state is presented once per SURFACE bound to it, so a second window would put
// up a second copy of every launch notice and dismissing one would leave the
// other standing (L238). The menu bar item and any URL handler bring THIS window
// forward rather than opening another.
@main
struct OvationApp: App {
    @State private var store: ProblemsStore
    @State private var presenter: LaunchPresenter
    /// ovation#162. The control behind the staleness notice. It is held here
    /// because it must be the SAME object the whole time the app is open: a fresh
    /// one per press could not know that a run is already going, and two exports
    /// over one folder write the same three files over each other.
    @State private var exportCommand: YearEndExportCommand
    /// The store the launch sequence opened, handed on rather than opened again:
    /// two containers over one file are two writers (ovation#84).
    @State private var opened: ModelContainer?
    /// ovation#40, PRD 44a. The roster pass and the rail around it. Both nil
    /// where no store was opened, which is every disposable launch, and where
    /// the client list could not be read, which raises its own problem.
    @State private var roster: RosterPresenter?
    @State private var shell: ShellPresenter?

    init() {
        // A disposable launch gets a journal that writes nowhere, so nothing a
        // test or a throwaway run reports can reach Dan's real history
        // (plan 1.9). The refusal lives where the path is resolved, so this is
        // the only decision made here.
        let journal: ProblemsJournal = FileProblemsJournal.liveURL()
            .map { FileProblemsJournal(url: $0) } ?? InMemoryProblemsJournal()

        let store = ProblemsStore(journal: journal)
        store.load(now: Date())

        // A SECOND RUNNING COPY STANDS ASIDE, BEFORE ANYTHING IS OPENED
        // (ovation#84, plan 1.3, PRD 5.37). Two copies over one store are two
        // writers of Dan's invoices, and the serialized writers that make the
        // rules enforceable serialize within ONE process: nothing in them can
        // see a second one, so an invoice number issued twice is reachable only
        // this way.
        //
        // It is checked HERE, before the launch sequence, because that sequence
        // writes: it checkpoints, backs up and opens. Standing aside afterwards
        // would be standing aside after doing the dangerous part.
        //
        // The refusal reaches Dan through the one launch presenter below, never
        // as an independent alert (L242).
        let ownExecutable = Bundle.main.executableURL?.resolvingSymlinksInPath().path
        let secondInstance = ownExecutable.map {
            SecondInstance.check(executablePath: $0, runningPIDs: SecondInstance.pidsRunning)
        } ?? .theOnlyCopy

        if let sentence = SecondInstance.sentence(for: secondInstance),
           case .standingAsideFor(let pid, _) = secondInstance {
            _ = store.raise(kind: .secondRunningCopy, subject: String(pid),
                            sentence: sentence, now: Date())
        }

        // THE LAUNCH SEQUENCE RUNS HERE, BEFORE THE PRESENTER REFRESHES, so a
        // refusal it raises is in the store by the time the first screen asks
        // what is wrong. Identify, checkpoint, back up, then open (plan 1.2).
        //
        // A disposable launch does none of it. `StoreLocation.liveStoreURL`
        // refuses under one, so there is nothing to identify and nothing to back
        // up, and running the sequence against a fabricated path would raise
        // problems about a store nobody has (plan 1.9, the isolation floor).
        // The container the sequence opens, caught on its way past so the export
        // command can read the store Dan is actually looking at (ovation#162).
        let openedStore = OpenedStore()

        if secondInstance.mayRun, let storeURL = StoreLocation.liveStoreURL() {
            var sequence = StoreLaunchSequence(
                storeURL: storeURL,
                problems: store,
                checkpoint: { StoreCheckpoint.run(storeURL: $0) },
                takeBackup: { _ in
                    // ovation#87 chooses the folder and schedules this. Until it
                    // does there is nowhere to write, and saying so through the
                    // Problems store is honest, where a silent no-op would leave
                    // the sequence reporting a backup it never took (L98).
                    throw BackupError.couldNotWrite("no backup folder has been chosen yet")
                },
                openContainer: { try OvationSchema.container(at: $0) },
                identify: {
                    StoreSchemaGuard.inspect(
                        storeURL: $0,
                        ownEntityTables: StoreSchemaGuard.entityTableNames(
                            for: OvationSchema.schema),
                        runningVersion: OvationSchema.versionedSchema.versionIdentifier)
                },
                // ovation#107. PRD 5.4's starting service types, into a store
                // that holds none. It runs here rather than anywhere a screen
                // could reach, because it must happen exactly once on an empty
                // store and never again: a rename Dan makes from inside an
                // invoice must not be undone by the next launch.
                seed: { try ServiceTypeSeed.seedIfEmpty(ModelContext($0)) },
                // ovation#116. Written after the open that established it, so the
                // next launch can refuse a downgrade before opening anything.
                recordVersion: {
                    try StoreVersionMarker.write(
                        OvationSchema.versionedSchema.versionIdentifier, besideStoreAt: $0)
                },
                // ovation#64. What is true about the year end export, derived at
                // every launch from the durable run record rather than stored as
                // a conclusion (L175). Both notices reach Dan through the same
                // presenter as everything else (L242).
                //
                // A RUN RECORD THAT EXISTS AND CANNOT BE READ IS ITS OWN PROBLEM,
                // never an empty history: an unreadable log would otherwise raise
                // staleness, which is a true sentence for the wrong reason and
                // sends Dan to run an export rather than to look at a damaged
                // file (L11, L215).
                exportNotices: { container, now in
                    guard let url = ExportRunLog.liveExportRunRecord() else { return [] }
                    let log = ExportRunLog(url: url)
                    let loaded: (runs: [ExportRun], skipped: Int)
                    do {
                        loaded = try log.load()
                    } catch {
                        _ = store.raise(
                            kind: .exportRunRecordUnreadable, subject: url.lastPathComponent,
                            sentence: "Ovation could not read its record of past exports at "
                                + "\(url.path): \(error.localizedDescription). Until it can, it "
                                + "cannot tell you when an export was last run.",
                            now: now)
                        return []
                    }
                    if loaded.skipped > 0 {
                        _ = store.raise(
                            kind: .exportRunRecordDamaged, subject: url.lastPathComponent,
                            sentence: "\(loaded.skipped) line(s) of Ovation's record of past "
                                + "exports could not be read. The runs they describe are lost "
                                + "from that history, and a staleness notice may name an older "
                                + "run than the one that actually happened.",
                            now: now)
                    }
                    return ExportRunLog.notices(
                        from: loaded.runs, now: now,
                        storeHasEverHeldSomethingToExport:
                            ExportRunLog.storeHasSomethingToExport(container))
                },
                // ovation#208. Downbeat's client roster, brought across and kept
                // in step. Nothing in Ovation created a client before this, so
                // the roster screen was correct and drew nothing.
                //
                // THE PATH IS PASSED IN RATHER THAN DEFAULTED, which is Downbeat's
                // own rule about this same file (downbeat#133): whether a launch
                // may read it is a decision made here, once, and not something a
                // convenient default makes for every caller.
                //
                // A READ OR A SAVE THAT FAILS IS A NOTICE, never a silent empty
                // roster. An import that returned nothing because it could not
                // read anything would be indistinguishable from one that ran and
                // found nothing to do, which is the outcome that happens on almost
                // every launch (L98).
                importClients: { container in
                    let support = FileManager.default.urls(
                        for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    let url = ClientImportRunner.productionURL(
                        applicationSupportDirectory: support)
                    let context = ModelContext(container)

                    var held: [Client]
                    do {
                        held = try context.fetch(FetchDescriptor<Client>())
                    } catch {
                        return [.couldNotRead(
                            file: url.lastPathComponent,
                            refusal: .notReadable(
                                detail: "Ovation could not read its own client list: "
                                    + error.localizedDescription))]
                    }

                    let result = ClientImportRunner.run(file: url, held: &held) {
                        try Data(contentsOf: $0)
                    }
                    guard !result.created.isEmpty || !result.notices.isEmpty else {
                        return []
                    }
                    for client in result.created { context.insert(client) }
                    do {
                        try context.save()
                    } catch {
                        return [.couldNotRead(
                            file: url.lastPathComponent,
                            refusal: .notReadable(
                                detail: "the clients could not be saved: "
                                    + error.localizedDescription))]
                    }
                    return result.notices
                }
            )
            sequence.onOpened = { openedStore.container = $0 }
            sequence.run(now: Date())
        }

        // ovation#40. The roster is read BEFORE the presenter refreshes, so that
        // a client list it could not read is already in the store by the time
        // the first screen asks what is wrong. Same ordering, and the same
        // reason, as the launch sequence above.
        //
        // ONE CONTEXT, held by the closures it was made for. The fetch and the
        // save must be the same context or a change is written back through a
        // second one, which is two writers over one file (ovation#84).
        var rosterPair: (roster: RosterPresenter, shell: ShellPresenter)?
        if let container = openedStore.container {
            let context = ModelContext(container)
            rosterPair = RosterLaunch.presenters(
                fetchClients: { try context.fetch(FetchDescriptor<Client>()) },
                save: { try context.save() },
                problems: store,
                now: Date())
        }

        let presenter = LaunchPresenter(store: store)
        presenter.refresh()

        _store = State(initialValue: store)
        _presenter = State(initialValue: presenter)
        _opened = State(initialValue: openedStore.container)
        _roster = State(initialValue: rosterPair?.roster)
        _shell = State(initialValue: rosterPair?.shell)
        // THE COMMAND IS BUILT EVEN WHEN THERE IS NOWHERE TO WRITE, and answers
        // why rather than being absent. A menu item that vanishes on a throwaway
        // launch teaches nothing; one that is there and says what is missing is
        // the difference between a dead control and a refusal (L109).
        _exportCommand = State(initialValue: YearEndExportCommand.forThisLaunch())
    }

    /// A box, because the launch sequence's hook is `@Sendable` and this runs
    /// before `self` exists.
    private final class OpenedStore: @unchecked Sendable {
        var container: ModelContainer?
    }

    var body: some Scene {
        Window(OvationBuild.displayName, id: OvationBuild.mainWindowID) {
            RootView(presenter: presenter, store: store, exportCommand: exportCommand,
                     roster: roster, shell: shell)
        }
        // ovation#162. THE CONTROL THE STALENESS NOTICE NAMES. Until this existed
        // `YearEndExport.run` was called by nothing, so that notice named a
        // remedy nobody could reach and pressing on was the only diagnosis
        // available (L109, L111, L148).
        //
        // IT IS NEVER HIDDEN, only disabled with a reason said out loud, because
        // a control that is not there cannot be asked why (L49).
        .commands {
            CommandGroup(after: .newItem) {
                Button(YearEndExportCommand.title) { runExport() }
                    .disabled(whyTheExportCannotRun != nil)
                if let why = whyTheExportCannotRun {
                    Text(why).font(.footnote)
                }
            }
        }
    }

    /// Why the menu item would do nothing, in Dan's words rather than the code's
    /// (L399). A disabled control with no reason is a dead control (L109).
    ///
    /// WHETHER IT IS DISABLED AND WHAT IT SAYS COME FROM THIS ONE ANSWER. They
    /// were two conditions written beside each other, and two conditions about
    /// one thing are two things that can disagree (L70).
    private var whyTheExportCannotRun: String? {
        exportCommand.whyItCannotRun(container: opened)
    }

    /// Runs one export through the command, which is the one place that marks a
    /// run started and finished and reports what it came to.
    private func runExport() {
        // NO GUARD THAT RETURNS SILENTLY. A press with no open store is a refusal
        // the command states, not a press that quietly does nothing (L109).
        exportCommand.press(now: Date(), container: opened, problems: store) {
            presenter.refresh()
        }
    }
}
