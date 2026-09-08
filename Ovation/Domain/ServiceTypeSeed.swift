// ovation#107, PRD 5.4. The service types a fresh installation starts with.
//
// WHY THIS IS NOT IN LineItem.swift BESIDE THE MODEL. A `startingList()` was
// written there during ovation#60 and removed in the same change, because
// nothing seeded a store yet and a seeder nobody calls is dead code that its own
// docstring turns into a decision nobody revisits (L29, L346). It comes back
// here, with the launch sequence that calls it, and not before.
//
// SEEDING RUNS ON AN EMPTY STORE AND NEVER AGAIN, and that is the part worth
// getting right rather than the list. The NAME of a type is Dan's, and PRD 5.4
// lets him rename one from inside an invoice. A seeder that ran on every launch
// would undo that rename with no symptom except the name reverting.
//
// THE CONDITION IS "NO SERVICE TYPE AT ALL", not "these three are missing". A
// store Dan has already shaped is his, and seeding into it would put back rows
// he retired or add ones he never wanted. A RETIRED type still counts as
// present, which is the case that makes the distinction real: PRD 5.30 retires
// rather than deletes, so retiring all three leaves three rows, and a condition
// written as "no ACTIVE type" would put back exactly what he had just retired.
//
// IT IS ONE SAVE. Saving per type and failing halfway would leave rows in the
// store, so the next launch would find the store non empty and never seed the
// rest: the missing one would be missing forever, and nothing would report it
// (L368).
import Foundation
import SwiftData

extension ServiceType {

    /// PRD 5.4's proposed starting list.
    ///
    /// NO DEFAULT AMOUNT ON ANY OF THEM, and that is a decision rather than an
    /// omission. PRD 5.3's $250 per hour belongs to whatever the invoice freezes
    /// its rate from, and `LineItem.hourly(hours:at:)` takes that frozen rate, so
    /// copying it onto the service type as well would give one fact two homes and
    /// let the two drift with nothing reporting it (L83). Rush turnaround and
    /// preview images have no amount recorded anywhere, so nil here is the truth
    /// rather than a placeholder standing in for one (L548).
    ///
    /// THE REFERRAL CREDIT IS NOT HERE. It was in PRD 5.4's list until round 6 of
    /// ovation#111 took the credit out of the line items (ovation#126). With no
    /// credit line there is nothing a credit service type could be chosen for, so
    /// it would be a picker entry that no line can legitimately use (L611).
    static func startingList() -> [ServiceType] {
        [
            ServiceType(name: "Photography", role: .hourlyPhotography, defaultUnitAmount: nil),
            ServiceType(name: "Rush turnaround", role: .ordinary, defaultUnitAmount: nil),
            ServiceType(name: "Preview images", role: .ordinary, defaultUnitAmount: nil),
        ]
    }
}

enum ServiceTypeSeed {

    /// Puts the starting list into a store that holds no service type at all.
    ///
    /// Returns how many were inserted, which is 0 on every launch after the
    /// first. The count is returned rather than a Bool so a caller can say what
    /// happened: "seeded 3" and "already had some" are different facts, and a
    /// seeder that reports nothing is one nobody can tell ran (L98).
    @discardableResult
    static func seedIfEmpty(_ context: ModelContext) throws -> Int {
        var anyAtAll = FetchDescriptor<ServiceType>()
        anyAtAll.fetchLimit = 1
        guard try context.fetch(anyAtAll).isEmpty else { return 0 }

        let list = ServiceType.startingList()
        for type in list { context.insert(type) }
        try context.save()
        return list.count
    }
}
