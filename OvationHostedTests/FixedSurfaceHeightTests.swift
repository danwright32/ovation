import AppKit
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// Whether each fixed size surface is tall enough for what it has to show (ovation#393).
///
/// ovation#391 held the Settings window to the invoices pane and nothing else, so the
/// rule existed and one surface honoured it. The failure it fixed was invisible to
/// every test and to the person who built it, because the state needing the most room
/// was one carrying warnings (L485). This holds the other fixed size surfaces to the
/// same rule, each at ITS tallest state, named in the test.
///
/// A LIST THAT GROWS FOR EVER HAS NO TALLEST STATE, and Dan settled what that means on
/// 2026-09-30: the surface fits its FIXED part without scrolling, in its tallest state
/// with every warning drawn, and the list scrolls inside its own box once long, with no
/// minimum row count. So each surface is asked for its fixed part, which is the whole
/// surface with the list left out, and a second case proves the list is in a box of its
/// own that scrolls, because a fixed part that fits says nothing if the list still
/// pushes it off the bottom.
///
/// THE CONTENT IS MEASURED, NOT THE FRAME AROUND IT. A fixed frame answers "how tall do
/// you want to be" with the frame's own height, and a ScrollView with whatever it is
/// given, so either would measure the window rather than what it holds (L63).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct FixedSurfaceHeightTests {

    // MARK: the backups pane, captured directly

    /// ITS TALLEST STATE: the folder cannot be reached, the archive list is replaced by
    /// its one line sentence, and the last press was a restore that stopped partway,
    /// which is the longest outcome the pane ever says. Each is the warning its half of
    /// the pane can carry, and all three can stand at once: a folder on a drive that went
    /// away mid restore. The path is a long one on a NAS share, which is where Dan's
    /// backups go, because a path is the one part of these sentences whose length is his.
    static let tallestBackupsPane = BackupsPaneView(
        folder: BackupsPaneView.folderSentence(for: .onADifferentVolume(
            "/Volumes/Synology Home/Dan Wright Photography/Ovation Backups is on a "
                + "different volume from the one it was chosen on")),
        retention: BackupSettingsPresenter.retention,
        archives: .sentence("Choose a folder first, and Ovation will start backing up."),
        outcome: RestorePresenter.partlyRestoredSentence(
            name: "Ovation-backup-2026-09-28-090000", replaced: ["Ovation.store", "Receipts"],
            failedAt: "Settings", snapshot: "Ovation-before-restore-2026-09-30-101500",
            cause: "The volume ran out of space while copying"))

    @Test("the Settings window fits the backups pane's fixed part, at its tallest")
    func theWindowFitsTheBackupsPane() throws {
        // CAPTURED DIRECTLY, as the decision of 2026-09-29 asked, rather than through
        // the tab the window happens to show first.
        let needed = Self.height(of: Self.tallestBackupsPane.fixedPart, width: SettingsView.minimumWidth)

        #expect(needed > 0, "the pane reported no height at all, so nothing was measured")
        #expect(SettingsView.minimumHeight >= needed + SettingsView.chromeAllowance,
                """
                the Settings window's minimum height is \(SettingsView.minimumHeight), and the \
                backups pane's fixed part needs \(needed) plus \(SettingsView.chromeAllowance) \
                of chrome at its tallest. It would open scrolling.
                """)
    }

    @Test("the archive list scrolls inside a box of its own")
    func theArchiveListScrollsInItsOwnBox() throws {
        let rows = (1...60).map { day in
            RestorePresenter.Archive(name: "Ovation-backup-\(day)", takenAt: nil, verifies: true)
        }
        let pane = BackupsPaneView(folder: "/Volumes/Backups", retention: BackupSettingsPresenter.retention,
                                   archives: .rows(rows), outcome: nil)

        let box = try pane.inspect().find(ViewType.ViewThatFits.self)
        #expect(throws: Never.self) {
            try box.find(ViewType.ScrollView.self).find(text: "Ovation-backup-60")
        }
    }

    @Test("and the fixed part holds no row, so a long list cannot count against the window")
    func theFixedPartLeavesTheListOut() throws {
        let one = [RestorePresenter.Archive(name: "Ovation-backup-1", takenAt: nil, verifies: true)]
        let pane = BackupsPaneView(folder: "/Volumes/Backups", retention: BackupSettingsPresenter.retention,
                                   archives: .rows(one), outcome: nil)

        // THE POSITIVE FIRST, in the same fixture (L159): the fixed part inspects and
        // holds what belongs to it, so the absence below is a fact about the rows
        // rather than about an inspection that failed for some other reason (L140).
        let fixed = try pane.fixedPart.inspect()
        #expect(throws: Never.self) { try fixed.find(text: "/Volumes/Backups") }
        // AND THE ROW IS ABSENT, counted rather than caught: a search for every Text
        // carrying its words finds none, where any throw at all would have passed.
        let rows = fixed.findAll(ViewType.Text.self, where: { try $0.string() == "Ovation-backup-1" })
        #expect(rows.isEmpty, "the fixed part draws an archive row, so the list counts against the window")
    }

    /// PRESSING RESTORE HANDS THE ROW TO THE PRESS, and drawing hands it to nothing.
    /// What restoring would do is read from the archive's manifest on disk, so it
    /// belongs to the press rather than the drawing, which runs on every redraw
    /// (ovation#246, ovation#255). The pane is drawn first and nothing may be asked;
    /// only the press may ask, and for the row pressed.
    @Test("drawing the archive list asks nothing, and pressing Restore asks for that row")
    func restoreIsAskedOnlyByThePress() throws {
        var asked: [String] = []
        let rows = [RestorePresenter.Archive(name: "Ovation-backup-1", takenAt: nil, verifies: true),
                    RestorePresenter.Archive(name: "Ovation-backup-2", takenAt: nil, verifies: true)]
        let pane = BackupsPaneView(folder: "/Volumes/Backups", retention: BackupSettingsPresenter.retention,
                                   archives: .rows(rows), outcome: nil,
                                   restore: { asked.append($0.name) })
        _ = Self.height(of: pane, width: SettingsView.minimumWidth)
        #expect(asked.isEmpty, "drawing the pane asked about a backup")

        let second = try pane.inspect().find(ViewType.ViewThatFits.self)
            .find(ViewType.ScrollView.self).find(text: "Ovation-backup-2")
            .find(ViewType.HStack.self, relation: .parent)
        try second.find(button: "Restore").tap()

        #expect(asked == ["Ovation-backup-2"])
    }

    // MARK: the launch day pane (ovation#655)

    /// EVERY STATE THE PANE CAN REACH, rather than one called its tallest. Which is
    /// tallest depends on wording that changes: the unreadable warning wraps to two
    /// lines, while a press just made draws its outcome under the control, and the
    /// pane draws that outcome ONLY while the control still shows the confirmed day.
    /// A fixture pairing an outcome with a state that never draws one measures a
    /// pane nobody can see (L485), so each case also asserts what it draws.
    static let launchDayStates: [(name: String, view: LaunchDaySettingsView, drawsOutcome: Bool)] = {
        let today = LaunchDay(dayKey: "2026-10-08")!
        let earlier = LaunchDay(dayKey: "2026-10-01")!
        let said = "Launch day confirmed as 8 Oct 2026."
        return [
            ("not confirmed", LaunchDaySettingsView(cutoff: .notConfirmed, chosen: .constant(today),
                                                    outcome: nil, confirm: {}), false),
            ("unreadable", LaunchDaySettingsView(cutoff: .unreadable(stored: "x"), chosen: .constant(today),
                                                 outcome: nil, confirm: {}), false),
            ("just confirmed", LaunchDaySettingsView(cutoff: .confirmed(today), chosen: .constant(today),
                                                     outcome: said, confirm: {}), true),
            ("confirmed, then moved", LaunchDaySettingsView(cutoff: .confirmed(today),
                                                            chosen: .constant(earlier),
                                                            outcome: said, confirm: {}), false),
        ]
    }()

    @Test("the Settings window fits the launch day pane in every state it can reach",
          arguments: 0..<4)
    func theWindowFitsTheLaunchDayPane(index: Int) throws {
        #expect(Self.launchDayStates.count == 4, "a state was added without widening the arguments")
        let state = Self.launchDayStates[index]
        let outcomeIsDrawn = (try? state.view.inspect().find(text: "Launch day confirmed as 8 Oct 2026.")) != nil
        #expect(outcomeIsDrawn == state.drawsOutcome,
                "\(state.name): the fixture is not a state the pane draws")

        let needed = Self.height(of: state.view, width: SettingsView.minimumWidth)

        #expect(needed > 0, "\(state.name): the pane reported no height at all, so nothing was measured")
        #expect(SettingsView.minimumHeight >= needed + SettingsView.chromeAllowance,
                "\(state.name): the launch day pane needs \(needed) plus \(SettingsView.chromeAllowance) of chrome")
    }

    // MARK: the review sheet, at its own size

    /// ITS TALLEST STATES, and there are two, because the warnings it carries exclude
    /// each other. REDIRECTED: the send will reach a test address, so both bands are
    /// drawn, the red one and the due date's, and nobody is named as passed over.
    /// OVERRIDDEN: the send goes to the client's own override, so only the due date band
    /// is drawn and the rail names who booked it. Both have an empty message, which
    /// adds the line saying what Send is waiting on.
    @Test("the review sheet fits its fixed part in each of its two tallest states",
          arguments: [true, false])
    func theReviewSheetFitsItsTallestStates(redirected: Bool) async throws {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let review = try await ReviewSheetShotTests.review(
            redirected: redirected, dueToday: true, day: day,
            overrideAddress: redirected ? nil : "accounts@example.com")
        review.message = ""
        #expect(review.whySendIsWaiting != nil, "the waiting line is part of the tallest state")
        #expect(review.presenter.dueDateWarning != nil, "the due date band is part of the tallest state")
        #expect((review.destinationWarning != nil) == redirected)
        #expect(redirected || review.presenter.passedOver != nil)

        let sheet = ReviewSheet(presenter: review.presenter, review: review, close: {})
        let needed = Self.height(of: sheet.fixedPart, width: ReviewSheet.size.width)

        #expect(needed > 0, "the sheet reported no height at all, so nothing was measured")
        // AT THE SMALLEST HEIGHT IT IS EVER GIVEN, which since ovation#547 is less than
        // its own 560 at the smallest window, because it floats clear of both edges.
        #expect(ReviewSheet.smallestHeight >= needed,
                """
                the review sheet is \(ReviewSheet.smallestHeight) tall in the smallest window \
                and its fixed part needs \
                \(needed) \(redirected ? "sent to a test address" : "sent to an override"), \
                due today, with an empty message. The foot would be cut off.
                """)
    }

    @Test("the recipients scroll inside a box of their own")
    func theRecipientsScrollInTheirOwnBox() throws {
        let many = (1...40).map { "person\($0)@example.com" }.joined(separator: ", ")
        let presenter = try ReviewSampleWorld.presenter(mainAddress: many)
        let sheet = ReviewSheet(presenter: presenter, close: {})

        let box = try sheet.inspect().find(ViewType.ViewThatFits.self)
        #expect(throws: Never.self) {
            try box.find(ViewType.ScrollView.self).find(text: "person40@example.com")
        }
    }

    /// How tall a view wants to be at a given width.
    static func height<V: View>(of view: V, width: CGFloat) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: width).ovationAppearance())
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }
}
