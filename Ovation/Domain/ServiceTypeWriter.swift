// ovation#457, PRD 5.4. Making a service type from inside an invoice.
//
// A SCREEN NEVER WRITES, AN ACTOR DOES (PRD 51l, ovation#440), the shape every
// other writer on this screen uses.
//
// THE ROLE IS CODE'S AND NOT DAN'S, which is why the panel has no third field.
// `ServiceRole.hourlyPhotography` is what the invoice's own pricing switches on,
// exactly one type is that line, and a second would make the pricing ambiguous
// (LineItem.swift). So everything made here is ordinary, and that is a decision
// recorded in the design record rather than a field nobody got round to.
//
// IT TAKES NO MONEY GATE, and that is deliberate rather than an oversight. A
// service type is not money against an invoice: it carries a usual amount that
// prefills a field, and nothing derived from an invoice's total changes when one
// is created. The gate exists to serialize writers whose decisions are made from
// `amountOutstanding` (ovation#175), and this makes no such decision.
//
// A NAME IS THE WHOLE IDENTITY OF A TYPE on every surface that shows one: the
// list offers types by name and a line records the name it was given. Two types
// with one name are one vocabulary with a collision in it, so a duplicate is
// refused rather than allowed and told apart by an identifier nobody can see
// (L131, L185).
import Foundation
import SwiftData

@ModelActor
actor ServiceTypeWriter {

    /// Records a new service type and hands back what it made.
    ///
    /// IT RETURNS THE IDENTIFIER because the caller's next act is to use it on
    /// the line it was making. An identifier SUPPLIED to a store is a request
    /// rather than a fact, so the caller reads back the one the store assigned
    /// rather than assuming its own (L127).
    func create(named name: String, usualAmount: Money?) throws -> PersistentIdentifier {
        // TRIMMED ONCE, HERE, and stored that way, because a name with trailing
        // space is a different string everywhere it is compared and the same
        // word everywhere it is drawn (L185).
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { throw ServiceTypeRefusal.nameIsEmpty }

        // A RETIRED TYPE STILL HOLDS ITS NAME. PRD 5.30 retires rather than
        // deletes precisely so that invoices already sent still read correctly,
        // and reusing the name would put two types with one name into the
        // history every report reads.
        let taken = try modelContext.fetch(FetchDescriptor<ServiceType>())
            .contains { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }
        guard !taken else { throw ServiceTypeRefusal.nameIsAlreadyUsed }

        let type = ServiceType(name: wanted, role: .ordinary, defaultUnitAmount: usualAmount)
        modelContext.insert(type)
        try modelContext.save()
        return type.persistentModelID
    }
}

/// Why a service type was not made.
enum ServiceTypeRefusal: Error, Equatable, CaseIterable {
    /// Nothing was typed, or only space was.
    case nameIsEmpty
    /// Another type already answers to that name, retired or not.
    case nameIsAlreadyUsed

    /// What the screen says. Each names what happened rather than only refusing,
    /// because a control that does nothing and gives no reason leaves pressing it
    /// again as the only diagnosis (L109).
    var sentence: String {
        switch self {
        case .nameIsEmpty:
            return "A service type needs a name, so nothing was created."
        case .nameIsAlreadyUsed:
            return "There is already a service type with that name."
        }
    }
}
