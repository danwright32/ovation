// ovation#655. Pictures of the launch day pane, so it can be judged by being
// looked at rather than described (L606). The same camera and the same rules as
// `InvoiceSettingsShotTests`: light only, since `AppearanceParityTests` refuses any
// difference in dark, and it says so when no folder was named.
import AppKit
import SwiftUI
import Testing
@testable import Ovation

@MainActor
struct LaunchDaySettingsShotTests {

    private static var outputDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        let named = environment["OVATION_SHOT_DIR"]
            ?? environment["TEST_RUNNER_OVATION_SHOT_DIR"] ?? ""
        return named.isEmpty ? nil : URL(fileURLWithPath: named)
    }

    @Test("the launch day pane is captured in each state, or it says it captured nothing")
    func captureThePane() throws {
        guard let directory = Self.outputDirectory else {
            print("LAUNCH DAY SHOTS: no TEST_RUNNER_OVATION_SHOT_DIR, so nothing was captured.")
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [String] = []
        for shot in Shot.all {
            try OffscreenShot.capture(Host(cutoff: shot.cutoff, chosen: shot.chosen,
                                           outcome: shot.outcome),
                                      size: shot.size, scheme: .light,
                                      to: directory.appending(path: shot.fileName))
            written.append(shot.fileName)
        }
        #expect(written.count == Shot.all.count)
        print("LAUNCH DAY SHOTS: wrote \(written.count) into \(directory.path)")
    }

    /// A host with real state, so the date control draws as one that can be moved.
    private struct Host: View {
        let cutoff: LaunchCutoff
        @State var chosen: LaunchDay
        let outcome: String?
        var body: some View {
            LaunchDaySettingsView(cutoff: cutoff, chosen: $chosen, outcome: outcome, confirm: {})
        }
    }

    private struct Shot {
        let cutoff: LaunchCutoff
        let chosen: LaunchDay
        let outcome: String?
        let size: CGSize
        let fileName: String

        static var all: [Shot] {
            let today = LaunchDay(dayKey: "2026-10-08")!
            let earlier = LaunchDay(dayKey: "2026-10-01")!
            let window = CGSize(width: SettingsView.minimumWidth, height: 360)
            return [
                // WHAT DAN SEES FIRST: nothing confirmed, the control on today.
                Shot(cutoff: .notConfirmed, chosen: today, outcome: nil,
                     size: window, fileName: "launch-01-not-confirmed.png"),
                // Just after pressing Confirm.
                Shot(cutoff: .confirmed(today), chosen: today,
                     outcome: "Launch day confirmed as 8 Oct 2026.",
                     size: window, fileName: "launch-02-just-confirmed.png"),
                // Confirmed, and the control moved to correct it.
                Shot(cutoff: .confirmed(today), chosen: earlier, outcome: nil,
                     size: window, fileName: "launch-03-moving-it.png"),
                // A damaged stored value.
                Shot(cutoff: .unreadable(stored: "x"), chosen: today, outcome: nil,
                     size: window, fileName: "launch-04-unreadable.png"),
            ]
        }
    }
}
