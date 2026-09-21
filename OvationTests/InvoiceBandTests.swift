import Foundation
import Testing

/// ovation#49, PRD section 6. Every state lands in exactly one band.
///
/// THE PROPERTY TEST IS THE POINT, and the example tests below it are not a
/// substitute for it. Examples confirm the states somebody thought of; the sweep
/// is what catches the one nobody did, which is by definition the state whose
/// records become unreachable. The list is the only way to reach an invoice, so a
/// state in no band is not awkward, it is invisible (L45).
///
/// IT ASSERTS BOTH DIRECTIONS. A record claimed by two bands is drawn twice and
/// makes every count over the list disagree with the list; a record claimed by
/// none is gone. Only one of those is visible by looking.
///
/// NOTHING HERE READS A CLOCK OR A STORE. Every day is a number relative to
/// `InvoiceBand.today`, so no case can walk into another state while the suite
/// runs, and the whole sweep is arithmetic over a value type (L130, L290).
struct InvoiceBandTests {

    // MARK: the state space

    /// A day that has been and gone, today, and one still ahead. Written relative
    /// to the band's own reference day rather than to a date, because the thing
    /// under test is an ordering and not a calendar.
    private static let past = InvoiceBand.today - 5
    private static let future = InvoiceBand.today + 5

    private static let endings: [InvoiceStanding.Ending?] = [nil, .cancelled, .deleted]

    /// All three answers of ovation#45's triple. The instants are fixed and
    /// arbitrary: nothing here reads them, and a `Date()` would make two runs of
    /// this suite compare different values.
    private static let sentStates: [SentStatus] = [
        .notSent,
        .sent(route: .ovationSentIt, at: Date(timeIntervalSince1970: 1_700_000_000)),
        .couldNotDetermine(checkedAt: Date(timeIntervalSince1970: 1_700_000_000)),
    ]

    /// Including nil, which is the invoice created from scratch with no booking
    /// behind it. That is the member this sweep exists to find a home for.
    private static let shootDays: [Int?] = [nil, past, InvoiceBand.today, future]

    private static let dueDays: [Int?] = [nil, past, future]

    /// Every combination of the six facts a band is allowed to read.
    private static var everyStanding: [InvoiceStanding] {
        var all: [InvoiceStanding] = []
        for ending in endings {
            for sent in sentStates {
                for shootDay in shootDays {
                    for dueDay in dueDays {
                        for money in InvoiceStanding.Money.allCases {
                            for couldSettle in [false, true] {
                                // THE UNREADABLE DATE IS A DIMENSION OF THE SWEEP,
                                // not a case beside it (L50). It changes which band
                                // claims an invoice, so the partition has to hold
                                // across it in both directions exactly as it does
                                // across every other fact.
                                for unreadable in [false, true] {
                                    all.append(InvoiceStanding(
                                        ending: ending, sent: sent, shootDay: shootDay,
                                        dueDay: dueDay, money: money,
                                        couldSettleMoreThanOne: couldSettle,
                                        datesCouldNotBeRead: unreadable))
                                }
                            }
                        }
                    }
                }
            }
        }
        return all
    }

    /// What a failure prints. It names the state rather than its index, because an
    /// index sends whoever reads the red back here to count rows (L11).
    private static func describe(_ it: InvoiceStanding) -> String {
        let ending = it.ending.map { "\($0)" } ?? "open"
        let sent: String
        switch it.sent {
        case .notSent: sent = "not sent"
        case .sent: sent = "sent"
        case .couldNotDetermine: sent = "could not determine"
        }
        let shoot = it.shootDay.map { day in
            day == InvoiceBand.today ? "shoot today"
                : (day < InvoiceBand.today ? "shoot passed" : "shoot ahead")
        } ?? "NO SHOOT DATE"
        let due = it.dueDay.map { day in
            day < InvoiceBand.today ? "overdue" : "due ahead"
        } ?? "no due date"
        let place = it.couldSettleMoreThanOne ? ", could settle more than one" : ""
        let unread = it.datesCouldNotBeRead ? ", DATES WOULD NOT READ" : ""
        return "\(ending), \(sent), \(shoot), \(due), \(it.money)\(place)\(unread)"
    }

    // MARK: the property

    @Test("every state a drawn invoice can be in is claimed by exactly one band")
    func everyDrawnStateLandsInExactlyOneBand() {
        var claimedByNothing: [String] = []
        var claimedBySeveral: [String] = []

        for standing in Self.everyStanding where standing.isDrawn {
            let claiming = InvoiceBand.allCases.filter { $0.claims(standing) }
            if claiming.isEmpty {
                claimedByNothing.append(Self.describe(standing))
            } else if claiming.count > 1 {
                let names = claiming.map(\.rawValue).joined(separator: " and ")
                claimedBySeveral.append("\(Self.describe(standing)) -> \(names)")
            }
        }

        // REPORTED SEPARATELY, because they are different faults with different
        // consequences: a record in two bands is drawn twice and every count over
        // the list disagrees with it, a record in none is unreachable (L53).
        #expect(claimedByNothing.isEmpty, """
            \(claimedByNothing.count) invoice states are in NO band, so an invoice \
            in any of them cannot be reached from the only screen that reaches \
            invoices:
            \(claimedByNothing.joined(separator: "\n"))
            """)
        #expect(claimedBySeveral.isEmpty, """
            \(claimedBySeveral.count) invoice states are claimed by more than one \
            band, so the invoice is drawn twice and the card's counts cannot agree \
            with the list:
            \(claimedBySeveral.joined(separator: "\n"))
            """)
    }

    @Test("a deleted invoice is claimed by no band at all, and that is the only way out of the list")
    func aDeletedInvoiceIsInNoBand() {
        // The other half of the property above. Every deleted state must be
        // claimed by nothing, and it is the ONLY state allowed to be.
        for standing in Self.everyStanding where !standing.isDrawn {
            let claiming = InvoiceBand.allCases.filter { $0.claims(standing) }
            let bands = claiming.map(\.rawValue).joined(separator: " and ")
            #expect(claiming.isEmpty,
                    "a deleted invoice is still drawn: \(Self.describe(standing)) -> \(bands)")
        }
        // And nothing but a deletion leaves the list, which is what keeps "absent"
        // to one cause (L622).
        let drawn = Self.everyStanding.filter(\.isDrawn)
        #expect(drawn.allSatisfy { it in it.ending != .deleted })
    }

    @Test("every band is reachable, so none of them is a band nothing can ever be in")
    func everyBandIsReachable() {
        // A band no state can reach is dead code that reads as coverage (L29). It
        // is also how a partition passes while a band is spelled wrong.
        let reached = Set(Self.everyStanding.filter(\.isDrawn).compactMap { standing in
            InvoiceBand.allCases.first { $0.claims(standing) }
        })
        let unreachable = InvoiceBand.allCases.filter { !reached.contains($0) }
        #expect(unreachable.isEmpty,
                "no state reaches: \(unreachable.map(\.rawValue).joined(separator: ", "))")
    }

    // MARK: the states named in the requirement

    @Test("a draft with no shoot date is the one PRD section 6 places with should have been sent")
    func aDatelessDraftNeedsSending() {
        let draft = InvoiceStanding(sent: .notSent, shootDay: nil)
        #expect(InvoiceBand.allCases.filter { $0.claims(draft) } == [.draftNeedsSending])
    }

    @Test("could not determine whether it was sent is its own band, never folded into either neighbour")
    func theThirdAnswerKeepsItsOwnBand() {
        let unknown = InvoiceStanding(
            sent: .couldNotDetermine(checkedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            shootDay: Self.past, dueDay: Self.past)
        #expect(InvoiceBand.allCases.filter { $0.claims(unknown) } == [.sayWhetherItWasSent])
    }

    @Test("a part paid invoice past its terms is chased rather than given a band of its own")
    func partPaidIsNotABand() {
        let partPaid = InvoiceStanding(
            sent: .sent(route: .ovationSentIt, at: Date(timeIntervalSince1970: 1_700_000_000)),
            shootDay: Self.past, dueDay: Self.past, money: .some)
        #expect(InvoiceBand.allCases.filter { $0.claims(partPaid) } == [.overdue])
    }

    @Test("an overdue invoice carrying an uncleared check is confirmed, not chased")
    func anUnclearedCheckOutranksBeingOverdue() {
        // The pair PRD section 6 names as satisfying two groups at once. It is
        // fully covered, so nothing is owed and nothing is chased: what is left is
        // confirming the check cleared.
        let check = InvoiceStanding(
            sent: .sent(route: .ovationSentIt, at: Date(timeIntervalSince1970: 1_700_000_000)),
            shootDay: Self.past, dueDay: Self.past, money: .allOfItAwaitingAClearedCheck)
        #expect(InvoiceBand.allCases.filter { $0.claims(check) } == [.checkNotCleared])
    }

    @Test("the band that cuts across takes its row out of the band it would otherwise be in")
    func toPlaceMovesRatherThanCopies() {
        // PRD 46d. Overdue in every other respect, and drawn once, at the top.
        let waiting = InvoiceStanding(
            sent: .sent(route: .ovationSentIt, at: Date(timeIntervalSince1970: 1_700_000_000)),
            shootDay: Self.past, dueDay: Self.past, money: .nothing,
            couldSettleMoreThanOne: true)
        #expect(InvoiceBand.allCases.filter { $0.claims(waiting) } == [.toPlace])
    }

    @Test("the bands are in the order the list draws them")
    func theOrderIsTheScreensOrder() {
        // PRD 46: the bands are not drawn, but they decide the order, so the order
        // is read from this list rather than restated by the screen (L41).
        #expect(InvoiceBand.allCases == [
            .toPlace, .draftShootToday, .overdue, .draftNeedsSending, .checkNotCleared,
            .sayWhetherItWasSent, .sentAwaitingPayment, .draftShootAhead,
            .paidOrCleared, .cancelled,
        ])
    }
}
