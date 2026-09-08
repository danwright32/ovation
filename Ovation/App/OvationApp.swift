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

        // THE LAUNCH SEQUENCE RUNS HERE, BEFORE THE PRESENTER REFRESHES, so a
        // refusal it raises is in the store by the time the first screen asks
        // what is wrong. Identify, checkpoint, back up, then open (plan 1.2).
        //
        // A disposable launch does none of it. `StoreLocation.liveStoreURL`
        // refuses under one, so there is nothing to identify and nothing to back
        // up, and running the sequence against a fabricated path would raise
        // problems about a store nobody has (plan 1.9, the isolation floor).
        if let storeURL = StoreLocation.liveStoreURL() {
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
