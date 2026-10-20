// ovation#760. What a design score snapshot reads from the settled design's own
// spec, so the built side draws exactly what the design side drew around it.
//
// ONE SOURCE FOR BOTH SIDES. make-settled.py writes the settled file from the
// round's settled.json: the chrome picture, the slot the round draws into, and the
// committed fixture. This reads the same settled.json, so the slot and the data the
// SwiftUI view is drawn with cannot drift from the ones the design was drawn with.
// Copying the slot's numbers into the test would be the second copy that drifts
// (L370).
//
// THE CHROME IS DRAWN FROM THE SAME PICTURE. Ovation is a native app, so its
// chrome is a screenshot of its real window and the design draws its frames on
// that picture. The built side draws the same picture and puts the real view in
// the slot, so the score compares what the round decided rather than the window
// around it. An HTML chrome is refused: a SwiftUI snapshot has no way to draw it.
//
// vendor/design-score/DesignScoreCapture.swift is claude-config's file verbatim,
// compiled into this target from outside it, and scripts/design-score.sh refuses
// to run when it differs, so anything Ovation needs on top of it lives here and
// never in that copy.
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
@testable import Ovation

@MainActor
struct DesignScoreSpec {
    /// The capture folder the runner hands the snapshot, or nil when the test was
    /// not started by scripts/design-score.sh. xcodebuild hands the test
    /// `TEST_RUNNER_DESIGN_SCORE_CAPTURE` as `DESIGN_SCORE_CAPTURE`.
    static var captureFolder: URL? {
        let environment = ProcessInfo.processInfo.environment
        let named = environment["DESIGN_SCORE_CAPTURE"] ?? environment["TEST_RUNNER_DESIGN_SCORE_CAPTURE"] ?? ""
        return named.isEmpty ? nil : URL(fileURLWithPath: named)
    }

    let chromeURL: URL
    let chromeSize: CGSize
    let slot: CGRect
    let fixtureURL: URL
    private let chrome: CGImage

    /// The spec at a path relative to the repository this file is in.
    init(_ repositoryPath: String, file: StaticString = #filePath) throws {
        let root = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try self.init(url: root.appending(path: repositoryPath))
    }

    init(url: URL) throws {
        func refuse(_ why: String) -> DesignScoreCaptureError {
            .unreadable("\(url.path): \(why)")
        }
        guard let data = try? Data(contentsOf: url),
              let spec = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw refuse("not a settled design spec")
        }
        guard let chromeSpec = spec["chrome"] as? [String: Any],
              let captured = chromeSpec["captured"] as? String else {
            throw refuse("it names no captured chrome")
        }
        guard captured.lowercased().hasSuffix(".png") else {
            throw refuse("its chrome \(captured) is not a picture, and a SwiftUI snapshot can only draw a picture's chrome")
        }
        guard let numbers = chromeSpec["slot"] as? [Int], numbers.count == 4 else {
            throw refuse("its chrome has no slot of [x, y, width, height]")
        }
        guard let fixture = spec["fixture"] as? String else {
            throw refuse("it names no fixture, the data both sides draw")
        }
        let base = url.deletingLastPathComponent()
        chromeURL = base.appending(path: captured)
        fixtureURL = base.appending(path: fixture)
        let size = try DesignScoreCapture.pictureSize(chromeURL)
        chromeSize = CGSize(width: size.width, height: size.height)
        slot = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        guard slot.minX >= 0, slot.minY >= 0, slot.width > 0, slot.height > 0,
              slot.maxX <= chromeSize.width, slot.maxY <= chromeSize.height else {
            throw refuse("the slot \(numbers) reaches outside its \(size.width) by \(size.height) chrome")
        }
        guard let source = CGImageSourceCreateWithURL(chromeURL as CFURL, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw refuse("the chrome picture \(chromeURL.path) could not be read")
        }
        chrome = picture
    }

    /// The committed fixture, decoded as the screen's own data.
    func fixture<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: fixtureURL))
    }

    /// The chrome picture, with `view` drawn in its slot, at the picture's size.
    func framed(_ view: some View) -> AnyView {
        AnyView(
            ZStack(alignment: .topLeading) {
                Image(decorative: chrome, scale: 1)
                view
                    .frame(width: slot.width, height: slot.height, alignment: .topLeading)
                    .clipped()
                    .offset(x: slot.minX, y: slot.minY)
            }
            .frame(width: chromeSize.width, height: chromeSize.height, alignment: .topLeading)
        )
    }
}
