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
        // AND THEN WHATEVER WOULD STOP A PAGE BEING DRAWN AT ALL (ovation#446).
        // `InvoiceDocument` refuses an invoice with no due date, no invoice date,
        // no client, a date that cannot be read or a due date before the invoice
        // date, and says in its own header that the refusal belongs here. It did
        // not: Review opened over every one of them and the sheet then had nothing
        // to show.
        //
        // IT IS ASKED RATHER THAN COPIED, so there is one list of what a page needs
        // and it is the one the page is actually drawn from (L370).
        //
        // LAST IN THE ORDER, ON PURPOSE. Everything above is a state Dan reaches in
        // the ordinary course of filling in a draft, and these mean something is
        // wrong with the record itself. Saying "waiting on a due date" over a draft
        // whose real state is that it has no end time yet is the shape Dan argued
        // against when the order was settled: "what happens if I set the tax status
        // before the hours? That line just disappears and nothing takes its place."
        if let cannotBeDrawn = InvoiceDocument.refusalToRender(invoice, footer: footer) {
            return sentence(forCannotBeDrawn: cannotBeDrawn)
        }
        return nil
    }

    /// THE SHORT FORM, drawn where the figure would be, for the refusals that have
    /// one (ovation#457, round 3).
    ///
    /// BOTH FORMS LIVE TOGETHER, which is `docs/design/rules/waiting.js`'s own
    /// arrangement and its stated reason: the reason and the two sentences that
    /// carry it come from one place "so the screen cannot say one thing where the
    /// figure is drawn and a different thing under the main action" (L113, L118).
    /// `sentence(for:)` above is that file's `tip`; this is its `says`.
    ///
    /// NIL WHERE THE DESIGN HAS NO SHORT FORM, which is every refusal that is not
    /// a state of waiting: the two Settings ones and the two about money are not
    /// things the amount column can say, and `waiting.js` gives them no `says`
    /// either. A caller with nil draws the figure it has.
    static func says(for refusal: InvoiceRefusal) -> String? {
        switch refusal {
        case .shootTimesNotGiven: return "Needs the times"
        case .shootEndTimeNotGiven: return "Needs the end time"
        case .shootStartTimeNotGiven: return "Needs the start time"
        case .durationLongerThanAShoot: return "Longer than a shoot"
        // NOT STATES OF WAITING, so the amount column has nothing to say for them
        // and the foot's sentence is where they are reported.
        case .taxStatusNeverRecorded, .discountExceedsSubtotal, .totalBelowZero,
             .paymentInstructionsNotSet, .contactDetailsNotSet, .nothingIsBeingCharged:
            return nil
        }
    }

    /// The one sentence for each way the page itself can be refused. Total over
    /// that vocabulary too, so a precondition added to the renderer cannot take a
    /// default here and read as a deliberate silence (L113).
    static func sentence(forCannotBeDrawn refusal: InvoiceDocument.Refusal) -> String {
        switch refusal {
        // NOT REACHABLE FROM HERE, and that is structural rather than hopeful:
        // `refusalToRender` carries its own stand in past the number, because
        // Review is what issues it. Worded anyway, because a vocabulary a lookup
        // reads must be total whatever the caller happens to do today.
        case .noNumber:
            return "This invoice has no number yet."
        // PRD 7: the invoice is dated its booking's shoot date. So the thing that
        // is missing is the shoot's date, and naming the field rather than the
        // shoot would send Dan looking for a date field that is not what he has to
        // fill in (L399).
        case .noInvoiceDate:
            return "Waiting on the shoot's date, which is this invoice's date."
        case .noDueDate:
            return "Waiting on the date this invoice is due."
        case .noClient:
            return "This invoice has no client, so there is nobody to send it to."
        // THE SAME SENTENCE AS THE INVOICE'S OWN, never a second wording of one
        // condition (L118). Both vocabularies carry this member and either can
        // reach it, so they say the same thing.
        case .discountExceedsSubtotal:
            return sentence(for: .discountExceedsSubtotal)
        case .unreadableDate:
            return "One of this invoice's dates cannot be read, so no page can be made from it."
        case .dueBeforeInvoiceDate:
            return "The due date is before the invoice date."
        }
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
        .taxStatusNeverRecorded, .nothingIsBeingCharged,
        .discountExceedsSubtotal, .totalBelowZero,
    ]

    /// The one sentence for each refusal. Total over the vocabulary, so a new member
    /// cannot take a default and read as a deliberate silence (L113).
    static func sentence(for refusal: InvoiceRefusal) -> String {
        switch refusal {
        case .taxStatusNeverRecorded:
            return "Waiting on this client's tax status."
        case .discountExceedsSubtotal:
            return "The discount is larger than everything on this invoice."
        // ovation#458. NAMES WHAT IS ABSENT rather than the figure it produces. A
        // sentence about the total being zero would be wrong about the comped
        // invoice PRD 5.1b protects, and would send Dan to look at a number when
        // what is missing is a line.
        case .nothingIsBeingCharged:
            return "There is nothing on this invoice to charge for."
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
