import Foundation
import Testing
import BackstageGoogle

/// ovation#424. The shared Google package is linked, and the one predicate
/// Ovation's design rests on behaves as that design assumes.
///
/// WHY A TEST RATHER THAN AN IMPORT SOMEWHERE. A dependency declared in
/// `project.yml` and imported by nothing is a dependency nothing exercises: it
/// resolves, it links, and the first thing to actually use it is where a
/// mismatch would surface. This file is the proof that it REACHES the build,
/// and it was seen to fail: with the `packages:` entry removed, the build dies
/// with `Unable to resolve module dependency: 'BackstageGoogle'` before any
/// test runs (L1).
///
/// WHAT IT IS NOT. It does not re-test backstage, which has its own suite over
/// this code. It asserts the contract OVATION depends on, in Ovation, because a
/// shared definition is only shared while both sides agree about what it means,
/// and two same-named things either side of a boundary can implement different
/// rules forever (L263). ovation#45 treats sent as something only ever observed,
/// and ovation#41's probe is designed around exactly this predicate, so if the
/// package's meaning of "sent" ever moves, this is where Ovation finds out.
///
/// THE SCOPES REFUSAL IS ovation#426 and is deliberately not here.
struct BackstagePackageTests {

    /// Gmail returns unsent drafts in the same collections as real mail, and every
    /// other attribute a match could use, the invoice number, an attachment, a
    /// recipient, is carried identically by a draft abandoned in Spark. Since
    /// Sent cannot be retracted by hand, accepting one would stamp an invoice sent
    /// permanently (L181).
    @Test("a sent message is sent, and an abandoned draft in the same folder is not")
    func adraftIsNeverSent() {
        #expect(GmailSentStatus.wasSentByUser(["labelIds": ["SENT"]]))
        #expect(GmailSentStatus.wasSentByUser(["labelIds": ["INBOX", "sent"]]),
                "Gmail's own constants, matched however they are cased")
        #expect(!GmailSentStatus.wasSentByUser(["labelIds": ["SENT", "DRAFT"]]),
                "carries SENT and is still being composed, which is the whole trap")
        #expect(!GmailSentStatus.wasSentByUser(["labelIds": ["DRAFT"]]))
    }

    /// PRD 5.10a and ovation#45: "we do not know" must never become "it went". A
    /// response that carries no `labelIds` at all is Gmail not having been asked,
    /// or a shape nobody has seen, and both are refusals rather than permission
    /// (L506, L215, L42).
    @Test("a message with NO label information is refused, never accepted")
    func missingLabelsFailClosed() {
        #expect(!GmailSentStatus.wasSentByUser([:]))
        #expect(!GmailSentStatus.wasSentByUser(["id": "abc"]))
        #expect(GmailSentStatus.labelIds(of: [:]) == nil,
                "absent, which is a different answer from an empty list")
        #expect(GmailSentStatus.labelIds(of: ["labelIds": []]) == [],
                "and Gmail saying it has no labels is NOT the same as not being asked")
    }
}
