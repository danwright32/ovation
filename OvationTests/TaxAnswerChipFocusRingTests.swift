import CoreGraphics
import Testing
@testable import Ovation

/// ovation#480. The one tax status chip's focus ring must sit where the design
/// record's `.taxpick:focus-visible` puts it: `outline: 2px; outline-offset: 1px`,
/// so a 2 point ring from 1 to 3 points outside the chip. A stroke straddles its
/// path, which is how the first version drew it 2 to 4 points out while its
/// comment said 1 (found in review of #587).
struct TaxAnswerChipFocusRingTests {

    @Test("the focus ring runs from 1 to 3 points outside the chip, as the record's outline does")
    func theRingSitsWhereTheRecordPutsIt() {
        let inner = TaxAnswerChips.focusRingPathOutset - TaxAnswerChips.focusRingWidth / 2
        let outer = TaxAnswerChips.focusRingPathOutset + TaxAnswerChips.focusRingWidth / 2

        #expect(inner == 1, "the ring starts \(inner) points out; the record's offset is 1")
        #expect(outer == 3, "the ring ends \(outer) points out; offset 1 plus width 2 is 3")
    }
}
