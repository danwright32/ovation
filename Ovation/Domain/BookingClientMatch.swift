// ovation#34. Which of Ovation's clients a queued booking names.
//
// MORE THAN ONE MATCH IS ITS OWN REFUSAL, never treated as no match, and that is
// the whole reason this is a type rather than a fetch at a call site. The two
// need opposite work: no match means create or ask, several means the data is
// ambiguous and a guess invoices the wrong customer. A lookup that requires
// exactly one result must refuse on many (L521).
//
// AND IT MAY NEVER SILENTLY TAKE THE FIRST. Ordering a result set and taking the
// head turns "which client" into "whichever the store happened to return", and a
// collection read from a store carries no order unless the read declares one
// (L343).
//
// WHY THE COST OF GETTING THIS WRONG COMPOUNDS. The create-new path manufactures
// a duplicate identity that every later invoice, payment and referral credit
// then feeds, and nothing downstream can tell the two apart afterwards. That is
// why an ambiguous booking waits rather than guessing.
//
// THE VALUES IN A QUEUED RECORD ARE FROZEN AT COMMIT TIME, deliberately (Dan,
// 2026-08-27), so that a client edited or removed after the commit does not
// change what an unconsumed record resolves to. Two consequences the matching
// order is built on: `clientId` is the STABLE thing, and a match on
// `displayName` can legitimately fail for a client whose name has since changed.
//
// AN EMPTY CONTRACT EMAIL IS NOT A MATCH CANDIDATE AT ALL. Matching on an empty
// string would link every client with no recorded address to each other, which
// measured against the real roster is 25 of 31 (ovation#40).
import Foundation

/// What matching a queued booking's client came to.
enum BookingClientMatch: Equatable {
    /// Downbeat's stable identifier, or an address, found exactly one client.
    case matched(clientID: UUID, on: Basis)
    /// Nothing matched. The caller creates a client from what the record carries.
    case noMatch
    /// Several clients matched. It WAITS, and names them, because a guess here
    /// manufactures a duplicate identity that compounds silently.
    case ambiguous(clientIDs: [UUID], on: Basis)

    /// What the match was made on, so a caller can tell an automatic link from
    /// one that needs confirming, and so a refusal can say what was ambiguous.
    enum Basis: String, Equatable {
        /// Downbeat's own id, stored on the client. The only basis that cannot
        /// drift, and the only one that links without asking.
        case downbeatIdentifier
        /// A contract or main email. Links automatically when exactly one
        /// client has it, because an address is specific enough to be a person.
        case emailAddress
        /// The display name only. Enough to propose, never enough to link
        /// silently, because two clients can legitimately share a name.
        case nameOnly
    }

    /// Whether this outcome may proceed without asking Dan.
    ///
    /// A NAME ONLY MATCH IS NOT AUTOMATIC even though it found exactly one, which
    /// is the distinction that stops a rename or a namesake quietly attaching a
    /// shoot to the wrong client.
    var linksWithoutAsking: Bool {
        switch self {
        case .matched(_, let basis): return basis != .nameOnly
        case .noMatch, .ambiguous: return false
        }
    }
}

enum BookingClientMatcher {

    /// One normalisation, used by every comparison here, so two spellings of one
    /// value cannot be treated as two candidates and then collide on one stored
    /// key (L185).
    static func normalised(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    /// Resolve a queued booking's client against the clients Ovation holds.
    ///
    /// THE ORDER IS THE RULE: the stable identifier, then an address, then the
    /// name. Each is tried only when the one before it found nothing, so a
    /// weaker basis can never override a stronger one, and an AMBIGUITY at any
    /// level stops there rather than falling through to a weaker basis that
    /// happens to be decisive. Falling through would resolve "two clients share
    /// this address" by picking whichever of them has the matching name, which
    /// is a guess wearing the appearance of a rule.
    static func match(
        downbeatClientID: UUID?,
        displayName: String?,
        emails: [String],
        against clients: [Client]
    ) -> BookingClientMatch {
        if let downbeatClientID {
            let byID = clients.filter { $0.downbeatClientID == downbeatClientID }
            if byID.count == 1 { return .matched(clientID: byID[0].id, on: .downbeatIdentifier) }
            if byID.count > 1 {
                return .ambiguous(clientIDs: byID.map(\.id).sorted { $0.uuidString < $1.uuidString },
                                  on: .downbeatIdentifier)
            }
        }

        // EVERY ADDRESS THE RECORD CARRIES, because Downbeat sends a main and a
        // contract address and either can be the one Ovation knows. Empty ones
        // are dropped BEFORE the comparison rather than compared and happening
        // not to match, so nothing rests on an empty string never being equal.
        let wanted = Set(emails.compactMap(normalised))
        if !wanted.isEmpty {
            let byEmail = clients.filter { client in
                let held = Set([client.email, client.contractEmail].compactMap(normalised))
                return !held.isDisjoint(with: wanted)
            }
            if byEmail.count == 1 { return .matched(clientID: byEmail[0].id, on: .emailAddress) }
            if byEmail.count > 1 {
                return .ambiguous(
                    clientIDs: byEmail.map(\.id).sorted { $0.uuidString < $1.uuidString },
                    on: .emailAddress)
            }
        }

        if let wantedName = normalised(displayName) {
            let byName = clients.filter { normalised($0.name) == wantedName }
            if byName.count == 1 { return .matched(clientID: byName[0].id, on: .nameOnly) }
            if byName.count > 1 {
                return .ambiguous(
                    clientIDs: byName.map(\.id).sorted { $0.uuidString < $1.uuidString },
                    on: .nameOnly)
            }
        }

        return .noMatch
    }
}
