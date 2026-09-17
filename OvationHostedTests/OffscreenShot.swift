// The camera both shot suites use. ovation#318 B7, ovation#319.
//
// ONE IMPLEMENTATION, because there are now two suites that photograph a surface
// and a third would have been a third copy. Copying the code that APPLIES a rule
// while sharing nothing is how two suites come to disagree about what a picture
// is (L370, L263), and the bug below is exactly that: it was fixed in one copy and
// would have lived on in the other.
//
// NEVER ORDERED FRONT. A capture that stole the front window would interrupt
// whatever Dan is doing, and these run inside an ordinary test run.
//
// ON SCREEN, AND NOWHERE ANYBODY CAN SEE IT. A window that was never ordered in
// does not draw its layer backed subviews, which is why the PDF page came out
// empty (ovation#374); ordering it BACK at a position far outside every display
// makes it draw without taking the front window.
//
// THE THEME IS THE WINDOW'S, not only the SwiftUI environment's. Materials and the
// standard control colours come from the window's appearance, so asking for light
// while the Mac is dark produced dark chrome under light text (measured
// 2026-09-16).
import AppKit
import SwiftUI
@testable import Ovation

/// ON THE MAIN ACTOR, because it drives AppKit. It used to inherit that from the
/// `@MainActor` suite it was written inside, and lifting it out lost it: the
/// isolation was never stated, only borrowed from where the code happened to sit
/// (L437).
@MainActor
enum OffscreenShot {

    enum Failure: Error {
        case nothingToDraw
        case couldNotEncode
    }

    /// Hosts a view in an offscreen window and writes what it drew, as a PNG.
    static func capture(_ view: some View, size: CGSize, scheme: ColorScheme,
                        to url: URL) throws {
        // THE SURFACE AT ITS OWN SIZE, over a window sized backdrop, because that is
        // how it appears. Hosting it as the whole content stretched it to the window
        // and measured the host rather than the surface (L472).
        let framed = ZStack {
            Color(nsColor: .windowBackgroundColor)
            view
        }
        .frame(width: size.width, height: size.height)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        // NOT RELEASED ON CLOSE, and this is not tidiness. An NSWindow made in code
        // releases itself when closed, which under ARC is a second release of an
        // object the caller already owns.
        //
        // MEASURED 2026-09-17, and it is worth the sentence because of HOW it failed.
        // Every picture was written and the test process then died at teardown.
        // xcodebuild reports that as "Restarting after unexpected exit" followed by a
        // run of ZERO tests, and a suite that executed nothing reports as passing. So
        // the pictures were all present, no assertion had failed, and the only thing
        // that said anything was wrong was the exit code (L184, L98). The review
        // sheet suite had shipped with it the day before and nobody had seen it,
        // because both suites do nothing at all unless a directory is named.
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: framed)
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        // One pass of the run loop, so a view that lays itself out asynchronously
        // (PDFKit does) has finished. It is a wait on the run loop rather than on the
        // clock.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        defer { window.close() }

        guard let content = window.contentView,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw Failure.nothingToDraw
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure.couldNotEncode
        }
        try data.write(to: url)
    }
}
