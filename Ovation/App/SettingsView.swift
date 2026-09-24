// ovation#231 and ovation#247. THE SETTINGS WINDOW, and the two controls that
// make the backup milestone usable at all.
//
// REOPENED BECAUSE IT WAS NOT THERE. ovation#243 shipped BackupSettingsPresenter
// with seven passing tests, and ovation#247 shipped RestorePresenter with seven
// more, and NOTHING PRESENTED EITHER. A backup folder could not be chosen, so no
// backup had ever been taken, so most of the milestone was inert. That is built
// is not wired (L3), and it survived because a surface nothing presents is
// invisible to every test that is not about presenting it (L546).
//
// IT IS THE APP'S SECOND WINDOW, which OvationApp is otherwise deliberately
// without: a flag on shared state is presented once per SURFACE bound to it, so
// a second window would put up a second copy of every launch notice and
// dismissing one would leave the other standing (L238). This binds to the two
// presenters and to nothing that PRESENTS a problem.
//
// Dan chose, 2026-09-12, to skip a design round on it and look at it when he
// next installs a build, so it is plain and uses the palette the rail already
// has.
import SwiftUI

struct SettingsView: View {

    /// THE WINDOW'S OWN SIZE, named so a test can hold it to the pane it has to
    /// show (ovation#391). Dan: "no real reason for me to have to scroll."
    static let minimumWidth: CGFloat = 520
    /// Held to the PANE, by `SettingsWindowSizeTests`, which asks the invoices pane
    /// how tall it wants to be at its tallest and refuses a window shorter than that
    /// plus the allowance below. The pane measured 527 on 2026-09-17.
    ///
    /// GENEROUSLY ABOVE THAT SUM RATHER THAN ON IT, for two reasons. An ordinary
    /// edit to the pane should not immediately bring the scrolling back, and the
    /// allowance below is an estimate, so the slack is what stops that estimate
    /// deciding whether content is visible. A window taller than it needs costs a
    /// little empty space; one a few points short hides the line saying why an
    /// invoice cannot be sent, so the error is taken on the harmless side (L648).
    static let minimumHeight: CGFloat = 680

    /// What the tab bar and the window's chrome take off the height before the pane
    /// gets any room.
    ///
    /// AN ESTIMATE, AND SAID TO BE ONE. It has NOT been measured against a real
    /// Settings window: doing that means running the app and reading the window, and
    /// this number was chosen from experience instead. An earlier version of this
    /// comment claimed it was measured, which was untrue and is exactly the kind of
    /// sentence that gets believed rather than checked (L407, L460). It is safe to
    /// be wrong here only because `minimumHeight` clears the sum with room to spare;
    /// if that margin is ever tightened, measure this first.
    static let chromeAllowance: CGFloat = 64

    @Bindable var backups: BackupSettingsPresenter
    /// HOW TO BUILD THE RESTORE CONTROL, not a built one.
    ///
    /// It only exists once a folder does, and on the launch where Dan first
    /// chooses one there was none when this window was made. A fixed value here
    /// meant the pane went on saying "choose a folder first" after he already
    /// had, until he quit and reopened: derived state that does not re-derive
    /// from the input that feeds it (L14).
    var makeRestore: () -> RestorePresenter? = { nil }

    /// Where the invoice footer is stored (ovation#319).
    ///
    /// PASSED IN, NOT BUILT HERE, and with no default resolving to `.standard`: a
    /// component that constructs its own dependency is beyond every refusal that
    /// dependency could offer (L196), and this one WRITES, so a rendered pane in a
    /// test would otherwise overwrite Dan's real footer (L201).
    var invoiceFooter: InvoiceFooterSetting

    /// What the last press said, kept so an action SAYS it happened rather than
    /// leaving the pane looking unchanged (L608, L12).
    @State private var lastOutcome: String?
    @State private var confirming: RestorePresenter.Archive?
    /// WHAT RESTORING THAT ONE WOULD DO, worked out WHEN THE BUTTON IS PRESSED
    /// rather than while the dialog draws. `consequence(of:)` reads the archive's
    /// manifest from disk, and a view builder is not a place to read files: it is
    /// the same shape as the archive list this pane already had to move off the
    /// drawing thread, smaller only by degree.
    @State private var confirmingConsequence: String = ""

    /// THE ARCHIVES, LOADED ONCE AND HELD, never read from the view's body.
    ///
    /// `archives()` VERIFIES each one, which reads and hashes every file in every
    /// backup, and a SwiftUI body is re-evaluated constantly. Calling it there put
    /// the heaviest work in the app on the drawing thread on every redraw, which
    /// on a folder that syncs to a NAS is a frozen window: the exact defect
    /// ovation#246 exists to prevent, written into the pane that fixes it.
    ///
    /// It loads off the main actor through the same helper the launch uses, under
    /// the same deadline, so a share that has gone quiet cannot hang the window
    /// either (L241, L110).
    @State private var rows: [RestorePresenter.Archive]?
    @State private var loadingArchives = true
    /// The control as it stands now, rebuilt whenever the folder changes.
    @State private var restore: RestorePresenter?

    var body: some View {
        TabView {
            // INVOICES FIRST. It is what Dan opens Settings to change, while the
            // backups pane is where he goes once, to choose a folder (L609).
            InvoiceSettingsPane(setting: invoiceFooter)
                .tabItem { Label("Invoices", systemImage: "doc.text") }
            backupsPane
                .tabItem { Label("Backups", systemImage: "externaldrive") }
        }
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
        // THE WHOLE WINDOW, not only the invoices pane, which already carried it
        // (ovation#475). The backups tab and the tab control share this window, and
        // macOS made it, so without this they take their colours from the Mac.
        .ovationAppearance()
    }

    private var backupsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                folderSection
                Divider()
                restoreSection
                if let lastOutcome {
                    Text(lastOutcome).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where backups go").font(.headline)
            Text(folderDescription)
            // THE SENTENCE IS COMPOSED FROM THE RULE, not typed beside it (L679).
            Text(backups.retentionSentence).font(.callout).foregroundStyle(.secondary)
            Button("Choose a folder") {
                switch backups.choose() {
                case .chosen(let folder):
                    lastOutcome = "Backups will go to \(folder.path)."
                    // THE REST OF THE PANE FOLLOWS THE CHOICE. Without this the
                    // restore half goes on asking for a folder he just gave (L14).
                    Task { await loadArchives() }
                case .cancelled:
                    break
                case .refusedInsideTheDataDirectory(let detail), .refused(let detail):
                    lastOutcome = detail
                }
            }
        }
    }

    /// What the pane says about the folder, one sentence per outcome, because
    /// each needs a different thing from Dan (L11).
    /// Reads the archives once, off the main actor.
    private func loadArchives() async {
        loadingArchives = true
        // REBUILT EACH TIME, because the folder it reads may have just changed.
        restore = makeRestore()
        guard let restore else {
            rows = nil
            loadingArchives = false
            return
        }
        rows = await restore.archivesOffTheMainActor()
        loadingArchives = false
    }

    private var folderDescription: String {
        switch backups.resolution {
        case .chosen(let folder): return folder.path
        case .notChosen: return "No folder chosen yet, so Ovation is not backing up."
        case .unresolvable(let detail): return "The folder cannot be reached: \(detail)"
        case .onADifferentVolume(let detail): return detail
        case .refusedUnderADisposableLaunch: return "Not available in this run."
        }
    }

    @ViewBuilder
    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Put a backup back").font(.headline)
            if loadingArchives {
                // STARTED, rather than an empty list that reads as "no backups"
                // while it is still looking (L10).
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking at your backups")
                }
            } else if let rows, !rows.isEmpty {
                ForEach(rows) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.takenAt.map(BusinessCalendar.dayKey(for:)) ?? row.name)
                            // WHETHER IT VERIFIES NOW, said plainly, because an
                            // archive that has rotted must not be offered as
                            // though it were sound (L336).
                            if !row.verifies {
                                Text("This backup no longer checks out")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Restore") {
                            confirmingConsequence =
                                (try? restore?.consequence(of: row.name))
                                ?? "Ovation could not read what is in this backup."
                            confirming = row
                        }
                        .disabled(!row.verifies)
                    }
                }
            } else {
                // AN EMPTY STATE AND AN ERROR STATE ARE DIFFERENT SCREENS (L10).
                Text(restore == nil
                     ? "Choose a folder first, and Ovation will start backing up."
                     : "There are no backups in that folder yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .task { await loadArchives() }
        .confirmationDialog(
            "Put this backup back?",
            isPresented: .init(get: { confirming != nil },
                               set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { row in
            Button("Restore, replacing what is there", role: .destructive) {
                guard let restore else { return }
                switch restore.restore(row.name) {
                case .restored(let detail): lastOutcome = detail
                case .partlyRestored(let detail): lastOutcome = detail
                case .refused(let detail): lastOutcome = detail
                }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: { _ in
            // THE CONSEQUENCE IS DERIVED FROM THE ARCHIVE, so it names what will
            // be replaced rather than reading the same whatever it takes (L180).
            // Read when the button was pressed, not here.
            Text(confirmingConsequence)
        }
    }
}
