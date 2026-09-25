// ovation#319. Pictures of the invoice settings pane, so it can be judged by being
// looked at rather than described.
//
// SAME CAMERA AS THE REVIEW SHEET (ovation#318 B7). The window is never ordered
// front, so a capture cannot interrupt whatever Dan is doing, and it is ordered
// BACK far off every display rather than left unordered, because a window that was
// never ordered in does not draw its layer backed subviews at all.
//
// LIGHT ONLY, SINCE ovation#475. This suite used to file a dark picture beside
// each light one, as separate deliverables, so the two being different was what
// it expected and nothing compared them: that is how the pane shipped near
// unreadable on a dark Mac. The pane is now pinned to light like every other
// screen, and `AppearanceParityTests` refuses any difference between the two, so
// a dark picture here would be a second copy of one already required to match.
//
// IT RUNS ON EVERY RUN (ovation#383): scripts/run-tests.sh always names a folder, a
// temporary one unless OVATION_SHOT_DIR names another, and CI keeps its pictures as
// an artifact. Run some other way, it still SAYS WHEN IT DID NOTHING (L98): with no directory named it writes
// nothing and prints that, because a run that quietly produced no pictures cannot
// be told from one whose pictures were never looked at. The variable carries the
// TEST_RUNNER_ prefix because the shell's environment does not otherwise reach the
// test process, and the bare name is read too because xcodebuild strips the prefix.
import AppKit
import SwiftUI
import Testing
@testable import Ovation

@MainActor
struct InvoiceSettingsShotTests {

    private static var outputDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        let named = environment["OVATION_SHOT_DIR"]
            ?? environment["TEST_RUNNER_OVATION_SHOT_DIR"] ?? ""
        return named.isEmpty ? nil : URL(fileURLWithPath: named)
    }

    @Test("the invoice settings pane is captured, or it says it captured nothing")
    func captureThePane() throws {
        guard let directory = Self.outputDirectory else {
            print("SETTINGS SHOTS: no TEST_RUNNER_OVATION_SHOT_DIR, so nothing was captured.")
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [String] = []
        for shot in Shot.all {
            try OffscreenShot.capture(Host(footer: shot.footer),
                                      size: shot.size, scheme: shot.scheme,
                                      to: directory.appending(path: shot.fileName))
            written.append(shot.fileName)
        }
        // THE COUNT IS ASSERTED, so a capture that silently wrote fewer than it
        // meant to is a failure rather than a shorter set of pictures nobody counts.
        #expect(written.count == Shot.all.count)
        print("SETTINGS SHOTS: wrote \(written.count) into \(directory.path)")
    }

    /// A host with real state, because a TextEditor over a constant binding draws
    /// as an editor nobody can type in, and the point of the picture is the control
    /// as it will actually behave.
    private struct Host: View {
        @State var footer: InvoiceFooter
        var body: some View {
            InvoiceSettingsView(footer: $footer)
        }
    }

    private struct Shot {
        let scheme: ColorScheme
        let size: CGSize
        let footer: InvoiceFooter
        let fileName: String

        /// THE REAL CONTENT, NOT A FIXTURE SHAPED TO FIT. The filled shot carries
        /// bank details over four lines, because that is what a payment instruction
        /// actually is and a one line stand in would make the pane look calmer than
        /// it will ever be (L48, L578). The window sizes are the Settings window's
        /// own minimum and a size Dan would actually open it at.
        static var all: [Shot] {
            let asItShipsToday = InvoiceFooter.fixed
            let asItWillBeUsed = InvoiceFooter(
                payment: """
                Bank transfer to Dan Wright Photography
                Routing 000000000, account 000000000
                Or by card at danwrightphotography.com/pay
                Please quote the invoice number.
                """,
                note: "Thank you for having me at your performance. Galleries are delivered within two weeks after the shoot.",
                contact: """
                dan@danwrightphotography.com
                (000) 000 0000
                """)
            let empty = InvoiceFooter(payment: "", note: "", contact: "")
            return [
                Shot(scheme: .light, size: CGSize(width: 640, height: 560),
                     footer: asItShipsToday, fileName: "01-as-it-ships-light.png"),
                Shot(scheme: .light, size: CGSize(width: 640, height: 560),
                     footer: asItWillBeUsed, fileName: "03-real-bank-details-light.png"),
                // AT THE WINDOW'S OWN MINIMUM, because a pane is shipped unseen when
                // it has only been looked at roomy (L606). Measured at the narrowest
                // width, since that is where the text wraps most and the pane is at
                // its tallest.
                Shot(scheme: .light, size: CGSize(width: 520, height: 510),
                     footer: asItWillBeUsed, fileName: "05-smallest-window-light.png"),
                // THE EMPTY STATE AT THAT SAME MINIMUM, which is the tallest the pane
                // ever gets: two of the three carry a warning line the filled pane
                // does not. If anything has to be scrolled to, it is here.
                Shot(scheme: .light, size: CGSize(width: 520, height: 560),
                     footer: empty, fileName: "07-empty-at-minimum-light.png"),
                // AND EMPTY, which is a state this pane really has: it is what Dan
                // sees while rewriting a line, and two of the three block sending.
                Shot(scheme: .light, size: CGSize(width: 640, height: 560),
                     footer: empty, fileName: "06-all-empty-light.png"),
            ]
        }
    }

}
