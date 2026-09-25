import AppKit
import Testing
@testable import Ovation

/// ovation#123. The window's title bar carries no title.
///
/// Decided by Dan, 2026-09-23: "the Instrument Serif heading in the content names
/// the screen, and the window title bar carries no title (hidden, as macOS apps
/// with a large content heading do)." The design record drew the screen's name in
/// both places; this is the real window built to match the record once it lost
/// the top one.
///
/// THE REAL WINDOW, not a view hosted in one made here. The title belongs to the
/// window the `Window` scene makes, and the test host launches the app, so that
/// window is asked directly. A view hosted in a test's own NSWindow would prove
/// the modifier works somewhere the app never puts it (L472).
///
/// HIDDEN, AND NOTHING ELSE MOVED. The decision was about the title text only, so
/// the title bar's height, the window's style and the absence of a toolbar are
/// asserted as they were measured on the unchanged app on 2026-09-25: a 32 point
/// title bar over a 450 point window, style mask titled, closable, miniaturizable,
/// resizable and full size content, and no toolbar. A way of hiding the title that
/// installed a toolbar or changed the title bar's style would move the height and
/// fail here rather than ship as a quiet layout change.
@MainActor
struct MainWindowTitleTests {

    /// The one window, waited for on the condition rather than the clock (L290),
    /// with a deadline so a window that never comes fails rather than hangs (L110).
    private static func mainWindow() -> NSWindow? {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let window = NSApp.windows.first(where: {
                $0.identifier?.rawValue == OvationBuild.mainWindowID && $0.isVisible
            }) {
                return window
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
    }

    @Test("the main window's title is hidden and its title bar is otherwise as it was")
    func theTitleIsHidden() throws {
        let window = try #require(Self.mainWindow(),
                                  "the app's main window never appeared in the test host")

        #expect(window.titleVisibility == .hidden)
        // STILL NAMED, only not drawn: the Window menu, Mission Control and a
        // screen reader read the title, and hiding it is not removing it.
        #expect(window.title == OvationBuild.displayName)

        #expect(window.toolbar == nil)
        #expect(window.styleMask == [.titled, .closable, .miniaturizable, .resizable,
                                     .fullSizeContentView])
        #expect(window.frame.height - window.contentLayoutRect.height == 32)
    }
}
