// ovation#760. The design match score's proof screen, and the one place the
// built side of a score is drawn in Ovation until a real screen is settled.
//
// WHAT IT PROVES. scripts/design-score.sh proof --design
// OvationHostedTests/DesignScore/Proof/proof.html draws the settled file's frame in
// the shared Playwright's Chromium, then this suite draws the same fixture through
// SwiftUI inside the same chrome picture, and the score compares the two. Measured
// 2026-10-20: 100% as built, and below it with one band's colour changed on purpose.
//
// COLOUR ONLY, and that is a measured limit rather than a simplification: the same
// 13pt line of text drawn by Chrome and by SwiftUI lands in the same box and still
// matched only 96.9%, because the two engines antialias glyph edges differently.
// A real screen with words on it meets that the first time it is scored.
//
// THE CAPTURE IS OPT IN, AND IT SAYS WHEN IT DID NOTHING (L98). It needs the design
// side drawn first, which only the runner does. The three tests above it always run,
// and hold the part that is Ovation's own: that the spec is read the way the
// settled file maker reads it, and that a view lands in the chrome's slot.
import AppKit
import ImageIO
import SwiftUI
import Testing
@testable import Ovation

/// The proof's committed data, the same file the settled design's builder draws.
struct ProofFixture: Decodable {
    struct Band: Decodable {
        let name: String
        let red: Int
        let green: Int
        let blue: Int
        let height: Int
    }
    let bands: [Band]
}

/// The proof screen: each band, top to bottom, at its own height and colour.
struct ProofBandsView: View {
    let bands: [ProofFixture.Band]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(bands, id: \.name) { band in
                Color(.sRGB, red: Double(band.red) / 255, green: Double(band.green) / 255,
                      blue: Double(band.blue) / 255)
                    .frame(height: CGFloat(band.height))
            }
        }
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProofDesignScoreTests {

    static let specPath = "OvationHostedTests/DesignScore/Proof/settled.json"

    @Test("the spec gives the chrome, its slot and the fixture the settled file was made from")
    func readsTheSpec() throws {
        let spec = try DesignScoreSpec(Self.specPath)
        #expect(spec.slot == CGRect(x: 16, y: 32, width: 208, height: 72))
        #expect(spec.chromeSize == CGSize(width: 240, height: 120))
        let fixture = try spec.fixture(ProofFixture.self)
        #expect(fixture.bands.map(\.name) == ["light", "dark"])
    }

    @Test("a spec naming a slot outside its chrome is refused rather than drawn")
    func refusesASlotOutsideTheChrome() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "design-score-spec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = try DesignScoreSpec(Self.specPath)
        try FileManager.default.copyItem(at: real.chromeURL, to: folder.appending(path: "chrome.png"))
        let spec = #"{"chrome": {"captured": "chrome.png", "slot": [200, 0, 80, 10]}, "fixture": "f.json"}"#
        try Data(spec.utf8).write(to: folder.appending(path: "settled.json"))
        #expect(throws: DesignScoreCaptureError.self) {
            try DesignScoreSpec(url: folder.appending(path: "settled.json"))
        }
    }

    @Test("a framed view draws the chrome around it and itself in the slot")
    func framesTheViewInTheSlot() throws {
        let spec = try DesignScoreSpec(Self.specPath)
        let fixture = try spec.fixture(ProofFixture.self)
        let file = FileManager.default.temporaryDirectory
            .appending(path: "design-score-framed-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        try DesignScoreCapture.render(spec.framed(ProofBandsView(bands: fixture.bands)),
                                      width: 240, height: 120, to: file)
        let picture = try Pixels(file)
        // The chrome's bar, the slot's two bands, and the chrome's body beside them.
        #expect(picture.near(x: 5, y: 5, 0x3B, 0x2B, 0x21))
        #expect(picture.near(x: 20, y: 40, 251, 244, 239))
        #expect(picture.near(x: 20, y: 90, 59, 43, 33))
        #expect(picture.near(x: 230, y: 110, 0xEF, 0xE8, 0xE3))
        #expect(picture.near(x: 8, y: 50, 0xEF, 0xE8, 0xE3), "the band reached left of its slot")
    }

    @Test("the proof screen as built, drawn for the design score")
    func matchesTheSettledDesign() throws {
        guard let folder = DesignScoreSpec.captureFolder else {
            print("DESIGN SCORE: no TEST_RUNNER_DESIGN_SCORE_CAPTURE, so the proof screen was not drawn. scripts/design-score.sh draws it.")
            return
        }
        let spec = try DesignScoreSpec(Self.specPath)
        let fixture = try spec.fixture(ProofFixture.self)
        try DesignScoreCapture.capture(
            folder: folder,
            build: "ProofBandsView",
            view: { _ in spec.framed(ProofBandsView(bands: fixture.bands)) },
            checks: { _ in
                let first = fixture.bands.first?.name ?? "none"
                return [DesignScoreCheck("D1", ok: first == "light", detail: "the first band drawn is \(first)")]
            })
    }
}

/// A PNG's pixels in sRGB, for asserting what a capture drew where.
private struct Pixels {
    let width: Int
    let bytes: [UInt8]

    init(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw DesignScoreCaptureError.unreadable(url.path)
        }
        width = image.width
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: srgb,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw DesignScoreCaptureError.unreadable(url.path) }
        self.bytes = bytes
    }

    /// Within the score's own tolerance, 8 levels a channel, of the colour given.
    func near(x: Int, y: Int, _ red: Int, _ green: Int, _ blue: Int) -> Bool {
        let at = (y * width + x) * 4
        return zip(bytes[at..<at + 3], [red, green, blue]).allSatisfy { abs(Int($0) - $1) <= 8 }
    }
}
