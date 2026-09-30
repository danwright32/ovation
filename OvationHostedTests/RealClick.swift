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
// A CLICK IS ANSWERED BEFORE `sendEvent` RETURNS. Measured 2026-09-30 in a bare
// AppKit host: the action had run by the time the release was delivered, both
// for the plain style on its words and for `WholeTarget` on its clear end, and
// a plain button's clear end did nothing, which is the defect reproduced.
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
        window.layoutIfNeeded()
        settle()
        return window
    }

    /// A click at every `step` points down the vertical line at `x`, between
    /// `fromTop` and `toTop` points below the top of the window's content, calling
    /// `after` once each click has been answered.
    static func sweep(x: CGFloat, in window: NSWindow, fromTop: CGFloat = 0, toTop: CGFloat? = nil,
                      step: CGFloat = 3, after: () -> Void) {
        let height = window.contentView?.bounds.height ?? 0
        let bottom = min(toTop ?? height, height)
        for fromTheTop in stride(from: fromTop + 1, to: bottom, by: step) {
            click(at: NSPoint(x: x, y: height - fromTheTop), in: window)
            after()
        }
    }

    /// One press and release of the left button at `point`, in window coordinates.
    static func click(at point: NSPoint, in window: NSWindow) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
            else { continue }
            window.sendEvent(event)
        }
    }

    /// One pass of the run loop, so a view that finishes its layout
    /// asynchronously has done so before the first click.
    private static func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
}
