import BackstageGoogle
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
    /// ovation#461. The control that turns what Downbeat has queued into drafts,
    /// which is the shortcut ovation#32's drain replaces.
    @State private var draftCommand: BookingDraftCommand
    /// The store the launch sequence opened, handed on rather than opened again:
    /// two containers over one file are two writers (ovation#84).
    @State private var opened: ModelContainer?
    /// ovation#40, PRD 44a. The roster pass and the rail around it. Both nil
    /// where no store was opened, which is every disposable launch, and where
    /// the client list could not be read, which raises its own problem.
    @State private var roster: RosterPresenter?
    @State private var shell: ShellPresenter?
    /// The invoice list, which is the screen the window opens on (ovation#49),
    /// and the thing that keeps it true (ovation#451).
    ///
    /// IT IS THE SOURCE THAT IS HELD, not the two figures it derives. Those used
    /// to be two pieces of state here, built once inside the launch and never
    /// rebuilt, so the list, the card's counts and the rail's held money figure
    /// were a photograph of the store taken at launch (L14). The source re-reads
    /// on every write to the store, and holding it rather than its output is what
    /// makes that reach the window.
    @State private var invoiceList: InvoiceListSource?
    #if DEBUG
    /// ovation#318 B5. Which review sheet sample is on screen, in the Debug build
    /// only. Real invoices reach the sheet with ovation#42.
    @State private var samples = ReviewSamplesCommand()
    #endif
    /// ovation#457. What the Edit menu may offer about the invoice on screen.
    /// The shell publishes into it and the menu below reads it.
    ///
    /// OUTSIDE THE DEBUG BLOCK, which is where it first landed: the Edit menu
    /// ships, so a declaration only the Debug build has compiles on this Mac and
    /// fails the Release build. `scripts/build-products.sh` builds both for
    /// exactly this reason.
    @State private var edits = InvoiceEditCommand()
    /// ovation#246. What the window shows while the launch runs behind it.
    @State private var progress = LaunchProgress()
    /// Whether the second copy check said this one may run, carried from init so
    /// the launch can read it once the window exists.
    @State private var secondInstance: SecondInstance.Verdict = .theOnlyCopy
    /// IT RUNS EXACTLY ONCE. A re-entered launch would open a second container
    /// over one file, which is two writers (ovation#84).
    @State private var hasLaunched = false
    /// ovation#231. The Backups pane's own state, built here because the window
    /// that shows it is a Scene rather than a view with a lifetime.
    @State private var backupSettings: BackupSettingsPresenter

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

        let presenter = LaunchPresenter(store: store)
        presenter.refresh()

        _store = State(initialValue: store)
        _presenter = State(initialValue: presenter)
        // NOTHING IS OPEN YET, and that is the change ovation#246 made. The
        // launch sequence used to run HERE, before any window existed, so a slow
        // backup and a failure to start looked identical and there was no surface
        // to tell them apart. It now runs from a task once the window is up, in
        // the same order, and these are filled in when it finishes.
        _opened = State(initialValue: nil)
        _roster = State(initialValue: nil)
        _shell = State(initialValue: nil)
        _secondInstance = State(initialValue: secondInstance)
        // The Backups pane, built with the live setting and the real data
        // directory, so the folder it refuses is the one it would damage.
        let dataDirectory = StoreLocation.liveStoreURL()?.deletingLastPathComponent()
            ?? StoreLocation.appSupport
        _backupSettings = State(initialValue: BackupSettingsPresenter(
            setting: BackupFolderSetting(
                defaults: .standard,
                isDisposableLaunch: { AppEnvironment.isDisposableLaunch() }),
            dataDirectory: dataDirectory,
            problems: store,
            now: Date.init,
            askForAFolder: { SettingsFolderPanel.ask() }))
        // THE COMMAND IS BUILT EVEN WHEN THERE IS NOWHERE TO WRITE, and answers
        // why rather than being absent. A menu item that vanishes on a throwaway
        // launch teaches nothing; one that is there and says what is missing is
        // the difference between a dead control and a refusal (L109).
        _exportCommand = State(initialValue: YearEndExportCommand.forThisLaunch())
        _draftCommand = State(initialValue: BookingDraftCommand.forThisLaunch())
    }


    /// THE LAUNCH, RUN ONCE THE WINDOW EXISTS (ovation#246).
    ///
    /// The ORDER is unchanged and is still the requirement: identify,
    /// checkpoint, prepare, back up, check the backups, then open. What changed
    /// is only WHEN it starts: before, it ran inside `init`, so nothing was on
    /// screen while it worked and a slow backup was indistinguishable from an app
    /// that would not start. Dan's standing rule wants started, still alive and
    /// failed to be three different things, and none of them can be shown from a
    /// place with no window.
    ///
    /// IT RUNS EXACTLY ONCE. `.task` is tied to the view's lifetime and a
    /// re-entered launch would open a second container over one file, which is
    /// two writers (ovation#84).
    @MainActor
    private func startLaunch() async {
        guard !hasLaunched else { return }
        hasLaunched = true

        let store = self.store
        let secondInstance = self.secondInstance
        let openedStore = OpenedStore()
        if secondInstance.mayRun, let storeURL = StoreLocation.liveStoreURL() {
            var sequence = StoreLaunchSequence(
                storeURL: storeURL,
                problems: store,
                checkpoint: { StoreCheckpoint.run(storeURL: $0) },
                // ovation#222. The directories BackupPlan requires, made before
                // the backup that refuses without them. Measured on this Mac:
                // the real data directory had no `documents` at all, and nothing
                // in the app created one until a receipt is filed (ovation#78).
                prepareDataDirectory: { try DataDirectory.prepare(storeURL.deletingLastPathComponent()) },
                takeBackup: { now in
                    // ovation#225 and ovation#228. The folder Dan chose, and one
                    // backup a day taken from it.
                    //
                    // The Debug build is given no folder at all, decided in
                    // `BackupFolderSetting.folderToBackUpInto` where both branches
                    // are testable (ovation#228).
                    //
                    // OFF THE MAIN ACTOR (ovation#246). Copying and hashing
                    // everything Ovation holds is the slowest thing a launch
                    // does, and on a folder that syncs to a NAS it is one to two
                    // orders of magnitude slower per file than the local disk the
                    // only measurement was taken on (L522). Run on the main actor
                    // it would leave the window up and frozen, which is a
                    // different defect from the one showing a window fixed.
                    //
                    // NOTHING CROSSES THE BOUNDARY but a URL and a Date: the
                    // service is built INSIDE the task, so no non-Sendable value
                    // has to travel.
                    //
                    // THROUGH BlockingWork, NOT Task.detached. The cooperative
                    // pool is about one thread per core and does not grow, so
                    // work that BLOCKS a thread never gives it back and enough of
                    // them starve every other await (L241). Copying and hashing a
                    // whole data directory is exactly that shape.
                    // `check-forbidden-constructs.sh` refuses the wrong one, and
                    // it caught this in the writing.
                    //
                    // THROUGH LaunchBackupOutcome.run, which is BlockingWork with
                    // the backup's own error carried out intact (ovation#505).
                    // Through BlockingWork alone, the throw below arrived as text
                    // and was read as a write failure.
                    return try await LaunchBackupOutcome.run {
                        // WHY THERE IS NO FOLDER IS THROWN AS THE REASON. Saying
                        // so through the Problems store is honest, where a silent
                        // no-op would leave the sequence reporting a backup it
                        // never took (L98). "Nothing chosen" is its own error
                        // (ovation#262), and so is "this build never backs up"
                        // (ovation#505), because on a launch about to upgrade the
                        // store the first refuses and the second does not.
                        let folder = try BackupFolderSetting.liveBackupDestination.get()
                        let service = BackupService(
                            dataDirectory: storeURL.deletingLastPathComponent(),
                            backupsDirectory: folder,
                            dailyKeep: BackupService.defaultDailyKeep,
                            referencedDocuments: {
                                try StoreDocumentReferences.read(storeURL: storeURL)
                            })
                        return try service.takeBackupIfDueToday(now: now)
                    }
                },
                // ovation#230. Whether the archives have kept up with the store,
                // read from the folder Dan chose. A build that never backs up has
                // nothing to judge, and neither does a launch with no folder, so
                // both answer `current` rather than raising a notice about a
                // feature that is not on.
                backupCurrency: { now in
                    guard let folder = BackupFolderSetting.liveBackupsDirectory else {
                        return .current
                    }
                    let service = BackupService(
                        dataDirectory: storeURL.deletingLastPathComponent(),
                        backupsDirectory: folder,
                        dailyKeep: BackupService.defaultDailyKeep,
                        referencedDocuments: {
                            try StoreDocumentReferences.read(storeURL: storeURL)
                        })
                    return BackupService.currency(
                        newestArchive: try? service.newestArchiveCreatedAt(),
                        dataChanged: BackupService.dataChangedAt(storeURL: storeURL),
                        now: now)
                },
                // ovation#233. One older archive, checked again, so bit rot in a
                // months old archive is found rather than assumed. A build with no
                // folder has nothing to check.
                reverifyAnArchive: { now in
                    // OFF THE MAIN ACTOR, for the same reason as the backup
                    // above: re-verifying reads and hashes every file in an
                    // archive, which is the same cost over the same network
                    // volume (ovation#246).
                    let checked = await BlockingWork.run {
                        guard let folder = BackupFolderSetting.liveBackupsDirectory else {
                            return BackupService.Reverification.nothingToCheck
                        }
                        let service = BackupService(
                            dataDirectory: storeURL.deletingLastPathComponent(),
                            backupsDirectory: folder,
                            dailyKeep: BackupService.defaultDailyKeep,
                            referencedDocuments: {
                                try StoreDocumentReferences.read(storeURL: storeURL)
                            })
                        return (try? service.reverifyOneArchive(now: now)) ?? .nothingToCheck
                    }
                    return LaunchBackupOutcome.reverification(from: checked)
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

                    // SAVE ON WHAT IT DID, NEVER ON WHAT IT SAID. A run whose only
                    // effect was a rename raises no notice, deliberately, and has
                    // still changed the store: deciding from the notices applied
                    // every rename in memory and dropped it when this context went,
                    // on every launch, with no symptom at all (L11).
                    guard result.summary.changedSomething else { return result.notices }
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
            sequence.onStep = { [progress] step in progress.stepStarted(step) }
            progress.finished(await sequence.run(now: Date()))
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
        var list: InvoiceListSource?
        if let container = openedStore.container {
            let context = ModelContext(container)
            rosterPair = RosterLaunch.presenters(
                fetchClients: { try context.fetch(FetchDescriptor<Client>()) },
                save: { try context.save() },
                problems: store,
                now: Date())
            // THE CONTAINER, NOT THIS CONTEXT, and that is the one place the
            // invoice list differs from the roster beside it (ovation#451). The
            // roster writes through the context above, so the context is dirty
            // whenever Dan is part way through answering, and `SwiftDataBehaviourTests`
            // measures that a dirty context re-reading does NOT see another
            // context's write. The list only ever reads, so it makes a fresh
            // context per read and sees whatever is committed.
            list = InvoiceListSource(over: container, problems: store, now: Date.init)
        }
        opened = openedStore.container
        roster = rosterPair?.roster
        shell = rosterPair?.shell
        invoiceList = list
        presenter.refresh()
    }

    /// Gmail for one send, or why it cannot be had (ovation#42).
    ///
    /// BUILT AT THE PRESS AND CONNECTED ONLY AFTER EVERY REFUSAL, by the send itself,
    /// so an ordinary refusal never opens a browser. The first send with no stored grant opens Google's consent page
    /// once; the grant is kept in the credentials folder for every send after. The one
    /// construction of the manager stays in `OvationGmail` (ovation#426).
    static func gmailSender(for settings: SendingSettings) -> Result<SendingRoute, SenderUnavailable> {
        OvationGmail.sender(for: settings, connection: { try OvationGmail.authManager() })
    }

    /// The restore control, or nil when there is no folder to restore from.
    ///
    /// NIL RATHER THAN AN EMPTY LIST, because "no folder chosen" and "a folder
    /// with nothing in it" are different things to say (L10).
    @MainActor
    private static func restorePresenter(for store: ProblemsStore) -> RestorePresenter? {
        guard let storeURL = StoreLocation.liveStoreURL(),
              let folder = BackupFolderSetting.liveBackupsDirectory else { return nil }
        return RestorePresenter(
            dataDirectory: storeURL.deletingLastPathComponent(),
            backupsDirectory: folder,
            dailyKeep: BackupService.defaultDailyKeep,
            referencedDocuments: { try StoreDocumentReferences.read(storeURL: storeURL) },
            now: Date.init,
            fileManager: { .default })
    }

    /// A box, because the launch sequence's hook is `@Sendable` and this runs
    /// before `self` exists.
    private final class OpenedStore: @unchecked Sendable {
        var container: ModelContainer?
    }

    var body: some Scene {
        Window(OvationBuild.displayName, id: OvationBuild.mainWindowID) {
            RootView(presenter: presenter, store: store, exportCommand: exportCommand,
                     roster: roster, shell: shell, invoices: invoiceList?.list,
                     heldMoney: invoiceList?.heldMoney,
                     // ovation#457. The SOURCE resolves an invoice, because it
                     // owns the container and a view may not (PRD 51l).
                     //
                     // THE FOOTER IS SETTINGS', READ AT THE MOMENT OF OPENING, never
                     // the shipped text (ovation#319). Two of the reasons an invoice
                     // may not go out live in Settings, so a screen judged against
                     // the shipped footer would offer Review on an invoice whose page
                     // cannot say how to pay, and refuse one whose Settings are fine.
                     // `check-invoice-footer-source.sh` refused the first version,
                     // which passed `.fixed` here. Read per opening rather than once,
                     // because Dan can change Settings between two invoices.
                     openInvoice: { [invoiceList] id in
                         invoiceList?.screen(
                             for: id,
                             footer: InvoiceFooterSetting(defaults: .standard).footer)
                     },
                     // ovation#457. THE WRITE IS AN ACTOR'S, never the view's
                     // (PRD 51l). It answers with a sentence when it refuses, which
                     // on this screen can only be a race, because the field is not
                     // offered on an invoice that may not be edited.
                     writeTime: opened.map { container in
                         { shoot, edge, time in
                             let writer = ShootTimesWriter(modelContainer: container)
                             do {
                                 switch edge {
                                 case .start: try await writer.setStart(time, on: shoot)
                                 case .end: try await writer.setEnd(time, on: shoot)
                                 }
                                 return nil
                             } catch let refusal as ShootTimesRefusal {
                                 return refusal.sentence
                             } catch {
                                 return "That time could not be saved: \(error)"
                             }
                         }
                     },
                     // ovation#473. The same shape for the due date, which PRD 5.7
                     // makes overridable per invoice and nothing could change.
                     writeDueDate: opened.map { container in
                         { invoice, due in
                             let writer = InvoiceDueDateWriter(modelContainer: container)
                             do {
                                 try await writer.setDueDate(due, on: invoice)
                                 return nil
                             } catch let refusal as InvoiceDueDateRefusal {
                                 return refusal.sentence
                             } catch {
                                 return "That date could not be saved: \(error)"
                             }
                         }
                     },
                     // ovation#457, PRD 5.5. The one write on the invoice screen
                     // that changes a fact about the CLIENT rather than the
                     // invoice, and the reason the screen can now answer the
                     // thing its own foot says it is waiting on.
                     writeTaxStatus: opened.map { container in
                         { client, status in
                             let writer = ClientTaxStatusWriter(modelContainer: container)
                             do {
                                 try await writer.setTaxStatus(status, on: client)
                                 return nil
                             } catch let refusal as ClientTaxStatusRefusal {
                                 return refusal.sentence
                             } catch {
                                 return "That tax status could not be saved: \(error)"
                             }
                         }
                     },
                     // ovation#457, PRD 5.4. Adding a line, and making a
                     // service type from inside the invoice.
                     writeLine: opened.map { container in
                         { invoice, type, amount in
                             let writer = InvoiceLineWriter(modelContainer: container)
                             do {
                                 try await writer.addLine(ofType: type, amount: amount,
                                                          to: invoice)
                                 return nil
                             } catch let refusal as InvoiceLineRefusal {
                                 return refusal.sentence
                             } catch {
                                 return "That line could not be added: \(error)"
                             }
                         }
                     },
                     writeServiceType: opened.map { container in
                         { name, usual in
                             let writer = ServiceTypeWriter(modelContainer: container)
                             do {
                                 _ = try await writer.create(named: name, usualAmount: usual)
                                 return nil
                             } catch let refusal as ServiceTypeRefusal {
                                 return refusal.sentence
                             } catch {
                                 return "That service type could not be created: \(error)"
                             }
                         }
                     },
                     // ovation#457, PRD 5.4a. Changing the discount, and the
                     // object the Edit menu reads to know what is open.
                     writeDiscount: opened.map { container in
                         { invoice, discount in
                             let writer = InvoiceDiscountWriter(modelContainer: container)
                             do {
                                 try await writer.setDiscount(discount, on: invoice)
                                 return nil
                             } catch let refusal as InvoiceDiscountRefusal {
                                 return refusal.sentence
                             } catch {
                                 return "That discount could not be saved: \(error)"
                             }
                         }
                     },
                     // ovation#457, PRD 5.8. Spending the client's referral
                     // credit on this invoice, or giving it back.
                     //
                     // THE DAY IS READ HERE AND NOWHERE DEEPER. The writer takes
                     // it, so the one place that asks the clock is the app's own
                     // edge and every layer beneath it can be tested across a
                     // date (L524).
                     writeReferralCredit: opened.map { container in
                         { invoice, change in
                             let writer = InvoiceReferralCreditWriter(modelContainer: container)
                             let today = BusinessDate.stamping(Date())
                             do {
                                 switch change {
                                 case .apply:
                                     try await writer.applyReferralCredit(on: invoice, on: today)
                                 case .remove:
                                     try await writer.removeReferralCredit(on: invoice, on: today)
                                 }
                                 return nil
                             } catch let refusal as InvoiceReferralCreditRefusal {
                                 return refusal.sentence
                             } catch {
                                 return "That referral credit could not be saved: \(error)"
                             }
                         }
                     },
                     // ovation#510, PRD 51m and 51n. Recording a payment and
                     // clearing a check. THE DAY A CHECK CLEARS IS READ HERE AND
                     // NOWHERE DEEPER, the one place that asks the clock (L524).
                     writePayment: opened.map { container in
                         { invoice, entry in
                             let recorder = PaymentAllocator(modelContainer: container)
                             do {
                                 try await recorder.record(entry.amount, method: entry.method,
                                                           receivedOn: entry.received,
                                                           onto: invoice, press: entry.press)
                                 return nil
                             } catch let refusal as PaymentRecordingRefusal {
                                 return refusal.sentence
                             } catch {
                                 return "That payment could not be recorded: \(error)"
                             }
                         }
                     },
                     writeCleared: opened.map { container in
                         { check in
                             let recorder = PaymentAllocator(modelContainer: container)
                             do {
                                 try await recorder.markCleared(check, on: .stamping(Date()))
                                 return nil
                             } catch let refusal as PaymentRecordingRefusal {
                                 return refusal.sentence
                             } catch {
                                 return "That check could not be marked cleared: \(error)"
                             }
                         }
                     },
                     edits: edits,
                     // ovation#42. The review of a real invoice, and its send. The
                     // sending settings file is nil in a Debug build and a test run,
                     // which may not reach live Google, so they cannot send whatever
                     // file is on the Mac.
                     reviewer: opened.map { container in
                         InvoiceReviewer(container: container,
                                         footer: { InvoiceFooterSetting(defaults: .standard).footer },
                                         settingsFile: StoreLocation.liveSendingSettingsFile(),
                                         makeSender: { settings in Self.gmailSender(for: settings) },
                                         clock: { Date() })
                     },
                     progress: progress)
                // THE WINDOW IS UP BEFORE ANY OF THIS RUNS (ovation#246). The
                // order inside the launch is unchanged; what changed is that
                // there is now somewhere for it to say what it is doing.
                .task { await startLaunch() }
                // NO TITLE IN THE TITLE BAR (ovation#123, Dan 2026-09-23). The
                // Instrument Serif heading in the content names the screen, so the
                // window's own title is hidden, as macOS apps with a large content
                // heading do. HIDDEN, NOT REMOVED: the Window menu and a screen
                // reader still read it. Only the text goes; `MainWindowTitleTests`
                // holds the title bar's height, style and lack of a toolbar at what
                // they measured before this line existed.
                .toolbar(removing: .title)
                // ovation#318 B5, PRD 52a: the sheet belongs to the WINDOW, so it is
                // presented from the window's content above RootView and a launch
                // finishing does not dismiss it. Debug only until ovation#42 gives
                // real invoices a way here.
                #if DEBUG
                .reviewSamples(samples)
                #endif
        }

        // ovation#231 and ovation#247. WHERE THE FOLDER IS CHOSEN AND A BACKUP IS
        // PUT BACK. Both presenters existed with tests and NOTHING PRESENTED
        // EITHER, so a folder could not be chosen and no backup had ever been
        // taken: built is not wired (L3).
        Settings {
            // A FACTORY, not a built one: the restore control only exists once a
            // folder does, and on the launch where Dan first chooses one there
            // was none when this window was made (ovation#247).
            SettingsView(backups: backupSettings,
                         makeRestore: { Self.restorePresenter(for: store) },
                         invoiceFooter: InvoiceFooterSetting(defaults: .standard))
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
                // ovation#461. Nothing in Ovation created an invoice before
                // this, so ovation#42 had nothing to send. Same shape as the
                // export above and for the same reason: never hidden, disabled
                // with the reason said out loud (L49, L109).
                Button(BookingDraftCommand.title) { runDraftFromTheQueue() }
                    .disabled(whyTheDraftCannotRun != nil)
                if let why = whyTheDraftCannotRun {
                    Text(why).font(.footnote)
                }
            }
            // ovation#457, PRD 5.4a. The rare actions on an invoice live in the
            // Edit menu, which is round 5 of the design record: space on the
            // screen is earned by frequency and 5 of 130 issued invoices carry a
            // discount.
            //
            // IT ADDS ONE AND NEVER REMOVES ONE. Once there is a discount the
            // row carries its own controls, so a Remove here would be the same
            // action offered twice on one screen, and this is the copy further
            // from the thing it acts on (L605).
            //
            // NEVER HIDDEN, ONLY DISABLED WITH ITS REASON, which is this menu's
            // own rule above and differs from the record, where the entry
            // disappears. Both concerns are kept and the difference is filed as
            // ovation#495.
            CommandGroup(after: .pasteboard) {
                Button(InvoiceEditCommand.addDiscountTitle) { addADiscount() }
                    .disabled(InvoiceEditCommand.whyADiscountCannotBeAdded(edits.open) != nil)
                if let why = InvoiceEditCommand.whyADiscountCannotBeAdded(edits.open) {
                    Text(why).font(.footnote)
                }
                // ovation#457, PRD 5.8 and 5.51e. ONE ENTRY WHOSE WORD CHANGES,
                // which is the design record's round 5 and is the whole of this
                // credit's interface: unlike the discount it has no controls of
                // its own anywhere on the invoice, so if it is not here it cannot
                // be done at all.
                Button(InvoiceEditCommand.referralCreditTitle(edits.open)) {
                    changeTheReferralCredit()
                }
                .disabled(InvoiceEditCommand.whyTheReferralCreditCannotChange(edits.open) != nil)
                if let why = InvoiceEditCommand.whyTheReferralCreditCannotChange(edits.open) {
                    Text(why).font(.footnote)
                }
            }
            #if DEBUG
            CommandMenu(ReviewSamplesCommand.title) {
                ForEach(ReviewSample.allCases) { sample in
                    Button(sample.says) { samples.press(sample) }
                }
            }
            #endif
        }
    }

    /// Adds the discount the menu offers, which is a tenth off: round 5's own
    /// measurement, the commonest of the five in the whole history.
    private func addADiscount() {
        guard let open = edits.open,
              InvoiceEditCommand.whyADiscountCannotBeAdded(open) == nil,
              let add = edits.addDiscount else { return }
        add(open.id, InvoiceEditCommand.whatItAdds)
    }

    /// Presses the one credit entry the way its word is currently pointing.
    ///
    /// THE STATE DECIDES, NEVER THE CALLER. The title and this both read
    /// `hasReferralCredit` off the same published facts, so the entry cannot say
    /// Remove and apply one (L70).
    private func changeTheReferralCredit() {
        guard let open = edits.open,
              InvoiceEditCommand.whyTheReferralCreditCannotChange(open) == nil else { return }
        if open.hasReferralCredit {
            edits.removeReferralCredit?(open.id)
        } else {
            edits.applyReferralCredit?(open.id)
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

    private var whyTheDraftCannotRun: String? {
        draftCommand.whyItCannotRun(container: opened)
    }

    /// Reads the booking queue and drafts what is in it, then refreshes the
    /// launch notices so what it reported is on screen rather than waiting for
    /// the next launch.
    private func runDraftFromTheQueue() {
        draftCommand.press(now: Date(), container: opened, problems: store) {
            presenter.refresh()
        }
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
