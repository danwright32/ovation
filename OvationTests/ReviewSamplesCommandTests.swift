import Foundation
import Testing

/// ovation#318 B5. What the Debug menu does, which is the only way the review sheet
/// can be opened at all until ovation#42.
///
/// A MENU THAT DOES NOTHING IS A BROKEN MENU (L109). Two of the samples are states
/// where Review is refused, and the sheet deliberately never opens over them, so
/// the press has to SAY the refusal rather than appear to do nothing.
@MainActor
struct ReviewSamplesCommandTests {

    @Test("pressing an ordinary sample puts it on screen")
    func anordinarySampleShows() {
        let command = ReviewSamplesCommand()

        command.press(.ordinary)

        #expect(command.showing == .ordinary)
        #expect(command.refused == nil)
    }

    @Test("pressing a refused sample opens nothing and says why")
    func arefusedSampleSaysWhy() {
        let command = ReviewSamplesCommand()

        command.press(.waitingOnTaxStatus)

        #expect(command.showing == nil, "the sheet never opens over an invoice that cannot go out")
        #expect(command.refused == "Waiting on this client's tax status.")
    }

    @Test("and the sentence is the gate's own, not a second wording of it")
    func therefusalIsTheGatesWording() {
        // Two vocabularies for one decision drift (L118), so the sample reads the
        // sentence from ReviewGate rather than carrying its own copy.
        let command = ReviewSamplesCommand()

        command.press(.discountTooLarge)

        #expect(command.refused == ReviewGate.sentence(for: .discountExceedsSubtotal))
    }

    @Test("pressing an ordinary sample after a refused one clears the refusal")
    func pressingOnClearsWhatCameBefore() {
        // A surface driven by one flag cannot notice WHICH thing changed, so a
        // refusal left standing would sit over the next sample (L243).
        let command = ReviewSamplesCommand()
        command.press(.waitingOnTaxStatus)

        command.press(.pastDue)

        #expect(command.showing == .pastDue)
        #expect(command.refused == nil)
    }

    @Test("closing puts both away")
    func closingClearsBoth() {
        let command = ReviewSamplesCommand()
        command.press(.ordinary)

        command.close()

        #expect(command.showing == nil)
        #expect(command.refused == nil)
    }

    @Test("every sample in the menu can actually be built, and says something of its own")
    func everySampleIsReachable() throws {
        // A sample added to the menu and not to the world would put an empty sheet
        // on screen, and a state nobody can reach is a state nobody reviews (L546,
        // L113). This is what makes the next one fail here rather than on screen.
        var seen: Set<String> = []
        for sample in ReviewSample.allCases {
            #expect(seen.insert(sample.says).inserted, "two samples say '\(sample.says)'")
            let presenter = try ReviewSampleWorld.presenter(for: sample)
            #expect(presenter.subtitle.isEmpty == false)
        }
    }
}
