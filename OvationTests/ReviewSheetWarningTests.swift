import Foundation
import SwiftData
import Testing
@testable import Ovation

/// ovation#318 B3, PRD 52e and PRD 7. The band across the sheet about the due date.
///
/// IT IS INFORMATION, NOT A QUESTION. Nothing can answer it except changing the
/// date, so it carries no control, which is what separates it from the shared
/// address band (PRD 52e). That band is deferred to ovation#362 with the first
/// stored schema version, because the acknowledgement it carries has to be
/// remembered against the address and Ovation has nowhere to remember it today
/// (Dan, 2026-09-16).
///
/// THE CLOCK IS INJECTED. A warning about how a stored date stands against today
/// is a relationship between two moments, and a fixture that pins only one of them
/// walks into a different state as real time passes (L130, L74).
@MainActor
struct ReviewSheetWarningTests {

    /// The due date every case here is about, and the instants around it, all in the
    /// business time zone so no case depends on the machine's (L504).
    private static let due = "2026-09-12"

    @Test("a due date already past says how far past, and names the date")
    func apastDueDateIsStated() throws {
        let presenter = try Self.presenter(now: "2026-09-19")

        #expect(presenter.dueDateWarning ==
                "This is already 7 days past its due date of 12 Sep 2026.")
    }

    @Test("one day past reads as one day, not 1 days")
    func onedayPastIsSingular() throws {
        let presenter = try Self.presenter(now: "2026-09-13")

        #expect(presenter.dueDateWarning ==
                "This is already 1 day past its due date of 12 Sep 2026.")
    }

    @Test("the due date itself is said as today, because past and today are different")
    func thedueDateItselfIsToday() throws {
        let presenter = try Self.presenter(now: Self.due)

        #expect(presenter.dueDateWarning == "This is due today, 12 Sep 2026.")
    }

    @Test("a due date close ahead warns, because PRD 7 warns on close as well as past")
    func acloseDueDateWarns() throws {
        let presenter = try Self.presenter(now: "2026-09-09")

        #expect(presenter.dueDateWarning == "This is due in 3 days, on 12 Sep 2026.")
    }

    @Test("and a due date comfortably ahead says nothing at all")
    func acomfortableDueDateSaysNothing() throws {
        // A band on every ordinary send is a band nobody reads (L36).
        let presenter = try Self.presenter(now: "2026-09-01")

        #expect(presenter.dueDateWarning == nil)
    }

    @Test("the warning is drawn from the day, never from the hour")
    func theWarningCountsDaysNotHours() throws {
        // Two instants on one business day are one day, whatever the clock says,
        // which is why the count comes from the day key (L39).
        let early = try Self.presenter(now: Self.due, atHour: 1)
        let late = try Self.presenter(now: Self.due, atHour: 23)

        #expect(early.dueDateWarning == late.dueDateWarning)
    }

    // MARK: staging

    private static func presenter(now: String, atHour hour: Int = 12) throws -> ReviewSheetPresenter {
        try ReviewSampleWorld.presenter(dueDate: day(due),
                                        now: { try! Self.instant(on: now, hour: hour) })
    }

    private static func day(_ key: String) -> BusinessDate {
        BusinessDate.stamping(try! instant(on: key, hour: 12))
    }

    private static func instant(on key: String, hour: Int) throws -> Date {
        let parts = key.split(separator: "-").map { Int($0)! }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour)
        return try #require(calendar.date(from: components))
    }
}
