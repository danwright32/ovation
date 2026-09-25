import AppKit
import SwiftUI
import Testing
@testable import Ovation

/// ovation#318 B7. Pictures of the real sheet, for Dan to judge before it merges.
///
/// LIGHT ONLY, SINCE ovation#479. This suite used to file a dark picture beside
/// two of the light ones, as separate deliverables that nothing compared. The sheet
/// is pinned to light like every other screen, and `AppearanceParityTests` now
/// refuses any difference between the two, so a dark picture here would be a
/// second copy of one already required to match, reading as a comparison somebody
/// made. The numbers the dark pictures held are left unused rather than renumbered,
/// so a picture keeps its name from one run to the next.
///
/// WHY A REAL WINDOW AND NOT A PREVIEW RENDERER. The page is a PDFKit view inside
/// an NSViewRepresentable, and SwiftUI's ImageRenderer does not draw those: the one
/// thing worth looking at would come out blank, and a blank page area in a
/// screenshot reads as a layout fault rather than as a limitation of the camera
/// (L115). So the sheet is hosted in an NSWindow that is never ordered front, laid
/// out, and captured from its own layer.
///
/// THE PAGE IN EACH PICTURE IS THE CAMERA'S DRAWING (ovation#374). PDFKit does not
/// draw into that capture either, so `OffscreenShot` draws the page the sheet's PDF
/// view holds into the area it occupies and marks it, in magenta, as not the live
/// view. `OffscreenShotPageTests` below reads the ink and the mark back out of the
/// picture.
///
/// IT RUNS ON EVERY RUN (ovation#383): scripts/run-tests.sh always names a folder,
/// and CI keeps the pictures as an artifact. Run some other way, it still SAYS WHEN IT
/// DID NOTHING. With no directory named it writes
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

    @Test("the sheet is captured, or it says it captured nothing")
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
            try OffscreenShot.capture(sheet, size: shot.size, scheme: shot.scheme, to: url)
            written.append(shot.fileName)
        }

        // AND THE PAGE ITSELF, as a PDF beside the pictures. The page in each
        // picture above is the camera's drawing of it, at the sheet's size, and is
        // marked as such (ovation#374); this is the page at full resolution, to be
        // judged on its own. The bytes written here are the ones the sheet was
        // handed, which are the ones a send would attach (PRD 10c).
        let pagePresenter = try ReviewSampleWorld.presenter(for: .ordinary)
        let page = InvoicePage()
        try pagePresenter.show(on: page)
        let bytes = try #require(page.bytes)
        try bytes.write(to: directory.appending(path: "00-the-page-itself.pdf"))
        written.append("00-the-page-itself.pdf")

        #expect(written.count == Shot.all.count + 1)
        print("REVIEW SHOTS: wrote \(written.count) file(s) to \(directory.path)")
    }

    // MARK: the send (ovation#42)

    /// THE SHEET OVER A REAL REVIEW, in every state the send can put it in, so the
    /// Send half is judged by being looked at like the rest (L606). The review is
    /// built the way the app builds one, over an in-memory store, and each state is
    /// set on it; a stand in Gmail is never asked, because no picture presses Send.
    @Test("the send states are captured, or it says it captured nothing")
    func captureTheSendStates() async throws {
        guard let directory = Self.outputDirectory else {
            print("REVIEW SEND SHOTS: no TEST_RUNNER_OVATION_SHOT_DIR, so nothing was captured.")
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        var written = 0
        for state in SendShot.all {
            let review = try await Self.review(redirected: state.redirected, dueToday: state.dueToday, day: day)
            review.state = state.state(day)
            let presenter = review.presenter
            let page = InvoicePage()
            try presenter.show(on: page)
            let sheet = ReviewSheet(presenter: presenter, review: review, page: page, close: {})
            try OffscreenShot.capture(sheet, size: CGSize(width: 1352, height: 878), scheme: .light,
                                      to: directory.appending(path: state.fileName))
            written += 1
        }
        #expect(written == SendShot.all.count)
        print("REVIEW SEND SHOTS: wrote \(written) file(s) to \(directory.path)")
    }

    private struct SendShot {
        let fileName: String
        let redirected: Bool
        var dueToday = false
        let state: (Date) -> ReviewSendState

        /// COMPUTED, not stored: each carries a closure, which a shared constant may not.
        static var all: [SendShot] { [
            SendShot(fileName: "09-send-ready-light.png", redirected: false, state: { _ in .ready }),
            SendShot(fileName: "10-send-ready-to-test-address-light.png", redirected: true, state: { _ in .ready }),
            SendShot(fileName: "11-sending-light.png", redirected: false,
                     state: { .working(since: $0.addingTimeInterval(-3)) }),
            SendShot(fileName: "12-sent-light.png", redirected: false,
                     state: { .sent(at: $0, to: ["booker@example.com"]) }),
            SendShot(fileName: "13-not-sent-light.png", redirected: false,
                     state: { _ in .refused("Gmail refused it: invalid recipient. Nothing was sent, and this is still a draft.") }),
            SendShot(fileName: "14-could-not-tell-light.png", redirected: false,
                     state: { _ in .couldNotTell("Gmail did not answer (the request timed out), so Ovation cannot tell whether it went. It will not be sent again until that is settled.") }),
            // BOTH BANDS AT ONCE, so the order is judged by being seen: the send that
            // will not reach the client is said first, above the due date.
            SendShot(fileName: "15-test-address-and-due-today-light.png", redirected: true,
                     dueToday: true, state: { _ in .ready }),
        ] }
    }

    /// A review of a real invoice over an in-memory store, as the app opens one.
    /// Not private: AppearanceParityTests opens the same one (ovation#479).
    static func review(redirected: Bool, dueToday: Bool, day: Date) async throws -> InvoiceReview {
        let container = try OvationSchema.container(inMemory: true)
        let context = container.mainContext
        let client = Client(name: "A Client", taxStatus: .notExempt)
        client.email = "booker@example.com"
        context.insert(client)
        let issued = BusinessDate.stamping(day)
        let invoice = Invoice(client: client, kind: .fromABooking, invoiceDate: issued,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        context.insert(invoice)
        // DUE TODAY is judged against the real clock, which is what the warning reads.
        invoice.dueDate = BusinessDate.stamping(dueToday ? Date() : day.addingTimeInterval(14 * 86_400))
        let shoot = Shoot(name: "Autumn Concert", when: .dayOnly(issued), venue: "Calder Street Theatre")
        shoot.shotFrom = ClockTime("19:00")
        shoot.shotUntil = ClockTime("21:30")
        invoice.add(shoot)
        invoice.add(LineItem.hourly(hours: Hours(quarters: 10), at: Money(dollars: 250),
                                    describedAs: "Concert photography", for: shoot))
        try context.save()
        let settings = URL.temporaryDirectory.appending(path: "ovation-shot-sending-\(UUID().uuidString).json")
        let destination = redirected
            ? #""destination":"test","testAddress":"second@example.com""#
            : #""destination":"clients""#
        try Data(#"{"fromName":"Dan Wright","fromEmail":"dan@example.com",\#(destination)}"#.utf8).write(to: settings)
        let reviewer = InvoiceReviewer(container: container, footer: { .fixed }, settingsFile: settings,
                                       makeSender: { _ in .failure(SenderUnavailable(sentence: "not in a picture")) },
                                       clock: { day })
        return try await reviewer.open(invoice.persistentModelID).get()
    }

    /// One picture to take.
    private struct Shot {
        let sample: ReviewSample
        let scheme: ColorScheme
        let opened: Bool
        let size: CGSize
        let fileName: String

        /// BOTH SIZES, because a surface looked at in one is a surface half seen
        /// (L606). The window sizes are Dan's smallest (1352 by 878) and a wide one.
        /// One theme, for the reason in the header.
        static let all: [Shot] = [
            Shot(sample: .ordinary, scheme: .light, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "01-ordinary-light.png"),
            Shot(sample: .ordinary, scheme: .light, opened: true,
                 size: CGSize(width: 1680, height: 1050), fileName: "03-page-opened-light.png"),
            Shot(sample: .pastDue, scheme: .light, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "04-past-due-light.png"),
            Shot(sample: .dueSoon, scheme: .light, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "05-due-soon-light.png"),
            Shot(sample: .genuineOverride, scheme: .light, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "07-override-light.png"),
            Shot(sample: .nowhereToSend, scheme: .light, opened: false,
                 size: CGSize(width: 1352, height: 878), fileName: "08-nowhere-to-send-light.png"),
        ]
    }

}

// MARK: the page in the picture (ovation#374)
//
// PDFKit does not draw into the camera's snapshot, so every picture of the sheet
// used to hold an empty rectangle where the page sits, and a reviewer handed that
// reads it as a layout fault or stops looking (L115). The camera now draws the
// page itself, from the PDF the page view holds, and marks the whole area as its
// own drawing so the substitute cannot be mistaken for the live view (L472).
//
// WHAT THIS MEASURES IS THE PICTURE, not the camera's report about it. The rect
// the camera returns only says where to look; the ink, the paper and the mark are
// read back out of the PNG that was written, because a camera that reported a
// substitution it never drew would otherwise pass (L63).
//
// IN THIS FILE RATHER THAN ITS OWN, so the capture it guards and the picture
// suite that depends on it are read together.

@MainActor
struct OffscreenShotPageTests {

    @Test("the review sheet's picture shows the page, marked as the camera's drawing")
    func thePageIsInThePicture() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ovation-page-shot-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let presenter = try ReviewSampleWorld.presenter(for: .ordinary)
        let page = InvoicePage()
        try presenter.show(on: page)
        let sheet = ReviewSheet(presenter: presenter, page: page, close: {})
        let url = directory.appending(path: "sheet.png")
        let shot = try OffscreenShot.capture(sheet, size: CGSize(width: 1352, height: 878),
                                             scheme: .light, to: url)

        // ONE PAGE, because the sheet shows one. Zero would mean the camera never
        // found the page view, and the checks below would then have nothing to read.
        try #require(shot.substitutedPages.count == 1)
        let area = shot.substitutedPages[0]
        let picture = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))

        var ink = 0, paper = 0, mark = 0
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) {
                // THE PICTURE'S OWN COMPONENTS, unconverted. The bitmap is calibrated
                // RGB, and the camera's magenta reads back as about (0.97, 0.2, 0.96)
                // in it (measured 2026-09-25), so the mark is recognised as magenta
                // by shape rather than matched to a value a conversion would move.
                guard let colour = picture.colorAt(x: x, y: y) else { continue }
                let (r, g, b) = (colour.redComponent, colour.greenComponent, colour.blueComponent)
                if r > 0.85, g < 0.4, b > 0.85 {
                    mark += 1
                } else if r > 0.97, g > 0.97, b > 0.97 {
                    paper += 1
                } else if r < 0.4, g < 0.4, b < 0.4 {
                    ink += 1
                }
            }
        }
        let total = Int(area.width) * Int(area.height)
        // THE PAGE: mostly white paper with the invoice's type on it. The blank
        // picture this replaces had neither, only the window's own backdrop.
        #expect(paper > total / 3, "only \(paper) of \(total) pixels in the page area are paper, so the page was not drawn")
        #expect(ink > 500, "only \(ink) pixels in the page area are ink, so there is no invoice on the page")
        // THE MARK, in a colour the app uses nowhere, so the drawing says whose it is.
        #expect(mark > 2_000, "only \(mark) pixels carry the substitute's mark, so it could be read as the live view")
    }
}
