// ovation#82, PRD 5.20. Which expenses look like the same purchase recorded
// twice.
//
// IT IS A SUSPICION AND NOT A VERDICT. Two receipts from one vendor on one day
// for one amount are usually a duplicate and sometimes two genuine purchases, so
// this flags for Dan rather than deciding, and nothing here deletes, merges or
// hides anything.
//
// AND THE ANSWER STICKS. A finding the system cannot verify was acted on must
// carry its own way to be settled, or it stands after the work is done and
// teaches its reader to ignore the whole surface (L269, L330). "These are both
// real" is recorded on the expense and consulted here, so the question is not
// asked again.
//
// A MISSING VENDOR IS NOT A VALUE. The rule keys on vendor plus amount plus date;
// treating an absent vendor as a matchable one would suspect every unfiled
// receipt of the same amount on one day against every other, which is a suspicion
// about nothing. So an expense with no vendor is never suspected, and that is
// stated rather than left to be discovered.
//
// THE VENDOR IS MATCHED FORGIVINGLY, on case and surrounding space, because it is
// typed off a receipt or read by a machine. It is NOT matched loosely beyond
// that: two spellings that differ by a word are two vendors here, because a
// looser rule produces suspicion between unrelated purchases and the cost of that
// falls on Dan every time he opens the queue (L104).
import Foundation

enum DuplicateSuspicion {

    /// What two expenses have to share to be suspected of each other.
    private struct Key: Hashable {
        let vendor: String
        let cents: Int64
        let dayKey: String
    }

    private static func key(for expense: Expense) -> Key? {
        guard let vendor = expense.vendor?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !vendor.isEmpty else { return nil }
        // An acknowledged expense is not in any group, which is what makes the
        // answer stick.
        guard expense.bothAreRealAcknowledgedOn == nil else { return nil }
        return Key(vendor: vendor, cents: expense.amount.cents,
                   dayKey: expense.incurredOn.dayKey)
    }

    /// The groups of expenses that look like one purchase recorded more than
    /// once, each group in a declared order so two runs read the same (L343).
    static func groups(in expenses: [Expense]) -> [[Expense]] {
        var buckets: [Key: [Expense]] = [:]
        for expense in expenses {
            guard let key = key(for: expense) else { continue }
            buckets[key, default: []].append(expense)
        }
        return buckets
            .filter { $0.value.count > 1 }
            .sorted { left, right in
                if left.key.dayKey != right.key.dayKey { return left.key.dayKey < right.key.dayKey }
                if left.key.vendor != right.key.vendor { return left.key.vendor < right.key.vendor }
                return left.key.cents < right.key.cents
            }
            .map { $0.value.sorted { $0.id.uuidString < $1.id.uuidString } }
    }

    /// Every expense that is in some group, for a surface that shows one row at a
    /// time rather than the groups.
    static func suspected(in expenses: [Expense]) -> [Expense] {
        groups(in: expenses).flatMap { $0 }
    }

    /// Records that these are genuinely separate purchases.
    ///
    /// It is written on EACH expense rather than on the group, because there is
    /// no group to write on: the grouping is derived at read time from what the
    /// rows say, so an acknowledgement stored anywhere else would be a second
    /// place the same fact lives (L83).
    static func acknowledgeBothAreReal(_ expenses: [Expense], on day: BusinessDate) {
        for expense in expenses {
            expense.bothAreRealAcknowledgedOn = day
        }
    }
}
