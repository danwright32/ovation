import Foundation
import Testing

/// ovation#60. The three closed vocabularies an invoice and a payment store, and
/// the rules each one carries.
///
/// A vocabulary that exists as a constant in code is a picker and never a text
/// box (L611), so each of these is an enum, and each is enumerable so the
/// screens, the export and these tests all derive their list from the same place
/// rather than three hand kept copies (L41).
struct VocabularyTests {

    // MARK: what kind of money an invoice is for (PRD 5.2a, 5.2b)

    @Test("the kinds are the four Dan named plus the one an import has to use")
    func theKindsAreTheFivePRD2aNames() {
        #expect(Set(InvoiceKind.allCases) == [
            .photography, .printSale, .licensing, .other, .notRecorded
        ])
    }

    @Test("every kind has its own export label, so a new one cannot land somewhere plausible")
    func everyKindHasItsOwnExportLabel() {
        let labels = InvoiceKind.allCases.map(\.exportLabel)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == InvoiceKind.allCases.count, "no two kinds share a label")
    }

    @Test("not recorded is the only kind that does not assert what the money was for")
    func notRecordedIsTheOnlyUnrecordedOne() {
        #expect(!InvoiceKind.notRecorded.wasRecorded)
        let recorded = InvoiceKind.allCases.filter(\.wasRecorded)
        #expect(Set(recorded) == [.photography, .printSale, .licensing, .other])
    }

    @Test("an invoice drafted from a booking is photography, which is the default nothing asks about")
    func aBookingIsPhotography() {
        #expect(InvoiceKind.fromABooking == .photography)
    }

    @Test("an imported row is NOT photography, because defaulting it would assert a fact nobody recorded")
    func anImportedRowIsNotPhotography() {
        #expect(InvoiceKind.fromAnImport == .notRecorded)
        #expect(InvoiceKind.fromAnImport != InvoiceKind.fromABooking)
    }

    // MARK: how money arrived (PRD 5.15)

    @Test("the methods are the four Dan takes")
    func theMethodsAreTheFour() {
        #expect(Set(PaymentMethod.allCases) == [.check, .zelle, .venmo, .payPal])
    }

    @Test("a check is the ONLY method that gains a cleared step")
    func onlyAChequeClears() {
        let clearing = PaymentMethod.allCases.filter(\.gainsAClearedStep)
        #expect(clearing == [.check], "one check clears once, and nothing else clears at all")
    }

    @Test("every method has its own export label")
    func everyMethodHasItsOwnExportLabel() {
        let labels = PaymentMethod.allCases.map(\.exportLabel)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == PaymentMethod.allCases.count)
    }

    // MARK: what an expense was for (PRD 5.19)

    @Test("the categories are the eight the PRD proposes, and the Schedule C map is not here")
    func theCategoriesAreTheEight() {
        #expect(Set(ExpenseCategory.allCases) == [
            .gear, .software, .travel, .insurance,
            .contractLabour, .professionalFees, .marketing, .meals
        ])
    }

    @Test("every category has its own export label")
    func everyCategoryHasItsOwnExportLabel() {
        let labels = ExpenseCategory.allCases.map(\.exportLabel)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == ExpenseCategory.allCases.count)
    }

    // MARK: the stored form every one of them takes

    @Test("each vocabulary stores as a stable string, so renaming a case cannot rewrite the store")
    func eachStoresAsAStableString() {
        #expect(InvoiceKind.printSale.rawValue == "print-sale")
        #expect(PaymentMethod.payPal.rawValue == "paypal")
        #expect(ExpenseCategory.contractLabour.rawValue == "contract-labour")
    }
}
