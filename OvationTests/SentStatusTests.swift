import Foundation
import Testing

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

    // MARK: a send that is in flight (ovation#460)

    /// ovation#460. THE STATE THAT MAKES THE REISSUE IMPOSSIBLE. While Ovation is
    /// handing a message to Gmail the invoice is neither sent nor a draft, and
    /// leaving it `notSent` across that call is what let a timeout release its
    /// number: `InvoiceNumberAllocator.release` refuses `sent` and
    /// `couldNotDetermine` and `notSent` is the one state it is FOR, so closing the
    /// sheet after a timeout handed back a number Gmail may already have delivered,
    /// and the next review issued it again. One number, two invoices, in a client's
    /// records and the accountant's.
    @Test("an attempt in flight is neither sent nor a draft")
    func anattemptIsItsOwnAnswer() {
        let attempt = SendAttempt(destination: ["client@example.com"], wasRedirected: false,
                                  renderSHA256: "abc", startedAt: Date(timeIntervalSince1970: 1))
        let status = SentStatus.attempting(attempt)

        #expect(status.wasSent == false, "nothing has been observed, so it is not income")
        #expect(status != .notSent)
        #expect(status.needsAPerson, "it cannot resolve itself, so somebody has to look")
    }

    /// IT IS NOT `couldNotDetermine`, and the two must stay apart. That one means
    /// the mailbox match RAN and could not answer, which is ovation#41 and
    /// ovation#45; this means Ovation was part way through its own send. Different
    /// findings with different remedies, and folding them together would make one
    /// field carry two and its timestamp mean two things (L11, L53, L55).
    @Test("an attempt is not the mailbox match failing to answer")
    func anattemptIsNotTheMatchFailing() {
        let attempt = SendAttempt(destination: ["a@example.com"], wasRedirected: false,
                                  renderSHA256: "abc", startedAt: Date(timeIntervalSince1970: 1))

        #expect(SentStatus.attempting(attempt)
                    != SentStatus.couldNotDetermine(checkedAt: Date(timeIntervalSince1970: 1)))
    }

    /// THE ATTEMPT RECORDS WHERE IT ACTUALLY WENT, not merely that it went. A first
    /// send redirected to Dan's own address would otherwise be stored as an
    /// ordinary send, and ovation#41 would later match it against the client
    /// (L529, L544).
    @Test("the attempt carries the destination actually used, and whether it was redirected")
    func theattemptCarriesWhereItWent() {
        let attempt = SendAttempt(destination: ["dan@example.com"], wasRedirected: true,
                                  renderSHA256: "abc", startedAt: Date(timeIntervalSince1970: 1))

        #expect(attempt.destination == ["dan@example.com"])
        #expect(attempt.wasRedirected)
    }

    // MARK: what adding a case did NOT change

    /// THE MEASUREMENT THAT DECIDES WHETHER THIS NEEDED A SCHEMA VERSION, taken
    /// rather than reasoned (L82). `sentStatus` is a plain stored property of this
    /// type, declared identically in every frozen shape, so adding a CASE changes
    /// no attribute SwiftData can see. What it could change is the stored
    /// ENCODING, and these are the three encodings already on disk in Dan's store.
    ///
    /// EACH IS A LITERAL CAPTURED BEFORE THE CASE WAS ADDED, not a round trip
    /// through the encoder, because a round trip agrees with whatever the encoder
    /// does today and would go on agreeing after a change that broke every stored
    /// row (L84, L638).
    @Test("every encoding already on disk still decodes, so no version was needed",
          arguments: [
            (#"{"notSent":{}}"#, SentStatus.notSent),
            (#"{"sent":{"route":"ovation-sent-it","at":790000000}}"#,
             SentStatus.sent(route: .ovationSentIt,
                             at: Date(timeIntervalSinceReferenceDate: 790_000_000))),
            (#"{"couldNotDetermine":{"checkedAt":790000000}}"#,
             SentStatus.couldNotDetermine(
                checkedAt: Date(timeIntervalSinceReferenceDate: 790_000_000))),
          ])
    func everyStoredEncodingStillDecodes(json: String, expected: SentStatus) throws {
        let decoded = try JSONDecoder().decode(SentStatus.self, from: Data(json.utf8))

        #expect(decoded == expected)
    }

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
