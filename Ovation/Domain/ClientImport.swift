// ovation#208. How Downbeat's 31 clients become Ovation's roster, and keep up
// with it afterwards.
//
// WHY IT EXISTS. Measured 2026-09-11: nothing in Ovation constructed a `Client`
// outside the model file itself. So the store held zero clients and there was no
// route for the export's roster to reach it, which made ovation#40's roster pass
// correct and inert, and left ovation#32's drain and ovation#35's backfill both
// written against a population nothing put there.
//
// THE DECISION IS SEPARATE FROM THE WRITE. `plan` is a pure function of the
// export's rows and the clients Ovation holds; `apply` is the only part that
// mutates anything. Every rule below is therefore testable without a store, a
// container or a file, and no rule can be enforced in one half and forgotten in
// the other.
//
// IT RUNS ON EVERY LAUNCH (Dan, 2026-09-11, choosing this over a control he
// presses and over a one time backfill). Downbeat rewrites its export when IT
// launches, so a launch is the natural cadence and the roster keeps up with no
// ceremony. Two consequences follow from re-running rather than running once,
// and they are the whole shape of this file.
//
//   1. WHICH FIELDS EACH SIDE OWNS HAS TO BE DECIDED, not left to whoever wrote
//      last. Downbeat owns the name and both addresses: Dan maintains them there
//      and a rename or a corrected address should reach Ovation. Ovation owns the
//      TAX STATUS the moment Dan answers it here, because answering it is what the
//      roster pass is for, and a rule that refreshed it from the export would
//      silently undo that pass on every launch and it would never stay cleared.
//      So a status is filled only where Ovation has none.
//
//      THE COST, STATED BECAUSE IT IS REAL (L93): a tax correction Dan makes in
//      DOWNBEAT after Ovation already holds an answer never arrives. He makes it
//      here instead. The alternative was a provenance flag recording where each
//      answer came from, which was put to him on 2026-09-11 and declined.
//
//   2. NOTHING IS EVER DELETED. A client that has gone from the export is kept
//      and, by Dan's decision that day, nothing is said about it. Keeping it is
//      not a preference: it may carry invoices, payments and referral credit,
//      which are Ovation's financial history, and a deletion upstream says
//      nothing about them (L5, L9). The cost of the silence is that the two
//      rosters can drift apart with nothing pointing at it.
//
// AN EMPTY EXPORT DELETES NOTHING, which falls out of the rule above rather than
// needing its own guard, and is asserted anyway: the dangerous reading of an empty
// upstream list is that everything here has been removed (L214, L98).
//
// THE MATCHING IS NOT REIMPLEMENTED. `BookingClientMatcher` already answers which
// client a Downbeat record names, in the order identifier, address, name, with
// more than one match as its own refusal (ovation#34, L521). Writing a second
// matcher here would be two things doing one job, and the two would drift.
import Foundation

/// What the import decided to do about one row of the export.
enum ClientImportAction: Equatable, Sendable {
    /// Nothing here matches it. It becomes a client.
    case create(DownbeatExport.Client)
    /// Exactly one client matched, on a basis strong enough to link without
    /// asking. It is refreshed from the row.
    case update(clientID: UUID, from: DownbeatExport.Client)
    /// It matched something, but not well enough to act on. Named rather than
    /// silently created, because creating is what manufactures the duplicate.
    case leftAlone(DownbeatExport.Client, why: Reason)

    /// The two ways a row can match and still not be acted on. They are separate
    /// cases because the work is different: a name only match usually wants
    /// confirming, and an ambiguous one means the data itself needs sorting out
    /// (L11).
    enum Reason: Equatable, Sendable {
        /// One client has this name and nothing stronger agreed. Two clients can
        /// legitimately share a name, and a rename is exactly the case a name
        /// match cannot tell from a namesake.
        case matchedOnNameOnly
        /// Several clients matched. A guess here invoices the wrong customer.
        case matchedMoreThanOne
    }
}

/// What a run came to, in counts, so a launch can tell a run that changed
/// something from one that did not.
struct ClientImportSummary: Equatable, Sendable {
    var created = 0
    var updated = 0
    var leftAlone = 0

    /// Whether this run is worth saying anything about. A launch that changed
    /// nothing is every launch after the first, and a notice on the commonest
    /// case is one Dan learns to click past (L36).
    var changedSomething: Bool { created > 0 || updated > 0 || leftAlone > 0 }
}

enum ClientImport {

    /// Decide what to do about every row, touching nothing.
    static func plan(for rows: [DownbeatExport.Client],
                     against held: [Client]) -> [ClientImportAction] {
        rows.map { row in
            let match = BookingClientMatcher.match(
                downbeatClientID: row.id,
                displayName: row.displayName,
                emails: [row.email, row.contractEmail],
                against: held)

            switch match {
            case .matched(let clientID, _) where match.linksWithoutAsking:
                return .update(clientID: clientID, from: row)
            case .matched:
                // The only match that does not link without asking. Asking is
                // what `linksWithoutAsking` already decided; this reads it rather
                // than deciding again, so the two can never disagree (L70).
                return .leftAlone(row, why: .matchedOnNameOnly)
            case .ambiguous:
                return .leftAlone(row, why: .matchedMoreThanOne)
            case .noMatch:
                return .create(row)
            }
        }
    }

    /// Carry out a plan. Returns the clients it CREATED, for the caller to insert,
    /// because inserting is the store's business and this stays testable without
    /// one. Clients it updated are mutated in place.
    @discardableResult
    static func apply(_ actions: [ClientImportAction], to held: inout [Client]) -> [Client] {
        var created: [Client] = []
        for action in actions {
            switch action {
            case .create(let row):
                let client = Client(name: row.displayName, taxStatus: status(of: row.isTaxExempt))
                client.email = row.email
                client.contractEmail = row.contractEmail
                client.downbeatClientID = row.id
                created.append(client)
                held.append(client)
            case .update(let clientID, let row):
                guard let client = held.first(where: { $0.id == clientID }) else { continue }
                refresh(client, from: row)
            case .leftAlone:
                continue
            }
        }
        return created
    }

    static func summary(of actions: [ClientImportAction]) -> ClientImportSummary {
        var summary = ClientImportSummary()
        for action in actions {
            switch action {
            case .create: summary.created += 1
            case .update: summary.updated += 1
            case .leftAlone: summary.leftAlone += 1
            }
        }
        return summary
    }

    // MARK: the two halves of ownership

    /// Everything Downbeat owns is taken from the row; the one thing Ovation owns
    /// is only filled where Ovation has nothing.
    private static func refresh(_ client: Client, from row: DownbeatExport.Client) {
        client.name = row.displayName
        client.email = row.email
        client.contractEmail = row.contractEmail

        // LEARNING THE KEY. A client matched by address carries no Downbeat id
        // yet, and stamping it here is what makes every later run match on the
        // basis that cannot drift (ovation#34).
        client.downbeatClientID = row.id

        // THE ONE FIELD OVATION OWNS. Filled only where nothing has been recorded
        // here, so the roster pass stays cleared across launches. Note this is
        // also correct when the ROW carries nothing: a client answered here must
        // not be reset by an absence upstream, which is 25 of 31 rows.
        if client.taxStatus == .neverRecorded, let upstream = row.isTaxExempt {
            client.taxStatus = upstream ? .exempt : .notExempt
        }
    }

    /// Downbeat's three states to Ovation's three. Absent is `neverRecorded` and
    /// never `notExempt`: a missing value must not report a client as confirmed
    /// taxable, which is the distinction the whole roster pass rests on (PRD 5,
    /// L257).
    private static func status(of isTaxExempt: Bool?) -> TaxStatus {
        switch isTaxExempt {
        case .some(true): return .exempt
        case .some(false): return .notExempt
        case .none: return .neverRecorded
        }
    }
}
