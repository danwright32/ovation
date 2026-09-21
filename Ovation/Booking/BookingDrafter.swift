// ovation#461, PRD 1, 3, 3a, 3c, 5.7, 42c. One queued booking becomes one draft.
//
// NOTHING IN OVATION CREATED AN INVOICE BEFORE THIS. Measured 2026-09-21: the
// only `context.insert(invoice)` outside tests was `ReviewSampleWorld`, which is
// Debug only, so ovation#42 had nothing to send and every screen in the
// Invoicing and sending milestone was built against a population nothing put
// there.
//
// THE SHORTCUT IS NAMED. ovation#32's drain replaces this, and ovation#31's
// referral ledger is what this deliberately does not write. Recording which is
// which is the difference between a stopgap and a second implementation nobody
// remembers to delete (L29).
//
// THE DRAFT IS UNPRICED, WHICH IS THE POINT. PRD 3a makes the booking's times a
// placeholder nothing may be priced from, and PRD 3c says a drafted invoice
// carries NO duration and cannot be sent until Dan supplies one. So the shoot
// arrives with its DAY and no times, and Dan types them on the invoice screen
// (ovation#457, ovation#467). Copying `startsAt` and `endsAt` onto the shoot
// would price every invoice from Downbeat's placeholder, which is the one thing
// both requirements forbid, and it is the easiest mapping in this file to write
// by accident.
//
// DOING IT TWICE IS THE FAILURE THIS TYPE IS SHAPED AROUND. The queue is not
// consumed, deliberately (Dan, 2026-09-21), so the same record is read again on
// the next run and a second draft for one shoot is an invoice Dan sends twice.
//
//   NOT A UNIQUE CONSTRAINT. `Invoice.swift` states the rule: no
//   `@Attribute(.unique)` anywhere, including on id, because PRD 42c makes it
//   choose which failure a duplicate becomes rather than prevent one, and a
//   colliding id destroys the row that was there. The mechanism this codebase
//   has is a serialized writer, which is what `@ModelActor` gives, the way
//   `InvoiceNumberAllocator` and `PaymentAllocator` do it. Proved by holding two
//   callers at the decision point, never by running it twice in sequence, which
//   is a different claim (L157, L407).
//
//   THE HOME OF THE BOOKING KEY IS THE SHOOT. Both `Invoice` and `Shoot` declare
//   a `bookingKey`, and a drafter stamping one while the refusal reads the other
//   mints a second invoice silently (L83). The shoot is the home because PRD 5.1a
//   puts more than one shoot on one invoice and ovation#147 combines two bookings
//   onto one, so an invoice has no single booking to be keyed by while a shoot
//   always has exactly one. `Invoice.bookingKey` is left alone here; ovation#32
//   and ovation#68 own what becomes of it.
//
//   A RERUN CARRIES A DIFFERENT ID, so the key alone cannot catch it.
//   `HandoffRecord.Booking.isRerunOf` warns in its own doc comment that dropping
//   it drafts a SECOND invoice for one shoot with nothing reporting it.
//
// WHICH CLIENT, AND EVERY ANSWER TO IT. `BookingClientMatch` returns four things
// and each one does something different here.
//
//   NO MATCH CREATES THE CLIENT, and that is the arm the REAL record takes.
//   Measured 2026-09-21: the one record in the live queue names a client that is
//   in neither Ovation's 31 clients nor Downbeat's own current export, having
//   been removed upstream after the booking was committed, which is exactly what
//   `HandoffRecord.Client` being frozen at commit is for. A drafter that refused
//   it would leave ovation#42 with nothing to send.
//
//   AND IT CREATES IT THROUGH `ClientImport`, never a second creator written
//   here, so the tax status rule (three states, absent is never taxable), the
//   identifier stamping and the address ownership cannot be right in one place
//   and forgotten in the other.
//
//   A NAME ONLY MATCH WAITS. It found exactly one, and a rename or a namesake is
//   what `linksWithoutAsking` exists to name. There is no surface in this slice
//   for asking, and creating a client beside the one that matched manufactures
//   the duplicate identity every later invoice, payment and referral credit then
//   feeds (ovation#34).
//
//   SEVERAL MATCHES IS ITS OWN REFUSAL, never a pick (L521).
import Foundation
import SwiftData

/// Why a queued booking was not drafted.
enum BookingDraftRefusal: Equatable, Sendable {
    /// More than one client matched. Naming the count rather than the clients,
    /// because the remedy is to look at them, not to be told which.
    case clientIsAmbiguous(count: Int)
    /// Exactly one client matched, on the display name alone, which is enough to
    /// propose and never enough to link.
    case clientNeedsConfirming(named: String)
    /// The matcher answered and the answer could not be acted on: an id this
    /// context does not hold, or a creation that produced nothing.
    ///
    /// ITS OWN CASE RATHER THAN A COUNT OF ZERO. Reporting "0 clients match, so
    /// Ovation did not choose between them" is a sentence claiming something the
    /// check never measured, and the remedy is the opposite: nothing is wrong
    /// with the data, something is wrong with Ovation (L11).
    case ovationCouldNotResolveTheClient

    /// What the app says. Every refusal has one, so none can reach a screen mute
    /// and leave pressing the control again as the only diagnosis (L109).
    var sentence: String {
        switch self {
        case .clientIsAmbiguous(let count):
            return "\(count) clients match this booking, so Ovation did not choose between them."
        case .clientNeedsConfirming(let name):
            return "This booking matches \(name) by name only, which is not enough to link it."
        case .ovationCouldNotResolveTheClient:
            return "Ovation could not settle which client this booking is for, which is a "
                + "fault in Ovation rather than in the booking."
        }
    }
}

/// What drafting one queued booking came to.
enum BookingDraftOutcome: Equatable, Sendable {
    case drafted(invoice: PersistentIdentifier)
    /// This booking, or the booking it reruns, already has an invoice.
    case alreadyDrafted(bookingKey: String)
    case refused(BookingDraftRefusal)
}

@ModelActor
actor BookingDrafter {

    /// Read, decide and write, with nothing in between.
    func draft(from record: HandoffRecord, at rate: Money) throws -> BookingDraftOutcome {
        // ALREADY DRAFTED IS ASKED FIRST, of the shoots, which is where the key
        // lives. Both this booking's id and the one it reruns, because a rerun
        // arrives with a new id for a shoot that already has an invoice.
        var keys = [record.booking.id.uuidString]
        if let rerun = record.booking.isRerunOf { keys.append(rerun.uuidString) }
        let drafted = try modelContext.fetch(FetchDescriptor<Shoot>())
        if let already = drafted.first(where: { shoot in
            guard let key = shoot.bookingKey else { return false }
            return keys.contains(key)
        }) {
            return .alreadyDrafted(bookingKey: already.bookingKey ?? keys[0])
        }

        var held = try modelContext.fetch(FetchDescriptor<Client>())
        let match = BookingClientMatcher.match(
            downbeatClientID: record.booking.clientID,
            displayName: record.booking.clientDisplayName,
            emails: [record.client.email, record.client.contractEmail],
            against: held)

        let client: Client
        switch match {
        case .matched(let clientID, _) where match.linksWithoutAsking:
            guard let found = held.first(where: { $0.id == clientID }) else {
                // The matcher answered with an id this context does not hold,
                // which cannot happen from the fetch above and is refused rather
                // than recovered from, because the recovery is a second client.
                return .refused(.ovationCouldNotResolveTheClient)
            }
            client = found
        case .matched:
            return .refused(.clientNeedsConfirming(named: record.booking.clientDisplayName))
        case .ambiguous(let clientIDs, _):
            return .refused(.clientIsAmbiguous(count: clientIDs.count))
        case .noMatch:
            let created = ClientImport.apply([.create(Self.row(from: record.client))], to: &held)
            guard let made = created.first else {
                return .refused(.ovationCouldNotResolveTheClient)
            }
            modelContext.insert(made)
            client = made
        }

        // THE INVOICE IS DATED FROM THE SHOOT, never from `committedAt`, which is
        // the distinction an unconsumed record turning up months later depends
        // on. A booking whose day Ovation cannot parse gets no date, which is a
        // state the invoice list already has a group for (ovation#49), rather
        // than today's date standing in for one nobody recorded (L192).
        let shootDay = BusinessCalendar.day(forKey: record.booking.startDate)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: shootDay,
                              hourlyRate: rate, taxRate: .newYorkCity)
        invoice.dueDate = shootDay.flatMap { BusinessCalendar.day(14, after: $0) }
        modelContext.insert(invoice)

        let shoot = Shoot(name: record.booking.shootName,
                          when: shootDay.map(ShootWhen.dayOnly),
                          venue: record.booking.venueName)
        shoot.bookingKey = record.booking.id.uuidString
        invoice.add(shoot)

        // THE LINE IS THERE WITH NO HOURS. `ReviewGate` refuses an invoice with
        // nothing on it (ovation#458), so a draft carrying a shoot and no line
        // would be refused for the wrong reason: it would name an empty invoice
        // when the truth is that it is waiting on a time. This is also the shape
        // `Invoice.clearTimes(of:)` leaves, so a draft and a draft whose times
        // were taken back are one state rather than two (L11).
        let line = LineItem.hourly(hours: Hours(whole: 1), at: rate,
                                   describedAs: "Photography", for: shoot)
        line.hours = nil
        invoice.add(line)

        try modelContext.save()
        return .drafted(invoice: invoice.persistentModelID)
    }

    /// The frozen client, in the shape `ClientImport` creates from. Every field
    /// that type reads is carried; the rest of the record's client fields
    /// (`hasLeftReview`, `specialBehaviors`, `hostingSite`, `shortName`,
    /// `phoneNumber`, `notes`) have no home on `Client` and are Downbeat's own
    /// business, which ovation#32 revisits when the drain is built.
    private static func row(from client: HandoffRecord.Client) -> DownbeatExport.Client {
        DownbeatExport.Client(id: client.id, displayName: client.displayName,
                              email: client.email, contractEmail: client.contractEmail,
                              isTaxExempt: client.isTaxExempt)
    }
}
