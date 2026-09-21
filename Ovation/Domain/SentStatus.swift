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

    /// ovation#460. Ovation is part way through its own send: the attempt was
    /// written, and Gmail has not yet answered or the app did not survive to hear
    /// it.
    ///
    /// IT EXISTS TO MAKE ONE DEFECT IMPOSSIBLE. `InvoiceNumberAllocator.release`
    /// refuses `sent` and `couldNotDetermine`, and `notSent` is the state it is
    /// FOR. Leaving an invoice `notSent` across the Gmail call meant a timeout let
    /// its number be handed back, and the next review issued the same number to an
    /// invoice a client may already hold. This is the state that stops it.
    ///
    /// IT IS NOT `couldNotDetermine`, and the two must never be folded together.
    /// That one means the mailbox match RAN and could not answer (ovation#41,
    /// ovation#45); this means Ovation's own send is unfinished. Different
    /// findings, different remedies, and one field carrying both would make its
    /// timestamp mean two things (L11, L53, L55).
    ///
    /// WHAT RESOLVES IT is ovation#42's send: an answer from Gmail moves it to
    /// `sent`, a refusal Gmail gave moves it back to `notSent`, and no answer at
    /// all leaves it here. Dan settled on 2026-09-21 that he may clear one by hand
    /// but may never assert a send, and that clearing it does NOT release the
    /// number, because he can be wrong and keeping the number turns a wrong answer
    /// into a duplicate of the same document rather than two invoices sharing one.
    case attempting(SendAttempt)

    /// Whether this invoice is income under the accrual basis (PRD 24, 24b).
    ///
    /// Only an established send counts. The other two are counted and NAMED in
    /// the export manifest rather than silently left out, because an invoice
    /// missing from the file is missing income and a short CSV totals cleanly
    /// against itself (ovation#63).
    var wasSent: Bool {
        switch self {
        case .sent: return true
        // AN ATTEMPT IS NOT INCOME. Under the accrual basis an invoice counts when
        // it was issued, and nothing has been observed here, so counting it would
        // put money on a return on the strength of a request that may have failed.
        case .notSent, .couldNotDetermine, .attempting: return false
        }
    }

    /// When the send was established, or nil where it was not. Never the moment
    /// the match merely LOOKED, which is a different fact and lives in the case
    /// that carries it.
    var establishedAt: Date? {
        switch self {
        case .sent(_, let at): return at
        // The moment an attempt STARTED is not the moment a send was established,
        // and it lives on the attempt where it cannot be read as one.
        case .notSent, .couldNotDetermine, .attempting: return nil
        }
    }

    /// Which route established it, or nil where nothing did.
    var route: SentRoute? {
        switch self {
        case .sent(let route, _): return route
        case .notSent, .couldNotDetermine, .attempting: return nil
        }
    }

    /// The one answer no amount of re-running can settle. A draft resolves itself
    /// when it is sent; an unanswerable match stays unanswerable, so it is work
    /// for Dan rather than something to poll.
    var needsAPerson: Bool {
        switch self {
        // BOTH ARE WORK FOR DAN, for the same reason and by different routes. An
        // unanswerable match stays unanswerable; an attempt Gmail never answered
        // cannot be re-run, because re-running it is how a client gets the invoice
        // twice. Neither resolves itself, so neither is something to poll.
        case .couldNotDetermine, .attempting: return true
        case .notSent, .sent: return false
        }
    }
}

/// ovation#460. What Ovation was part way through when it wrote the attempt.
///
/// IT RECORDS WHERE THE MESSAGE ACTUALLY WENT, not merely that something went. The
/// first real send is redirected to an address Dan controls rather than to the
/// client (ovation#42), and an attempt that stored only "sent" would leave
/// ovation#41 matching that message against the client later. The destination and
/// whether it was redirected are ONE fact recorded together, never a value beside
/// a flag a reader can take without the other (L529, L544).
///
/// IT CARRIES THE RENDER'S HASH so the message that was sent can be told from the
/// invoice as it stands now. `ReviewSession` guarantees one render and hands the
/// same bytes to the page and the attachment (ovation#167); this is how a later
/// reader knows WHICH render a client received.
struct SendAttempt: Equatable, Hashable, Codable, Sendable {
    /// Every address the message was addressed to, as resolved at the moment of
    /// sending rather than as the client stands now.
    let destination: [String]
    /// Whether that destination was a redirect rather than the client's own.
    let wasRedirected: Bool
    /// SHA-256 of the rendered PDF, through the app's one hashing rule.
    let renderSHA256: String
    /// When the attempt was written, which is BEFORE Gmail was called.
    let startedAt: Date
}
