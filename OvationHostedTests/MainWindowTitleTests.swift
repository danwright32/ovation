import AppKit
import SwiftUI
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
///
/// ovation#593 MADE THE TITLE BAR TRANSPARENT, deliberately, and moved nothing
/// else this case measures: the height, style mask and missing toolbar still hold,
/// and the cases below hold the title bar's appearance and what shows through it.
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

    // MARK: the light title bar, whatever the Mac is set to (ovation#593)

    /// Whether an appearance resolves to light.
    private static func isLight(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            .map { $0 == .aqua || $0 == .vibrantLight } ?? false
    }

    /// THE MAC IS MADE DARK FOR THIS PROCESS ONLY, through the app's own appearance,
    /// which is what a window with none of its own inherits from the system. Dan's
    /// Mac is in Dark mode and CI's is not, so the case sets it rather than depending
    /// on the machine (L504).
    private static func withTheMacDark<T>(_ body: @MainActor () throws -> T) rethrows -> T {
        let before = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
        defer { NSApp.appearance = before }
        return try body()
    }

    /// Dan, 2026-09-27, on the installed build with his Mac in Dark mode: the top of
    /// the window was "kind of jarringly black". Measured in this test host on the
    /// real window before the fix: its appearance was nil and its title bar resolved
    /// VibrantDark, because the light pin lived on each screen and the screen the
    /// window opens on (Starting) carried none.
    ///
    /// ASKED OF THE TITLE BAR ITSELF, not only the window, because the title bar is
    /// what Dan saw, and it is a view AppKit owns rather than one of ours.
    @Test("the main window and its title bar are light when the Mac is dark")
    func theTitleBarIsLightWhenTheMacIsDark() throws {
        try Self.withTheMacDark {
            let window = try #require(Self.mainWindow(),
                                      "the app's main window never appeared in the test host")
            // One pass of the run loop, so a change of appearance has propagated.
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            #expect(!Self.isLight(NSApp.effectiveAppearance),
                    "the Mac has to read as dark for this to prove anything")

            #expect(window.appearance?.name == .aqua, "the pin sets the window's own")
            #expect(Self.isLight(window.effectiveAppearance))
            let titleBar = try #require(window.standardWindowButton(.closeButton)?.superview,
                                        "the window has no title bar to ask")
            #expect(Self.isLight(titleBar.effectiveAppearance))
            // THE TITLE BAR DRAWS NOTHING OF ITS OWN (the design record, lines 147 to
            // 167): the rail runs under the traffic lights and the content draws the
            // chrome, so the system's title bar material is not what anyone sees.
            #expect(window.titlebarAppearsTransparent)
        }
    }

    /// Draws a view in a window made the way the scene makes the main window,
    /// ordered back far outside every display (never front, as `OffscreenShot`),
    /// and hands back what its content drew.
    private static func picture(of view: some View, size: NSSize) throws -> NSBitmapImageRep {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                          .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: view)
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)
        defer { window.close() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        window.layoutIfNeeded()
        window.displayIfNeeded()
        let content = try #require(window.contentView)
        let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        return bitmap
    }

    /// A pixel's components as the picture holds them, as hex. NOT CONVERTED: the
    /// picture's colour space tag does not round trip (measured 2026-09-28, the
    /// chrome read F2EDE9 through sRGB), so a sample is compared with a SWATCH of
    /// the token drawn through the same camera, never with a hex literal.
    nonisolated private static func hex(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat,
                            width: CGFloat) -> String {
        let scale = CGFloat(bitmap.pixelsWide) / width
        guard let c = bitmap.colorAt(x: Int(x * scale), y: Int(y * scale)) else { return "none" }
        return String(format: "%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    /// The four tokens the window top is made of, each drawn as a band across a
    /// picture the size of the shell's, through the same camera, and read in the
    /// middle of its band. A window as small as one swatch drew nothing at all.
    private static func swatches(_ colours: [Color], size: NSSize) throws -> [String] {
        let bands = HStack(spacing: 0) {
            ForEach(colours.indices, id: \.self) { colours[$0] }
        }
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
        let bitmap = try picture(of: bands, size: size)
        let band = size.width / CGFloat(colours.count)
        return colours.indices.map {
            hex(bitmap, x: band * (CGFloat($0) + 0.5), y: size.height / 2, width: size.width)
        }
    }

    /// The design record's window top, drawn by the shell in a window made the way
    /// the scene makes the main window, with the Mac dark: the rail's colour under
    /// the traffic lights, and `--chrome` over the content for 38 points ending in
    /// a one point `--rule`.
    ///
    /// A WINDOW MADE HERE, and that is the residual stated rather than hidden: the
    /// test host never gets past the Starting screen, so the real window never
    /// shows the shell. The case above holds the real window to the same style.
    @Test("the rail runs to the top of the window and the content carries the chrome title bar")
    func theWindowTopIsTheDesignRecords() throws {
        try Self.withTheMacDark {
            let clients = (0..<3).map { i -> Client in
                let client = Client(name: "Client \(i)", taxStatus: .neverRecorded)
                client.email = "c\(i)@example.example"
                return client
            }
            let shell = ShellView(
                shell: ShellPresenter(selected: .roster, rosterHasWork: { true }),
                roster: RosterPresenter(clients: clients, write: { _, _ in }),
                problems: ProblemsStore(journal: InMemoryProblemsJournal()))
            let width: CGFloat = 1000
            let bitmap = try Self.picture(of: shell, size: NSSize(width: width, height: 680))
            func at(_ x: CGFloat, _ y: CGFloat) -> String { Self.hex(bitmap, x: x, y: y, width: width) }
            // FILED WHEN ASKED, like every shot suite, so the top can be looked at
            // rather than only sampled (L606). Opt in, and never a condition of the
            // assertions below.
            let environment = ProcessInfo.processInfo.environment
            let named = environment["OVATION_SHOT_DIR"]
                ?? environment["TEST_RUNNER_OVATION_SHOT_DIR"] ?? ""
            if !named.isEmpty, let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: named).appending(path: "window-top.png"))
            }

            let tokens = try Self.swatches(
                [OvationPalette.rail, OvationPalette.chrome, OvationPalette.rule,
                 OvationPalette.background],
                size: NSSize(width: width, height: 680))
            let (rail, chrome, rule, page) = (tokens[0], tokens[1], tokens[2], tokens[3])
            #expect(Set([rail, chrome, rule, page]).count == 4,
                    "the four tokens have to draw differently for this to tell them apart")

            let content = OvationWindow.railWidth + 200
            #expect(at(100, 4) == rail, "the rail under the traffic lights")
            #expect(at(content, 4) == chrome, "--chrome at the top")
            #expect(at(content, 30) == chrome, "--chrome under the title bar")
            #expect(at(content, 37.5) == rule, "--rule ending it at 38")
            #expect(at(content, 40) == page, "the screen's own page below it")
        }
    }
}
