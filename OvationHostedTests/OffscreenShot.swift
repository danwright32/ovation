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
// AND THE PDF PAGE IS STILL THE CAMERA'S DRAWING, NOT PDFKIT'S (ovation#374).
// Ordering the window back did not make PDFKit draw into the cached display:
// measured 2026-09-25, the page area of the review sheet held no ink at all. So
// after the snapshot the camera draws each page a PDF view holds, from that view's
// own document and geometry, and marks the whole area as its own drawing, so the
// picture shows the page in place and cannot be read as the live view. Every
// suite gets it, because a blank page in any picture reads as a layout fault
// (L115), and the parity suite's two themes get the same drawing.
//
// THE THEME IS THE WINDOW'S, not only the SwiftUI environment's. Materials and the
// standard control colours come from the window's appearance, so asking for light
// while the Mac is dark produced dark chrome under light text (measured
// 2026-09-16).
import AppKit
import PDFKit
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

    /// What a capture did beyond writing the picture.
    struct Capture {
        /// Where the camera drew a page in place of PDFKit, in the written PNG's
        /// pixels with the origin at the top left, which is how a reader of it
        /// addresses them.
        let substitutedPages: [CGRect]
    }

    /// The substitute's mark, as sRGB components: magenta, which OvationPalette
    /// uses nowhere.
    static let substituteMark = (r: CGFloat(1), g: CGFloat(0), b: CGFloat(1))

    /// Hosts a view in an offscreen window and writes what it drew, as a PNG.
    @discardableResult
    static func capture(_ view: some View, size: CGSize, scheme: ColorScheme,
                        to url: URL) throws -> Capture {
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
        let pages = substitutePages(in: content, on: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure.couldNotEncode
        }
        try data.write(to: url)
        return Capture(substitutedPages: pages)
    }

    // MARK: the page PDFKit does not draw (ovation#374)

    /// What the mark says, inside the picture, so a reviewer given only the PNG
    /// knows the page area is the camera's drawing and not the app's.
    static let substituteLabel = "NOT THE LIVE VIEW: the test camera drew this page from the page view's PDF (ovation#374)"

    /// DRAWS EACH PAGE A PDF VIEW IS SHOWING into the picture, where PDFKit left
    /// the area empty, and marks the whole area as the camera's own drawing.
    ///
    /// THE PAGE COMES FROM THE VIEW, never from the test. It is the document the
    /// PDF view was handed, which is the one render's bytes the sheet shows, so a
    /// sheet showing nothing still photographs as nothing (L472). Its place and size
    /// come from the view's own geometry, at the scale it was set to, clipped to what
    /// the view can actually show inside its scroll view.
    ///
    /// MARKED, because a substitute that looks like the real thing is the camera
    /// lying (L472): a magenta border round the area and a magenta band across its
    /// foot, in a colour the app uses nowhere, carrying the sentence above.
    private static func substitutePages(in content: NSView, on bitmap: NSBitmapImageRep) -> [CGRect] {
        let views = pdfViews(in: content)
        guard !views.isEmpty, content.bounds.width > 0,
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return [] }
        let scale = CGFloat(bitmap.pixelsWide) / content.bounds.width
        let height = content.bounds.height
        /// A rect in the content view's points, as the bitmap's context addresses
        /// it: bottom left origin, whether or not the content view is flipped.
        func unflipped(_ rect: CGRect) -> CGRect {
            content.isFlipped
                ? CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
                : rect
        }
        let mark = NSColor(srgbRed: substituteMark.r, green: substituteMark.g, blue: substituteMark.b, alpha: 1)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        // POINTS IN, whatever the context already does. A context made over a
        // bitmap whose size is set in points may map points to pixels itself, and
        // scaling again would draw everything at twice the offset, outside the
        // picture; so only the part of the scale it does not already apply is added.
        let applied = context.cgContext.userSpaceToDeviceSpaceTransform.a
        if applied > 0, abs(applied - scale) > 0.001 {
            context.cgContext.scaleBy(x: scale / applied, y: scale / applied)
        }

        var drawn: [CGRect] = []
        for view in views {
            guard let document = view.document, document.pageCount > 0 else { continue }
            let visible = unflipped(content.convert(view.visibleRect, from: view)).integral
            guard visible.width > 1, visible.height > 1 else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: visible).setClip()
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let media = page.bounds(for: .mediaBox)
                let placed = unflipped(content.convert(view.convert(media, from: page), from: view))
                guard placed.intersects(visible) else { continue }
                NSColor.white.setFill()
                placed.fill()
                page.thumbnail(of: NSSize(width: placed.width * scale, height: placed.height * scale),
                               for: .mediaBox)
                    .draw(in: placed)
            }
            // AT THE FOOT OF THE AREA, not the head, because the head of an invoice
            // is what a reviewer reads first and the foot of a fitted page is paper.
            let band = CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: 36)
            mark.setFill()
            band.fill()
            let border = NSBezierPath(rect: visible.insetBy(dx: 2, dy: 2))
            border.lineWidth = 4
            mark.setStroke()
            border.stroke()
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            NSAttributedString(string: substituteLabel, attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: style,
            ]).draw(in: band.insetBy(dx: 8, dy: 5))
            NSGraphicsContext.restoreGraphicsState()
            drawn.append(CGRect(x: visible.minX * scale, y: (height - visible.maxY) * scale,
                                width: visible.width * scale, height: visible.height * scale))
        }
        context.flushGraphics()
        return drawn
    }

    private static func pdfViews(in view: NSView) -> [PDFView] {
        if let pdf = view as? PDFView { return [pdf] }
        return view.subviews.flatMap(pdfViews(in:))
    }
}
