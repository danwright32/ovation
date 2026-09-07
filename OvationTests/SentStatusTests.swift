import Foundation
import Testing
@testable import Ovation

/// ovation#60. Whether an invoice was sent is something Ovation OBSERVED, never
/// something anybody asserted (PRD 5.10a), and there are three answers rather
/// than two (ovation#49).
///
/// This is the vocabulary only. What MOVES an invoice between these, and how the
/// mailbox match is measured before it is trusted, is ovation#41 and ovation#45.
struct SentStatusTests {

    private static let when = Date(timeIntervalSince1970: 1_767_000_000)

    // MARK: the three answers, which must stay three

    @Test("a draft has no observation at all, which is different from a failed one")
    func aDraftHasNoObservation() {
        #expect(!SentStatus.notSent.wasSent)
        #expect(SentStatus.notSent.establishedAt == nil)
        #expect(!SentStatus.notSent.needsAPerson)
    }

    @Test("an established send carries WHEN and by WHICH route")
    func anEstablishedSendCarriesItsRoute() {
        let sent = SentStatus.sent(route: .ovationSentIt, at: Self.when)
        #expect(sent.wasSent)
        #expect(sent.establishedAt == Self.when)
        #expect(sent.route == .ovationSentIt)
        #expect(!sent.needsAPerson)
    }

    @Test("could not determine is its OWN answer, neither sent nor a draft")
    func couldNotDetermineIsItsOwnAnswer() {
        let unknown = SentStatus.couldNotDetermine(checkedAt: Self.when)
        #expect(!unknown.wasSent, "it is not income until somebody establishes it")
        #expect(unknown.establishedAt == nil)
        #expect(unknown.needsAPerson, "this is the one a person has to settle")
        #expect(unknown != SentStatus.notSent, "collapsing the two hides the one that needs work")
    }

    // MARK: the routes, and the one that does not exist

    @Test("there are exactly two routes, and neither of them is Dan saying so")
    func thereAreOnlyTwoRoutes() {
        #expect(Set(SentRoute.allCases) == [.ovationSentIt, .foundInTheMailbox])
    }

    @Test("each route stores as a stable string and says which one established the send")
    func eachRouteIsDistinguishableAfterTheFact() {
        #expect(SentRoute.ovationSentIt.rawValue == "ovation-sent-it")
        #expect(SentRoute.foundInTheMailbox.rawValue == "found-in-the-mailbox")
    }

    // MARK: what the export selects on (PRD 24, 24b)

    @Test("only an established send is income, so the other two are counted rather than excluded")
    func onlyAnEstablishedSendIsIncome() {
        let all: [SentStatus] = [
            .notSent,
            .couldNotDetermine(checkedAt: Self.when),
            .sent(route: .ovationSentIt, at: Self.when),
            .sent(route: .foundInTheMailbox, at: Self.when),
        ]
        #expect(all.filter(\.wasSent).count == 2)
        #expect(all.filter(\.needsAPerson).count == 1)
    }
}
