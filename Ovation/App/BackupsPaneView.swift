import SwiftUI

/// The Settings window's backups pane, drawn from values (ovation#393).
///
/// IT WAS A PRIVATE PROPERTY OF `SettingsView`, reading presenters and state it did not
/// own, so the only way to see it was through the window's tabs, and the offscreen
/// capture draws whichever tab comes first. Lifted out, as `InvoiceSettingsView` was, it
/// can be drawn in any state by handing it that state, and `FixedSurfaceHeightTests`
/// holds the window to it at its tallest.
///
/// IT DECIDES NOTHING. `SettingsView` owns the presenters, the loading and the
/// confirmation; this draws what it is given and says when a button is pressed.
struct BackupsPaneView: View {

    /// What the restore half shows under its heading.
    enum Archives {
        /// Still reading the folder: STARTED, rather than an empty list that reads as
        /// "no backups" while it is still looking (L10).
        case loading
        /// No list to show, and the one sentence saying why.
        case sentence(String)
        case rows([RestorePresenter.Archive])
    }

    let folder: String
    let retention: String
    let archives: Archives
    let outcome: String?
    var choose: () -> Void = {}
    var restore: (RestorePresenter.Archive) -> Void = { _ in }

    var body: some View { laidOut(withList: true) }

    /// THE PANE WITH ITS ARCHIVE LIST LEFT OUT, which is what has to fit the window
    /// (Dan, 2026-09-30): the list grows by one row per archive for ever, so it scrolls
    /// in its own box and never counts against the window's height.
    var fixedPart: some View { laidOut(withList: false) }

    private func laidOut(withList: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Where backups go").font(.headline)
                Text(folder)
                // THE SENTENCE IS COMPOSED FROM THE RULE, not typed beside it (L679).
                Text(retention).font(.callout).foregroundStyle(.secondary)
                Button("Choose a folder", action: choose)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Put a backup back").font(.headline)
                switch archives {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking at your backups")
                    }
                case .sentence(let said):
                    // AN EMPTY STATE AND AN ERROR STATE ARE DIFFERENT SCREENS (L10).
                    Text(said).foregroundStyle(.secondary)
                case .rows(let rows):
                    if withList {
                        ScrollsWhenLong {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(rows) { row in archiveRow(row) }
                            }
                        }
                        // FIRST CALL ON THE ROOM LEFT, ahead of the spacer beneath, so
                        // a list that fits is drawn whole rather than scrolled early.
                        .layoutPriority(1)
                    }
                }
            }
            if let outcome {
                Text(outcome).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func archiveRow(_ row: RestorePresenter.Archive) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.takenAt.map(BusinessCalendar.dayKey(for:)) ?? row.name)
                // WHETHER IT VERIFIES NOW, said plainly, because an archive that has
                // rotted must not be offered as though it were sound (L336).
                if !row.verifies {
                    Text("This backup no longer checks out")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Restore") { restore(row) }
                .disabled(!row.verifies)
        }
    }

    /// What the pane says about the folder, one sentence per outcome, because each
    /// needs a different thing from Dan (L11).
    static func folderSentence(for resolution: BackupFolderSetting.Resolution) -> String {
        switch resolution {
        case .chosen(let folder): return folder.path
        case .notChosen: return "No folder chosen yet, so Ovation is not backing up."
        case .unresolvable(let detail): return "The folder cannot be reached: \(detail)"
        case .onADifferentVolume(let detail): return detail
        case .refusedUnderADisposableLaunch: return "Not available in this run."
        }
    }
}
