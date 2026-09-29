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

    /// THE MAC IS MADE DARK OR LIGHT FOR THIS PROCESS ONLY, through the app's own
    /// appearance, which is what a window with none of its own inherits from the
    /// system. Dan's Mac is in Dark mode and CI's is not, so the case sets each
    /// rather than depending on the machine (L504).
    private static func withTheMac<T>(_ appearance: NSAppearance.Name,
                                      _ body: @MainActor () throws -> T) rethrows -> T {
        let before = NSApp.appearance
        NSApp.appearance = NSAppearance(named: appearance)
        defer { NSApp.appearance = before }
        // One pass of the run loop, so a change of appearance has propagated.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return try body()
    }

    /// Draws a view in a window made the way the scene makes the main window,
    /// ordered back far outside every display (never front, as `OffscreenShot`),
    /// and hands back what its content drew. The camera the tokens' swatches are
    /// drawn through; the shell itself is photographed in the real window.
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

    /// What the real window's content drew, as the shell draws it into the window.
    private static func picture(ofTheRealWindow window: NSWindow) throws -> NSBitmapImageRep {
        window.layoutIfNeeded()
        window.displayIfNeeded()
        let content = try #require(window.contentView)
        let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        return bitmap
    }

    /// THE REAL WINDOW, WITH THE SHELL IN IT (ovation#604), in both appearances of
    /// the Mac.
    ///
    /// Dan, 2026-09-27, on the installed build with his Mac in Dark mode: the top of
    /// the window was "kind of jarringly black". Measured in this test host on the
    /// real window before the fix: its appearance was nil and its title bar resolved
    /// VibrantDark, because the light pin lived on each screen and the screen the
    /// window opens on (Starting) carried none.
    ///
    /// IT USED TO BE TWO CASES, and the second drew the shell in a window made here,
    /// because the test host never got past the Starting screen: a disposable launch
    /// opened no store, so the shell never owned the real window. A regression only
    /// the scene's own window has (its appearance, its title bar, its safe area) was
    /// invisible to both (L472, L3). A disposable launch now opens a store in memory
    /// when this case asks (`DisposableLaunchStore`), so it asks the window Dan
    /// actually gets, on Starting and then on the shell. ONE CASE, because the order
    /// is the point: Starting can only be asked before the shell has shown.
    ///
    /// ASKED OF THE TITLE BAR ITSELF, not only the window, because the title bar is
    /// what Dan saw, and it is a view AppKit owns rather than one of ours. And the
    /// design record's window top is SAMPLED FROM THE HEIGHT THE SHELL DRAWS
    /// (ovation#607): points written as numbers here would go on sampling the old
    /// rows the day `ShellView.titleBarHeight` moves (L401).
    @Test("the real window shows the shell, light, with the design record's window top, whether the Mac is dark or light")
    func theRealWindowTopIsTheDesignRecords() async throws {
        let window = try #require(Self.mainWindow(),
                                  "the app's main window never appeared in the test host")

        let railPoint = OvationWindow.railWidth / 2
        let startingSize = try #require(window.contentView?.bounds.size)
        let rail = try Self.swatches([OvationPalette.rail], size: startingSize)[0]

        // FIRST THE STARTING SCREEN, which carries no pin of its own, so only the
        // scene's pin can make this window light. The shell pins its window as
        // well, so once it has shown this could no longer tell whether the scene's
        // pin is there; that is why the store opens only when asked, below.
        try Self.withTheMac(.darkAqua) {
            let before = Self.hex(try Self.picture(ofTheRealWindow: window), x: railPoint, y: 4,
                                  width: startingSize.width)
            try #require(before != rail,
                         "the shell was already showing, so the Starting screen cannot be asked")
            #expect(!Self.isLight(NSApp.effectiveAppearance),
                    "the Mac has to read as dark for this to prove anything")
            #expect(window.appearance?.name == .aqua, "the scene's pin sets the window's own")
            let titleBar = try #require(window.standardWindowButton(.closeButton)?.superview,
                                        "the window has no title bar to ask")
            #expect(Self.isLight(titleBar.effectiveAppearance))
        }

        // THEN THE SHELL, WAITED FOR ON THE CONDITION (L290): the launch opens the
        // store in memory once asked, from its own task. The rail under the traffic
        // lights is drawn by the shell and by nothing else.
        DisposableLaunchStore.Gate.shared.ask()
        var seen = "none"
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let width = try #require(window.contentView?.bounds.width)
            seen = Self.hex(try Self.picture(ofTheRealWindow: window), x: railPoint, y: 4,
                            width: width)
            if seen == rail { break }
            // SLEPT, NOT SPUN. The launch finishes on the main actor, and a run loop
            // turned from inside this main actor job never runs another one: spun
            // here, the shell never came (measured, the whole 20 seconds).
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(seen == rail,
                     "the real window never showed the shell: its top left read \(seen), not the rail's \(rail)")

        for mac in [NSAppearance.Name.darkAqua, .aqua] {
            try Self.withTheMac(mac) {
                #expect(Self.isLight(NSApp.effectiveAppearance) == (mac == .aqua),
                        "the Mac has to read as \(mac.rawValue) for this to prove anything")

                #expect(window.appearance?.name == .aqua, "the pin sets the window's own")
                #expect(Self.isLight(window.effectiveAppearance))
                let titleBar = try #require(window.standardWindowButton(.closeButton)?.superview,
                                            "the window has no title bar to ask")
                #expect(Self.isLight(titleBar.effectiveAppearance))
                // THE TITLE BAR DRAWS NOTHING OF ITS OWN (the design record, lines 147
                // to 167): the rail runs under the traffic lights and the content draws
                // the chrome, so the system's title bar material is not what anyone sees.
                #expect(window.titlebarAppearsTransparent)

                let size = try #require(window.contentView?.bounds.size)
                let tokens = try Self.swatches(
                    [OvationPalette.rail, OvationPalette.chrome, OvationPalette.rule,
                     OvationPalette.background],
                    size: size)
                let (rail, chrome, rule, page) = (tokens[0], tokens[1], tokens[2], tokens[3])
                #expect(Set([rail, chrome, rule, page]).count == 4,
                        "the four tokens have to draw differently for this to tell them apart")

                let bitmap = try Self.picture(ofTheRealWindow: window)
                // FILED WHEN ASKED, like every shot suite, so the top can be looked at
                // rather than only sampled (L606). Opt in, and never a condition of the
                // assertions below.
                let environment = ProcessInfo.processInfo.environment
                let named = environment["OVATION_SHOT_DIR"]
                    ?? environment["TEST_RUNNER_OVATION_SHOT_DIR"] ?? ""
                if !named.isEmpty, let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: URL(fileURLWithPath: named)
                        .appending(path: "window-top-\(mac.rawValue).png"))
                }

                func at(_ x: CGFloat, _ y: CGFloat) -> String {
                    Self.hex(bitmap, x: x, y: y, width: size.width)
                }
                let bar = ShellView.titleBarHeight
                let content = OvationWindow.railWidth + 200
                #expect(at(railPoint, 4) == rail, "the rail under the traffic lights")
                #expect(at(content, 4) == chrome, "--chrome at the top")
                #expect(at(content, bar - 8) == chrome, "--chrome under the title bar")
                #expect(at(content, bar - 0.5) == rule, "--rule ending it at \(bar)")
                #expect(at(content, bar + 2) == page, "the screen's own page below it")
            }
        }
    }
}
