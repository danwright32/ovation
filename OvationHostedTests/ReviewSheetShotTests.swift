import AppKit
import SwiftUI
import Testing
@testable import Ovation

/// ovation#318 B7. Pictures of the real sheet, for Dan to judge before it merges.
///
/// WHY A REAL WINDOW AND NOT A PREVIEW RENDERER. The page is a PDFKit view inside
/// an NSViewRepresentable, and SwiftUI's ImageRenderer does not draw those: the one
/// thing worth looking at would come out blank, and a blank page area in a
/// screenshot reads as a layout fault rather than as a limitation of the camera
/// (L115). So the sheet is hosted in an NSWindow that is never ordered front, laid
/// out, and captured from its own layer.
///
/// IT IS OPT IN AND IT SAYS WHEN IT DID NOTHING. With no directory named it writes
/// nothing and reports that, because a capture run that quietly produced no files
/// is indistinguishable from one whose pictures were never looked at (L98). The
/// variable carries the TEST_RUNNER_ prefix because the shell's environment does
/// not otherwise reach the test process.
@MainActor
struct ReviewSheetShotTests {

    /// BOTH SPELLINGS, and that is not belt and braces. `xcodebuild` forwards only
    /// variables named TEST_RUNNER_<NAME> into the test process, and it STRIPS the
    /// prefix on the way in, so the name here is the bare one; a test run directly
    /// from a shell sees the name it was given. Reading one of the two would work
    /// on one route and silently capture nothing on the other, which is the state
    /// this suite exists to make impossible to mistake for success (L98).
    private static var outputDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        let named = environment["OVATION_SHOT_DIR"]
            ?? environment["TEST_RUNNER_OVATION_SHOT_DIR"] ?? ""
        return named.isEmpty ? nil : URL(fileURLWithPath: named)
    }

    @Test("the sheet is captured in both themes, or it says it captured nothing")
    func captureTheSheet() throws {
        guard let directory = Self.outputDirectory else {
            print("REVIEW SHOTS: no TEST_RUNNER_OVATION_SHOT_DIR, so nothing was captured.")
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [String] = []
        for shot in Shot.all {
            let presenter = try ReviewSampleWorld.presenter(for: shot.sample)
            // THE PAGE IS DRAWN BEFORE THE PICTURE IS TAKEN. The sheet loads it when
            // it appears, and a window that is never ordered front does not appear,
            // so relying on that produced eight pictures of an empty page area
            // (measured 2026-09-16). The state is reached the way a person reaches
            // it, through the presenter, rather than by setting a field.
            let page = InvoicePage()
            if shot.opened {
                try presenter.open(on: page)
            } else {
                try presenter.show(on: page)
            }
            let sheet = ReviewSheet(presenter: presenter, page: page, close: {})
                .environment(\.colorScheme, shot.scheme)
            let url = directory.appending(path: shot.fileName)
            try Self.capture(sheet, size: shot.size, scheme: shot.scheme, to: url)
            written.append(shot.fileName)
        }

        // AND THE PAGE ITSELF, as a PDF beside the pictures. PDFKit does not draw
        // into an offscreen snapshot, so the page area of every picture above is
        // empty: that is the camera's limit and not the sheet's, and a reader given
        // only those pictures would judge a blank document (L115). The bytes written
        // here are the ones the sheet was handed, which are the ones a send would
        // attach (PRD 10c).
        let pagePresenter = try ReviewSampleWorld.presenter(for: .ordinary)
        let page = InvoicePage()
        try pagePresenter.show(on: page)
        let bytes = try #require(page.bytes)
        try bytes.write(to: directory.appending(path: "00-the-page-itself.pdf"))
        written.append("00-the-page-itself.pdf")

        #expect(written.count == Shot.all.count + 1)
        print("REVIEW SHOTS: wrote \(written.count) file(s) to \(directory.path)")
    }

    /// One picture to take.
    private struct Shot {
        let sample: ReviewSample
        let scheme: ColorScheme
        let opened: Bool
        let size: CGSize
        let fileName: String

        /// BOTH THEMES AND BOTH SIZES, because a surface looked at in one is a
        /// surface half seen (L69, L606). The window sizes are Dan's smallest
        /// (1352 by 878) and a wide one.
        static let all: [Shot] = [
            Shot(sample: .ordinary, scheme: .light, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "01-ordinary-light.png"),
            Shot(sample: .ordinary, scheme: .dark, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "02-ordinary-dark.png"),
            Shot(sample: .ordinary, scheme: .light, opened: true,
                 size: CGSize(width: 1680, height: 1050), fileName: "03-page-opened-light.png"),
            Shot(sample: .pastDue, scheme: .light, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "04-past-due-light.png"),
            Shot(sample: .dueSoon, scheme: .light, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "05-due-soon-light.png"),
            Shot(sample: .dueSoon, scheme: .dark, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "06-due-soon-dark.png"),
            Shot(sample: .genuineOverride, scheme: .light, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "07-override-light.png"),
            Shot(sample: .nowhereToSend, scheme: .light, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "08-nowhere-to-send-light.png"),
        ]
    }

    /// Hosts a view in an offscreen window and writes what it drew.
    ///
    /// NEVER ORDERED FRONT. A capture that stole the front window would interrupt
    /// whatever Dan is doing, and this runs inside an ordinary test run.
    private static func capture(_ view: some View, size: CGSize, scheme: ColorScheme,
                                to url: URL) throws {
        // THE SHEET AT ITS OWN SIZE, over a window sized backdrop, because that is
        // how it appears: hosting it as the whole content stretched it to the window
        // and measured the host rather than the sheet (L472).
        let framed = ZStack {
            Color(nsColor: .windowBackgroundColor)
            view
        }
        .frame(width: size.width, height: size.height)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        // THE THEME IS THE WINDOW'S, not only the SwiftUI environment's: the
        // materials and the standard control colours come from the window's
        // appearance, so asking for light while the Mac is dark produced dark
        // chrome with light text over it (measured 2026-09-16).
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: framed)

        // ON SCREEN, AND NOWHERE ANYBODY CAN SEE IT. A window that was never ordered
        // in does not draw its layer backed subviews, which is why the page came out
        // empty; ordering it BACK at a position far outside every display makes it
        // draw without taking the front window from whatever Dan is doing.
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        // One pass of the run loop, so PDFKit finishes laying the page out. It is a
        // wait on the run loop rather than on the clock.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        defer { window.close() }

        guard let content = window.contentView,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw ShotFailure.nothingToDraw
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ShotFailure.couldNotEncode
        }
        try data.write(to: url)
    }

    private enum ShotFailure: Error {
        case nothingToDraw
        case couldNotEncode
    }
}
