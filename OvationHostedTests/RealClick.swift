// A real click, delivered through a window, for the question a view tree cannot
// answer. ovation#615.
//
// WHERE A CLICK LANDS IS DECIDED BY HIT TESTING, AND NOTHING ELSE SEES IT.
// ViewInspector's `tap()` calls a button's action directly, so it reports a row as
// pressable whether a click on its empty half does anything or not; that is how
// the rail's rows shipped answering only on their words (Dan, 2026-09-28). Only a
// mouse event sent through a window goes through the hit test, so that is what
// this does.
//
// THE PLACE IS FOUND BY SWEEPING, never by asking the accessibility tree. SwiftUI
// builds that tree only while something assistive is reading it, so in a test run
// it is empty (measured 2026-09-30: every lookup saw no buttons at all). A click
// is sent at every few points down a line a row's words cannot reach, and what
// each one did is collected, so the case asserts WHICH rows answered there and
// a layout change moves nothing it depends on (L237).
//
// A CLICK IS ANSWERED BEFORE `click` RETURNS. Measured 2026-09-30 in a bare
// AppKit host: the action had run by the time the release was delivered, both
// for the plain style on its words and for `WholeTarget` on its clear end, and
// a plain button's clear end did nothing, which is the defect reproduced. How
// the release reaches a control that tracks the press is in `click`.
//
// NEVER ORDERED FRONT, for the reason `OffscreenShot` gives: these run inside an
// ordinary test run while Dan is working. The window is ordered BACK, far outside
// every display, which is enough for it to lay out and take events.
import AppKit
import SwiftUI
@testable import Ovation

@MainActor
enum RealClick {

    /// A window holding `view` at `size`, laid out and able to take events. The
    /// caller closes it.
    static func host(_ view: some View, size: CGSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        // NOT RELEASED ON CLOSE: see `OffscreenShot`, where a second release at
        // teardown killed the test process and read as a pass.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.frame(width: size.width,
                                                                height: size.height))
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)
        // THE KEY WINDOW OF THE TEST APP, so a click in it is a click and never only
        // the first click that brings a window forward. This does not activate the
        // app or take the front window from anyone: on a Mac being worked on the
        // test app is not the active one, and its key window stays behind.
        window.makeKey()
        window.layoutIfNeeded()
        settle()
        return window
    }

    /// A click at every `step` points down the vertical line at `x`, between
    /// `fromTop` and `toTop` points below the top of the window's content, calling
    /// `after` once each click has been answered. Returns how many clicks it sent
    /// and how many of their releases something else took off the queue (see
    /// `click`), so a case that fails can say which of the two happened.
    @discardableResult
    static func sweep(x: CGFloat, in window: NSWindow, fromTop: CGFloat = 0, toTop: CGFloat? = nil,
                      step: CGFloat = 3, after: () -> Void) -> (clicks: Int, releasesTaken: Int) {
        let height = window.contentView?.bounds.height ?? 0
        let bottom = min(toTop ?? height, height)
        var clicks = 0
        var taken = 0
        for fromTheTop in stride(from: fromTop + 1, to: bottom, by: step) {
            if click(at: NSPoint(x: x, y: height - fromTheTop), in: window) { taken += 1 }
            clicks += 1
            after()
        }
        return (clicks, taken)
    }

    /// One press and release of the left button at `point`, in window coordinates.
    ///
    /// BOTH HALVES GO ON THE EVENT QUEUE AND THE APPLICATION DISPATCHES THEM, the
    /// way a real click arrives. Measured on the CI runner, where the test app is
    /// the active one (review of #644): a release sent only after the press hung the
    /// Clients names for the job's hour (run 36801613438, L110), and a press handed
    /// straight to the window with its release queued behind it left the scroll
    /// view's tracking loop taking 234 of 250 releases while not one name answered
    /// (run 36884439109). So the press is dispatched by `NSApp.sendEvent`, which
    /// does what the application does with a click in one of its windows before
    /// the window sees it, and the release waits on the queue where a loop
    /// tracking the press finds it. Handing the press to the view under it does not
    /// work at all: SwiftUI takes clicks only through the window (measured, 0 of 20).
    ///
    /// Returns whether the release was taken by something else, a loop tracking the
    /// press, before it could be dispatched here; a case that fails says how many,
    /// because that count is what a regression would need to be diagnosed.
    @discardableResult
    static func click(at point: NSPoint, in window: NSWindow) -> Bool {
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else {
            preconditionFailure("AppKit made no mouse event for \(point)")
        }
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
        guard let press = NSApp.nextEvent(matching: .leftMouseDown, until: .distantPast,
                                          inMode: .default, dequeue: true) else {
            preconditionFailure("the press posted for \(point) never reached the queue")
        }
        NSApp.sendEvent(press)
        if let release = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast,
                                         inMode: .default, dequeue: true) {
            NSApp.sendEvent(release)
            return false
        }
        return true
    }

    /// One pass of the run loop, so a view that finishes its layout
    /// asynchronously has done so before the first click.
    private static func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
}
