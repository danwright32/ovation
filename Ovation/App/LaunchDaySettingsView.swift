// ovation#655, PRD 1d. Where Dan confirms the day Ovation took over billing from
// QuickBooks, which the draft from the queue command waits on.
//
// DAN CHOSE THE SHAPE, 2026-10-08: a field in Settings with a Confirm control, so
// he can see the day and correct it later. There is no design record for this
// pane (docs/design has none for Settings), so it follows the invoices pane:
// a heading, one sentence of domain, the control, and what the last press said.
//
// IT IS THE PLATFORM'S DATE CONTROL IN ITS FIELD STYLE, which is the app's own
// choice for a day or a time (the shoot's times on the invoice screen, whose
// design record says so in as many words), pinned to the business zone so the
// day drawn is the day stored on a Mac set to any other zone (L39).
//
// NOTHING IS STORED UNTIL CONFIRM IS PRESSED. Moving the date is choosing; the
// press is the decision, and the button names the day it will record, so what
// is pressed is what is stored (L64).
//
// TWO TYPES, as `InvoiceSettingsView` does it: `LaunchDaySettingsView` draws what
// it is handed in any state, and `LaunchDaySettingsPane` owns the setting.
import SwiftUI

struct LaunchDaySettingsView: View {

    let cutoff: LaunchCutoff
    @Binding var chosen: LaunchDay
    /// What the last press said, so a press SAYS it happened (L608, L12).
    let outcome: String?
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Launch day").font(.headline)
                    .accessibilityAddTraits(.isHeader)
                // THE DOMAIN, said once (L604): what the day decides, which the
                // reader cannot know from the control.
                Text("Bookings committed before this day were invoiced in QuickBooks, "
                     + "so Ovation leaves them there and drafts only the ones from "
                     + "this day on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    DatePicker("Launch day", selection: dayBinding, displayedComponents: .date)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .environment(\.timeZone, BusinessCalendar.timeZone)
                        .environment(\.calendar, Self.businessCalendar)
                        .accessibilityLabel("Launch day")
                        .fixedSize()
                    Button(confirmTitle, action: confirm)
                        .disabled(chosen == cutoff.confirmed)
                }
                // NOT DRAWN WHILE THE CONTROL ALREADY SHOWS THE CONFIRMED DAY,
                // beside a button saying Confirmed: that would be the one fact
                // said twice (L605). It is drawn when the day is not confirmed,
                // and when the control has been moved off the confirmed day, which
                // is the moment the stored one is no longer on screen.
                if chosen != cutoff.confirmed {
                    status
                }
            }
            // ONLY WHILE THE CONTROL SHOWS THE DAY IT IS ABOUT. Moved to another
            // day, "confirmed as 8 Oct" beside "Confirm 1 Oct" reads as the new day
            // being confirmed (L680).
            if let outcome, chosen == cutoff.confirmed {
                Text(outcome).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ovationAppearance()
    }

    /// "Confirm 8 Oct 2026", naming the day the press records, or "Confirmed"
    /// once that day is the stored one.
    private var confirmTitle: String {
        chosen == cutoff.confirmed ? "Confirmed" : "Confirm \(chosen.written)"
    }

    /// Where the day stands. Unconfirmed is drawn as a warning, because it stops
    /// something; the sentence says what, so colour is not the only carrier (L149).
    @ViewBuilder
    private var status: some View {
        let said = Self.status(for: cutoff)
        if cutoff.confirmed == nil {
            Label(said, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Text(said).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// One sentence per state, because each needs something different (L11).
    static func status(for cutoff: LaunchCutoff) -> String {
        switch cutoff {
        case .confirmed(let day):
            return "Currently confirmed as \(day.written)."
        case .notConfirmed:
            return "Not confirmed yet, so nothing is drafted from the booking queue."
        case .unreadable:
            return "The saved day could not be read, so nothing is drafted from the "
                + "booking queue until it is confirmed again."
        }
    }

    /// The picker works in instants; the day is the business day the instant is
    /// in, read and written through the one calendar (L39).
    private var dayBinding: Binding<Date> {
        Binding(get: { chosen.instant ?? Date(timeIntervalSince1970: 0) },
                set: { chosen = LaunchDay(containing: $0) })
    }

    /// The gregorian calendar pinned to the business zone, so the picker's days
    /// are New York's days. `Calendar.current` is refused by the forbidden
    /// constructs scanner for exactly this reason.
    private static var businessCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BusinessCalendar.timeZone
        return calendar
    }
}

/// The pane Settings shows: the stored launch day, confirmed by a press.
struct LaunchDaySettingsPane: View {

    let setting: LaunchCutoffSetting
    @State private var chosen: LaunchDay
    @State private var outcome: String?

    init(setting: LaunchCutoffSetting, today: BusinessDate) {
        self.setting = setting
        _chosen = State(initialValue: Self.seed(for: setting.cutoff, today: today))
    }

    /// The day the control starts on: the confirmed day, or TODAY when there is
    /// none, never PRD 1d's placeholder. Every booking queued so far was committed
    /// after the placeholder and before launch, so a Confirm pressed on it would
    /// draft each of them a second time; today is the day Ovation is being set up
    /// to draft from (PRD 1d: "the launch moves the cutoff to that day").
    static func seed(for cutoff: LaunchCutoff, today: BusinessDate) -> LaunchDay {
        cutoff.confirmed ?? LaunchDay(containing: today.instant)
    }

    /// Records `day` and says what that means. Internal so its suite can press it
    /// exactly as the button does (L442).
    @discardableResult
    func confirm(_ day: LaunchDay) -> String {
        setting.confirm(day)
        return "Launch day confirmed as \(day.written)."
    }

    var body: some View {
        LaunchDaySettingsView(cutoff: setting.cutoff, chosen: $chosen, outcome: outcome,
                              confirm: { outcome = confirm(chosen) })
    }
}
