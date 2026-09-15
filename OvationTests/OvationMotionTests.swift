import Foundation
import SwiftUI
import Testing

/// ovation#124. HOW MOTION WORKS, HELD TO THE FILE THAT DRAWS IT.
///
/// `OvationMotion` carries two durations and one curve, and every one of them is
/// quoted from `docs/design/invoice.html` rather than chosen in Swift. A test
/// asserting agreement with a designed artifact has to READ that artifact, or it
/// asserts agreement with whatever the person writing it believed the design said
/// (L638). So these cases open the design file, parse the two `transition`
/// declarations out of it, and hold the component to what they find.
///
/// THE REDUCE MOTION CASE IS THE ONE THAT MATTERS. The person who asked their Mac
/// to reduce motion is not the person building the screen, so the failure is
/// silent for everybody who could report it (ovation#124). The component answers
/// with NO ANIMATION rather than a shorter one, which is what the design file's
/// own `prefers-reduced-motion: reduce` rules do.
struct OvationMotionTests {

    // MARK: what the component answers

    /// Enumerated from `Kind.allCases` rather than listed here, so a transition
    /// added to the component is covered by this case without anybody
    /// remembering to extend it (L96, L217).
    @Test("reduce motion turns every transition off, not merely shortens one")
    func reduceMotionTurnsEveryTransitionOff() {
        for kind in OvationMotion.Kind.allCases {
            #expect(OvationMotion.animation(kind, reduceMotion: true) == nil,
                    "\(kind) still animates when motion is reduced")
        }
    }

    @Test("with motion on, every transition has an animation and no two are the same")
    func everyKindAnimatesWhenMotionIsOn() {
        var seen: [Animation] = []
        for kind in OvationMotion.Kind.allCases {
            let animation = try? #require(OvationMotion.animation(kind, reduceMotion: false))
            guard let animation else { continue }
            #expect(!seen.contains(animation),
                    "\(kind) draws the same animation as another kind, so one is standing in for the other")
            seen.append(animation)
        }
        #expect(seen.count == OvationMotion.Kind.allCases.count)
    }

    // MARK: held to the design file

    @Test("the slide is the duration and the curve the design file draws")
    func theSlideIsWhatTheDesignFileDraws() throws {
        let declaration = try Self.onlyMatch(
            #"transition:\s*width\s+(\d+)ms\s+cubic-bezier\(([^)]*)\)"#,
            in: try Self.invoiceDesignFile())

        #expect(OvationMotion.milliseconds(.slide) == Int(declaration[0]))

        let points = declaration[1].split(separator: ",").map {
            Self.number(String($0).trimmingCharacters(in: .whitespaces))
        }
        #expect(points.count == 4)
        #expect(points == [OvationMotion.slideCurve.x1, OvationMotion.slideCurve.y1,
                           OvationMotion.slideCurve.x2, OvationMotion.slideCurve.y2])
    }

    @Test("the fade is the duration the design file draws, and it is linear")
    func theFadeIsWhatTheDesignFileDraws() throws {
        let declaration = try Self.onlyMatch(
            #"transition:\s*opacity\s+(\d+)ms\s+([a-z-]+)"#,
            in: try Self.invoiceDesignFile())

        #expect(OvationMotion.milliseconds(.fade) == Int(declaration[0]))
        #expect(declaration[1] == "linear")
    }

    /// The component and the design file must agree about WHICH transitions stand
    /// down, not only about how long they run. A design file that stopped turning
    /// one off would leave the app honouring a rule its own record had dropped.
    @Test("the design file turns both of its transitions off for reduce motion")
    func theDesignFileHonoursReduceMotion() throws {
        let page = try Self.invoiceDesignFile()
        let rules = Self.matches(
            #"@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{\s*\.(\w+)\s*\{\s*transition:\s*none"#,
            in: page)

        #expect(rules.count == OvationMotion.Kind.allCases.count,
                "the design file turns off \(rules.count) transitions and the component carries \(OvationMotion.Kind.allCases.count)")
    }

    // MARK: reading the design

    /// Located from THIS file, never from the working directory, the same way
    /// `InvoiceFixtures` reaches the design's own expected text (L372).
    private static func invoiceDesignFile(_ file: StaticString = #filePath) throws -> String {
        let repository = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repository.appending(path: "docs/design/invoice.html"),
                          encoding: .utf8)
    }

    /// Every capture group of every match, in order.
    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: whole).map { found in
            (1..<found.numberOfRanges).compactMap { index in
                Range(found.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }

    /// A declaration the design file carries EXACTLY ONCE. Several matches is a
    /// refusal of its own rather than a silent choice of the first (L521): two
    /// slide declarations in one file is the drift this suite exists to see.
    private static func onlyMatch(_ pattern: String, in text: String) throws -> [String] {
        let found = matches(pattern, in: text)
        return try #require(found.count == 1 ? found.first : nil,
                            "the design file carries \(found.count) declarations matching \(pattern), not one")
    }

    /// CSS writes `.32` where Swift wants `0.32`, so the leading zero is put back
    /// rather than the parse being trusted to accept either.
    private static func number(_ written: String) -> Double {
        Double(written.hasPrefix(".") ? "0" + written : written) ?? .nan
    }
}
