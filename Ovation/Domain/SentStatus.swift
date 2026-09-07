// ovation#60, PRD 5.10a. Whether an invoice was sent, which is only ever
// something Ovation OBSERVED.
//
// THERE IS NO WAY TO SAY IT WAS SENT. Dan cannot mark an invoice sent by hand,
// so this vocabulary offers no case and no route meaning that he said so. A flag
// written only by actions inside the product is permanently wrong for work done
// in the mail client instead (L162), which is why the second route exists at all,
// and the same defect already shipped in Overture as `replyHandledAt`.
//
// THERE ARE THREE ANSWERS, NOT TWO, and the third is the point of this type.
// "Sent", "not sent yet" and "the match ran and could not tell" are different
// situations needing different work, and collapsing the third into either of the
// others hides the only one that needs a person (ovation#49, L11). It is not a
// draft, because somebody may well have sent it; it is not sent, because under
// the accrual basis that would put money on a tax return on a guess.
//
// DELIBERATELY NOT HERE: what MOVES an invoice between these. Ovation's own send
// is ovation#42, the derived mailbox match and the measurement of its false
// negative rate before anything is built on it are ovation#41 and ovation#45.
import Foundation

/// The two ways a send can be established. Both are observations.
enum SentRoute: String, CaseIterable, Codable, Hashable, Sendable {
    /// Ovation built the message and sent it.
    case ovationSentIt = "ovation-sent-it"
    /// Ovation found a message carrying this invoice number in the Sent folder,
    /// which is how an invoice sent from Spark stops claiming to be a draft.
    case foundInTheMailbox = "found-in-the-mailbox"
}

enum SentStatus: Equatable, Hashable, Codable, Sendable {
    /// Nothing has been observed. An ordinary draft.
    case notSent

    /// A send was established, by which route and when. The route is recorded
    /// because the two carry different confidence and ovation#45 has to be able
    /// to report on the derived one separately.
    case sent(route: SentRoute, at: Date)

    /// The match ran and could not answer. Carries when it looked, so a stale
    /// verdict is distinguishable from a fresh one.
    case couldNotDetermine(checkedAt: Date)

    /// Whether this invoice is income under the accrual basis (PRD 24, 24b).
    ///
    /// Only an established send counts. The other two are counted and NAMED in
    /// the export manifest rather than silently left out, because an invoice
    /// missing from the file is missing income and a short CSV totals cleanly
    /// against itself (ovation#63).
    var wasSent: Bool {
        switch self {
        case .sent: return true
        case .notSent, .couldNotDetermine: return false
        }
    }

    /// When the send was established, or nil where it was not. Never the moment
    /// the match merely LOOKED, which is a different fact and lives in the case
    /// that carries it.
    var establishedAt: Date? {
        switch self {
        case .sent(_, let at): return at
        case .notSent, .couldNotDetermine: return nil
        }
    }

    /// Which route established it, or nil where nothing did.
    var route: SentRoute? {
        switch self {
        case .sent(let route, _): return route
        case .notSent, .couldNotDetermine: return nil
        }
    }

    /// The one answer no amount of re-running can settle. A draft resolves itself
    /// when it is sent; an unanswerable match stays unanswerable, so it is work
    /// for Dan rather than something to poll.
    var needsAPerson: Bool {
        switch self {
        case .couldNotDetermine: return true
        case .notSent, .sent: return false
        }
    }
}
