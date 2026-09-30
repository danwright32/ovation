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
// THE PLACE IS FOUND FROM THE ACCESSIBILITY TREE, never typed as a coordinate.
// A button's accessibility frame is the frame the layout gave it, so a point near
// its far end is inside the row and away from its words however the row is laid
// out, and a layout change moves the point with it (L237).
//
// NEVER ORDERED FRONT, for the reason `OffscreenShot` gives: these run inside an
// ordinary test run while Dan is working. The window is ordered BACK, far outside
// every display, which is enough for it to lay out and take events.
import AppKit
import SwiftUI

@MainActor
enum RealClick {

    enum Failure: Error, CustomStringConvertible {
        case noSuchButton(String, seen: [String])

        var description: String {
            switch self {
            case .noSuchButton(let label, let seen):
                return "no button labelled \(label) in the hosted view; saw \(seen)"
            }
        }
    }

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

    /// The frame, in the window's coordinates, of the button whose accessibility
    /// label or title is `label`.
    static func frame(ofButton label: String, in window: NSWindow) throws -> CGRect {
        var seen: [String] = []
        var found: CGRect?
        func walk(_ element: Any, depth: Int) {
            guard found == nil, depth < 60,
                  let node = element as? NSAccessibilityProtocol else { return }
            let role: NSAccessibility.Role? = node.accessibilityRole()
            if role == .button {
                let named: String? = node.accessibilityLabel()
                let titled: String? = node.accessibilityTitle()
                let said = [named, titled].compactMap { $0 }.first { !$0.isEmpty } ?? ""
                seen.append(said)
                if said == label {
                    found = window.convertFromScreen(node.accessibilityFrame())
                    return
                }
            }
            let children: [Any]? = node.accessibilityChildren()
            for child in children ?? [] { walk(child, depth: depth + 1) }
        }
        if let content = window.contentView { walk(content, depth: 0) }
        guard let found else { throw Failure.noSuchButton(label, seen: seen) }
        return found
    }

    /// A point inside `frame`, `inset` points in from its trailing edge and halfway
    /// down: where a row's words are not.
    static func nearTrailingEnd(of frame: CGRect, inset: CGFloat = 6) -> NSPoint {
        NSPoint(x: frame.maxX - inset, y: frame.midY)
    }

    /// A point inside `frame`, `inset` points in from its leading edge: where a
    /// row's words start.
    static func nearLeadingEnd(of frame: CGRect, inset: CGFloat = 14) -> NSPoint {
        NSPoint(x: frame.minX + inset, y: frame.midY)
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
        settle()
    }

    /// One pass of the run loop, so an action dispatched after the release has
    /// run. A wait on the run loop rather than on the clock (L290).
    private static func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
}
