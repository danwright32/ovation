// ovation#610, ovation#614. WHAT IS WRONG WITH A BACKUP, IN THE WORDS DAN APPROVED.
//
// Two surfaces say it: the "Old backup broken" problem the launch raises, and the
// refusal a restore gives. The restore said only "N problem(s) with what is in it"
// after the problem had learned to name the file and whether the backup had
// changed, because the sentence lived in the launch sequence and the refusal was
// written beside the restore. So the parts live here, once, and each surface adds
// only the sentence that is true of it: the launch that today's backup is fine,
// the restore that nothing in Ovation was changed (L263, L370).
//
// Wording approved by Dan on 2026-09-28.
import Foundation

enum BackupFailureSentences {

    /// "from 17 Sep", read from the archive's own manifest, or the folder name
    /// when that date could not be read. The manifest's, never the name's, which a
    /// sync or a rename can change.
    static func which(name: String, writtenAt: Date?) -> String {
        writtenAt.map { "from \(dayAndMonth($0))" } ?? name
    }

    /// The sentences that say which files are wrong and whether anything in the
    /// backup changed.
    ///
    /// "Nothing in that backup has changed" is said only when every reason is a
    /// file Ovation expected or requires since, and no recorded file failed its
    /// hash, so it never sits beside a reason that contradicts it (L11, L440).
    /// Three are named and the rest counted, so one damaged archive cannot fill
    /// the panel.
    static func whatIsWrong(with which: String,
                            failures: [BackupReport.Failure]) -> [String] {
        let changed = failures.filter { $0.verdict.meansARecordedFileChanged }
        let expected = failures.filter { $0.verdict == .memberMissing }.map(\.path)
        let others = failures.filter {
            !$0.verdict.meansARecordedFileChanged && $0.verdict != .memberMissing
        }

        var sentences: [String] = []
        if !changed.isEmpty {
            sentences.append("The backup \(which) has changed since it was made: "
                + plainList(changed.map { $0.verdict.reason(for: $0.path) }) + ".")
        }
        var reasons: [String] = []
        if !expected.isEmpty {
            reasons.append(expected.count == 1
                ? "Ovation expected a file (\(expected[0])) that it never had"
                : "Ovation expected files (\(plainList(expected))) that it never had")
        }
        reasons += others.map { $0.verdict.reason(for: $0.path) }
        if !reasons.isEmpty {
            let opening = changed.isEmpty ? "The backup \(which) failed" : "It also failed"
            sentences.append("\(opening) its check because \(plainList(reasons)).")
            // A file Ovation expected, or one required since, is about the rule.
            // A document whose copy differs, or a copy of a secret, is about the
            // backup itself, and "nothing has changed" beside it contradicts it.
            let untouched = failures.allSatisfy {
                $0.verdict == .memberMissing || $0.verdict == .requiredAfterItWasWritten
            }
            if untouched { sentences.append("Nothing in that backup has changed.") }
        }
        return sentences
    }

    /// "a", "a and b", "a, b and c", then "a, b, c and 2 more".
    private static func plainList(_ items: [String]) -> String {
        let named = Array(items.prefix(3))
        if items.count > named.count {
            return named.joined(separator: ", ") + " and \(items.count - named.count) more"
        }
        guard let last = named.last else { return "" }
        let rest = named.dropLast()
        return rest.isEmpty ? last : rest.joined(separator: ", ") + " and " + last
    }

    /// "17 Sep", on the business calendar, so a trip cannot move a backup to a
    /// neighbouring day.
    private static func dayAndMonth(_ instant: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = BusinessCalendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: instant)
    }
}
