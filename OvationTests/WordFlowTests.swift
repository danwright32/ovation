import CoreGraphics
import Testing

/// Review of ovation#616. The shared address notice's sentence wraps the way text
/// does, because its names are controls a Text cannot carry. `WordFlow.arrange` is
/// where the wrapping is decided, so it is tested here as values; the notice drawn
/// at the 860 point window is `ClientsViewTests`.
struct WordFlowTests {

    private static func arrange(_ widths: [CGFloat], joins: [Bool] = [], width: CGFloat?)
        -> (origins: [CGPoint], size: CGSize) {
        WordFlow.arrange(widths.map { CGSize(width: $0, height: 16) },
                         joins: joins.isEmpty ? widths.map { _ in false } : joins,
                         width: width, wordSpacing: 4, lineSpacing: 2)
    }

    @Test("words that fit stay on one line, a space apart")
    func wordsThatFitStayOnOneLine() {
        let laid = Self.arrange([40, 30, 20], width: 200)

        #expect(laid.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 44, y: 0), CGPoint(x: 78, y: 0)])
        #expect(laid.size == CGSize(width: 98, height: 16))
    }

    @Test("a word that would not fit starts the next line, at the left")
    func aWordThatWouldNotFitWraps() {
        let laid = Self.arrange([60, 60, 60], width: 130)

        #expect(laid.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 64, y: 0), CGPoint(x: 0, y: 18)])
        #expect(laid.size.height == 34)
    }

    /// A comma after a name belongs to it: no space before it, and a line never
    /// starts with one, even where it runs a little past the edge.
    @Test("a word that joins the one before has no space and never starts a line")
    func aJoinedWordNeverStartsALine() {
        let laid = Self.arrange([60, 4, 60], joins: [false, true, false], width: 62)

        #expect(laid.origins[1] == CGPoint(x: 60, y: 0))
        #expect(laid.origins[2] == CGPoint(x: 0, y: 18))
    }

    /// NOTHING IS SHRUNK OR DROPPED. A word wider than the whole width is a client's
    /// name, and a cut name is the one thing the notice exists to say.
    @Test("a word wider than the width sits alone on its line rather than being lost")
    func aWordWiderThanTheWidthSitsAlone() {
        let laid = Self.arrange([30, 300, 30], width: 100)

        #expect(laid.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 18), CGPoint(x: 0, y: 36)])
        #expect(laid.size.width == 300)
    }

    /// ovation#665. A line starts at a word's INDEX on it, not at an x of zero, so
    /// a first word that draws nothing still has its space after it.
    @Test("a word after a zero width first word keeps its space")
    func aWordAfterAZeroWidthWordKeepsItsSpace() {
        let laid = Self.arrange([0, 30], width: 200)

        #expect(laid.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0)])
    }

    @Test("with no width to fit, everything is one line")
    func withNoWidthItIsOneLine() {
        let laid = Self.arrange([60, 60, 60], width: nil)

        #expect(laid.origins.map(\.y) == [0, 0, 0])
    }
}
