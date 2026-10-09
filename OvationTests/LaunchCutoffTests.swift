import Foundation
import Testing

/// ovation#655, PRD 1d. Which bookings QuickBooks already billed, decided by one
/// rule that the stopgap draft command and ovation#32's drain both ask.
///
/// THE DAY IS NEW YORK'S, and the cases are placed where that matters: a booking
/// committed late in the evening the day before launch is already the launch day
/// in UTC, and a rule reading the instant in UTC (or in whatever zone the Mac is
/// set to) would draft a booking QuickBooks has billed (L39, L504).
///
/// EVERY CASE USES A THROWAWAY DEFAULTS SUITE, because the setting WRITES and a
/// test that reached `.standard` would confirm a launch day on Dan's real Ovation
/// (L201, L2).
@MainActor
struct LaunchCutoffTests {

    private static func instant(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private static let launch = LaunchDay(dayKey: "2026-10-08")!

    // MARK: the rule

    @Test("a booking committed the day before launch was billed in QuickBooks")
    func thedayBeforeIsQuickBooks() throws {
        let committed = try Self.instant("2026-10-07T17:00:00Z")

        #expect(Self.launch.whoBills(bookingCommittedAt: committed)
                == .quickBooks(committedOn: "2026-10-07"))
    }

    @Test("a booking committed on launch day is Ovation's to draft")
    func launchDayIsOvations() throws {
        let committed = try Self.instant("2026-10-08T17:00:00Z")

        #expect(Self.launch.whoBills(bookingCommittedAt: committed) == .ovation)
    }

    /// 23:30 in New York on the 7th is 03:30 UTC on the 8th. Read in UTC this
    /// booking is on launch day and would be drafted a second time.
    @Test("late on the evening before launch, in New York, is still before launch")
    func lateTheEveningBeforeIsStillBefore() throws {
        let committed = try Self.instant("2026-10-08T03:30:00Z")

        #expect(Self.launch.whoBills(bookingCommittedAt: committed)
                == .quickBooks(committedOn: "2026-10-07"))
    }

    /// And the other edge: 00:30 in New York on the 8th is launch day, though
    /// it is only four and a half hours into the UTC day.
    @Test("just after midnight on launch day, in New York, is launch day")
    func justAfterMidnightIsLaunchDay() throws {
        let committed = try Self.instant("2026-10-08T04:30:00Z")

        #expect(Self.launch.whoBills(bookingCommittedAt: committed) == .ovation)
    }

    @Test("a day key that is not a calendar day is refused rather than made plausible")
    func amalformedDayIsRefused() {
        #expect(LaunchDay(dayKey: "2026-13-01") == nil)
        #expect(LaunchDay(dayKey: "") == nil)
        #expect(LaunchDay(dayKey: "8 Oct 2026") == nil)
    }

    // MARK: the stored setting

    /// PRD 1d: the cutoff is recorded as 12 September and that date is a
    /// placeholder, so nothing stored is NOT CONFIRMED, never confirmed as the
    /// placeholder.
    @Test("with nothing stored the cutoff is not confirmed, and drafting waits on it")
    func nothingStoredIsNotConfirmed() throws {
        let throwaway = try ThrowawayDefaults()
        let setting = LaunchCutoffSetting(defaults: throwaway.defaults)

        #expect(setting.cutoff == .notConfirmed)
        #expect(setting.cutoff.confirmed == nil)
        #expect(LaunchCutoff.placeholder.dayKey == "2026-09-12")
        let why = try #require(setting.cutoff.whyDraftingWaits)
        #expect(why.contains("launch day"), "it said \(why)")
        #expect(why.contains("Settings"), "it does not say where to confirm it: \(why)")
    }

    @Test("a confirmed launch day is stored, and a second reader sees it confirmed")
    func confirmingStoresTheDay() throws {
        let throwaway = try ThrowawayDefaults()
        let setting = LaunchCutoffSetting(defaults: throwaway.defaults)

        setting.confirm(Self.launch)

        #expect(setting.cutoff == .confirmed(Self.launch))
        #expect(setting.cutoff.whyDraftingWaits == nil)
        #expect(LaunchCutoffSetting(defaults: throwaway.defaults).cutoff == .confirmed(Self.launch))
    }

    @Test("confirming another day later replaces the first")
    func confirmingAgainCorrectsIt() throws {
        let throwaway = try ThrowawayDefaults()
        let setting = LaunchCutoffSetting(defaults: throwaway.defaults)
        setting.confirm(Self.launch)

        let corrected = try #require(LaunchDay(dayKey: "2026-10-12"))
        setting.confirm(corrected)

        #expect(LaunchCutoffSetting(defaults: throwaway.defaults).cutoff == .confirmed(corrected))
    }

    /// A stored value that is not a day is its own state, with its own sentence,
    /// and it is never read as confirmed: a damaged setting must not open the
    /// queue to drafting (L42, L11).
    @Test("a stored value that is not a day is refused by name and does not confirm")
    func adamagedValueDoesNotConfirm() throws {
        let throwaway = try ThrowawayDefaults()
        throwaway.defaults.set("not a day", forKey: LaunchCutoffSetting.key)

        let cutoff = LaunchCutoffSetting(defaults: throwaway.defaults).cutoff

        #expect(cutoff == .unreadable(stored: "not a day"))
        #expect(cutoff.confirmed == nil)
        let why = try #require(cutoff.whyDraftingWaits)
        #expect(why.contains("could not be read"), "it said \(why)")
        #expect(why != LaunchCutoff.notConfirmed.whyDraftingWaits)
    }
}
