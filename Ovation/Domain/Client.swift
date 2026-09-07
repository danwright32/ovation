// ovation#60. Who is invoiced.
//
// TAX STATUS LIVES HERE AND NOT ON THE INVOICE, which is one of the facts PRD
// 5.83 says must have a single declared home. It is a property of the client
// rather than of a job, which is why ovation#40's roster pass is per client, and
// why an invoice reads it rather than copying it.
//
// TWO ADDRESSES, AND THE SECOND IS AN OVERRIDE. Corrected 2026-09-07 by Dan, who
// read the roster round and said plainly that not having a contract email is the
// DEFAULT: the person who booked him is usually the person he emails the invoice
// to, and only a handful of clients want it sent elsewhere, a treasurer for the
// invoice and a director for the photographs. The model here had one field named
// `contractEmail` and treated its absence as a gap, which is backwards.
//
// DOWNBEAT ALREADY EXPORTS BOTH, `email` and `contractEmail`
// (`mac/Overture/Domain/DownbeatExport.swift:11-12`), so this is inherited rather
// than invented, and the earlier model had simply dropped one of them.
//
// MEASURED against the custody export of 2026-09-05, counts only, no addresses:
// 31 clients, EVERY ONE has a main email, 1 has an empty override, and the other
// 30 carry an override that is an exact copy of the main address. NOT ONE CLIENT
// HAS A GENUINE OVERRIDE TODAY. So a screen that shows a contract email on every
// client is showing the same fact twice on 30 of 31 (L605), and a roster pass
// that lists an empty override as a gap is listing the ordinary case.
//
// MONEY HELD ON A CLIENT IS DERIVED, NEVER STORED. See `Payment` (ovation#60
// step 3b): it is what was received minus what is allocated, computed from one
// predicate so a count and the rows it promises can never disagree (L16).
import Foundation
import SwiftData

@Model
final class Client {
    var id: UUID = UUID()

    var name: String = ""

    /// PRD 5. Three answers, because a missing one is not a no.
    var taxStatus: TaxStatus = TaxStatus.neverRecorded

    /// The address of whoever booked the work. This is where an invoice goes
    /// unless the client asked for somewhere else.
    var email: String = ""

    /// WHERE INVOICES GO INSTEAD, for the handful of clients who want them sent
    /// somewhere other than to the person who booked. ABSENT IS THE ORDINARY
    /// CASE and is never a gap.
    ///
    /// Empty and whitespace are treated as absent, not as a value, because the
    /// export's own field is a non-optional String and the one client without an
    /// override carries an empty string rather than a missing key (L257).
    var contractEmail: String?

    /// That a shared address was looked at and found correct, recorded against
    /// the ADDRESS it was given for.
    ///
    /// Dan, 2026-09-07: "it should give me a warning but I should be allowed to
    /// dismiss it as correct." So it is an acknowledgement rather than a
    /// suppression: keyed to the address, so changing the address asks again,
    /// and consulted by EVERY rule that raises the question rather than only by
    /// the one whose control recorded it (L330).
    var sharedAddressAcknowledgedFor: String?
    var sharedAddressAcknowledgedOn: BusinessDate?

    /// PRD 5.7's per client override of the fourteen day default. Nil means the
    /// default, and it is a real absence rather than a zero.
    var paymentTermDays: Int?

    @Relationship(deleteRule: .nullify, inverse: \Invoice.client)
    var invoices: [Invoice] = []

    @Relationship(deleteRule: .nullify, inverse: \Payment.client)
    var payments: [Payment] = []

    @Relationship(deleteRule: .nullify, inverse: \ReferralLedgerEntry.client)
    var referralEntries: [ReferralLedgerEntry] = []

    init(name: String, taxStatus: TaxStatus) {
        self.name = name
        self.taxStatus = taxStatus
    }

    /// Money Ovation is holding on this client's behalf: what arrived, less what
    /// is spoken for. PRD 5.14a says this is a real state rather than an error,
    /// and it is where a deposit taken before the shoot sits.
    ///
    /// DERIVED, NEVER STORED, and computed from the same predicate every payment
    /// uses, so this number and the payments a screen lists cannot disagree (L16).
    ///
    /// IT IS NOT REFERRAL CREDIT. See the header on `Payment`.
    var moneyHeld: Money { Money.sum(of: payments.map(\.unallocated)) }

    /// Referral credit standing to this client, in hours. PRD 5.8.
    ///
    /// A SUM OVER THE LEDGER, never a stored field, so nothing has to remember to
    /// keep a total in step and no edit can leave the two disagreeing.
    ///
    /// IT IS NOT MONEY HELD, and the two never add up (PRD 5.14c). Credit was
    /// earned against a ledger and is spent as a negative line inside an invoice;
    /// held money actually arrived and is owed back if it is never used. They
    /// will look alike on the Clients screen, which is why they are two accessors
    /// of two different types rather than one number.
    var referralBalance: Hours {
        referralEntries.reduce(Hours.zero) { $0 + $1.hours }
    }

    // MARK: where an invoice actually goes

    /// One normalisation, used by every comparison here, so two spellings of one
    /// address cannot be treated as two (L185).
    private static func normalised(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private var mainAddress: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var overrideAddress: String? {
        let trimmed = (contractEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether this client really sends invoices somewhere else.
    ///
    /// AN OVERRIDE THAT COPIES THE MAIN ADDRESS IS NOT ONE, which is 30 of the 31
    /// real clients. Counting those as overrides would put a second address on
    /// every screen and produce thirty findings about nothing.
    var hasInvoiceOverride: Bool {
        guard let over = Client.normalised(overrideAddress) else { return false }
        return over != Client.normalised(mainAddress)
    }

    /// The value an invoice is sent to, as written, or nil where there is none at
    /// all. Never an empty string: an empty address is an absence and must not
    /// reach a send path as a value (L67).
    var emailForInvoices: String? { hasInvoiceOverride ? overrideAddress : mainAddress }

    /// EVERY recipient an invoice goes to, which is usually one and is sometimes
    /// several. Empty where the value cannot be sent to at all, so a caller
    /// cannot send to a subset of a broken value by accident.
    ///
    /// This is what the review screen renders, because what a person approves
    /// must include who it goes to (L64).
    var recipientsForInvoices: [String] {
        guard let value = emailForInvoices, Client.problem(with: value) == nil else { return [] }
        return Client.addresses(in: value)
    }

    // MARK: what is genuinely wrong with the contact details

    /// One address the send path can consume: exactly one `@` and no whitespace.
    /// Validated against what the sender can take, never against a list of things
    /// it must not be (L150, L257).
    private static func isOneAddress(_ value: String) -> Bool {
        value.filter { $0 == "@" }.count == 1 && !value.contains(where: { $0.isWhitespace })
    }

    /// SEVERAL ADDRESSES IN ONE FIELD IS A VALUE, NOT A FAULT (Dan, 2026-09-07,
    /// overruling PRD 38 as first written): "there's nothing stopping me from
    /// invoicing 2 emails at the same company at the same time for the same
    /// event." Measured: 1 of the 31 real clients has one.
    ///
    /// What 38a was actually protecting, that a recipient nobody chose must not
    /// reach an invoice already approved, is the review screen's job: it shows
    /// every recipient (PRD 5.10, L64). It is not this function's job, and doing
    /// it here refused a value Dan writes on purpose.
    private static func addresses(in value: String) -> [String] {
        value.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Nil where the value is fine, otherwise what is wrong with it.
    ///
    /// ONE BAD PART SPOILS THE WHOLE VALUE. Sending to the parts that happen to
    /// parse would deliver an invoice to a subset nobody chose, which is worse
    /// than refusing, and it is the failure 38a named.
    private static func problem(with value: String) -> ClientContactProblem? {
        let parts = addresses(in: value)
        guard !parts.isEmpty else { return .addressIsNotAnAddress }
        return parts.allSatisfy(isOneAddress) ? nil : .addressIsNotAnAddress
    }

    /// The distinct things wrong here, each named for WHAT it is rather than for
    /// needing attention, because they need different work and a single flag
    /// collapses them into one pile (ovation#40, L11).
    ///
    /// A SHARED ADDRESS IS NOT IN HERE. Dan settled that it warns rather than
    /// faults, so it is asked separately and can be answered.
    var contactProblems: Set<ClientContactProblem> {
        var found: Set<ClientContactProblem> = []
        if mainAddress == nil && overrideAddress == nil { found.insert(.noAddressAtAll) }
        if let main = mainAddress, let p = Client.problem(with: main) { found.insert(p) }
        if let over = overrideAddress, let p = Client.problem(with: over) { found.insert(p) }
        return found
    }

    // MARK: a shared address, warned about once and settleable

    /// Whether the address invoices go to also belongs to somebody else.
    func sharesItsAddress(with others: [String]) -> Bool {
        guard let mine = Client.normalised(emailForInvoices) else { return false }
        return others.contains { Client.normalised($0) == mine }
    }

    /// Whether the share is still an open question. False once it has been
    /// acknowledged FOR THIS ADDRESS, and true again the moment the address
    /// changes, because that is a different question.
    func shareNeedsAnswering(against others: [String]) -> Bool {
        guard sharesItsAddress(with: others) else { return false }
        guard let answered = Client.normalised(sharedAddressAcknowledgedFor) else { return true }
        return answered != Client.normalised(emailForInvoices)
    }

    /// Records that the share was looked at and is correct.
    func acknowledgeSharedAddress(on day: BusinessDate) {
        sharedAddressAcknowledgedFor = emailForInvoices
        sharedAddressAcknowledgedOn = day
    }
}
