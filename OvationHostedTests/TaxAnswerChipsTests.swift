import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#480, PRD 5a2. The one chip that answers the tax status question,
/// wherever it is asked. Hosted for the reason `RosterPassViewTests` give: what
/// these assert lives in the binding, so they render the real view.
@MainActor
struct TaxAnswerChipsTests {

    /// A CONTROL WIRED TO THE WRONG VALUE is the defect no rendering can show:
    /// both answers draw alike and only the press tells them apart (L442).
    @Test("pressing a chip hands back the answer it names", arguments: TaxStatus.answers)
    func pressingHandsBackItsAnswer(_ answer: TaxStatus) throws {
        var given: [TaxStatus] = []
        let chips = TaxAnswerChips(answers: TaxStatus.answers) { given.append($0) }

        try chips.inspect().find(ViewType.Button.self, where: { button in
            (try? button.labelView().text().string()) == answer.exportLabel
        }).tap()

        #expect(given == [answer])
    }

    /// Every answer it is given is offered, and nothing else: the list is the
    /// caller's, from `TaxStatus.answers`, never two strings written here (L611).
    @Test("it offers exactly the answers it is given, in their order")
    func itOffersExactlyItsAnswers() throws {
        let chips = TaxAnswerChips(answers: TaxStatus.answers) { _ in }
        let offered = try chips.inspect().findAll(ViewType.Button.self)
            .compactMap { try? $0.labelView().text().string() }

        #expect(offered == TaxStatus.answers.map(\.exportLabel))
    }

    /// THE ROSTER PASS ASKS WITH IT. Its own chip, the design record's `.chip`,
    /// is the one this decision retired, so a pass still drawing its answers any
    /// other way is the second treatment ovation#480 exists to remove.
    @Test("the roster pass draws its answers with the one chip")
    func theRosterPassUsesIt() throws {
        let client = Client(name: "Client 0", taxStatus: .neverRecorded)
        client.email = "c0@example.example"
        let view = RosterPassView(presenter: RosterPresenter(clients: [client], write: { _, _ in }))

        #expect(try view.inspect().findAll(TaxAnswerChips.self).count == 1)
    }
}
