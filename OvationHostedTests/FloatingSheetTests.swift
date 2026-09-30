import AppKit
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#547, PRD 48a. Every sheet floats, centred in the window, with every corner
/// rounded, and never hangs from the title bar (Dan, 2026-09-25: "I don't want it to
/// hang down because that makes the top flat and it's ugly").
///
/// THE SHAPE IS READ OFF A PICTURE, not off the modifiers, because a sheet can carry
/// every right modifier and still be drawn flat topped by whatever presents it: the
/// review sheet did, as a system sheet, while its own view said nothing about its top
/// (L442). So the floating sheet is drawn in a window of the sizes the design checks
/// measure, and the card is found by its colour and measured.
@MainActor
struct FloatingSheetTests {

    /// A colour the palette uses nowhere, so the card is found by it alone.
    private static let card = NSColor(srgbRed: 0, green: 0.8, blue: 0.2, alpha: 1)

    /// The card's box in points, top left origin, and the bitmap it was found in.
    private struct Drawn {
        let bitmap: NSBitmapImageRep
        let scale: CGFloat
        let box: CGRect

        @MainActor func isCard(_ x: CGFloat, _ y: CGFloat) -> Bool {
            FloatingSheetTests.isCard(bitmap, Int(x * scale), Int(y * scale))
        }
    }

    private static func isCard(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
        // BY ITS HUE, NOT ITS EXACT VALUES, because the picture is written in the
        // window's colour space and a saturated green moves by more than a rounding
        // in the conversion back. Nothing else in the picture is green at all: the
        // dim is brown and the backdrop grey.
        guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        return colour.greenComponent - colour.redComponent > 0.35
            && colour.greenComponent - colour.blueComponent > 0.25
    }

    /// Draws a card that would be 800 by 560 if the window let it, the review
    /// sheet's size, floating in a window of `size`, and finds it.
    private static func draw(in size: CGSize) throws -> Drawn {
        let sheet = FloatingSheet(below: ShellView.titleBarHeight) {
            Color(nsColor: Self.card).frame(width: 800).frame(maxHeight: 560)
        }
        // Kept beside the other pictures where a folder is named, so a failure here
        // can be looked at rather than guessed about.
        let environment = ProcessInfo.processInfo.environment
        let kept = environment["OVATION_SHOT_DIR"] ?? environment["TEST_RUNNER_OVATION_SHOT_DIR"]
        let folder = kept.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        if let folder {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let url = (folder ?? FileManager.default.temporaryDirectory)
            .appending(path: "floating-sheet-\(Int(size.width))x\(Int(size.height)).png")
        defer { if folder == nil { try? FileManager.default.removeItem(at: url) } }
        try OffscreenShot.capture(sheet, size: size, scheme: .light, to: url)
        let bitmap = try #require(NSBitmapImageRep(data: try Data(contentsOf: url)))
        let scale = CGFloat(bitmap.pixelsWide) / size.width

        // The card's edges, along the lines through the window's middle.
        let midX = bitmap.pixelsWide / 2, midY = bitmap.pixelsHigh / 2
        let column = (0..<bitmap.pixelsHigh).filter { isCard(bitmap, midX, $0) }
        let row = (0..<bitmap.pixelsWide).filter { isCard(bitmap, $0, midY) }
        let middle = bitmap.colorAt(x: midX, y: midY)?.usingColorSpace(.sRGB)
        let top = try #require(column.first, "no card found; the middle pixel is \(String(describing: middle))")
        let bottom = try #require(column.last)
        let left = try #require(row.first), right = try #require(row.last)
        let box = CGRect(x: CGFloat(left) / scale, y: CGFloat(top) / scale,
                         width: CGFloat(right - left + 1) / scale,
                         height: CGFloat(bottom - top + 1) / scale)
        return Drawn(bitmap: bitmap, scale: scale, box: box)
    }

    /// The smallest window the app allows, where the room is least, and a roomy one.
    nonisolated private static let windows = [CGSize(width: OvationWindow.minimumWidth, height: 620),
                                  CGSize(width: 1064, height: 900)]

    @Test("the sheet is centred below the title bar, with room left above and below it",
          arguments: windows)
    func itIsCentred(in window: CGSize) throws {
        let drawn = try Self.draw(in: window)
        let above = drawn.box.minY - ShellView.titleBarHeight
        let below = window.height - drawn.box.maxY
        let beside = (drawn.box.minX, window.width - drawn.box.maxX)

        #expect(abs(above - below) <= 1, "above \(above), below \(below)")
        #expect(abs(beside.0 - beside.1) <= 1, "left \(beside.0), right \(beside.1)")
        // FLOATING, NOT HANGING: never touching the title bar or the window's foot.
        #expect(above >= FloatingSheet<EmptyView>.margin - 1, "only \(above) points below the title bar")
        #expect(below >= FloatingSheet<EmptyView>.margin - 1, "only \(below) points above the window's foot")
    }

    @Test("every corner of the sheet is rounded, the top two as well as the bottom",
          arguments: windows)
    func everyCornerIsRounded(in window: CGSize) throws {
        let drawn = try Self.draw(in: window)
        let box = drawn.box
        let inset: CGFloat = 0.5
        let corners = [("top left", box.minX + inset, box.minY + inset),
                       ("top right", box.maxX - inset - 1 / drawn.scale, box.minY + inset),
                       ("bottom left", box.minX + inset, box.maxY - inset - 1 / drawn.scale),
                       ("bottom right", box.maxX - inset - 1 / drawn.scale,
                        box.maxY - inset - 1 / drawn.scale)]
        for (name, x, y) in corners {
            #expect(!drawn.isCard(x, y), "the \(name) corner is square")
        }
        // The control (L1): the edges beside each corner are the card's, so a corner
        // reading as not card is the rounding and not a box found in the wrong place.
        let along = FloatingSheet<EmptyView>.cornerRadius + 2
        #expect(drawn.isCard(box.minX + along, box.minY + inset))
        #expect(drawn.isCard(box.minX + inset, box.minY + along))
        #expect(drawn.isCard(box.maxX - along, box.maxY - inset - 1 / drawn.scale))
    }

    /// The review sheet is 560 points tall where the window has room, and gives way
    /// in the smallest window, whose 582 points under the title bar would otherwise
    /// leave it touching both edges. Its page scrolls, so nothing is lost.
    @Test("the review sheet asks for 560 points and gives way to a shorter window")
    func theReviewSheetGivesWay() throws {
        let presenter = try ReviewSampleWorld.presenter(mainAddress: "booker@example.com",
                                                        overrideAddress: nil)
        let host = NSHostingController(rootView: ReviewSheet(presenter: presenter, close: {}))
        let roomy = host.sizeThatFits(in: CGSize(width: 800, height: 900))
        let short = host.sizeThatFits(in: CGSize(width: 800, height: 520))

        #expect(roomy.height == 560)
        #expect(roomy.width == 800)
        #expect(short.height <= 520)
    }

    @Test("Escape reaches the sheet's own escape, and only that")
    func escapeCallsEscape() throws {
        var escaped = 0
        var outside = 0
        let sheet = FloatingSheet(below: 0, outside: { outside += 1 },
                                  escape: { escaped += 1 }) { Text("card") }

        try sheet.inspect().zStack().callOnExitCommand()

        #expect(escaped == 1)
        #expect(outside == 0)
    }

    /// A click on the dimmed window around the sheet is swallowed, so nothing under
    /// it is pressed, and closes the sheet only where the sheet asked for that.
    @Test("a click outside the sheet reaches outside when given, and nothing beneath it")
    func aClickOutside() throws {
        var outside = 0
        let asked = FloatingSheet(below: 0, outside: { outside += 1 }, escape: nil) {
            Text("card")
        }
        try asked.inspect().zStack().color(0).callOnTapGesture()
        #expect(outside == 1)

        // Given none, the click is still taken, and does nothing.
        let unasked = FloatingSheet(below: 0, outside: nil, escape: nil) { Text("card") }
        #expect(throws: Never.self) {
            try unasked.inspect().zStack().color(0).callOnTapGesture()
        }
    }

    /// With no escape, as while a send is in flight, Escape does nothing at all.
    @Test("with no escape given, Escape does nothing")
    func noEscapeDoesNothing() throws {
        let sheet = FloatingSheet(below: 0, outside: nil, escape: nil) { Text("card") }
        #expect(throws: Never.self) { try sheet.inspect().zStack().callOnExitCommand() }
    }
}
