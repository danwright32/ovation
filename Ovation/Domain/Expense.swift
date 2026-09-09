// ovation#60 step 3c, PRD 5.16 to 5.22 and 5.28. What Ovation spent.
//
// THE RECEIPT IS THREE SITUATIONS, NOT A BOOLEAN. There is a receipt; Dan filed
// the expense without one, which PRD 5.21 allows and requires to be MARKED in the
// CSV; and it was imported from QuickBooks, which by 5.28 has no image and is
// marked as such. A boolean would fold the last two together, and they are
// different facts that the accountant reads differently: one is a receipt nobody
// kept, the other is a year Ovation never saw (L163, L544).
//
// THE RE-FILING KEY IS ONE OVATION CAN RECOMPUTE (PRD 5.22a, L186, L127). It is
// the message id, the receipt file's own SHA-256, and the part index that
// separates two identical attachments in the same message. Gmail's attachment id
// is stored for FETCHING and is never the key, because its stability across
// separate fetches is not guaranteed and a key that changes makes the record
// unfindable, which files a duplicate expense into a seven year tax record.
//
// AN EXPENSE WITH NO SOURCE HAS NO KEY AT ALL, rather than a plausible one. One
// Dan typed in came from no message, and a key built out of empty strings would
// collide with every other one like it.
//
// DELIBERATELY NOT HERE: the asset threshold and its override (PRD 5.20), the
// duplicate flag (5.22), and the ambiguity counters (5.18b). Those are
// ovation#82 and ovation#83, in the milestone that owns them.
import Foundation
import SwiftData

/// Whether there is a receipt behind this expense, and where there is not, why.
/// Whether an expense is an asset, as Dan answered it (ovation#82, PRD 5.20).
///
/// THREE CASES RATHER THAN A BOOLEAN. "Nobody has said" is a real state and is
/// not the same as "no": while it stands, Ovation's suggestion applies, and the
/// moment Dan answers, his answer applies for ever. A boolean would make the
/// suggestion and the decision the same field, and every later edit to the amount
/// would silently rewrite an answer (L544, L432).
enum AssetJudgement: String, CaseIterable, Codable, Hashable, Sendable {
    case notDecided = "not-decided"
    case treatAsAsset = "treat-as-asset"
    case notAnAsset = "not-an-asset"
}

/// The amount at or above which Ovation SUGGESTS an expense is an asset.
///
/// PROVISIONAL, AND IT SAYS SO. $2,500 is the IRS de minimis safe harbour, but
/// PRD 9.4 records that it is an ELECTION made on the return, that Section 179
/// may make it moot, and that whether it applies per item or per receipt total is
/// unanswered. All three are questions for Dan's accountant (ovation#65).
///
/// A threshold that reads as settled is one nobody re-examines, so the pending
/// question travels with the number rather than living in a document beside it
/// (L316, L407).
struct AssetThreshold: Equatable, Sendable {
    let amount: Money
    let isProvisional: Bool
    let pendingQuestion: String

    static let inForce = AssetThreshold(
        amount: Money(dollars: 2_500),
        isProvisional: true,
        pendingQuestion: "PRD 9.4: whether the de minimis threshold applies per item or per "
            + "receipt total, whether Dan's return makes the safe harbour election, and "
            + "whether Section 179 makes the question moot. All three are for the accountant "
            + "(ovation#65).")
}

enum ReceiptEvidence: Equatable, Hashable, Codable, Sendable {
    /// A file Ovation manages, addressed by content hash so the backup can
    /// enumerate it and check it (PRD 42b, 5.29).
    case file(sha256: String, relativePath: String)
    /// PRD 5.21. Allowed, and the mark reaches the CSV.
    case noneRecorded
    /// PRD 5.28. An imported 2026 row, which never had one here.
    case importedWithoutOne
}

extension OvationSchemaV1 {
    @Model
    final class Expense {
        var id: UUID = UUID()

        var amount: Money = Money.zero

        /// The day that decides the tax year, stamped at write.
        var incurredOn: BusinessDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "")

        /// PRD 5.18: filled only where the reading is unambiguous, left empty where
        /// it is doubtful. Absent is a real answer here, never a guess.
        var vendor: String?

        /// PRD 5.19. Absent until it is filed, which is why the export has to be able
        /// to report an expense that has not been categorised rather than dropping it.
        var category: ExpenseCategory?

        /// Whether this is an asset rather than an ordinary expense (ovation#82,
        /// PRD 5.20). Dan's answer, or that he has not given one.
        ///
        /// STORED SEPARATELY FROM THE AMOUNT, so the suggestion can never
        /// overwrite the answer. A field re-derived from a sibling whenever that
        /// sibling changes hides itself, because the values it produces vary and
        /// read as entered (L432).
        var assetJudgement: AssetJudgement = AssetJudgement.notDecided

        /// When Dan said this expense and its lookalikes are all genuine
        /// (ovation#82). Nil while nobody has said so.
        ///
        /// The suspicion consults it, which is the whole point: a rule that goes
        /// on asking a question after it has been answered leaves nothing that
        /// could ever satisfy it (L330, L269).
        var bothAreRealAcknowledgedOn: BusinessDate?

        var receipt: ReceiptEvidence = ReceiptEvidence.noneRecorded

        var note: String?

        // MARK: where it came from, for LOOKUP only, never as the identity

        /// The Gmail message this was filed from.
        var gmailMessageKey: String?

        /// Which attachment of that message. Two identical attachments in one message
        /// are two expenses and are told apart by this.
        var attachmentPartIndex: Int?

        /// Gmail's own attachment id, stored so the file can be FETCHED again. Never
        /// part of the key: see the header.
        var gmailAttachmentID: String?

        /// The QuickBooks import batch this came from. ovation#69 owns what goes in it.
        var importKey: String?

        init(amount: Money, incurredOn: BusinessDate, receipt: ReceiptEvidence) {
            self.amount = amount
            self.incurredOn = incurredOn
            self.receipt = receipt
        }

        var hasReceipt: Bool {
            if case .file = receipt { return true }
            return false
        }

        /// The receipt's content hash, where there is one. This is what the backup
        /// enumerates and re-checks, so a document that has gone missing is reported
        /// rather than passing because the database still opens.
        var receiptHash: String? {
            if case .file(let sha256, _) = receipt { return sha256 }
            return nil
        }

        /// What the CSV says about a missing receipt, which is nothing at all when
        /// there is one. Two absences, two sentences (L11).
        var receiptMissingNote: String {
            switch receipt {
            case .file: return ""
            case .noneRecorded: return "No receipt"
            case .importedWithoutOne: return "Imported without a receipt"
            }
        }

        /// PRD 5.19: every expense carries a category, so one without it is work
        /// waiting rather than a settled row.
        var needsACategory: Bool { category == nil }

        /// What Ovation would say if nobody had answered: the amount is at or
        /// above the provisional threshold.
        ///
        /// A SUGGESTION AND NOT A DETERMINATION (PRD 5.20). It stays visible
        /// beside the answer rather than being replaced by it, so a surface can
        /// show both.
        var suggestsAsset: Bool { amount >= AssetThreshold.inForce.amount }

        /// Whether it IS one. Dan's answer wins in both directions; the
        /// suggestion stands only while he has not given one.
        var isAsset: Bool {
            switch assetJudgement {
            case .treatAsAsset: return true
            case .notAnAsset: return false
            case .notDecided: return suggestsAsset
            }
        }

        /// Where this expense is reported, which is the flag's whole consequence.
        ///
        /// AN ASSET GOES TO LINE 13 whatever its category would have said.
        /// `ScheduleCMap` records that gear maps provisionally to Supplies and
        /// that this flag is what moves an individual expense to depreciation, so
        /// reading the category alone would leave the flag changing nothing
        /// anybody sees (L46).
        ///
        /// Nil for an expense with no category and no flag: a line asserted on no
        /// evidence puts money on a line of a return nobody chose (L192).
        var scheduleCLine: ScheduleCLine? {
            if isAsset { return .depreciation }
            return category?.scheduleC.line
        }

        /// The key that stops the same attachment being filed twice, recomputable
        /// from the message and the file itself. Nil where this expense came from no
        /// message at all.
        var intakeKey: String? {
            guard let gmailMessageKey, let receiptHash, let attachmentPartIndex else { return nil }
            return "\(gmailMessageKey):\(receiptHash):\(attachmentPartIndex)"
        }
    }
}

/// One movement of referral credit. PRD 5.8, plan 1.12.
///
/// THE BALANCE IS A SUM OVER THESE AND NEVER A STORED FIELD, so nothing has to
/// remember to keep a total in step. Its one declared home is the client who
/// earned it (L83), and `Client.referralBalance` is the one predicate that reads
/// it.
///
/// IN HOURS, because that is what is earned and what is spent: one hour per hour
/// of the referred client's first booking. Turning it into money here would
/// freeze it at whatever the rate was on the day, which is a different promise.
///
/// WHAT WRITES ONE, and the idempotency key that stops the credit being earned
/// twice when a paid transition is re-crossed by an edit and resend or a cancel,
/// refund and repay, is ovation#38.
extension OvationSchemaV1 {
    @Model
    final class ReferralLedgerEntry {
        var id: UUID = UUID()

        var client: Client?

        /// Positive where it was earned, negative where it was spent.
        var hours: Hours = Hours.zero

        var occurredOn: BusinessDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "")

        /// The booking that earned it, which is what a second append for the same key
        /// is refused against (ovation#38). Nil on a spending entry.
        var earnedFromBookingKey: String?

        /// The invoice this credit was spent on (ovation#38). Nil on an earning.
        ///
        /// IT IS THE SECOND IDEMPOTENCY KEY, and it is here for the same reason the
        /// first one is: editing and resending an invoice re-runs whatever applied
        /// its credit, exactly as it re-crosses the paid transition, and without a
        /// key the client is charged their own credit twice.
        ///
        /// It also makes the two records reconcilable. The invoice FREEZES what it
        /// applied (`ReferralCredit`) and the ledger is the running total, and the
        /// two must agree about which credit was used; without this neither can be
        /// checked against the other.
        ///
        /// Ovation's own UUID rather than a relationship, because a ledger entry is
        /// an append only fact about the past and must not be cascaded away with the
        /// invoice it mentions (L38, PRD 5.30).
        var spentOnInvoiceID: UUID?

        var note: String?

        init(
            client: Client?, hours: Hours, occurredOn: BusinessDate,
            earnedFromBookingKey: String?, spentOnInvoiceID: UUID? = nil, note: String?
        ) {
            self.client = client
            self.hours = hours
            self.occurredOn = occurredOn
            self.earnedFromBookingKey = earnedFromBookingKey
            self.spentOnInvoiceID = spentOnInvoiceID
            self.note = note
        }
    }
}

// THE NAME THE REST OF THE APP USES (ovation#134). The type belongs to a
// schema VERSION, because a version has to be able to describe a shape that
// is no longer current. Everything outside the store speaks about the shape
// in force, so it says the bare name and this is what points that name at the
// version in force. When a version 2 exists, this line moves to it and every
// call site is already correct.
typealias Expense = OvationSchemaV1.Expense
typealias ReferralLedgerEntry = OvationSchemaV1.ReferralLedgerEntry
