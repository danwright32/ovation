import Foundation
import Testing

/// ovation#167, PRD 50c. How money, hours and dates are WRITTEN on the invoice PDF.
///
/// THE CASES ARE THE DESIGN RECORD'S OWN, read from
/// `docs/design/rules/pdf-text.cases.json`, the file the design's rule is tested
/// against by `scripts/test-design-rules.sh`. Two implementations of one
/// formatting rule, each tested against cases of its own, agree on the day they
/// are written and then drift, and the page the client receives is where it would
/// show (L26). Dates are the one exception: the design writes them as literal
/// text, so only the app formats one and their cases live here.
struct PDFTextTests {

    private struct MoneyCase: Decodable { let cents: Int64; let text: String; let why: String }
    private struct HoursCase: Decodable { let hundredths: Int64; let text: String; let why: String }
    private struct HourlyCase: Decodable {
        let hundredths: Int64; let rateCents: Int64; let amountCents: Int64; let why: String
    }
    private struct Cases: Decodable {
        let money: [MoneyCase]
        let hours: [HoursCase]
        let hourly: [HourlyCase]
    }

    /// Located from this file, never from the working directory, which is wherever
    /// the test runner happened to start (L372).
    private static func cases(_ file: StaticString = #filePath) throws -> Cases {
        let repository = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repository.appending(path: "docs/design/rules/pdf-text.cases.json")
        return try JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
    }

    @Test("the shared cases are read and hold something, so no test below runs over nothing")
    func theSharedCasesAreThere() throws {
        let cases = try Self.cases()
        #expect(cases.money.count >= 8)
        #expect(cases.hours.count >= 9)
        #expect(cases.hourly.count >= 4)
    }

    @Test("money is written the way the settled invoice PDF writes it")
    func moneyIsWrittenAsTheDesignWritesIt() throws {
        for item in try Self.cases().money {
            #expect(PDFText.money(Money(cents: item.cents)) == item.text, "\(item.why)")
        }
    }

    @Test("hours are written the way the settled invoice PDF writes them")
    func hoursAreWrittenAsTheDesignWritesThem() throws {
        for item in try Self.cases().hours {
            #expect(PDFText.hours(Hours(hundredths: item.hundredths)) == item.text, "\(item.why)")
        }
    }

    /// PRD 50c: the client can reconstruct every figure. So the hours AS PRINTED,
    /// read back, times the rate must be the amount, which is exactly what a
    /// one decimal spelling of a quarter hour broke.
    @Test("on every hourly line the printed hours times the rate is the printed amount")
    func printedHoursReconstructTheAmount() throws {
        for item in try Self.cases().hourly {
            let hours = Hours(hundredths: item.hundredths)
            let rate = Money(cents: item.rateCents)
            #expect(Money.charge(for: hours, at: rate) == Money(cents: item.amountCents), "\(item.why)")
            let readBack = try #require(Self.hundredths(in: PDFText.hours(hours)), "\(item.why)")
            #expect(Money.charge(for: Hours(hundredths: readBack), at: rate) == Money(cents: item.amountCents),
                    "\(item.why)")
        }
    }

    /// "1.25 hrs" read back as 125 hundredths, by digits alone, so the reading
    /// cannot borrow the formatter it is checking.
    private static func hundredths(in printed: String) -> Int64? {
        guard let number = printed.split(separator: " ").first else { return nil }
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let whole = Int64(parts[0]), parts[1].count <= 2,
              let fraction = Int64(parts[1].padding(toLength: 2, withPad: "0", startingAt: 0))
        else { return nil }
        return whole * 100 + fraction
    }

    @Test("a date is written in full, the way the settled invoice PDF writes it")
    func aDateIsWrittenInFull() {
        // 2026-10-25 12:00 New York.
        let noon = BusinessDate.stamping(Date(timeIntervalSince1970: 1_792_944_000))
        #expect(PDFText.date(noon) == "October 25, 2026")
    }

    /// L39: the business day is New York's. 23:30 on 31 December in New York is
    /// already 1 January in UTC, and an invoice dated then belongs to 2026.
    @Test("a late evening date is New York's day, not the next day in UTC")
    func aLateEveningDateIsNewYorksDay() {
        // 2026-12-31 23:30 New York, which is 2027-01-01 04:30 UTC. Converted and
        // checked before this test was trusted: the first value written here was an
        // hour late and would have tested a different day.
        let lateEvening = BusinessDate.stamping(Date(timeIntervalSince1970: 1_798_777_800))
        #expect(PDFText.date(lateEvening) == "December 31, 2026")
    }
}
