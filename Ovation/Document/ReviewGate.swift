import Foundation

/// Whether Review can be pressed, and the one sentence it says when it cannot
/// (ovation#318 B4, PRD 51b and 52g).
///
/// THE SHEET NEVER OPENS OVER AN INVOICE THAT CANNOT GO OUT. Review is the moment
/// right before sending, so opening it over a refused invoice would offer an
/// approval that cannot be given, and a greyed control with no reason beside it is
/// a dead control (L109).
///
/// ONE SENTENCE, AND THE ORDER IS THE DECISION. A half filled draft carries several
/// refusals at once and a control can say one, so which one is written down here
/// rather than left to whichever the set happens to yield first (L170, L343).
///
/// THE WORDS ARE THE ONES THE INVOICE SCREEN ALREADY USES,
/// `docs/design/rules/waiting.js`, so one condition cannot be worded two ways on
/// two surfaces (L118).
enum ReviewGate {

    /// Why this invoice cannot be reviewed, or nil when it can.
    @MainActor
    static func refusal(for invoice: Invoice) -> String? {
        let refusals = invoice.refusals
        // ASKED IN A WRITTEN ORDER, not over a Set, whose order is not a fact about
        // anything (L343). The tax status comes first because answering it is a
        // fact about the client that outlives this invoice, while an oversized
        // discount is a number on this one.
        for refusal in order where refusals.contains(refusal) {
            return sentence(for: refusal)
        }
        return nil
    }

    /// Every refusal, in the order a control says them.
    ///
    /// DERIVED FROM THE VOCABULARY, never a second list: a refusal added to
    /// `InvoiceRefusal` and not placed here is caught by the suite rather than
    /// silently ranked last (L41, L96).
    static let order: [InvoiceRefusal] = [.taxStatusNeverRecorded, .discountExceedsSubtotal]

    /// The one sentence for each refusal. Total over the vocabulary, so a new member
    /// cannot take a default and read as a deliberate silence (L113).
    static func sentence(for refusal: InvoiceRefusal) -> String {
        switch refusal {
        case .taxStatusNeverRecorded:
            return "Waiting on this client's tax status."
        case .discountExceedsSubtotal:
            return "The discount is larger than everything on this invoice."
        }
    }
}
