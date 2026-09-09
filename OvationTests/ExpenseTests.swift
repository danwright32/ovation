import Foundation
import SwiftData
import Testing

/// ovation#60 step 3c. What Ovation spent, which is the other half of the export.
struct ExpenseTests {

    /// 2026-11-12 America/New_York.
    private static let day = Date(timeIntervalSince1970: 1_794_531_600)

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    private static func expense(
        _ context: ModelContext,
        _ amount: Money = Money(dollars: 40),
        receipt: ReceiptEvidence = .noneRecorded
    ) -> Expense {
        let expense = Expense(amount: amount, incurredOn: .stamping(day), receipt: receipt)
        context.insert(expense)
        return expense
    }

    // MARK: what an expense is

    @Test("an expense carries its amount, its day and its category")
    func anExpenseCarriesWhatTheExportNeeds() throws {
        let context = try Self.store()
        let expense = Self.expense(context, Money(cents: 4_299))
        expense.vendor = "A shop"
        expense.category = .software
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        #expect(read.amount == Money(cents: 4_299))
        #expect(read.incurredOn.dayKey == BusinessCalendar.dayKey(for: Self.day))
        #expect(read.category == .software)
    }

    @Test("a category can be absent, because a receipt arrives before anybody has filed it")
    func aCategoryCanBeAbsent() throws {
        let context = try Self.store()
        let expense = Self.expense(context)
        #expect(expense.category == nil)
        #expect(expense.needsACategory, "and the expense SAYS so rather than picking one")
    }

    // MARK: the receipt, which is three situations and not a boolean

    @Test("an expense with a receipt names the file by hash, never by a path alone")
    func aFiledReceiptIsAddressedByHash() throws {
        let context = try Self.store()
        let expense = Self.expense(context, receipt: .file(
            sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            relativePath: "2026/11/a-receipt.pdf"))
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        #expect(read.hasReceipt)
        #expect(read.receiptHash != nil, "the backup enumerates every referenced document by hash")
        #expect(read.receiptMissingNote.isEmpty, "there is nothing missing to say anything about")
    }

    @Test("no receipt and no receipt BECAUSE it was imported are different, and both reach the CSV")
    func theTwoWaysOfHavingNoReceiptStayApart() throws {
        let context = try Self.store()
        let filedWithout = Self.expense(context, receipt: .noneRecorded)
        let imported = Self.expense(context, receipt: .importedWithoutOne)

        #expect(!filedWithout.hasReceipt)
        #expect(!imported.hasReceipt)
        #expect(filedWithout.receipt != imported.receipt,
                "PRD 5.21 and 5.28 are different marks and the export tells them apart")
        #expect(filedWithout.receiptMissingNote != imported.receiptMissingNote)
        #expect(!filedWithout.receiptMissingNote.isEmpty)
    }

    @Test("an expense with a receipt has nothing to note about a missing one")
    func aFiledReceiptNotesNothing() throws {
        let context = try Self.store()
        let expense = Self.expense(context, receipt: .file(
            sha256: "abc", relativePath: "2026/11/a-receipt.pdf"))
        #expect(expense.receiptMissingNote.isEmpty)
    }

    // MARK: identity, and the keys that are never it

    @Test("the re-filing key is the message, the file's own hash and the part index together")
    func theRefilingKeyIsRecomputable() throws {
        let context = try Self.store()
        let expense = Self.expense(context, receipt: .file(sha256: "abc123", relativePath: "a.pdf"))
        expense.gmailMessageKey = "18f2c4"
        expense.attachmentPartIndex = 2

        #expect(expense.intakeKey == "18f2c4:abc123:2")
    }

    @Test("two attachments in one message are two expenses, told apart by their part index")
    func twoAttachmentsAreTwoExpenses() throws {
        let context = try Self.store()
        let first = Self.expense(context, receipt: .file(sha256: "same", relativePath: "a.pdf"))
        let second = Self.expense(context, receipt: .file(sha256: "same", relativePath: "b.pdf"))
        first.gmailMessageKey = "18f2c4"
        second.gmailMessageKey = "18f2c4"
        first.attachmentPartIndex = 0
        second.attachmentPartIndex = 1

        #expect(first.intakeKey != second.intakeKey,
                "two identical attachments in one message must not collapse into one expense")
    }

    @Test("an expense with nothing to key on has no intake key at all, rather than a plausible one")
    func anExpenseWithNoSourceHasNoKey() throws {
        let context = try Self.store()
        #expect(Self.expense(context).intakeKey == nil,
                "an expense Dan typed in came from no message and must not look like one that did")
    }

    @Test("two expenses from the same message and hash are two rows, not one replacing the other")
    func anExternalKeyNeverBecomesTheIdentity() throws {
        let context = try Self.store()
        let first = Self.expense(context, receipt: .file(sha256: "abc", relativePath: "a.pdf"))
        let second = Self.expense(context, receipt: .file(sha256: "abc", relativePath: "a.pdf"))
        first.gmailMessageKey = "18f2c4"
        second.gmailMessageKey = "18f2c4"
        first.attachmentPartIndex = 0
        second.attachmentPartIndex = 0
        try context.save()

        let all = try context.fetch(FetchDescriptor<Expense>())
        #expect(all.count == 2, "the duplicate is visible so something can refuse it")
        #expect(Set(all.map(\.id)).count == 2)
    }
}
