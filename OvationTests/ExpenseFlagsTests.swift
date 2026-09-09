import Foundation
import SwiftData
import Testing

/// ovation#82, PRD 5.20 and 9.4. The two flags that are not categories.
///
/// WHY THEY ARE FLAGS. An expense is ONE category and can independently be an
/// asset or a suspected duplicate. Making either a category forces a choice
/// between two facts that are both true.
///
/// THE ASSET THRESHOLD IS A SUGGESTION AND NOT A DETERMINATION, and it rests on
/// a question nobody has answered: PRD 9.4 asks whether the threshold applies per
/// item or per receipt total, and whether Section 179 makes it moot. So Ovation
/// SUGGESTS, Dan decides, and the suggestion never overwrites the decision.
///
/// THE DUPLICATE FLAG IS A SUSPICION AND NOT A VERDICT. Two receipts from one
/// vendor on one day for one amount are usually a duplicate and sometimes two
/// genuine purchases, so it flags rather than decides, and the answer "these are
/// both real" STICKS: a rule that goes on asking a question after it has been
/// answered leaves nothing that could ever satisfy it (L330, L269).
struct ExpenseFlagsTests {

    // MARK: the asset suggestion

    @Test("an amount at the threshold suggests an asset, and one below it does not")
    func thesuggestionIsMadeAtTheThreshold() throws {
        // Both sides of the line, so a change to the number is a change to a test
        // rather than a silent widening (L172).
        let world = try World()
        let at = world.expense(amount: AssetThreshold.inForce.amount)
        let below = world.expense(amount: AssetThreshold.inForce.amount - Money(cents: 1))

        #expect(at.suggestsAsset)
        #expect(!below.suggestsAsset)
        #expect(at.isAsset)
        #expect(!below.isAsset)
    }

    @Test("the threshold says it is PROVISIONAL and names the question it waits on")
    func thethresholdIsVisiblyProvisional() {
        // PRD 9.4, one of the five questions carried into the accountant
        // conversation (ovation#65). A threshold that reads as settled is one
        // nobody re-examines, and this one was never measured (L316, L182).
        #expect(AssetThreshold.inForce.isProvisional)
        #expect(AssetThreshold.inForce.pendingQuestion.contains("9.4"))
        #expect(!AssetThreshold.inForce.pendingQuestion.isEmpty)
    }

    @Test("Dan's decision wins in BOTH directions, and the suggestion does not overwrite it")
    func thedecisionOverridesTheSuggestion() throws {
        // A default re-derived from a sibling field hides itself: the values it
        // produces vary and read as entered (L432). Here the decision is stored
        // separately from the amount, so a suggestion can never quietly replace
        // an answer, and a later edit to the amount cannot either.
        let world = try World()
        let expensive = world.expense(amount: Money(dollars: 4_000))
        let cheap = world.expense(amount: Money(dollars: 20))

        expensive.assetJudgement = .notAnAsset
        cheap.assetJudgement = .treatAsAsset

        #expect(!expensive.isAsset, "Dan said it is not one")
        #expect(cheap.isAsset, "and that this one is")
        #expect(expensive.suggestsAsset, "the suggestion is still visible beside the answer")
        #expect(!cheap.suggestsAsset)
    }

    @Test("an expense nobody has judged says so, rather than reading as a decision")
    func anundecidedExpenseSaysSo() throws {
        let world = try World()
        let expense = world.expense(amount: Money(dollars: 4_000))
        #expect(expense.assetJudgement == .notDecided)
        #expect(expense.isAsset, "and the suggestion stands until it is answered")
    }

    // MARK: what the flag actually changes

    @Test("an asset is reported on the depreciation line, not on its category's line")
    func anassetMovesToDepreciation() throws {
        // The flag has to CHANGE something or it is a field nothing reads (L46).
        // `ScheduleCMap` records that gear maps provisionally to Supplies and that
        // the asset flag is what moves an individual expense to line 13.
        let world = try World()
        let expense = world.expense(amount: Money(dollars: 4_000), category: .gear)

        #expect(expense.isAsset)
        #expect(expense.scheduleCLine == .depreciation)
        #expect(ExpenseCategory.gear.scheduleC.line == .supplies,
                "and its category still says what it would be otherwise")
    }

    @Test("an ordinary expense is reported on its category's line")
    func anordinaryExpenseKeepsItsCategoryLine() throws {
        let world = try World()
        let expense = world.expense(amount: Money(dollars: 20), category: .gear)

        #expect(!expense.isAsset)
        #expect(expense.scheduleCLine == .supplies)
    }

    @Test("an expense with no category has no line, rather than a guessed one")
    func anuncategorisedExpenseHasNoLine() throws {
        let world = try World()
        let expense = world.expense(amount: Money(dollars: 20), category: nil)
        #expect(expense.scheduleCLine == nil)
    }

    @Test("an ASSET with no category is still an asset, and still lands on line 13")
    func anuncategorisedAssetStillHasALine() throws {
        // The one case where a line can be known without a category: the flag
        // says which line it is, whatever the category would have said.
        let world = try World()
        let expense = world.expense(amount: Money(dollars: 4_000), category: nil)
        #expect(expense.scheduleCLine == .depreciation)
    }

    @Test("the year end export writes the EXPENSE's line, not its category's")
    func theexportReadsTheFlag() throws {
        // Otherwise the flag changes nothing anybody sees, which is the failure
        // this is guarding against rather than a tidy-up (L46, L402).
        let world = try World()
        let asset = world.expense(amount: Money(dollars: 4_000), category: .gear,
                                  on: "2026-03-01")

        let export = TaxExport.expenses(from: [asset], in: .calendarYear(2026))
        let column = try #require(export.document.header.firstIndex(of: "Schedule C line"))
        let rendered: String
        switch export.document.rows[0][column] {
        case .text(let value), .formatted(let value): rendered = value
        }

        #expect(rendered == ScheduleCLine.depreciation.exportLabel)
    }

    @Test("the export says whether a row is an asset, because the line alone does not")
    func theexportCarriesTheFlag() throws {
        // Two expenses can land on line 13 for different reasons once other
        // categories map there, and the accountant's question is about the FLAG.
        let world = try World()
        let asset = world.expense(amount: Money(dollars: 4_000), category: .gear,
                                  on: "2026-03-01")
        let ordinary = world.expense(amount: Money(dollars: 20), category: .gear,
                                     on: "2026-03-02")

        let export = TaxExport.expenses(from: [asset, ordinary], in: .calendarYear(2026))
        let column = try #require(export.document.header.firstIndex(of: "Asset"))
        let values = export.document.rows.map { row -> String in
            switch row[column] {
            case .text(let value), .formatted(let value): return value
            }
        }
        #expect(values == ["Yes", ""])
    }

    // MARK: the duplicate suspicion

    @Test("same vendor, same amount, same day is a suspected duplicate")
    func thesuspicionKeysOnTheThreeThings() throws {
        let world = try World()
        let first = world.expense(amount: Money(dollars: 30), vendor: "A camera shop",
                                  on: "2026-03-01")
        let second = world.expense(amount: Money(dollars: 30), vendor: "A camera shop",
                                   on: "2026-03-01")

        let groups = DuplicateSuspicion.groups(in: [first, second])

        #expect(groups.count == 1)
        #expect(groups.first?.count == 2)
    }

    @Test("a different amount, day or vendor is not suspected")
    func onedifferenceIsEnoughToBeUnsuspicious() throws {
        let world = try World()
        let base = world.expense(amount: Money(dollars: 30), vendor: "A camera shop",
                                 on: "2026-03-01")
        let otherAmount = world.expense(amount: Money(dollars: 31), vendor: "A camera shop",
                                        on: "2026-03-01")
        let otherDay = world.expense(amount: Money(dollars: 30), vendor: "A camera shop",
                                     on: "2026-03-02")
        let otherVendor = world.expense(amount: Money(dollars: 30), vendor: "A print shop",
                                        on: "2026-03-01")

        #expect(DuplicateSuspicion.groups(in: [base, otherAmount, otherDay, otherVendor]).isEmpty)
    }

    @Test("the vendor is matched ignoring case and surrounding space, because a receipt is typed")
    func thevendorMatchIsForgiving() throws {
        let world = try World()
        let first = world.expense(amount: Money(dollars: 30), vendor: "A Camera Shop",
                                  on: "2026-03-01")
        let second = world.expense(amount: Money(dollars: 30), vendor: "  a camera shop ",
                                   on: "2026-03-01")

        #expect(DuplicateSuspicion.groups(in: [first, second]).count == 1)
    }

    @Test("an expense with NO vendor is never suspected, and that is deliberate")
    func novendorMeansNoSuspicion() throws {
        // The rule keys on vendor plus amount plus date. Treating a missing
        // vendor as a value would match every unfiled receipt of the same amount
        // on one day against every other, which is a suspicion about nothing
        // (L185: two spellings that normalize to the same thing).
        let world = try World()
        let first = world.expense(amount: Money(dollars: 30), vendor: nil, on: "2026-03-01")
        let second = world.expense(amount: Money(dollars: 30), vendor: nil, on: "2026-03-01")

        #expect(DuplicateSuspicion.groups(in: [first, second]).isEmpty)
    }

    @Test("three identical receipts are ONE group of three, not three pairs")
    func threeIdenticalAreOneGroup() throws {
        let world = try World()
        let expenses = (0..<3).map { _ in
            world.expense(amount: Money(dollars: 30), vendor: "A camera shop", on: "2026-03-01")
        }

        let groups = DuplicateSuspicion.groups(in: expenses)

        #expect(groups.count == 1)
        #expect(groups.first?.count == 3)
    }

    @Test("saying they are BOTH REAL silences the suspicion, and it sticks")
    func theacknowledgementSticks() throws {
        // A finding the system cannot verify was acted on must carry its own way
        // to be settled, or it stands after the work is done and teaches Dan to
        // ignore the whole surface (L269, L330).
        let world = try World()
        let first = world.expense(amount: Money(dollars: 30), vendor: "A camera shop",
                                  on: "2026-03-01")
        let second = world.expense(amount: Money(dollars: 30), vendor: "A camera shop",
                                   on: "2026-03-01")
        #expect(DuplicateSuspicion.groups(in: [first, second]).count == 1)

        DuplicateSuspicion.acknowledgeBothAreReal([first, second],
                                                  on: .stamping(Self.instant))

        #expect(DuplicateSuspicion.groups(in: [first, second]).isEmpty)
        #expect(first.bothAreRealAcknowledgedOn != nil)
        #expect(second.bothAreRealAcknowledgedOn != nil)
    }

    @Test("acknowledging one of a PAIR ends the pair, and one of three leaves the other two")
    func anacknowledgementRemovesOnlyItsOwnMember() throws {
        // The suspicion is about a pair, so removing one member leaves nothing to
        // suspect. With three, two still are, which is the case a rule written as
        // "silence the whole group" would get wrong.
        let world = try World()
        let expenses = (0..<3).map { _ in
            world.expense(amount: Money(dollars: 30), vendor: "A camera shop", on: "2026-03-01")
        }

        DuplicateSuspicion.acknowledgeBothAreReal([expenses[0]], on: .stamping(Self.instant))

        let groups = DuplicateSuspicion.groups(in: expenses)
        #expect(groups.count == 1)
        #expect(groups.first?.count == 2)

        DuplicateSuspicion.acknowledgeBothAreReal([expenses[1]], on: .stamping(Self.instant))
        #expect(DuplicateSuspicion.groups(in: expenses).isEmpty)
    }

    @Test("a suspected expense says so on itself, so a surface does not have to group")
    func anexpenseCanAnswerForItself() throws {
        let world = try World()
        let first = world.expense(amount: Money(dollars: 30), vendor: "A camera shop",
                                  on: "2026-03-01")
        let second = world.expense(amount: Money(dollars: 30), vendor: "A camera shop",
                                   on: "2026-03-01")
        let alone = world.expense(amount: Money(dollars: 99), vendor: "A print shop",
                                  on: "2026-03-01")

        let suspected = DuplicateSuspicion.suspected(in: [first, second, alone])

        #expect(suspected.count == 2)
        #expect(!suspected.contains { $0.id == alone.id })
    }

    // MARK: every category still maps to a line

    @Test("every category has a Schedule C mapping, with no default branch to hide in")
    func everyCategoryIsMapped() {
        // ovation#62 already enforces this over the enum. Repeated here because
        // this issue is the one that adds categories, and a category added
        // without a mapping must fail rather than take a default (L113).
        for category in ExpenseCategory.allCases {
            _ = category.scheduleC.line
        }
        #expect(ExpenseCategory.allCases.count >= 8)
    }

    // MARK: fixtures

    private static let instant = Date(timeIntervalSince1970: 1_800_000_000)

    private final class World {
        let context: ModelContext

        init() throws {
            context = ModelContext(try OvationSchema.container(inMemory: true))
        }

        @discardableResult
        func expense(amount: Money, category: ExpenseCategory? = .gear,
                     vendor: String? = "A vendor", on dayKey: String = "2026-03-01") -> Expense {
            let instant = BusinessCalendar.startOfDay(forDayKey: dayKey)!
            let expense = Expense(amount: amount, incurredOn: .stamping(instant),
                                  receipt: .noneRecorded)
            expense.category = category
            expense.vendor = vendor
            context.insert(expense)
            return expense
        }
    }
}
