// A sentence whose words are views, laid out the way text wraps. ovation#616.
//
// WHY NOT ONE TEXT. The shared address notice names each other client, and each
// name is a control that opens that client (L80), so a name has to be a real
// button a keyboard can reach. A Text carries no buttons, and a row of views in a
// stack never wraps: three long names at the 860 point window truncated or pushed
// "That is correct" out of the notice (review of ovation#616, L606). So each word
// is its own view, placed left to right and moved to the next line when the next
// one would not fit.
//
// A WORD MARKED `joinsPrevious` IS NEVER THE FIRST ON A LINE and has no space
// before it, which is what a comma after a name is: a line starting with a comma
// reads as a fault.
//
// NOTHING IS SHRUNK. Every word is placed at its own ideal size, so no name is
// ever cut short; a single word wider than the whole width sits on a line of its
// own rather than being truncated, because a cut client's name is the one thing
// this notice exists to say.
import SwiftUI

struct WordFlow: Layout {
    /// The space between two words, and between two lines.
    var wordSpacing: CGFloat
    var lineSpacing: CGFloat = 2

    /// Marks a word that belongs to the one before it.
    struct JoinsPrevious: LayoutValueKey {
        static let defaultValue = false
    }

    /// Where each word goes, for words of `sizes` in a width of `width`, with no
    /// space before those marked in `joins`. Nil width is one line.
    ///
    /// PURE, so the wrapping is testable without drawing anything.
    static func arrange(_ sizes: [CGSize], joins: [Bool], width: CGFloat?,
                        wordSpacing: CGFloat, lineSpacing: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var lineTop: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let joined = index < joins.count && joins[index] && index > 0
            let gap = x == 0 || joined ? 0 : wordSpacing
            if let width, x > 0, !joined, x + gap + size.width > width {
                lineTop += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            let lead = x == 0 ? 0 : (joined ? 0 : wordSpacing)
            origins.append(CGPoint(x: x + lead, y: lineTop))
            x += lead + size.width
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x)
        }
        return (origins, CGSize(width: widest, height: sizes.isEmpty ? 0 : lineTop + lineHeight))
    }

    private func measured(_ subviews: Subviews) -> ([CGSize], [Bool]) {
        (subviews.map { $0.sizeThatFits(.unspecified) }, subviews.map { $0[JoinsPrevious.self] })
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (sizes, joins) = measured(subviews)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let laid = Self.arrange(sizes, joins: joins, width: width,
                                wordSpacing: wordSpacing, lineSpacing: lineSpacing)
        return CGSize(width: width.map { max($0, 0) } ?? laid.size.width, height: laid.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        let (sizes, joins) = measured(subviews)
        let laid = Self.arrange(sizes, joins: joins, width: bounds.width,
                                wordSpacing: wordSpacing, lineSpacing: lineSpacing)
        for (index, subview) in subviews.enumerated() {
            let origin = laid.origins[index]
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(sizes[index]))
        }
    }
}

extension View {
    /// This word belongs to the one before it in a `WordFlow`.
    func joinsPreviousWord(_ joins: Bool = true) -> some View {
        layoutValue(key: WordFlow.JoinsPrevious.self, value: joins)
    }
}
