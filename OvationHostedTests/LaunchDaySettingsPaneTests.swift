// ovation#655, PRD 1d. Where Dan confirms Ovation's launch day, and whether that
// confirmation actually reaches the setting the draft command waits on.
//
// BUILT IS NOT WIRED (L3, L546). The setting and the command are tested in the
// pure suite; what is in question here is that Settings PRESENTS a way to confirm
// the day, that pressing it stores what was chosen, and that the pane starts on a
// day that is safe to confirm without thinking.
//
// EVERY CASE USES A THROWAWAY DEFAULTS SUITE, because this pane WRITES (L201).
import AppKit
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LaunchDaySettingsPaneTests {

    private static let today = BusinessDate.stamping(
        ISO8601DateFormatter().date(from: "2026-10-08T16:00:00Z")!)

    /// THE PLACEHOLDER IS NEVER OFFERED AS THE ANSWER. Every booking queued so far
    /// was committed after 12 September and before launch, so a Confirm pressed on
    /// the placeholder would draft every one of them a second time. The pane
    /// starts on today, the day Ovation is being set up to draft from (PRD 1d:
    /// "the launch moves the cutoff to that day"), and Dan moves it from there.
    @Test("with nothing confirmed the pane starts on today, not on the placeholder")
    func unconfirmedStartsOnToday() {
        let seeded = LaunchDaySettingsPane.seed(for: .notConfirmed, today: Self.today)

        #expect(seeded.dayKey == "2026-10-08")
        #expect(seeded != LaunchCutoff.placeholder)
    }

    @Test("with a day confirmed the pane starts on that day")
    func confirmedStartsOnTheConfirmedDay() throws {
        let day = try #require(LaunchDay(dayKey: "2026-10-01"))

        #expect(LaunchDaySettingsPane.seed(for: .confirmed(day), today: Self.today) == day)
    }

    @Test("pressing Confirm stores the chosen day, and says which day it stored")
    func confirmingStoresIt() throws {
        let throwaway = try ThrowawayDefaults()
        let setting = LaunchCutoffSetting(defaults: throwaway.defaults)
        let pane = LaunchDaySettingsPane(setting: setting, today: Self.today)
        let chosen = try #require(LaunchDay(dayKey: "2026-10-06"))

        let said = pane.confirm(chosen)

        #expect(LaunchCutoffSetting(defaults: throwaway.defaults).cutoff == .confirmed(chosen))
        #expect(said.contains("6 Oct 2026"), "it said \(said)")
    }

    /// Each state says something different, because each needs something
    /// different (L11), and the unconfirmed one says what it stops (L604).
    @Test("not confirmed, unreadable and confirmed each say something different")
    func eachStateSaysItsOwnThing() throws {
        let day = try #require(LaunchDay(dayKey: "2026-10-06"))
        let notConfirmed = LaunchDaySettingsView.status(for: .notConfirmed)
        let unreadable = LaunchDaySettingsView.status(for: .unreadable(stored: "x"))
        let confirmed = LaunchDaySettingsView.status(for: .confirmed(day))

        #expect(Set([notConfirmed, unreadable, confirmed]).count == 3)
        #expect(notConfirmed.contains("Not confirmed"), "it said \(notConfirmed)")
        #expect(confirmed.contains("6 Oct 2026"), "it said \(confirmed)")
    }

    /// The date control is otherwise a set of anonymous segments to somebody
    /// moving by control alone (L20).
    @Test("the date control announces itself as the launch day")
    func theDateControlIsNamed() throws {
        let view = LaunchDaySettingsView(
            cutoff: .notConfirmed,
            chosen: .constant(LaunchDay(dayKey: "2026-10-08")!),
            outcome: nil, confirm: {})

        let picker = try view.inspect().find(ViewType.DatePicker.self)
        #expect(try picker.accessibilityLabel().string() == "Launch day")
    }

    /// THE OUTCOME OF A PRESS IS ABOUT THE DAY THAT WAS PRESSED. Once the control
    /// is moved off it, "confirmed as 8 Oct" beside "Confirm 1 Oct" reads as the new
    /// day being confirmed, so it is not drawn (L680).
    @Test("the last press's outcome goes once the control is moved to another day")
    func theOutcomeGoesWhenTheDayMoves() throws {
        let confirmed = try #require(LaunchDay(dayKey: "2026-10-08"))
        let said = "Launch day confirmed as 8 Oct 2026."
        let moved = LaunchDaySettingsView(
            cutoff: .confirmed(confirmed),
            chosen: .constant(try #require(LaunchDay(dayKey: "2026-10-01"))),
            outcome: said, confirm: {})
        let stayed = LaunchDaySettingsView(cutoff: .confirmed(confirmed),
                                           chosen: .constant(confirmed),
                                           outcome: said, confirm: {})

        #expect(throws: (any Error).self) { try moved.inspect().find(text: said) }
        #expect(throws: Never.self) { try stayed.inspect().find(text: said) }
    }

    /// THE PANE IS REACHABLE, which is the other half of being wired.
    @Test("Settings presents a Bookings pane")
    func settingsPresentsThePane() throws {
        let throwaway = try ThrowawayDefaults()
        let view = SettingsView(
            backups: BackupSettingsPresenter(
                setting: BackupFolderSetting(defaults: throwaway.defaults,
                                             isDisposableLaunch: { true }),
                dataDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
                problems: ProblemsStore(journal: InMemoryProblemsJournal()),
                now: Date.init,
                askForAFolder: { nil }),
            invoiceFooter: InvoiceFooterSetting(defaults: throwaway.defaults),
            launchCutoff: LaunchCutoffSetting(defaults: throwaway.defaults),
            today: { Self.today })

        #expect(throws: Never.self) {
            try view.inspect().find(text: "Bookings")
        }
    }
}
