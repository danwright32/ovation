// ovation#231. The open panel, kept apart from everything that decides.
//
// `BackupSettingsPresenter` takes the folder as an injected closure precisely so
// that every outcome is reachable without a person clicking (L196). This is the
// one place that actually asks, and it holds no decision: what is refused, what
// is remembered and what is said are all the presenter's.
import AppKit

enum SettingsFolderPanel {
    @MainActor
    static func ask() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        panel.message = "Choose where Ovation copies your records."
        return panel.runModal() == .OK ? panel.url : nil
    }
}
