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
    ///
    /// IT TAKES THE FOOTER, AND THERE IS NO OVERLOAD THAT DOES NOT (ovation#319).
    /// Two of the reasons come from Settings rather than from the invoice, so a
    /// caller able to ask the invoice-only question would be able to wave through
    /// an invoice whose page cannot say how to pay it. One function taking both
    /// means a caller cannot ask the narrower question by accident (L16, L667).
    @MainActor
    static func refusal(for invoice: Invoice, footer: InvoiceFooter) -> String? {
        let refusals = invoice.refusals.union(footer.refusals)
        // ASKED IN A WRITTEN ORDER, not over a Set, whose order is not a fact about
        // anything (L343). The two footer reasons come FIRST because they are not
        // about this invoice at all: they stop every invoice in the app, they are
        // fixed once in Settings, and saying "waiting on this client's tax status"
        // to somebody whose real problem is that no invoice can go out would send
        // them to the wrong screen (L111). Below them, the tax status comes before
        // an oversized discount because answering it is a fact about the client
        // that outlives this invoice, while a discount is a number on this one.
        //
        // A NEGATIVE TOTAL COMES LAST, and that is what lets its sentence name the
        // credit (ovation#136). An oversized dollar discount drives the total below
        // zero too, so in that case both refusals are present at once; saying the
        // discount first names the number actually typed wrong, and leaves the
        // negative total sentence to be reached only when the discount is not the
        // cause, which is when the referral credit exceeds the charges.
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
    ///
    /// THE DURATION COMES BEFORE THE TAX STATUS, which is the design's own order
    /// rather than a fresh judgement: `waiting.js` asks the times, then the duration
    /// they produce, then the tax status. Dan's argument for a fixed order, given
    /// while it was settled: "what happens if I set the tax status before the hours?
    /// That line just disappears and nothing takes its place."
    static let order: [InvoiceRefusal] = [
        .paymentInstructionsNotSet, .contactDetailsNotSet,
        .shootTimesNotGiven, .shootEndTimeNotGiven, .shootStartTimeNotGiven,
        .durationLongerThanAShoot,
        .taxStatusNeverRecorded, .discountExceedsSubtotal, .totalBelowZero,
    ]

    /// The one sentence for each refusal. Total over the vocabulary, so a new member
    /// cannot take a default and read as a deliberate silence (L113).
    static func sentence(for refusal: InvoiceRefusal) -> String {
        switch refusal {
        case .taxStatusNeverRecorded:
            return "Waiting on this client's tax status."
        case .discountExceedsSubtotal:
            return "The discount is larger than everything on this invoice."
        // NAMES THE SCREEN TO GO TO, because neither is anything to do with the
        // invoice in front of him and nothing on this one can fix it (L111, L399).
        case .paymentInstructionsNotSet:
            return "Settings has no payment instructions, so no invoice can be sent."
        case .contactDetailsNotSet:
            return "Settings has no contact details, so no invoice can be sent."
        // NAMES THE CREDIT, and it can, because of where this sits in the order
        // above. An oversized DISCOUNT also drives the total below zero, and it is
        // said first and by its own name, so by the time this sentence is reached
        // the discount is not the cause and the credit exceeding the charges is the
        // only way left to get here. A sentence naming a cause that cannot be the
        // cause sends somebody to change a number that changes nothing (L111).
        case .totalBelowZero:
            return "The credit is larger than everything charged, so this invoice comes to less than nothing."
        // THE DESIGN'S OWN SENTENCES, `waiting.js`, word for word, and each names
        // the thing that is actually missing rather than its class (PRD 51b).
        // `scripts/check-waiting-sentences-agree.sh` is what holds them to it.
        case .shootTimesNotGiven:
            return "Waiting on the shoot's start and end times."
        case .shootEndTimeNotGiven:
            return "Waiting on the time the shoot ended."
        case .shootStartTimeNotGiven:
            return "Waiting on the time the shoot started."
        // THE DESIGN'S OWN SENTENCE, `waiting.js`, word for word, and the number in
        // it comes from the rule rather than from a second copy typed here (L370).
        // PRD 51c: it says the times cannot be right rather than asking for times
        // that have already been given.
        case .durationLongerThanAShoot:
            return "That is more than \(ShootDuration.cap.hundredths / 100) hours, "
                + "so it prices nothing. Check the times."
        }
    }
}
