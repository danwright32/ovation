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
        if secondInstance.mayRun, let storeURL = StoreLocation.liveStoreURL() {
            StoreLaunchSequence(
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
                }
            ).run(now: Date())
        }

        let presenter = LaunchPresenter(store: store)
        presenter.refresh()

        _store = State(initialValue: store)
        _presenter = State(initialValue: presenter)
    }

    var body: some Scene {
        Window(OvationBuild.displayName, id: OvationBuild.mainWindowID) {
            RootView(presenter: presenter, store: store)
        }
    }
}
