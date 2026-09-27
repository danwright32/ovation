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
        }
        return names
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
