import Foundation
import Testing

/// ovation#62, PRD 5.19a. Every expense category maps to a Schedule C line, and
/// nothing may land on a default branch.
///
/// COMPLETENESS IS THE COMPILER'S JOB HERE, and that is stronger than a test. The
/// switch in `ExpenseCategory.scheduleC` is exhaustive with no default, so adding
/// a category fails the BUILD. Seen to fail before it was trusted: a
/// `studioRent` case was added to `ExpenseCategory` on 2026-09-08 and the build
/// answered
///
///     Ovation/Domain/ScheduleCMap.swift:105:9: error: switch must be exhaustive
///
/// which names the file and the line rather than merely reporting that something
/// broke (L154). The case was then removed.
///
/// So what these tests cover is everything the compiler cannot: that no mapping
/// is a placeholder, that a provisional one says what it is waiting on, and that
/// the provisional ones are exactly the two the PRD has open questions about.
struct ScheduleCMapTests {

    @Test("every category has a mapping, and the map is derived from the vocabulary")
    func everyCategoryMaps() {
        // The map cannot be short, because it is built from `allCases` rather
        // than from a second list beside the switch (L41).
        #expect(ScheduleCMap.all.count == ExpenseCategory.allCases.count)
        #expect(ScheduleCMap.all.map(\.category) == ExpenseCategory.allCases)
        #expect(ScheduleCMap.all.allSatisfy { ExpenseCategory.allCases.contains($0.category) })
    }

    @Test("the unambiguous categories are settled, and they are the ones you would expect")
    func thesettledOnesAreSettled() {
        #expect(ExpenseCategory.marketing.scheduleC == .settled(.advertising))
        #expect(ExpenseCategory.contractLabour.scheduleC == .settled(.contractLabour))
        #expect(ExpenseCategory.insurance.scheduleC == .settled(.insurance))
        #expect(ExpenseCategory.professionalFees.scheduleC == .settled(.legalAndProfessional))
        #expect(ExpenseCategory.travel.scheduleC == .settled(.travel))
        #expect(ExpenseCategory.meals.scheduleC == .settled(.deductibleMeals))
    }

    @Test("meals are their OWN line, never folded into travel")
    func mealsAreNotTravel() {
        // 24a and 24b are two lines on one row of the form, and meals are
        // deductible at a different rate. Folding them together changes the
        // return, which is why this is asserted rather than left to the reader.
        #expect(ExpenseCategory.meals.scheduleC.line != ExpenseCategory.travel.scheduleC.line)
        #expect(ExpenseCategory.meals.scheduleC.line.rawValue == "24b")
        #expect(ExpenseCategory.travel.scheduleC.line.rawValue == "24a")
    }

    @Test("exactly TWO mappings are provisional, and they are gear and software")
    func theprovisionalOnesAreNamed() {
        // A provisional mapping that quietly becomes settled, because somebody
        // removed the marker or added a category and copied a neighbour, is the
        // failure this shape exists to prevent. The count is asserted so a third
        // one cannot appear unnoticed and neither of these two can vanish.
        let provisional = ScheduleCMap.provisional.map(\.category)
        #expect(Set(provisional) == [.gear, .software])
        #expect(provisional.count == 2)
    }

    @Test("a provisional mapping names WHAT it is waiting on, not merely that it is unsure")
    func eachprovisionalOneCarriesItsQuestion() {
        // "Provisional" with no question attached is a flag nobody can clear.
        for (category, pending) in ScheduleCMap.provisional {
            #expect(!pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    Comment(rawValue: "\(category) is provisional and says nothing about why"))
            #expect(pending.count > 40,
                    Comment(rawValue: "\(category)'s question is too short to act on"))
        }
        let gear = try? #require(ScheduleCMap.provisional.first { $0.category == .gear }?.pending)
        #expect(gear?.contains("9.4") == true, "the asset threshold is PRD 9.4's question")
        #expect(gear?.contains("Depreciation") == true, "and it names the other line it could be")
    }

    @Test("a provisional mapping still produces a LINE, so the export is not blocked")
    func aprovisionalMappingStillWorks() {
        // The export has to run before the accountant conversation happens, and a
        // provisional mapping that produced nothing would make an empty column
        // indistinguishable from a category nobody spent anything in (L98).
        #expect(ExpenseCategory.gear.scheduleC.line == .supplies)
        #expect(ExpenseCategory.software.scheduleC.line == .officeExpense)
        #expect(ScheduleCMap.all.allSatisfy { ScheduleCLine.allCases.contains($0.mapping.line) })
    }

    @Test("every line carries a title and a label that names the line number")
    func everyLineReadsAsTheFormReadsIt() {
        // The number alone makes the reader look up the title, and the title
        // alone makes them look up the number.
        for line in ScheduleCLine.allCases {
            #expect(!line.title.isEmpty)
            #expect(line.exportLabel.hasPrefix(line.rawValue))
            #expect(line.exportLabel.hasSuffix(line.title))
        }
    }

    @Test("no two lines share a number, since the number is what an accountant reads")
    func thelineNumbersAreDistinct() {
        let numbers = ScheduleCLine.allCases.map(\.rawValue)
        #expect(Set(numbers).count == numbers.count)
    }

    @Test("several categories MAY share a line, and nothing here forbids it")
    func sharingALineIsAllowed() {
        // Stated as a test rather than a comment because the opposite rule looks
        // plausible: an implementer adding a uniqueness assertion here would
        // break the first time two of Dan's categories legitimately land on
        // Other expenses.
        let lines = ScheduleCMap.all.map(\.mapping.line)
        #expect(lines.count == ExpenseCategory.allCases.count)
        #expect(Set(lines).count <= lines.count)
    }
}
