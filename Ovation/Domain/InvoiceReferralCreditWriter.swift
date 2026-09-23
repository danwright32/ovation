// ovation#457, PRD 5.8, 5.4b and 5.51e. Spending a client's referral credit on
// an invoice.
//
// A SCREEN NEVER WRITES, AN ACTOR DOES (PRD 51l, ovation#440), the shape every
// other writer on this screen uses.
//
// THE AMOUNT IS DERIVED AND NEVER TYPED. PRD 5.51e settles that the credit
// "keeps its menu entry, having no controls of its own anywhere", so there is no
// figure for anybody to enter and the menu entry is the whole interface. What it
// spends is the smaller of what the client has banked and what the invoice is
// charging.
//
// BOTH HALVES OF THAT CAP ARE RECORDED DECISIONS. The design record's own rules
// state it in one sentence (`docs/design/rules/money.js`: "A credit may never
// exceed the balance, nor take an invoice below nothing"), and Dan settled it
// again on 2026-09-23 when the two records were put in front of him, choosing it
// over spending the whole balance and letting `Invoice.totalBelowZero` refuse
// the send, and over a sheet asking him how much to spend.
//
// THE CAP LIVES HERE AND NOT IN THE LEDGER, and that is what keeps two written
// decisions from overruling each other (L542). `ReferralLedger`'s header records
// that spending more than the balance is allowed THERE on purpose, because PRD
// 5.8 asks for a warning when a booking is flagged as spending credit the client
// does not have, and a warning is not a refusal. That stays exactly as it was:
// this is what the invoice screen offers to spend, and the log beneath it goes
// on accepting whatever it is told.
//
// IT TAKES THE STORE'S MONEY GATE, for the reason `InvoiceDiscountWriter`
// records: a credit changes the invoice's total, and `PaymentAllocator` refuses
// an allocation larger than `amountOutstanding`, which is derived from that
// total (ovation#175, L157).
import Foundation
import SwiftData

@ModelActor
actor InvoiceReferralCreditWriter {

    /// Spends as much of this client's banked credit as the invoice can take.
    ///
    /// THE DAY IS GIVEN, NEVER READ FROM THE CLOCK, the shape `InvoiceCloser`
    /// already uses: a ledger entry is a fact about a date, and a writer that
    /// asked the clock itself could not be tested across one (L524).
    func applyReferralCredit(on invoiceID: PersistentIdentifier,
                             on day: BusinessDate) async throws {
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }

        let invoice = try open(invoiceID)
        guard let client = invoice.client else {
            throw InvoiceReferralCreditRefusal.noSuchClient
        }
        guard invoice.referralCredit == nil else {
            throw InvoiceReferralCreditRefusal.creditIsAlreadyApplied
        }

        let ledger = ReferralLedger(modelContainer: modelContainer)
        let standing = try await ledger.spendStanding(onInvoice: invoice.id)

        let spending: Hours
        if standing < .zero {
            // A SPEND STANDS WITH NO CREDIT ON THE INVOICE, so this attempt is
            // FINISHING the last one rather than starting a new one, and the hours
            // come from the entry that is already there. Recomputing them would
            // move the balance a second time and disagree with the ledger about
            // what was spent, which nothing downstream could then reconcile.
            spending = Hours(hundredths: -standing.hundredths)
        } else {
            // THE BALANCE IS ASKED FIRST, and the order is written down here
            // because `InvoiceEditCommand` disables the menu entry in the same
            // order and must say the same thing (L118). With neither a balance
            // nor a charge, naming the charge would send Dan to add a line and
            // leave him exactly as stuck, since the client still has nothing to
            // spend (L111).
            let banked = client.referralBalance
            guard banked > .zero else { throw InvoiceReferralCreditRefusal.noCreditToSpend }
            let charges = Money.sum(of: invoice.lineItems.map(\.amount))
            guard charges > .zero else {
                throw InvoiceReferralCreditRefusal.nothingIsBeingCharged
            }
            spending = min(banked, ReferralCredit.mostThatFits(in: charges,
                                                               at: invoice.hourlyRate))
        }

        // THE CREDIT'S OWN INITIALISER IS THE ONLY WAY ONE IS MADE, and it refuses
        // a credit worth nothing. Reaching it takes a rate so small that no whole
        // hundredth of an hour is chargeable, which is not a shape to write a
        // second refusal for: this one names what happened.
        guard let credit = ReferralCredit(hours: spending, at: invoice.hourlyRate,
                                          earnedFrom: nil)
        else { throw InvoiceReferralCreditRefusal.noCreditToSpend }

        // THE LEDGER IS WRITTEN FIRST, and the order is the decision. Its entry
        // carries the invoice as an idempotency key, so a crash between the two
        // writes leaves a spend recorded with no credit on the invoice, which the
        // branch above finishes. The other order leaves a credit on the invoice
        // that the balance knows nothing about, and nothing can detect that (L33).
        if standing == .zero {
            try await ledger.spend(spending, for: client.persistentModelID,
                                   onInvoice: invoice.id, on: day)
        }

        invoice.referralCredit = credit
        try modelContext.save()
    }

    /// Takes the referral credit off an invoice and gives the hours back.
    ///
    /// THE INVOICE IS CLEARED FIRST, which is the opposite order to applying and
    /// for the same reason: of the two states a crash between the writes can
    /// leave, this one costs nothing. An invoice with no credit and a spend still
    /// standing is a balance temporarily short, and the next Apply finishes it. A
    /// balance given back while the invoice still shows the credit is the same
    /// hours counted twice, which is money invented (L33).
    ///
    /// IT FINISHES A HALF DONE REMOVAL rather than refusing one, for the same
    /// reason: the refusal is asked of BOTH records, so a removal interrupted
    /// between them can be completed by pressing it again.
    func removeReferralCredit(on invoiceID: PersistentIdentifier,
                              on day: BusinessDate) async throws {
        let gate = MoneyWriteGates.gate(for: modelContainer)
        await gate.lock()
        defer { gate.unlock() }

        let invoice = try open(invoiceID)
        let ledger = ReferralLedger(modelContainer: modelContainer)
        let standing = try await ledger.spendStanding(onInvoice: invoice.id)
        guard invoice.referralCredit != nil || standing < .zero else {
            throw InvoiceReferralCreditRefusal.noCreditIsApplied
        }

        if invoice.referralCredit != nil {
            invoice.referralCredit = nil
            try modelContext.save()
        }
        if standing < .zero {
            try await ledger.returnSpend(onInvoice: invoice.id, on: day)
        }
    }

    /// The invoice, if it is still there and its figures may still change.
    ///
    /// FETCHED AND MATCHED, NEVER SUBSCRIPTED. `ModelContext`'s subscript traps on
    /// a row deleted since the caller read it, and the screen is a photograph
    /// taken at the last write.
    ///
    /// THE SENT STATES ARE REFUSED HERE SO BOTH SIDES ASK ONE QUESTION. A credit
    /// moves the total exactly as a discount does, so a sent invoice's credit is
    /// what the client was told, and an unsettled send may already be in an inbox
    /// (`InvoiceDiscountWriter` keeps the same rule, in the same words).
    private func open(_ invoiceID: PersistentIdentifier) throws -> Invoice {
        guard let invoice = try modelContext.fetch(FetchDescriptor<Invoice>())
            .first(where: { $0.persistentModelID == invoiceID })
        else { throw InvoiceReferralCreditRefusal.noSuchInvoice }

        switch invoice.sentStatus {
        case .notSent: return invoice
        case .sent: throw InvoiceReferralCreditRefusal.invoiceWasSent
        case .attempting, .couldNotDetermine:
            throw InvoiceReferralCreditRefusal.sendIsUnsettled
        }
    }
}

/// Which way the one menu entry is being pressed.
///
/// A NAMED PAIR RATHER THAN A BOOLEAN, because the value travels through three
/// layers of the app to reach the writer and `true` at any of those call sites
/// says nothing about which way round it means, while these two do opposite
/// things to a client's balance.
enum ReferralCreditChange: Equatable, Sendable {
    case apply
    case remove
}

/// Why a referral credit was not spent.
enum InvoiceReferralCreditRefusal: Error, Equatable, CaseIterable {
    /// The invoice is gone, removed since the screen read it.
    case noSuchInvoice
    /// The invoice names no client, so there is no balance to spend from.
    case noSuchClient
    /// It has been sent, so its figures are what the client was told.
    case invoiceWasSent
    /// A send is in flight or could not be settled, so the render this would
    /// change may already be in a client's inbox.
    case sendIsUnsettled
    /// The invoice charges nothing, so a credit would burn the balance and
    /// reduce nothing.
    case nothingIsBeingCharged
    /// This client has nothing banked.
    case noCreditToSpend
    /// The invoice already carries one, which is taken off rather than replaced.
    case creditIsAlreadyApplied
    /// There is nothing to take off, on the invoice or in the ledger.
    case noCreditIsApplied

    /// What the screen says. Each names what happened rather than only refusing,
    /// because a control that does nothing and gives no reason leaves pressing it
    /// again as the only diagnosis (L109).
    var sentence: String {
        switch self {
        case .noSuchInvoice:
            return "That invoice is no longer there, so no credit was applied."
        case .noSuchClient:
            return "That invoice has no client, so there is no referral credit to spend."
        case .invoiceWasSent:
            return "This invoice has been sent, so its referral credit is what the client was told."
        case .sendIsUnsettled:
            return "A send for this invoice has not settled, so its referral credit cannot change yet."
        case .nothingIsBeingCharged:
            return "This invoice is not charging for anything yet, so a credit would take nothing off."
        case .noCreditToSpend:
            return "This client has no referral credit banked."
        case .creditIsAlreadyApplied:
            return "This invoice already has a referral credit on it."
        case .noCreditIsApplied:
            return "This invoice has no referral credit on it."
        }
    }
}
