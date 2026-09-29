// ovation#596, PRD 51d, schema version 7. One message Ovation sent about an
// invoice and Gmail accepted: the send that issued it, a reminder, or a copy.
//
// WRITTEN ONLY AFTER GMAIL ACCEPTED, never before and never on a guess (PRD 10c,
// ovation#45: sent is observed, never asserted). A send Gmail refused, or never
// answered, writes no row, so a row is always a message that went. The first send
// writes its row in the same save that records the invoice as sent, so the two
// cannot disagree; a reminder or a copy writes its row alone, because it moves
// nothing else.
//
// THE GMAIL IDENTIFIERS ARE WHAT GMAIL REPORTED, never what Ovation asked for
// (L127). `gmailThreadID` is the thread Gmail says the message is in, and
// `messageID` is the Message-ID header Gmail stamped on it, read back off the sent
// message. Either is nil where Gmail's answer did not carry it readably, because a
// stand in would read as a real value and send a reply to a thread that does not
// exist (backstage#483, backstage#2647).
//
// WHO IT WENT TO IS WHO IT WENT TO, the addresses on the message as it left, which
// can differ from the client's addresses today (L443). They are not re-derived
// from the client when the history is drawn.
//
// NO ROW EXISTS FOR A SEND MADE BEFORE VERSION 7, and none is invented: an invoice
// sent earlier has no record of who its first send went to or which thread it
// started, and the history says so rather than drawing one from the client (L192).
import Foundation
import SwiftData

/// Which message this was. Its raw value is stored, so a rename is a migration
/// (L1006), not a tidy-up.
enum SentMessageKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// The send that issued the invoice.
    case invoice
    case reminder
    case copy
}

extension OvationSchemaV8 {
    @Model
    final class SentMessage {
        var id: UUID = UUID()
        var kind: SentMessageKind = SentMessageKind.invoice
        /// The addresses the message went to, as it left.
        var recipients: [String] = []
        /// When Gmail accepted it, and the day that was.
        var sentAt: Date = Date.distantPast
        var sentOn: BusinessDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "")
        /// The subject the message went under, exactly. A reminder is sent as "Re: "
        /// and the issuing send's subject AS RECORDED HERE, never re-composed from the
        /// invoice as it stands, because Gmail joins a reply to a thread only when the
        /// subjects match (Dan, 2026-09-28).
        var subject: String?
        /// The thread Gmail reported the message in, or nil where it did not say.
        var gmailThreadID: String?
        /// The Message-ID header Gmail stamped, or nil where it could not be read back.
        var messageID: String?
        var invoice: Invoice?

        init(kind: SentMessageKind, recipients: [String], sentAt: Date, subject: String?,
             gmailThreadID: String?, messageID: String?) {
            self.kind = kind
            self.recipients = recipients
            self.sentAt = sentAt
            self.sentOn = .stamping(sentAt)
            self.subject = subject
            self.gmailThreadID = gmailThreadID
            self.messageID = messageID
        }
    }
}

extension SentMessageKind {
    init(_ kind: InvoiceMailKind) {
        switch kind {
        case .reminder: self = .reminder
        case .copy: self = .copy
        }
    }
}

// The typealias pointing the bare name at the version in force, as every domain
// file carries.
typealias SentMessage = OvationSchemaV8.SentMessage
