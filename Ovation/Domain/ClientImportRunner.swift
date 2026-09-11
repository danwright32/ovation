// ovation#208. Reading Downbeat's export off disk, carrying out the plan, and
// saying what happened.
//
// THE BYTES ARRIVE THROUGH AN INJECTED CLOSURE, with no default anywhere, so a
// test can make the read fail without damaging anything. A runner that opened the
// file itself would be beyond every refusal that read could offer (L196).
//
// THE PATH TAKES NO DEFAULT ARGUMENT EITHER, and that is inherited rather than
// invented: Downbeat's own `OvertureExportWriter` says the same thing about the
// same file, in the same words, because a convenient default is how a Debug
// launch came to overwrite it (downbeat#133). Whether a given launch may read
// this path is the caller's decision and it is made once, in the app.
//
// THREE OUTCOMES THAT LOOK ALIKE AND ARE NOT (L11, L98):
//
//   THE EXPORT IS NOT THERE. Downbeat has never been launched on this Mac, or it
//   has been moved. The remedy is to open Downbeat once. Nothing is wrong.
//
//   THE EXPORT IS THERE AND WILL NOT READ. A damaged or truncated file, or one
//   from a Downbeat older than this build. The remedy is about the file.
//
//   THE EXPORT READ AND THERE WAS NOTHING TO DO. Every launch after the first is
//   this one, and it says NOTHING, because a notice on the commonest case is the
//   one Dan learns to click past (L36).
//
// A REFUSAL SAYS THE ROSTER IS UNHARMED, in the same sentence. On a screen about
// clients, "the import failed" reads as clients lost, and the true and reassuring
// half is that every client Ovation holds is exactly as it was.
import Foundation

/// What Ovation should say about the client import at this moment. Derived on
/// each run, never stored, because a recorded fact about something outside the
/// app is only true on the day it was written (L175).
enum ClientImportNotice: Equatable, Sendable {
    /// There is no export at that path at all.
    case exportMissing(file: String)
    /// There is one and it could not be read, carrying WHY.
    case couldNotRead(file: String, refusal: DownbeatReadRefusal)
    /// Clients that were not here before are here now.
    case broughtAcross(count: Int)
    /// Rows that matched something without matching it well enough to act on.
    /// The one outcome that speaks although nothing changed, because it is the
    /// one Dan has to do something about.
    case needsYou(count: Int)

    var kind: ProblemKind {
        switch self {
        case .exportMissing: return .clientImportExportMissing
        case .couldNotRead: return .clientImportUnreadable
        case .broughtAcross: return .clientImportBroughtClientsAcross
        case .needsYou: return .clientImportNeedsAnAnswer
        }
    }

    /// What the problem is ABOUT, which is half the identity a problem is
    /// deduplicated on. Stable across launches on purpose: the same standing
    /// condition seen on ten launches is one problem seen ten times, not ten
    /// problems. So the COUNTS are deliberately not part of it.
    var subject: String {
        switch self {
        case .exportMissing(let file): return file
        case .couldNotRead(let file, _): return file
        case .broughtAcross: return "downbeat-roster"
        case .needsYou: return "downbeat-roster-unmatched"
        }
    }

    var sentence: String {
        switch self {
        case .exportMissing(let file):
            return "Ovation could not find Downbeat's export (\(file)), so no clients were "
                + "brought across and your client list is exactly as it was. Downbeat writes "
                + "that file when it starts up, so opening Downbeat once will create it."
        case .couldNotRead(let file, let refusal):
            return DownbeatExport.sentence(for: refusal, file: file)
        case .broughtAcross(let count):
            let clients = count == 1 ? "client" : "clients"
            return "Ovation brought \(count) \(clients) across from Downbeat, so your client "
                + "list now has \(clients == "client" ? "it" : "them"). Tax status came across "
                + "for anyone Downbeat had an answer for; the rest are waiting for you on the "
                + "Clients screen."
        case .needsYou(let count):
            let rows = count == 1 ? "client in Downbeat" : "clients in Downbeat"
            let verb = count == 1 ? "matches" : "match"
            return "\(count) \(rows) could not be brought across safely, because each \(verb) "
                + "more than one of your clients, or matches only by name. Nothing was changed "
                + "for them, deliberately: guessing here would invoice the wrong customer."
        }
    }
}

enum ClientImportRunner {

    /// The one path Downbeat writes, which all three apps read.
    ///
    /// DELIBERATELY NOT A DEFAULT ARGUMENT ANYWHERE. See the header: Downbeat's
    /// own writer refuses to default this for the same reason.
    ///
    /// IT SITS UNDER OVERTURE'S FOLDER, not Ovation's, and that is not a mistake
    /// to tidy. Downbeat wrote this file for Overture first and publishes the path
    /// in its own `Integration/OvertureExport/CONTRACT.md`; moving it would be a
    /// change to all three apps at once.
    static func productionURL(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("Overture", isDirectory: true)
            .appendingPathComponent("downbeat-export.json")
    }

    /// Read the export, decide, carry it out, and say what happened.
    ///
    /// Returns the clients it CREATED, for the caller to insert into the store,
    /// the notices to raise, and a SUMMARY of what it did. Updates are made in
    /// place on `held`.
    ///
    /// THE SUMMARY IS NOT THE NOTICES, and conflating them is a silent data loss.
    /// A run whose only effect was a rename says NOTHING, deliberately, because a
    /// refreshed address is invisible maintenance; but it has still changed the
    /// store and the caller must save. A caller deciding whether to write from
    /// "did it have anything to say" would apply every rename in memory and drop
    /// it when the context went, on every launch, with no symptom (L11).
    static func run(
        file url: URL,
        held: inout [Client],
        contentsOf: (URL) throws -> Data
    ) -> (created: [Client], notices: [ClientImportNotice], summary: ClientImportSummary) {
        let filename = url.lastPathComponent

        let data: Data
        do {
            data = try contentsOf(url)
        } catch {
            // ABSENT AND UNREADABLE ARE DIFFERENT FACTS, so they are told apart
            // here rather than both reported as a failed read. The remedy for one
            // is to open Downbeat; for the other it is to look at the file.
            if isNoSuchFile(error) {
                return ([], [.exportMissing(file: filename)], ClientImportSummary())
            }
            return ([], [.couldNotRead(file: filename,
                                       refusal: .notReadable(detail: error.localizedDescription))],
                    ClientImportSummary())
        }

        let export: DownbeatExport
        switch DownbeatExport.read(data) {
        case .read(let value):
            export = value
        case .refused(let refusal):
            return ([], [.couldNotRead(file: filename, refusal: refusal)], ClientImportSummary())
        }

        let actions = ClientImport.plan(for: export.clients, against: held)
        let created = ClientImport.apply(actions, to: &held)
        let summary = ClientImport.summary(of: actions)

        // A RUN THAT ONLY REFRESHED FIELDS SAYS NOTHING. Updates are invisible
        // maintenance; what is worth a sentence is a client appearing, and a row
        // that needs Dan.
        var notices: [ClientImportNotice] = []
        if summary.created > 0 { notices.append(.broughtAcross(count: summary.created)) }
        if summary.leftAlone > 0 { notices.append(.needsYou(count: summary.leftAlone)) }
        return (created, notices, summary)
    }

    /// Whether this error means the file simply is not there. Checked against the
    /// codes Foundation actually raises rather than by reading the message, which
    /// is localized and would stop matching on another Mac.
    private static func isNoSuchFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == CocoaError.fileNoSuchFile.rawValue
                || nsError.code == CocoaError.fileReadNoSuchFile.rawValue
        }
        if nsError.domain == NSPOSIXErrorDomain { return nsError.code == Int(ENOENT) }
        return false
    }
}
