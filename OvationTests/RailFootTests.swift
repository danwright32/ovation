import AppKit
import Foundation
import Testing

/// ovation#99 and ovation#566. The foot of the rail, as Dan settled it on 2026-09-26:
/// each open thing on its own line, as a SHORT NAME with its own Read beside it, newest
/// first, at most two, then "and N more". No counts, read and unread alike, and no foot
/// at all when nothing is open.
///
/// THE SHORT NAMES ARE A VOCABULARY KEYED BY PROBLEM KIND, and a lookup keyed by a
/// vocabulary needs its completeness enforced, because a missing key takes the
/// fallback and looks deliberate (L113). The kinds are DERIVED from the app's own
/// declarations rather than listed here, so the next kind declared fails this until it
/// is named (L41, L96).
@MainActor
struct RailFootTests {

    // MARK: every kind has a short name, and it fits

    /// The repository root, from this file rather than a working directory.
    private static func repositoryRoot(_ file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // OvationTests
            .deletingLastPathComponent()   // the repository
    }

    /// Every `ProblemKind("...")` the app declares, read from its sources. Tests are
    /// not scanned: a kind made up in a test is not one Dan can meet.
    private static func declaredKinds() throws -> [ProblemKind] {
        let root = repositoryRoot().appending(path: "Ovation")
        let declaration = try NSRegularExpression(pattern: #"ProblemKind\("([^"\\]+)"\)"#)
        var found: Set<String> = []
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in declaration.matches(in: text, range: range) {
                if let name = Range(match.range(at: 1), in: text) { found.insert(String(text[name])) }
            }
        }
        return found.sorted().map { ProblemKind(rawValue: $0) }
    }

    @Test("the scan finds the kinds the app declares, so an empty answer cannot pass")
    func theScanFindsTheKinds() throws {
        // The control (L98). A scan that read nothing would pass every test below.
        let kinds = try Self.declaredKinds()
        #expect(kinds.count >= 40, "only \(kinds.count) kinds found; the scan is not reading the sources")
        #expect(kinds.contains(.backupsAreStale))
        #expect(kinds.contains(.exportWritten))
        #expect(kinds.contains(.rosterUnreadable))
    }

    @Test("every problem kind the app declares has a short name")
    func everyKindHasAShortName() throws {
        let unnamed = try Self.declaredKinds().filter { $0.shortName(subject: nil) == nil }
        #expect(unnamed.isEmpty, "no short name for: \(unnamed.map(\.rawValue))")
    }

    @Test("no two kinds share a short name, so the foot never says one thing for two")
    func shortNamesAreDistinct() throws {
        let names = try Self.declaredKinds().compactMap { $0.shortName(subject: nil) }
        let repeated = Dictionary(grouping: names, by: { $0 }).filter { $1.count > 1 }.keys
        #expect(repeated.isEmpty, "shared by more than one kind: \(repeated.sorted())")
    }

    /// Every name the foot can draw, with the years an export can be named for.
    private static func everyDrawableName() throws -> [String] {
        var names: [String] = []
        for kind in try declaredKinds() {
            if let plain = kind.shortName(subject: nil) { names.append(plain) }
            for year in 2000...2099 {
                if let named = kind.shortName(subject: "year-end-export-\(year)") {
                    names.append(named)
                }
            }
            // A broken backup named for its archive's day, on every day of a leap year,
            // so the widest date is measured rather than guessed (ovation#609).
            for day in Self.everyArchiveDay() {
                if let dated = kind.shortName(subject: day, sharingKind: true),
                   dated != kind.shortName(subject: nil) {
                    names.append(dated)
                }
            }
        }
        return names
    }

    /// An archive name for every day of 2028, a leap year, at the hour backups run.
    static func everyArchiveDay() -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BusinessCalendar.timeZone
        let start = calendar.date(from: DateComponents(year: 2028, month: 1, day: 1, hour: 21))!
        return (0..<366).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            return String(format: "Ovation-backup-%04d-%02d-%02d-210000",
                          parts.year!, parts.month!, parts.day!)
        }
    }

    private static func width(_ text: String, _ weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: RailFoot.textSize, weight: weight)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Measured in the round: the bold name with Read ran 3.2 points past the edge the
    /// other Reads align to. So every name is measured, in the foot's own face, against
    /// the column the foot really has, with Read and the gap beside it.
    @Test("every short name fits one line of the foot with Read beside it")
    func everyShortNameFits() throws {
        let read = Self.width(RailFoot.readWord, .semibold)
        let room = RailFoot.column - RailFoot.gap - read
        let names = try Self.everyDrawableName()
        #expect(names.count > 40)
        let tooLong = names.filter { Self.width($0, .bold) > room }
        #expect(tooLong.isEmpty,
                "wider than the \(Int(room)) points the foot has: \(tooLong.sorted())")
    }

    @Test("the column is the rail's width less its insets, not a number chosen here")
    func theColumnIsTheRailLessItsInsets() {
        #expect(RailFoot.column == OvationWindow.railWidth
                    - 2 * (RailFoot.railInset + RailFoot.footInset + RailFoot.footPadding))
        #expect(RailFoot.column > 150 && RailFoot.column < 180)
    }

    @Test("an export's short name carries its year, from the subject it was raised with")
    func anExportIsNamedForItsYear() {
        #expect(ProblemKind.exportWritten.shortName(subject: "year-end-export-2026")
                    == "2026 export written")
        #expect(ProblemKind.exportFailed.shortName(subject: "year-end-export-2026")
                    == "2026 export failed")
        // With no year to read, it still has a name rather than none.
        #expect(ProblemKind.exportWritten.shortName(subject: "year-end-export") == "Export written")
        // A kind that is not about a year ignores a subject that looks like one.
        #expect(ProblemKind.backupsAreStale.shortName(subject: "year-end-export-2026")
                    == ProblemKind.backupsAreStale.shortName(subject: nil))
    }

    @Test("a problem reads its short name from its kind and subject")
    func aProblemHasItsShortName() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let raised = store.raise(kind: .exportWritten, subject: "year-end-export-2026",
                                 sentence: "The 2026 export is written.", now: at(1))
        #expect(raised.shortName == "2026 export written")
    }

    // MARK: several of one kind open at once (ovation#609)

    /// Dan, 2026-09-29: when several old backups are broken, each line reads
    /// "Bad backup, 30 May", the day read from the archive's own name. On the
    /// installed build three such problems all read "Old backup broken".
    @Test("two broken backups open at once are each named for their archive's day")
    func severalBrokenBackupsAreNamedForTheirDays() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let may = store.raise(kind: .archiveNoLongerVerifies,
                              subject: "Ovation-backup-2026-05-30-210000",
                              sentence: "may", now: at(1))
        let september = store.raise(kind: .archiveNoLongerVerifies,
                                    subject: "Ovation-backup-2026-09-17-210000",
                                    sentence: "september", now: at(2))

        #expect(may.shortName(among: store.open) == "Bad backup, 30 May")
        #expect(september.shortName(among: store.open) == "Bad backup, 17 Sep")
    }

    @Test("one broken backup alone keeps its plain name")
    func oneBrokenBackupKeepsItsName() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let only = store.raise(kind: .archiveNoLongerVerifies,
                               subject: "Ovation-backup-2026-05-30-210000",
                               sentence: "only", now: at(1))
        // Another open problem of a DIFFERENT kind is not a second broken backup.
        _ = store.raise(kind: .backupsAreStale, subject: "store", sentence: "stale", now: at(2))

        #expect(only.shortName(among: store.open) == "Old backup broken")
    }

    @Test("a broken backup settled since stops counting as a second one")
    func aResolvedBackupDoesNotCount() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let settled = store.raise(kind: .archiveNoLongerVerifies,
                                  subject: "Ovation-backup-2026-05-30-210000",
                                  sentence: "settled", now: at(1))
        let standing = store.raise(kind: .archiveNoLongerVerifies,
                                   subject: "Ovation-backup-2026-09-17-210000",
                                   sentence: "standing", now: at(2))
        _ = store.resolve(settled.id, because: "the backup was checked again and verifies",
                          now: at(3))

        #expect(standing.shortName(among: store.open) == "Old backup broken")
    }

    /// The day is the business calendar's, the one the archive name was written in,
    /// so a backup taken late in the evening is not named for the next day wherever
    /// the Mac's own clock is set.
    @Test("the day is read in the calendar the archive name was written in")
    func theDayIsTheArchiveNamesDay() {
        #expect(ProblemKind.archiveNoLongerVerifies.shortName(
            subject: "Ovation-backup-2026-05-30-235900", sharingKind: true)
                    == "Bad backup, 30 May")
        #expect(ProblemKind.archiveNoLongerVerifies.shortName(
            subject: "Ovation-backup-2026-06-01-000100", sharingKind: true)
                    == "Bad backup, 1 Jun")
    }

    /// A name with no day in it, from a folder renamed by hand or a sync, has no day
    /// to show, so the line says what it knows rather than inventing one.
    @Test("a broken backup whose name carries no day keeps the plain name")
    func noDayKeepsThePlainName() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let renamed = store.raise(kind: .archiveNoLongerVerifies, subject: "My old backup",
                                  sentence: "renamed", now: at(1))
        let dated = store.raise(kind: .archiveNoLongerVerifies,
                                subject: "Ovation-backup-2026-09-17-210000",
                                sentence: "dated", now: at(2))

        #expect(renamed.shortName(among: store.open) == "Old backup broken")
        #expect(dated.shortName(among: store.open) == "Bad backup, 17 Sep")
    }

    @Test("a kind with no dated name is unchanged when several of it are open")
    func otherKindsAreUnchanged() {
        #expect(ProblemKind.backupsAreStale.shortName(
            subject: "Ovation-backup-2026-05-30-210000", sharingKind: true) == "Backups are behind")
        #expect(ProblemKind.exportFailed.shortName(
            subject: "year-end-export-2026", sharingKind: true) == "2026 export failed")
    }

    @Test("a dated name for every day of the year was measured")
    func everyDayWasMeasured() throws {
        let names = try Self.everyDrawableName().filter { $0.hasPrefix("Bad backup, ") }
        #expect(Set(names).count == 366)
    }

    // MARK: one line for several (Dan, 2026-09-30, ovation#609)

    @Test("two backups broken on the same day stand as one line, and Read lists each with its time")
    func sameDayBackupsShareALine() throws {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .archiveNoLongerVerifies, subject: "Ovation-backup-2026-05-30-090000",
                    sentence: "The morning one.", now: at(1))
        store.raise(kind: .archiveNoLongerVerifies, subject: "Ovation-backup-2026-05-30-210000",
                    sentence: "The evening one.", now: at(2))

        let lines = RailFoot.lines(for: store.open)
        #expect(lines.shown.count == 1)
        #expect(lines.more == 0)
        let line = try #require(lines.shown.first)
        #expect(line.shortName(among: store.open) == "Bad backup, 30 May")
        let members = RailFoot.members(of: line, among: store.open)
        #expect(members.count == 2)
        #expect(RailFoot.sentence(for: members)
                    == "Taken at 21:00. The evening one.\n\nTaken at 09:00. The morning one.")
    }

    @Test("backups broken on different days keep a line each")
    func differentDaysKeepTheirLines() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .archiveNoLongerVerifies, subject: "Ovation-backup-2026-05-30-210000",
                    sentence: "may", now: at(1))
        store.raise(kind: .archiveNoLongerVerifies, subject: "Ovation-backup-2026-05-31-210000",
                    sentence: "may again", now: at(2))

        let names = RailFoot.lines(for: store.open).shown.map { $0.shortName(among: store.open) }
        #expect(names == ["Bad backup, 31 May", "Bad backup, 30 May"])
    }

    @Test("a kind that does not share a line keeps one line per problem")
    func otherKindsDoNotShare() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .backupsAreStale, subject: "a", sentence: "a", now: at(1))
        store.raise(kind: .backupsAreStale, subject: "b", sentence: "b", now: at(2))
        #expect(RailFoot.lines(for: store.open).shown.count == 2)
    }

    // MARK: which lines the foot draws

    @Test("nothing open draws no foot at all")
    func nothingOpenDrawsNothing() {
        let lines = RailFoot.lines(for: [])
        #expect(lines.shown.isEmpty)
        #expect(lines.more == 0)
        #expect(RailFoot.moreSentence(lines.more) == nil)
    }

    @Test("newest first, at most two, then and N more")
    func newestFirstAtMostTwo() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .backupsAreStale, subject: "a", sentence: "oldest", now: at(10))
        store.raise(kind: .exportWritten, subject: "year-end-export-2026", sentence: "newest",
                    now: at(30))
        store.raise(kind: .rosterUnreadable, subject: "c", sentence: "middle", now: at(20))

        let lines = RailFoot.lines(for: store.open)

        #expect(lines.shown.map(\.sentence) == ["newest", "middle"])
        #expect(lines.more == 1)
        #expect(RailFoot.moreSentence(1) == "and 1 more")
        #expect(RailFoot.moreSentence(4) == "and 4 more")
    }

    @Test("a standing problem raised again moves back to the top")
    func raisedAgainIsNewest() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .backupsAreStale, subject: "a", sentence: "standing", now: at(10))
        store.raise(kind: .rosterUnreadable, subject: "c", sentence: "other", now: at(20))
        store.raise(kind: .backupsAreStale, subject: "a", sentence: "standing", now: at(30))

        #expect(RailFoot.lines(for: store.open).shown.map(\.sentence) == ["standing", "other"])
    }

    /// Read and unread look the same (Dan, 2026-09-26): what stays after reading is a
    /// standing problem, which is open until its condition clears.
    @Test("a standing problem stays in the foot once read, and a notice leaves it")
    func readStandingStaysReadNoticeGoes() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let standing = store.raise(kind: .backupsAreStale, subject: "a", sentence: "standing",
                                   now: at(10))
        let notice = store.raise(kind: .exportWritten, subject: "year-end-export-2026",
                                 sentence: "notice", now: at(20))
        store.acknowledge(standing.id, now: at(21))
        store.acknowledge(notice.id, now: at(22))

        #expect(RailFoot.lines(for: store.open).shown.map(\.sentence) == ["standing"])
    }

    /// A NOTICE CLOSES ONCE READ, which the decision rests on. These report something
    /// that happened with nothing left for Dan to do, so reading them is the end of
    /// them; left open they would sit in the foot for ever after being read.
    @Test("the reports of something done close once read")
    func reportsCloseOnceRead() {
        #expect(ProblemKind.exportWritten.closesOnceRead)
        #expect(ProblemKind.bookingsDrafted.closesOnceRead)
        #expect(ProblemKind.exportFoundNothing.closesOnceRead)
        #expect(ProblemKind.clientImportBroughtClientsAcross.closesOnceRead)
        // And a condition that still needs Dan does not.
        #expect(!ProblemKind.backupsAreStale.closesOnceRead)
        #expect(!ProblemKind.exportFailed.closesOnceRead)
        #expect(!ProblemKind.clientImportNeedsAnAnswer.closesOnceRead)
    }

    private func at(_ second: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(second))
    }
}
